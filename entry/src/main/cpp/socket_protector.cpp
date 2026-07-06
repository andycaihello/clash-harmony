#include "socket_protector.h"

void (*SocketProtector::s_protectCallback)(int32_t) = nullptr;

void SocketProtector::SetProtectCallback(void (*callback)(int32_t fd))
{
    s_protectCallback = callback;
}

void SocketProtector::Protect(int32_t fd)
{
    if (s_protectCallback != nullptr) {
        s_protectCallback(fd);
    }
}

bool SocketProtector::HasProtectCallback()
{
    return s_protectCallback != nullptr;
}
