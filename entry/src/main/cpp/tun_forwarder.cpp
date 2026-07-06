#include "tun_forwarder.h"

#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <unistd.h>

TunForwarder::TunForwarder() = default;

TunForwarder::~TunForwarder()
{
    Stop();
}

bool TunForwarder::Start(int32_t tunFd, PacketHandler handler, ProtectFunc protectFn)
{
    if (m_active.load()) {
        m_lastError = "forwarder already active";
        return false;
    }

    if (tunFd < 0) {
        m_lastError = "invalid tun fd";
        return false;
    }

    if (handler == nullptr) {
        m_lastError = "packet handler is null";
        return false;
    }

    // Set TUN fd to non-blocking mode
    int flags = fcntl(tunFd, F_GETFL, 0);
    if (flags < 0) {
        m_lastError = std::string("fcntl F_GETFL failed: ") + strerror(errno);
        return false;
    }
    if (fcntl(tunFd, F_SETFL, flags | O_NONBLOCK) < 0) {
        m_lastError = std::string("fcntl F_SETFL O_NONBLOCK failed: ") + strerror(errno);
        return false;
    }

    m_tunFd = tunFd;
    m_packetHandler = handler;
    m_protectFn = protectFn;
    // 逐一重置 atomic 字段（std::atomic 无拷贝赋值）
    m_stats.packetsRead.store(0);
    m_stats.packetsWritten.store(0);
    m_stats.bytesRead.store(0);
    m_stats.bytesWritten.store(0);
    m_stats.readErrors.store(0);
    m_stats.writeErrors.store(0);
    m_lastError.clear();
    m_active.store(true);

    m_worker = std::thread(&TunForwarder::WorkerLoop, this);
    return true;
}

void TunForwarder::Stop()
{
    if (!m_active.load()) {
        return;
    }

    m_active.store(false);

    if (m_worker.joinable()) {
        m_worker.join();
    }

    m_tunFd = -1;
    m_packetHandler = nullptr;
    m_protectFn = nullptr;
}

ForwarderStatsSnapshot TunForwarder::GetStats() const
{
    ForwarderStatsSnapshot snapshot;
    snapshot.packetsRead = m_stats.packetsRead.load();
    snapshot.packetsWritten = m_stats.packetsWritten.load();
    snapshot.bytesRead = m_stats.bytesRead.load();
    snapshot.bytesWritten = m_stats.bytesWritten.load();
    snapshot.readErrors = m_stats.readErrors.load();
    snapshot.writeErrors = m_stats.writeErrors.load();
    return snapshot;
}

bool TunForwarder::IsActive() const
{
    return m_active.load();
}

std::string TunForwarder::GetLastError() const
{
    return m_lastError;
}

void TunForwarder::WorkerLoop()
{
    uint8_t readBuffer[TUN_READ_BUFFER_SIZE];
    uint8_t writeBuffer[TUN_READ_BUFFER_SIZE];

    while (m_active.load()) {
        ssize_t bytesRead = read(m_tunFd, readBuffer, TUN_READ_BUFFER_SIZE);

        if (bytesRead < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                continue;
            }
            if (errno == EINTR) {
                continue;
            }

            m_stats.readErrors.fetch_add(1);
            m_lastError = std::string("read error: ") + strerror(errno);
            break;
        }

        if (bytesRead == 0) {
            // EOF - TUN fd closed
            break;
        }

        m_stats.packetsRead.fetch_add(1);
        m_stats.bytesRead.fetch_add(static_cast<uint64_t>(bytesRead));

        size_t outputLen = TUN_READ_BUFFER_SIZE;
        int result = m_packetHandler(readBuffer, static_cast<size_t>(bytesRead), writeBuffer, &outputLen);

        if (result == 0 && outputLen > 0 && outputLen <= TUN_READ_BUFFER_SIZE) {
            ssize_t bytesWritten = write(m_tunFd, writeBuffer, outputLen);

            if (bytesWritten < 0) {
                if (errno == EAGAIN || errno == EWOULDBLOCK) {
                    m_stats.writeErrors.fetch_add(1);
                    continue;
                }
                if (errno == EINTR) {
                    m_stats.writeErrors.fetch_add(1);
                    continue;
                }

                m_stats.writeErrors.fetch_add(1);
                m_lastError = std::string("write error: ") + strerror(errno);
                break;
            }

            if (bytesWritten > 0) {
                m_stats.packetsWritten.fetch_add(1);
                m_stats.bytesWritten.fetch_add(static_cast<uint64_t>(bytesWritten));
            }
        } else {
            // Handler indicated no packet to write, or invalid output
            m_stats.writeErrors.fetch_add(1);
        }
    }

    m_active.store(false);
}
