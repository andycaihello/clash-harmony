/*
 * fake_mihomo.c — 功能性透明 TCP 代理适配器
 *
 * 实现完整的 TUN-to-TCP 透明代理，作为 libmihomo_ohos.so 的替代品。
 * 导出 C ABI: MihomoStart, MihomoStop, MihomoVersion, MihomoLastError
 *
 * 架构:
 *   主循环 (poll/select) 监听:
 *     1. TUN fd — 来自设备的 IP 包
 *     2. 每个活跃 real socket fd — 远程响应数据
 *
 *   对每个新 TCP SYN 包:
 *     1. 解析目标 IP:port
 *     2. 创建真实 socket 连接
 *     3. 向 TUN 回复 SYN-ACK（完成握手）
 *     4. 双向转发数据直到 FIN/RST
 *
 *   连接跟踪: 使用 (src_ip, src_port, dst_ip, dst_port) 五元组
 */

#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/ip.h>
#include <netinet/tcp.h>

/* macOS/BSD 兼容层 — 定义 Linux 风格的 TCP 标志常量 */
#ifndef TCP_SYN
#define TCP_SYN TH_SYN
#endif
#ifndef TCP_ACK
#define TCP_ACK TH_ACK
#endif
#ifndef TCP_FIN
#define TCP_FIN TH_FIN
#endif
#ifndef TCP_RST
#define TCP_RST TH_RST
#endif
#ifndef TCP_PSH
#define TCP_PSH TH_PUSH
#endif
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

/* === C ABI 导出 === */
#define EXPORT __attribute__((visibility("default")))

/* === 常量 === */
#define MAX_CONNECTIONS 256
#define TUN_MTU 1500
#define READ_BUF_SIZE 65536
#define CONNECTION_TIMEOUT_SEC 120

/* === TCP 连接状态 === */
typedef enum {
    CONN_FREE = 0,
    CONN_SYN_SENT,      /* 真实 socket connect() 已调用，等待完成 */
    CONN_ESTABLISHED,   /* 双向已建立，转发数据中 */
    CONN_CLOSING,       /* 一方已发 FIN */
    CONN_CLOSED         /* 等待清理 */
} conn_state_t;

/* === 连接跟踪条目 === */
typedef struct {
    uint32_t src_ip;
    uint16_t src_port;
    uint32_t dst_ip;
    uint16_t dst_port;
    int real_fd;                /* 真实 socket fd */
    conn_state_t state;
    time_t last_active;

    /* TCP 序列号跟踪 (TUN 侧 ← → real 侧) */
    uint32_t tun_seq;           /* 下一个期望从 TUN 收到的 seq */
    uint32_t tun_ack;           /* 下一个要发给 TUN 的 ack */
    uint32_t real_seq;          /* 从 real socket 收到的字节数 (用作 seq) */
    uint32_t real_ack;          /* 已确认发给 real socket 的字节数 */

    /* 初始序列号 (用于握手验证) */
    uint32_t client_isn;        /* 客户端(TUN侧)的初始 seq */
    uint32_t server_isn;        /* 服务端(real侧)的初始 seq — 从 SYN-ACK 提取 */

    /* 缓冲 */
    uint8_t pending_data[READ_BUF_SIZE];
    size_t pending_len;
    int fin_sent;
    int fin_received;
} connection_t;

/* === 全局状态 === */
static int g_tun_fd = -1;
static volatile int g_running = 0;
static pthread_t g_worker_thread;
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static char g_last_error[256] = "";
static connection_t g_connections[MAX_CONNECTIONS];
static uint64_t g_packets_read = 0;
static uint64_t g_bytes_read = 0;
static uint64_t g_packets_written = 0;
static uint64_t g_bytes_written = 0;
static uint64_t g_active_connections = 0;

/* === 前置声明 === */
static void* worker_loop(void* arg);
static void handle_tun_packet(const uint8_t* packet, size_t length);
static void handle_real_data(int conn_idx);
static int find_connection(uint32_t src_ip, uint16_t src_port,
                           uint32_t dst_ip, uint16_t dst_port);
static int alloc_connection(uint32_t src_ip, uint16_t src_port,
                            uint32_t dst_ip, uint16_t dst_port);
static void free_connection(int idx);
static void cleanup_all_connections(void);
static void build_tcp_packet(uint8_t* out, size_t* out_len,
                             uint32_t src_ip, uint16_t src_port,
                             uint32_t dst_ip, uint16_t dst_port,
                             uint32_t seq, uint32_t ack,
                             uint8_t flags, const uint8_t* payload, size_t payload_len);

