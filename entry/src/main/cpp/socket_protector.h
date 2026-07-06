#ifndef CLASH_HARMONY_SOCKET_PROTECTOR_H
#define CLASH_HARMONY_SOCKET_PROTECTOR_H

#include <cstdint>

class SocketProtector {
public:
    static void SetProtectCallback(void (*callback)(int32_t fd));
    static void Protect(int32_t fd);
    static bool HasProtectCallback();

private:
    static void (*s_protectCallback)(int32_t);
};

#endif
