#include "health_monitor.h"

#include <ctime>

HealthStatus HealthMonitor::Check(const ForwarderStats& stats)
{
    HealthStatus result;
    result.lastPacketAt = 0;
    result.stallDurationMs = 0;
    result.consecutiveFailures = 0;

    uint64_t readErrors = stats.readErrors.load();
    uint64_t writeErrors = stats.writeErrors.load();
    uint64_t packetsRead = stats.packetsRead.load();

    if (readErrors > 0 || writeErrors > 0) {
        result.consecutiveFailures = static_cast<uint32_t>(readErrors + writeErrors);
        result.lastError = "forwarder errors detected";
    }

    // Get current time in milliseconds
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) == 0) {
        uint64_t nowMs = static_cast<uint64_t>(ts.tv_sec) * 1000 + static_cast<uint64_t>(ts.tv_nsec) / 1000000;
        result.lastPacketAt = nowMs;
    }

    if (packetsRead == 0) {
        result.coreResponsive = false;
        result.stallDurationMs = MAX_STALL_MS;
        result.lastError = "no packets read since start";
    } else {
        result.coreResponsive = true;
        if (readErrors > 100 || writeErrors > 100) {
            result.coreResponsive = false;
            result.lastError = "excessive forwarder errors";
        }
    }

    return result;
}

bool HealthMonitor::IsHealthy(const HealthStatus& status)
{
    if (!status.coreResponsive) {
        return false;
    }
    if (status.stallDurationMs > MAX_STALL_MS) {
        return false;
    }
    if (status.consecutiveFailures > 100) {
        return false;
    }
    return true;
}