/* === 工具函数 === */

static void set_nonblock(int fd)
{
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}

static uint16_t ip_checksum(const uint8_t* data, size_t len)
{
    uint32_t sum = 0;
    for (size_t i = 0; i < len; i += 2) {
        uint16_t word = (uint16_t)data[i] << 8;
        if (i + 1 < len) word |= data[i + 1];
        sum += word;
    }
    while (sum >> 16) sum = (sum & 0xFFFF) + (sum >> 16);
    return (uint16_t)~sum;
}

static uint16_t tcp_checksum(uint32_t src_ip, uint32_t dst_ip,
                             const uint8_t* tcp_header, size_t tcp_len,
                             const uint8_t* payload, size_t payload_len)
{
    /* 伪头部 + TCP 头部 + 负载 */
    size_t total = 12 + tcp_len + payload_len;
    uint8_t* buf = (uint8_t*)malloc(total);
    if (!buf) return 0;

    /* 伪头部 */
    memcpy(buf, &src_ip, 4);
    memcpy(buf + 4, &dst_ip, 4);
    buf[8] = 0;
    buf[9] = IPPROTO_TCP;
    uint16_t total_len = htons((uint16_t)(tcp_len + payload_len));
    memcpy(buf + 10, &total_len, 2);

    /* TCP 头部 */
    memcpy(buf + 12, tcp_header, tcp_len);
    /* 校验和字段清零 */
    memset(buf + 12 + 16, 0, 2);

    /* 负载 */
    if (payload && payload_len > 0) {
        memcpy(buf + 12 + tcp_len, payload, payload_len);
    }

    uint16_t csum = ip_checksum(buf, total);
    free(buf);
    return csum;
}

static uint16_t extract_port(const uint8_t* packet, size_t offset)
{
    return ((uint16_t)packet[offset] << 8) | packet[offset + 1];
}

static uint32_t extract_seq(const uint8_t* tcp_data)
{
    return ((uint32_t)tcp_data[4] << 24) | ((uint32_t)tcp_data[5] << 16) |
           ((uint32_t)tcp_data[6] << 8)  | (uint32_t)tcp_data[7];
}

static uint32_t extract_ack(const uint8_t* tcp_data)
{
    return ((uint32_t)tcp_data[8] << 24) | ((uint32_t)tcp_data[9] << 16) |
           ((uint32_t)tcp_data[10] << 8) | (uint32_t)tcp_data[11];
}

static void set_seq(uint8_t* tcp_data, uint32_t seq)
{
    tcp_data[4] = (seq >> 24) & 0xFF;
    tcp_data[5] = (seq >> 16) & 0xFF;
    tcp_data[6] = (seq >> 8) & 0xFF;
    tcp_data[7] = seq & 0xFF;
}

static void set_ack(uint8_t* tcp_data, uint32_t ack)
{
    tcp_data[8] = (ack >> 24) & 0xFF;
    tcp_data[9] = (ack >> 16) & 0xFF;
    tcp_data[10] = (ack >> 8) & 0xFF;
    tcp_data[11] = ack & 0xFF;
}

/* === 连接管理 === */

static int find_connection(uint32_t src_ip, uint16_t src_port,
                           uint32_t dst_ip, uint16_t dst_port)
{
    for (int i = 0; i < MAX_CONNECTIONS; i++) {
        if (g_connections[i].state == CONN_FREE) continue;
        if (g_connections[i].src_ip == src_ip &&
            g_connections[i].src_port == src_port &&
            g_connections[i].dst_ip == dst_ip &&
            g_connections[i].dst_port == dst_port) {
            return i;
        }
    }
    return -1;
}

static int alloc_connection(uint32_t src_ip, uint16_t src_port,
                            uint32_t dst_ip, uint16_t dst_port)
{
    for (int i = 0; i < MAX_CONNECTIONS; i++) {
        if (g_connections[i].state == CONN_FREE) {
            memset(&g_connections[i], 0, sizeof(connection_t));
            g_connections[i].src_ip = src_ip;
            g_connections[i].src_port = src_port;
            g_connections[i].dst_ip = dst_ip;
            g_connections[i].dst_port = dst_port;
            g_connections[i].real_fd = -1;
            g_connections[i].state = CONN_SYN_SENT;
            g_connections[i].last_active = time(NULL);
            return i;
        }
    }
    return -1;
}

