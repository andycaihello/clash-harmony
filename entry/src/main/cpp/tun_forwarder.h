#ifndef CLASH_HARMONY_TUN_FORWARDER_H
#define CLASH_HARMONY_TUN_FORWARDER_H

#include <atomic>
#include <cstdint>
#include <string>
#include <thread>

/* 内部统计 (用 atomic 保证线程安全) */
struct ForwarderStats {
    std::atomic<uint64_t> packetsRead{0};
    std::atomic<uint64_t> packetsWritten{0};
    std::atomic<uint64_t> bytesRead{0};
    std::atomic<uint64_t> bytesWritten{0};
    std::atomic<uint64_t> readErrors{0};
    std::atomic<uint64_t> writeErrors{0};
};

/* 快照 (plain struct, 可安全按值返回) */
struct ForwarderStatsSnapshot {
    uint64_t packetsRead = 0;
    uint64_t packetsWritten = 0;
    uint64_t bytesRead = 0;
    uint64_t bytesWritten = 0;
    uint64_t readErrors = 0;
    uint64_t writeErrors = 0;
};

class TunForwarder {
public:
    TunForwarder();
    ~TunForwarder();

    // C ABI compatible callbacks
    using PacketHandler = int (*)(const uint8_t* input, size_t inputLen, uint8_t* output, size_t* outputLen);
    using ProtectFunc = void (*)(int32_t socketFd);

    bool Start(int32_t tunFd, PacketHandler handler, ProtectFunc protectFn);
    void Stop();
    ForwarderStatsSnapshot GetStats() const;
    bool IsActive() const;
    std::string GetLastError() const;

private:
    void WorkerLoop();

    int32_t m_tunFd = -1;
    std::atomic<bool> m_active{false};
    std::thread m_worker;
    ForwarderStats m_stats;
    PacketHandler m_packetHandler = nullptr;
    ProtectFunc m_protectFn = nullptr;
    std::string m_lastError;

    static constexpr size_t TUN_READ_BUFFER_SIZE = 65536;
};

#endif
