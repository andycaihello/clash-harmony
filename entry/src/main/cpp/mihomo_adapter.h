#ifndef CLASH_HARMONY_MIHOMO_ADAPTER_H
#define CLASH_HARMONY_MIHOMO_ADAPTER_H

#ifndef __cplusplus
#include <stdbool.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

int MihomoStart(const char* configPath, int tunFd);
int MihomoStartCore(const char* configPath);
int MihomoAttachTun(int tunFd);
int MihomoDetachTun(void);
int MihomoStop(void);
const char* MihomoVersion(void);
const char* MihomoLastError(void);
const char* MihomoAdapterMode(void);
const char* MihomoAdapterKind(void);
const char* MihomoAdapterInfo(void);
const char* MihomoAdapterLoadError(void);
bool MihomoSupportsControllerOnly(void);
bool MihomoSupportsTunAttach(void);

#ifdef __cplusplus
}
#endif

#endif