static void free_connection(int idx)
{
    if (idx < 0 || idx >= MAX_CONNECTIONS) return;
    if (g_connections[idx].real_fd >= 0) {
        close(g_connections[idx].real_fd);
    }
    memset(&g_connections[idx], 0, sizeof(connection_t));
    g_active_connections--;
}

static void cleanup_all_connections(void)
{
    for (int i = 0; i < MAX_CONNECTIONS; i++) {
        free_connection(i);
    }
    g_active_connections = 0;
}

/* === TCP 包构建 === */

static void build_ip_header(uint8_t* out, size_t* offset,
                            uint32_t src_ip, uint32_t dst_ip,
                            uint8_t protocol, size_t payload_len)
{
    /* IP 头部 20 字节（无选项） */
    size_t ip_len = 20 + payload_len;
    out[(*offset)++] = 0x45;           /* Version=4, IHL=5 */
    out[(*offset)++] = 0x00;           /* DSCP+ECN */
    out[(*offset)++] = (ip_len >> 8) & 0xFF;
    out[(*offset)++] = ip_len & 0xFF;
    out[(*offset)++] = 0x00;           /* ID high */
    out[(*offset)++] = 0x00;           /* ID low */
    out[(*offset)++] = 0x40;           /* Flags: Don't Fragment */
    out[(*offset)++] = 0x00;           /* Fragment offset */
    out[(*offset)++] = 64;             /* TTL */
    out[(*offset)++] = protocol;
    /* Checksum — 稍后填充 */
    size_t csum_pos = *offset;
    out[(*offset)++] = 0x00;
    out[(*offset)++] = 0x00;
    /* Source IP */
    memcpy(out + *offset, &src_ip, 4); *offset += 4;
    /* Dest IP */
    memcpy(out + *offset, &dst_ip, 4); *offset += 4;
    /* 计算 IP 校验和 */
    uint16_t csum = ip_checksum(out + (*offset) - 20, 20);
    out[csum_pos] = (csum >> 8) & 0xFF;
    out[csum_pos + 1] = csum & 0xFF;
}

static void build_tcp_packet(uint8_t* out, size_t* out_len,
                             uint32_t src_ip, uint16_t src_port,
                             uint32_t dst_ip, uint16_t dst_port,
                             uint32_t seq, uint32_t ack,
                             uint8_t flags, const uint8_t* payload, size_t payload_len)
{
    size_t offset = 0;

    /* TCP 头部 20 字节 */
    size_t tcp_hdr_offset;
    build_ip_header(out, &offset, src_ip, dst_ip, IPPROTO_TCP, 20 + payload_len);
    tcp_hdr_offset = offset;

    /* Src port */
    out[offset++] = (src_port >> 8) & 0xFF;
    out[offset++] = src_port & 0xFF;
    /* Dst port */
    out[offset++] = (dst_port >> 8) & 0xFF;
    out[offset++] = dst_port & 0xFF;
    /* Seq */
    set_seq(out + offset, seq); offset += 4;
    /* Ack */
    set_ack(out + offset, ack); offset += 4;
    /* Data offset (5) + Reserved + Flags */
    out[offset++] = 0x50;  /* 5 * 4 = 20 字节头部 */
    out[offset++] = flags; /* SYN=0x02, ACK=0x10, FIN=0x01, RST=0x04, PSH=0x08 */
    /* Window */
    out[offset++] = 0xFF; out[offset++] = 0xFF;  /* 65535 */
    /* Checksum — 先填 0 */
    out[offset++] = 0x00; out[offset++] = 0x00;
    /* Urgent pointer */
    out[offset++] = 0x00; out[offset++] = 0x00;

    /* 负载 */
    if (payload && payload_len > 0) {
        memcpy(out + offset, payload, payload_len);
        offset += payload_len;
    }

    /* 计算 TCP 校验和 */
    uint16_t csum = tcp_checksum(src_ip, dst_ip, out + tcp_hdr_offset, 20, payload, payload_len);
    out[tcp_hdr_offset + 16] = (csum >> 8) & 0xFF;
    out[tcp_hdr_offset + 17] = csum & 0xFF;

    *out_len = offset;
}

/* === 写 TUN 包 === */

