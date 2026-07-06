#ifndef CLASH_HARMONY_HEALTH_MONITOR_H
#define CLASH_HARMONY_HEALTH_MONITOR_H

#include "tun_forwarder.h"
#include <cstdint>
#include <string>

struct HealthStatus {
    bool coreResponsive = false;
    uint64_t lastPacketAt = 0;
    uint64_t stallDurationMs = 0;
    uint32_t consecutiveFailures = 0;
    std::string lastError;
};

class HealthMonitor {
public:
    static HealthStatus Check(const ForwarderStats& stats);
    static bool IsHealthy(const HealthStatus& status);
    static constexpr uint64_t MAX_STALL_MS = 30000;
};

#endif