static int write_tun_packet(uint32_t src_ip, uint16_t src_port,
                            uint32_t dst_ip, uint16_t dst_port,
                            uint32_t seq, uint32_t ack,
                            uint8_t flags, const uint8_t* payload, size_t payload_len)
{
    if (g_tun_fd < 0) return -1;

    uint8_t packet[TUN_MTU];
    size_t pkt_len = 0;
    build_tcp_packet(packet, &pkt_len, src_ip, src_port, dst_ip, dst_port,
                     seq, ack, flags, payload, payload_len);

    ssize_t n = write(g_tun_fd, packet, pkt_len);
    if (n > 0) {
        g_packets_written++;
        g_bytes_written += (uint64_t)n;
    }
    return (int)n;
}

/* === 处理 TUN 包 === */

static void handle_tun_packet(const uint8_t* packet, size_t length)
{
    g_packets_read++;
    g_bytes_read += length;

    /* 至少要有 IP 头部 (20字节) */
    if (length < 20) return;

    uint8_t version_ihl = packet[0];
    uint8_t version = (version_ihl >> 4) & 0x0F;
    if (version != 4) return;  /* 只支持 IPv4 */

    uint8_t ihl = version_ihl & 0x0F;
    size_t ip_hdr_len = ihl * 4;
    if (length < ip_hdr_len) return;

    uint8_t protocol = packet[9];
    if (protocol != IPPROTO_TCP) return;  /* 只处理 TCP */

    /* 提取 IP 地址 */
    uint32_t src_ip, dst_ip;
    memcpy(&src_ip, packet + 12, 4);
    memcpy(&dst_ip, packet + 16, 4);

    /* TCP 头部 */
    const uint8_t* tcp_data = packet + ip_hdr_len;
    size_t tcp_data_len = length - ip_hdr_len;
    if (tcp_data_len < 20) return;

    uint16_t src_port = extract_port(tcp_data, 0);
    uint16_t dst_port = extract_port(tcp_data, 2);
    uint32_t seq = extract_seq(tcp_data);
    uint32_t ack = extract_ack(tcp_data);
    uint8_t tcp_flags = tcp_data[13];

    size_t tcp_hdr_len = ((tcp_data[12] >> 4) & 0x0F) * 4;
    size_t payload_len = (tcp_data_len > tcp_hdr_len) ? (tcp_data_len - tcp_hdr_len) : 0;
    const uint8_t* payload = (payload_len > 0) ? (tcp_data + tcp_hdr_len) : NULL;

    /* 查找或创建连接 */
    int conn_idx = find_connection(src_ip, src_port, dst_ip, dst_port);

    /* SYN 包 — 新连接 */
    if ((tcp_flags & TCP_SYN) && !(tcp_flags & TCP_ACK)) {
        if (conn_idx >= 0) {
            /* 重传 SYN — 重新连接 */
            free_connection(conn_idx);
        }
        conn_idx = alloc_connection(src_ip, src_port, dst_ip, dst_port);
        if (conn_idx < 0) {
            /* 连接表满 — 发 RST */
            write_tun_packet(dst_ip, dst_port, src_ip, src_port,
                             ack, seq + 1, TCP_RST | TCP_ACK, NULL, 0);
            return;
        }

        connection_t* conn = &g_connections[conn_idx];
        conn->client_isn = seq;
        conn->tun_seq = seq + 1;  /* 期望下一个字节 */
        conn->tun_ack = conn->client_isn + 1;
        conn->last_active = time(NULL);
        g_active_connections++;

        /* 创建真实 socket 连接 */
        int sock = socket(AF_INET, SOCK_STREAM, 0);
        if (sock < 0) {
            write_tun_packet(dst_ip, dst_port, src_ip, src_port,
                             ack, seq + 1, TCP_RST | TCP_ACK, NULL, 0);
            free_connection(conn_idx);
            return;
        }
        set_nonblock(sock);

        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = dst_ip;
        addr.sin_port = dst_port;

        conn->real_fd = sock;
        int ret = connect(sock, (struct sockaddr*)&addr, sizeof(addr));
        if (ret < 0 && errno != EINPROGRESS) {
            /* 连接失败 — 发 RST */
            write_tun_packet(dst_ip, dst_port, src_ip, src_port,
                             ack, seq + 1, TCP_RST | TCP_ACK, NULL, 0);
            free_connection(conn_idx);
            return;
        }
        /* EINPROGRESS — 等待 select() 通知连接完成 */
        return;
    }

    /* 连接不存在且不是 SYN — 发 RST */
    if (conn_idx < 0) {
        write_tun_packet(dst_ip, dst_port, src_ip, src_port,
                         ack, seq + 1, TCP_RST | TCP_ACK, NULL, 0);
        return;
    }

    connection_t* conn = &g_connections[conn_idx];
    conn->last_active = time(NULL);

    /* FIN 处理 */
    if (tcp_flags & TCP_FIN) {
        conn->fin_received = 1;
        conn->tun_seq = seq + 1;
        /* 向 real socket 发 FIN */
        if (conn->real_fd >= 0 && conn->state == CONN_ESTABLISHED) {
            shutdown(conn->real_fd, SHUT_WR);
            conn->fin_sent = 1;
        }
        /* 回复 ACK */
        write_tun_packet(dst_ip, dst_port, src_ip, src_port,
                         conn->tun_ack, conn->tun_seq, TCP_ACK, NULL, 0);

        if (conn->fin_received && conn->fin_sent) {
            conn->state = CONN_CLOSED;
        }
        return;
    }

    /* RST 处理 */
    if (tcp_flags & TCP_RST) {
        free_connection(conn_idx);
        return;
    }

    /* 数据转发 */
    if (payload_len > 0 && conn->real_fd >= 0 && conn->state == CONN_ESTABLISHED) {
        uint32_t expected_seq = conn->tun_seq;
        if (seq == expected_seq) {
            /* 按序到达 — 转发到 real socket */
            ssize_t sent = write(conn->real_fd, payload, payload_len);
            if (sent > 0) {
                conn->tun_seq = seq + (uint32_t)sent;
                conn->tun_ack = conn->tun_seq;
                conn->real_ack += (uint32_t)sent;
            }
        }
        /* 发送 ACK */
        write_tun_packet(dst_ip, dst_port, src_ip, src_port,
                         conn->tun_ack, conn->tun_seq, TCP_ACK, NULL, 0);
    } else if (tcp_flags & TCP_ACK) {
        /* 纯 ACK — 更新状态 */
        conn->tun_ack = ack;
    }
}

/* === 处理 real socket 数据 === */

static void handle_real_data(int conn_idx)
{
    connection_t* conn = &g_connections[conn_idx];
    if (conn->real_fd < 0) return;

    /* 检查连接是否完成 */
    if (conn->state == CONN_SYN_SENT) {
        int error = 0;
        socklen_t len = sizeof(error);
        if (getsockopt(conn->real_fd, SOL_SOCKET, SO_ERROR, &error, &len) == 0 && error == 0) {
            /* 连接成功 — 发 SYN-ACK 给 TUN */
            conn->server_isn = (uint32_t)(time(NULL) * 1000) & 0xFFFFFFFF;
            conn->real_seq = conn->server_isn;
            conn->state = CONN_ESTABLISHED;

            write_tun_packet(conn->dst_ip, conn->dst_port, conn->src_ip, conn->src_port,
                             conn->server_isn, conn->tun_seq, TCP_SYN | TCP_ACK, NULL, 0);
            conn->real_seq++;  /* SYN 消耗一个序列号 */
            return;
        } else {
            /* 连接失败 */
            write_tun_packet(conn->dst_ip, conn->dst_port, conn->src_ip, conn->src_port,
                             0, conn->tun_seq, TCP_RST | TCP_ACK, NULL, 0);
            free_connection(conn_idx);
            return;
        }
    }

    /* 读取数据 */
    uint8_t buf[READ_BUF_SIZE];
    ssize_t n = read(conn->real_fd, buf, sizeof(buf));
    if (n > 0 && conn->state == CONN_ESTABLISHED) {
        /* 转发数据到 TUN */
        write_tun_packet(conn->dst_ip, conn->dst_port, conn->src_ip, conn->src_port,
                         conn->real_seq, conn->tun_seq, TCP_PSH | TCP_ACK, buf, (size_t)n);
        conn->real_seq += (uint32_t)n;
        conn->last_active = time(NULL);
    } else if (n == 0 || (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK)) {
        /* 连接关闭 */
        if (!conn->fin_sent) {
            write_tun_packet(conn->dst_ip, conn->dst_port, conn->src_ip, conn->src_port,
                             conn->real_seq, conn->tun_seq, TCP_FIN | TCP_ACK, NULL, 0);
            conn->fin_sent = 1;
        }
        if (conn->fin_received) {
            conn->state = CONN_CLOSED;
        } else {
            conn->state = CONN_CLOSING;
        }
    }
}

/* === 超时清理 === */

static void cleanup_stale_connections(void)
{
    time_t now = time(NULL);
    for (int i = 0; i < MAX_CONNECTIONS; i++) {
        if (g_connections[i].state == CONN_FREE) continue;
        if (g_connections[i].state == CONN_CLOSED) {
            free_connection(i);
            continue;
        }
        if (now - g_connections[i].last_active > CONNECTION_TIMEOUT_SEC) {
            free_connection(i);
        }
    }
}

/* === 工作线程 === */

static void* worker_loop(void* arg)
{
    (void)arg;

    while (g_running) {
        fd_set read_fds;
        FD_ZERO(&read_fds);

        int max_fd = g_tun_fd;
        FD_SET(g_tun_fd, &read_fds);

        /* 添加所有活跃 real socket */
        for (int i = 0; i < MAX_CONNECTIONS; i++) {
            if (g_connections[i].state >= CONN_SYN_SENT &&
                g_connections[i].state < CONN_CLOSED &&
                g_connections[i].real_fd >= 0) {
                FD_SET(g_connections[i].real_fd, &read_fds);
                if (g_connections[i].real_fd > max_fd) {
                    max_fd = g_connections[i].real_fd;
                }
            }
        }

        struct timeval tv;
        tv.tv_sec = 1;   /* 1 秒超时用于清理 */
        tv.tv_usec = 0;

        int ret = select(max_fd + 1, &read_fds, NULL, NULL, &tv);
        if (ret < 0) {
            if (errno == EINTR) continue;
            snprintf(g_last_error, sizeof(g_last_error), "select failed: %s", strerror(errno));
            break;
        }

        /* 检查 TUN fd */
        if (FD_ISSET(g_tun_fd, &read_fds)) {
            uint8_t buf[READ_BUF_SIZE];
            ssize_t n = read(g_tun_fd, buf, sizeof(buf));
            if (n > 0) {
                handle_tun_packet(buf, (size_t)n);
            } else if (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK) {
                snprintf(g_last_error, sizeof(g_last_error), "TUN read error: %s", strerror(errno));
            }
        }

        /* 检查 real socket */
        for (int i = 0; i < MAX_CONNECTIONS; i++) {
            if (g_connections[i].state >= CONN_SYN_SENT &&
                g_connections[i].state < CONN_CLOSED &&
                g_connections[i].real_fd >= 0 &&
                FD_ISSET(g_connections[i].real_fd, &read_fds)) {
                handle_real_data(i);
            }
        }

        /* 定期清理 */
        cleanup_stale_connections();
    }

    cleanup_all_connections();
    return NULL;
}

/* === C ABI 导出 === */

EXPORT int MihomoStart(const char* config_path, int tun_fd)
{
    pthread_mutex_lock(&g_lock);

    if (g_running) {
        pthread_mutex_unlock(&g_lock);
        return -1;
    }

    if (tun_fd < 0) {
        snprintf(g_last_error, sizeof(g_last_error), "invalid tun fd: %d", tun_fd);
        pthread_mutex_unlock(&g_lock);
        return -2;
    }

    g_tun_fd = tun_fd;
    g_running = 1;
    g_last_error[0] = '\0';
    memset(g_connections, 0, sizeof(g_connections));
    g_packets_read = 0;
    g_bytes_read = 0;
    g_packets_written = 0;
    g_bytes_written = 0;
    g_active_connections = 0;

    int ret = pthread_create(&g_worker_thread, NULL, worker_loop, NULL);
    if (ret != 0) {
        snprintf(g_last_error, sizeof(g_last_error), "pthread_create failed: %d", ret);
        g_running = 0;
        pthread_mutex_unlock(&g_lock);
        return -3;
    }

    pthread_mutex_unlock(&g_lock);
    return 0;
}

EXPORT int MihomoStop(void)
{
    pthread_mutex_lock(&g_lock);

    g_running = 0;
    if (g_worker_thread) {
        pthread_mutex_unlock(&g_lock);
        pthread_join(g_worker_thread, NULL);
        pthread_mutex_lock(&g_lock);
        g_worker_thread = 0;
    }

    cleanup_all_connections();
    g_tun_fd = -1;
    g_last_error[0] = '\0';

    pthread_mutex_unlock(&g_lock);
    return 0;
}

EXPORT const char* MihomoVersion(void)
{
    return "fake-mihomo-tcp-1.0";
}

EXPORT const char* MihomoLastError(void)
{
    return g_last_error;
}
