#include "mihomo_adapter.h"

#include <cerrno>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <fcntl.h>
#include <dlfcn.h>
#include <pthread.h>
#if defined(__OHOS__)
#include <hilog/log.h>
#endif
#include <signal.h>
#if defined(__OHOS__) || defined(__linux__)
#include <sys/mman.h>
#endif
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <fstream>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>

#if defined(__OHOS__) || defined(__linux__)
extern "C" char** environ;
#endif

namespace {

using StartFn = int (*)(const char*, int);
using StartCoreFn = int (*)(const char*);
using AttachTunFn = int (*)(int);
using DetachTunFn = int (*)(void);
using StopFn = int (*)(void);
using StringFn = const char* (*)(void);
using FreeCStringFn = void (*)(char*);

const char* REAL_ADAPTER_LIBRARY = "libmihomo_ohos.so";
const char* EXEC_ADAPTER_LIBRARY = "libmihomo_exec.so";

#if defined(__OHOS__)
constexpr unsigned int ADAPTER_LOG_DOMAIN = 0x0001;
constexpr const char* ADAPTER_LOG_TAG = "ClashMihomoAdapter";
#endif

std::mutex g_adapterMutex;
bool g_started = false;
bool g_loadAttempted = false;
bool g_execStarted = false;
pid_t g_execPid = -1;
void* g_realAdapterHandle = nullptr;
StartFn g_realStart = nullptr;
StartCoreFn g_realStartCore = nullptr;
AttachTunFn g_realAttachTun = nullptr;
DetachTunFn g_realDetachTun = nullptr;
StopFn g_realStop = nullptr;
StringFn g_realVersion = nullptr;
StringFn g_realLastError = nullptr;
StringFn g_realAdapterInfo = nullptr;
FreeCStringFn g_realFreeCString = nullptr;
std::string g_lastError;
std::string g_realLoadError;
std::string g_stringScratch;
std::string g_execGeneratedConfigPath;

enum class ExecLaunchKind {
    PATH,
    FD
};

struct RealStartCoreCall {
    StartCoreFn fn = nullptr;
    std::string configPath;
    int result = -1;
};

void AdapterLogInfo(const char* format, ...)
{
    char buffer[1024];
    va_list args;
    va_start(args, format);
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
#if defined(__OHOS__)
    OH_LOG_Print(LOG_APP, LOG_INFO, ADAPTER_LOG_DOMAIN, ADAPTER_LOG_TAG, "%{public}s", buffer);
#else
    (void)buffer;
#endif
}

void AdapterLogError(const char* format, ...)
{
    char buffer[1024];
    va_list args;
    va_start(args, format);
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
#if defined(__OHOS__)
    OH_LOG_Print(LOG_APP, LOG_ERROR, ADAPTER_LOG_DOMAIN, ADAPTER_LOG_TAG, "%{public}s", buffer);
#else
    (void)buffer;
#endif
}

void* RealStartCoreWorker(void* opaque)
{
    auto* call = reinterpret_cast<RealStartCoreCall*>(opaque);
    AdapterLogInfo("worker calling real MihomoStartCore: config=%s", call->configPath.c_str());
    call->result = call->fn(call->configPath.c_str());
    AdapterLogInfo("worker real MihomoStartCore returned: result=%d", call->result);
    return nullptr;
}

int CallRealStartCoreOnWorker(StartCoreFn fn, const char* configPath)
{
    RealStartCoreCall call;
    call.fn = fn;
    call.configPath = configPath == nullptr ? "" : configPath;

    pthread_attr_t attr;
    int attrResult = pthread_attr_init(&attr);
    if (attrResult != 0) {
        g_lastError = std::string("pthread_attr_init failed: ") + strerror(attrResult);
        AdapterLogError("%s", g_lastError.c_str());
        return -1;
    }

    constexpr size_t GO_WORKER_STACK_SIZE = 8 * 1024 * 1024;
    int stackResult = pthread_attr_setstacksize(&attr, GO_WORKER_STACK_SIZE);
    if (stackResult != 0) {
        AdapterLogError("pthread_attr_setstacksize failed: %s", strerror(stackResult));
    }

    pthread_t thread {};
    int createResult = pthread_create(&thread, &attr, RealStartCoreWorker, &call);
    pthread_attr_destroy(&attr);
    if (createResult != 0) {
        g_lastError = std::string("pthread_create failed: ") + strerror(createResult);
        AdapterLogError("%s", g_lastError.c_str());
        return -1;
    }

    int joinResult = pthread_join(thread, nullptr);
    if (joinResult != 0) {
        g_lastError = std::string("pthread_join failed: ") + strerror(joinResult);
        AdapterLogError("%s", g_lastError.c_str());
        return -1;
    }
    return call.result;
}

bool HasRealAdapterLocked()
{
    return g_realAdapterHandle != nullptr && g_realStart != nullptr && g_realStop != nullptr &&
           g_realVersion != nullptr && g_realLastError != nullptr;
}

void ResetRealAdapterLocked()
{
    if (g_realAdapterHandle != nullptr) {
        dlclose(g_realAdapterHandle);
    }
    g_realAdapterHandle = nullptr;
    g_realStart = nullptr;
    g_realStartCore = nullptr;
    g_realAttachTun = nullptr;
    g_realDetachTun = nullptr;
    g_realStop = nullptr;
    g_realVersion = nullptr;
    g_realLastError = nullptr;
    g_realAdapterInfo = nullptr;
    g_realFreeCString = nullptr;
}

std::string ParentDir(const std::string& path)
{
    size_t slash = path.rfind('/');
    if (slash == std::string::npos) {
        return ".";
    }
    return path.substr(0, slash);
}

std::string FileName(const std::string& path)
{
    size_t slash = path.rfind('/');
    if (slash == std::string::npos) {
        return path.empty() ? "config.yaml" : path;
    }
    if (slash + 1 >= path.size()) {
        return "config.yaml";
    }
    return path.substr(slash + 1);
}

std::string JoinPath(const std::string& dir, const std::string& name)
{
    if (dir.empty() || dir == ".") {
        return name;
    }
    if (dir[dir.size() - 1] == '/') {
        return dir + name;
    }
    return dir + "/" + name;
}

void LogTextInChunks(const char* label, const std::string& text)
{
    constexpr size_t CHUNK_SIZE = 700;
    if (text.empty()) {
        return;
    }
    for (size_t offset = 0; offset < text.size(); offset += CHUNK_SIZE) {
        std::string chunk = text.substr(offset, CHUNK_SIZE);
        AdapterLogError("%s: %s", label, chunk.c_str());
    }
}

void PrepareGoRuntimeStderrCaptureLocked(const char* configPath)
{
    if (configPath == nullptr || configPath[0] == '\0') {
        return;
    }

    std::string capturePath = JoinPath(ParentDir(configPath), "go-runtime-stderr.log");
    {
        std::ifstream previous(capturePath, std::ios::binary);
        if (previous.good()) {
            std::ostringstream buffer;
            buffer << previous.rdbuf();
            std::string text = buffer.str();
            if (!text.empty()) {
                AdapterLogError("previous Go runtime stderr found: %s bytes=%zu", capturePath.c_str(), text.size());
                if (text.size() > 4096) {
                    text = text.substr(text.size() - 4096);
                }
                LogTextInChunks("previous Go runtime stderr", text);
            }
        }
    }

    int fd = open(capturePath.c_str(), O_CREAT | O_TRUNC | O_WRONLY, 0600);
    if (fd < 0) {
        AdapterLogError("open Go runtime stderr capture failed: path=%s errno=%d (%s)",
                        capturePath.c_str(), errno, strerror(errno));
        return;
    }
    if (dup2(fd, STDERR_FILENO) < 0) {
        AdapterLogError("dup2 stderr capture failed: path=%s errno=%d (%s)",
                        capturePath.c_str(), errno, strerror(errno));
    }
    if (dup2(fd, STDOUT_FILENO) < 0) {
        AdapterLogError("dup2 stdout capture failed: path=%s errno=%d (%s)",
                        capturePath.c_str(), errno, strerror(errno));
    }
    close(fd);
    AdapterLogInfo("redirected Go runtime stderr/stdout: %s", capturePath.c_str());
}

std::string ErrnoMessage(int value)
{
    return std::to_string(value) + " (" + strerror(value) + ")";
}

void SetExecErrorLocked(const std::string& message)
{
    if (g_realLoadError.empty()) {
        g_lastError = message;
        return;
    }
    g_lastError = "real adapter load error: " + g_realLoadError + "; " + message;
}

std::string ResolveExecSourcePathLocked()
{
    Dl_info info;
    if (dladdr(reinterpret_cast<void*>(&ResolveExecSourcePathLocked), &info) == 0 || info.dli_fname == nullptr) {
        return "";
    }
    return JoinPath(ParentDir(info.dli_fname), EXEC_ADAPTER_LIBRARY);
}

bool FileReadable(const std::string& path)
{
    return !path.empty() && access(path.c_str(), R_OK) == 0;
}

bool FileExecutable(const std::string& path)
{
    return !path.empty() && access(path.c_str(), X_OK) == 0;
}

void AddUniqueDir(std::vector<std::string>& dirs, const std::string& dir)
{
    if (dir.empty()) {
        return;
    }
    for (const std::string& existing : dirs) {
        if (existing == dir) {
            return;
        }
    }
    dirs.push_back(dir);
}

bool EnsureWritableDirLocked(const std::string& dir, const std::string& targetPath, bool createDir,
                             std::string& detail)
{
    if (createDir && mkdir(dir.c_str(), 0700) != 0 && errno != EEXIST) {
        detail = "target_dir=" + dir + " target=" + targetPath + " mkdir_errno=" + ErrnoMessage(errno);
        return false;
    }

    struct stat dirStat {};
    if (stat(dir.c_str(), &dirStat) != 0) {
        detail = "target_dir=" + dir + " target=" + targetPath + " access_errno=" + ErrnoMessage(errno);
        return false;
    }
    if (!S_ISDIR(dirStat.st_mode)) {
        detail = "target_dir=" + dir + " target=" + targetPath + " access_errno=" + ErrnoMessage(ENOTDIR);
        return false;
    }
    if (access(dir.c_str(), W_OK | X_OK) != 0) {
        detail = "target_dir=" + dir + " target=" + targetPath + " access_errno=" + ErrnoMessage(errno);
        return false;
    }
    return true;
}

bool CopyFileLocked(const std::string& sourcePath, const std::string& targetPath, std::string& detail)
{
    int sourceFd = open(sourcePath.c_str(), O_RDONLY);
    if (sourceFd < 0) {
        detail = "source=" + sourcePath + " target=" + targetPath + " copy_step=open_source copy_errno=" +
                 ErrnoMessage(errno);
        return false;
    }

    int targetFd = open(targetPath.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (targetFd < 0) {
        int savedErrno = errno;
        close(sourceFd);
        detail = "source=" + sourcePath + " target=" + targetPath + " copy_step=open_target copy_errno=" +
                 ErrnoMessage(savedErrno);
        return false;
    }

    char buffer[64 * 1024];
    while (true) {
        ssize_t readSize = read(sourceFd, buffer, sizeof(buffer));
        if (readSize < 0 && errno == EINTR) {
            continue;
        }
        if (readSize == 0) {
            break;
        }
        if (readSize < 0) {
            int savedErrno = errno;
            close(sourceFd);
            close(targetFd);
            unlink(targetPath.c_str());
            detail = "source=" + sourcePath + " target=" + targetPath + " copy_step=read copy_errno=" +
                     ErrnoMessage(savedErrno);
            return false;
        }

        ssize_t written = 0;
        while (written < readSize) {
            ssize_t writeSize = write(targetFd, buffer + written, static_cast<size_t>(readSize - written));
            if (writeSize < 0 && errno == EINTR) {
                continue;
            }
            if (writeSize < 0) {
                int savedErrno = errno;
                close(sourceFd);
                close(targetFd);
                unlink(targetPath.c_str());
                detail = "source=" + sourcePath + " target=" + targetPath + " copy_step=write copy_errno=" +
                         ErrnoMessage(savedErrno);
                return false;
            }
            written += writeSize;
        }
    }

    if (fsync(targetFd) != 0) {
        int savedErrno = errno;
        close(sourceFd);
        close(targetFd);
        unlink(targetPath.c_str());
        detail = "source=" + sourcePath + " target=" + targetPath + " copy_step=fsync copy_errno=" +
                 ErrnoMessage(savedErrno);
        return false;
    }

    close(sourceFd);
    if (close(targetFd) != 0) {
        int savedErrno = errno;
        unlink(targetPath.c_str());
        detail = "source=" + sourcePath + " target=" + targetPath + " copy_step=close_target copy_errno=" +
                 ErrnoMessage(savedErrno);
        return false;
    }
    return true;
}

bool PrepareExecPathLocked(const char* configPath, std::string& sourcePath, std::string& executablePath,
                           std::string& executableDir, int& missingErrno)
{
    missingErrno = 0;
    sourcePath = ResolveExecSourcePathLocked();
    if (sourcePath.empty()) {
        missingErrno = ENOENT;
        SetExecErrorLocked("mihomo exec fallback prepare failed: source=<unresolved> target=<unresolved> "
                           "access_errno=" + ErrnoMessage(missingErrno));
        return false;
    }

    if (access(sourcePath.c_str(), R_OK) != 0) {
        missingErrno = errno;
        SetExecErrorLocked("mihomo exec fallback source not readable: source=" + sourcePath +
                           " target=<unresolved> access_errno=" + ErrnoMessage(missingErrno));
        return false;
    }

    std::string config = configPath == nullptr ? "" : configPath;
    std::string configDir = ParentDir(config);
    std::string configParent = ParentDir(configDir);
    std::string siblingExecDir = JoinPath(configParent, "mihomo_exec");

    std::vector<std::string> candidateDirs;
    AddUniqueDir(candidateDirs, configDir);
    if (!configParent.empty() && configParent != "." && siblingExecDir != configDir) {
        AddUniqueDir(candidateDirs, siblingExecDir);
    }

    std::ostringstream failures;
    for (size_t index = 0; index < candidateDirs.size(); index++) {
        std::string candidateDir = candidateDirs[index];
        std::string candidateTarget = JoinPath(candidateDir, EXEC_ADAPTER_LIBRARY);
        bool createDir = candidateDir == siblingExecDir;
        std::string detail;
        if (!EnsureWritableDirLocked(candidateDir, candidateTarget, createDir, detail)) {
            failures << " candidate[" << index << "] " << detail << ";";
            continue;
        }

        if (!CopyFileLocked(sourcePath, candidateTarget, detail)) {
            failures << " candidate[" << index << "] " << detail << ";";
            continue;
        }

        if (chmod(candidateTarget.c_str(), 0700) != 0) {
            failures << " candidate[" << index << "] source=" << sourcePath << " target=" << candidateTarget
                     << " chmod_errno=" << ErrnoMessage(errno) << ";";
            unlink(candidateTarget.c_str());
            continue;
        }

        if (!FileExecutable(candidateTarget)) {
            failures << " candidate[" << index << "] source=" << sourcePath << " target=" << candidateTarget
                     << " access_errno=" << ErrnoMessage(errno) << ";";
            unlink(candidateTarget.c_str());
            continue;
        }

        executablePath = candidateTarget;
        executableDir = candidateDir;
        return true;
    }

    SetExecErrorLocked("mihomo exec fallback prepare failed: source=" + sourcePath +
                       " target_candidates=" + std::to_string(candidateDirs.size()) + ";" + failures.str());
    return false;
}

std::string FormatExitStatus(int status)
{
    if (WIFEXITED(status)) {
        return "exit=" + std::to_string(WEXITSTATUS(status));
    }
    if (WIFSIGNALED(status)) {
        return "signal=" + std::to_string(WTERMSIG(status));
    }
    return "status=" + std::to_string(status);
}

int ForkExecAttemptLocked(const std::string& label, const std::string& sourcePath, const std::string& execPath,
                          const std::string& configToUse, int tunFd, bool enableTun, ExecLaunchKind kind,
                          int execFd, std::string& detail)
{
    (void)execFd;
    int execErrorPipe[2] = {-1, -1};
    if (pipe(execErrorPipe) != 0) {
        detail = label + ": pipe_errno=" + ErrnoMessage(errno);
        return -12;
    }

    int pipeFdFlags = fcntl(execErrorPipe[1], F_GETFD);
    if (pipeFdFlags < 0 || fcntl(execErrorPipe[1], F_SETFD, pipeFdFlags | FD_CLOEXEC) != 0) {
        int savedErrno = errno;
        close(execErrorPipe[0]);
        close(execErrorPipe[1]);
        detail = label + ": fcntl_errno=" + ErrnoMessage(savedErrno);
        return -12;
    }

    int originalTunFdFlags = -1;
    if (enableTun) {
        originalTunFdFlags = fcntl(tunFd, F_GETFD);
        if (originalTunFdFlags < 0) {
            int savedErrno = errno;
            close(execErrorPipe[0]);
            close(execErrorPipe[1]);
            detail = label + ": tunFd=" + std::to_string(tunFd) + " read_fd_flags_errno=" +
                     ErrnoMessage(savedErrno);
            return -16;
        }
        if (fcntl(tunFd, F_SETFD, originalTunFdFlags & ~FD_CLOEXEC) != 0) {
            int savedErrno = errno;
            close(execErrorPipe[0]);
            close(execErrorPipe[1]);
            detail = label + ": tunFd=" + std::to_string(tunFd) + " clear_cloexec_errno=" +
                     ErrnoMessage(savedErrno);
            return -16;
        }
    }

    pid_t pid = fork();
    if (pid < 0) {
        int savedErrno = errno;
        if (originalTunFdFlags >= 0) {
            fcntl(tunFd, F_SETFD, originalTunFdFlags);
        }
        close(execErrorPipe[0]);
        close(execErrorPipe[1]);
        detail = label + ": fork_errno=" + ErrnoMessage(savedErrno);
        return -12;
    }
    if (pid == 0) {
        close(execErrorPipe[0]);
        setsid();
        int nullFd = open("/dev/null", O_RDWR);
        if (nullFd >= 0) {
            dup2(nullFd, STDIN_FILENO);
            dup2(nullFd, STDOUT_FILENO);
            dup2(nullFd, STDERR_FILENO);
            if (nullFd > STDERR_FILENO) {
                close(nullFd);
            }
        }

        if (kind == ExecLaunchKind::PATH) {
            execl(execPath.c_str(), execPath.c_str(), "-f", configToUse.c_str(), static_cast<char*>(nullptr));
        } else {
#if defined(__OHOS__) || defined(__linux__)
            char* const argv[] = {
                const_cast<char*>(execPath.c_str()),
                const_cast<char*>("-f"),
                const_cast<char*>(configToUse.c_str()),
                nullptr
            };
            fexecve(execFd, argv, environ);
#else
            errno = ENOSYS;
#endif
        }

        int execErrno = errno;
        ssize_t ignored = write(execErrorPipe[1], &execErrno, sizeof(execErrno));
        (void)ignored;
        _exit(127);
    }

    if (originalTunFdFlags >= 0) {
        fcntl(tunFd, F_SETFD, originalTunFdFlags);
    }
    close(execErrorPipe[1]);
    g_execPid = pid;

    int execErrno = 0;
    ssize_t readSize = read(execErrorPipe[0], &execErrno, sizeof(execErrno));
    while (readSize < 0 && errno == EINTR) {
        readSize = read(execErrorPipe[0], &execErrno, sizeof(execErrno));
    }
    int savedReadErrno = errno;
    close(execErrorPipe[0]);
    if (readSize == static_cast<ssize_t>(sizeof(execErrno))) {
        while (waitpid(pid, nullptr, 0) < 0 && errno == EINTR) {
        }
        g_execPid = -1;
        g_execStarted = false;
        detail = label + ": source=" + sourcePath + " target=" + execPath + " config=" + configToUse +
                 " exec_errno=" + ErrnoMessage(execErrno);
        return -15;
    }
    if (readSize < 0) {
        g_execPid = -1;
        g_execStarted = false;
        detail = label + ": source=" + sourcePath + " target=" + execPath + " config=" + configToUse +
                 " pipe_read_errno=" + ErrnoMessage(savedReadErrno);
        return -15;
    }
    if (readSize > 0) {
        g_execPid = -1;
        g_execStarted = false;
        detail = label + ": source=" + sourcePath + " target=" + execPath + " config=" + configToUse +
                 " partial_errno_bytes=" + std::to_string(readSize);
        return -15;
    }

    usleep(200000);

    int status = 0;
    pid_t waitResult = waitpid(pid, &status, WNOHANG);
    while (waitResult < 0 && errno == EINTR) {
        waitResult = waitpid(pid, &status, WNOHANG);
    }
    if (waitResult == pid) {
        g_execPid = -1;
        g_execStarted = false;
        detail = label + ": source=" + sourcePath + " target=" + execPath + " config=" + configToUse +
                 " early_exit=" + FormatExitStatus(status);
        return -13;
    }
    if (waitResult < 0) {
        int savedErrno = errno;
        g_execPid = -1;
        g_execStarted = false;
        detail = label + ": source=" + sourcePath + " target=" + execPath + " config=" + configToUse +
                 " wait_errno=" + ErrnoMessage(savedErrno);
        return -13;
    }

    g_execStarted = true;
    g_started = true;
    g_lastError.clear();
    return 0;
}

int OpenExecFdLocked(const std::string& path, const std::string& label, std::string& detail)
{
    int fd = open(path.c_str(), O_RDONLY);
    if (fd < 0) {
        detail = label + ": source=" + path + " open_errno=" + ErrnoMessage(errno);
    }
    return fd;
}

int CreateMemfdExecLocked(const std::string& sourcePath, std::string& detail)
{
#if defined(__OHOS__) || defined(__linux__)
    int sourceFd = open(sourcePath.c_str(), O_RDONLY);
    if (sourceFd < 0) {
        detail = "memfd: source=" + sourcePath + " open_source_errno=" + ErrnoMessage(errno);
        return -1;
    }

    int memfd = memfd_create("clash_harmony_mihomo_exec", 0);
    if (memfd < 0) {
        int savedErrno = errno;
        close(sourceFd);
        detail = "memfd: source=" + sourcePath + " memfd_create_errno=" + ErrnoMessage(savedErrno);
        return -1;
    }

    char buffer[64 * 1024];
    while (true) {
        ssize_t readSize = read(sourceFd, buffer, sizeof(buffer));
        if (readSize < 0 && errno == EINTR) {
            continue;
        }
        if (readSize == 0) {
            break;
        }
        if (readSize < 0) {
            int savedErrno = errno;
            close(sourceFd);
            close(memfd);
            detail = "memfd: source=" + sourcePath + " read_errno=" + ErrnoMessage(savedErrno);
            return -1;
        }

        ssize_t written = 0;
        while (written < readSize) {
            ssize_t writeSize = write(memfd, buffer + written, static_cast<size_t>(readSize - written));
            if (writeSize < 0 && errno == EINTR) {
                continue;
            }
            if (writeSize < 0) {
                int savedErrno = errno;
                close(sourceFd);
                close(memfd);
                detail = "memfd: source=" + sourcePath + " write_errno=" + ErrnoMessage(savedErrno);
                return -1;
            }
            written += writeSize;
        }
    }
    close(sourceFd);

    if (fchmod(memfd, 0700) != 0) {
        int savedErrno = errno;
        close(memfd);
        detail = "memfd: source=" + sourcePath + " fchmod_errno=" + ErrnoMessage(savedErrno);
        return -1;
    }
    if (lseek(memfd, 0, SEEK_SET) < 0) {
        int savedErrno = errno;
        close(memfd);
        detail = "memfd: source=" + sourcePath + " lseek_errno=" + ErrnoMessage(savedErrno);
        return -1;
    }
    return memfd;
#else
    detail = "memfd: source=" + sourcePath + " unsupported_errno=" + ErrnoMessage(ENOSYS);
    return -1;
#endif
}

void StopExecLocked()
{
    if (g_execPid > 0) {
        kill(g_execPid, SIGTERM);
        for (int index = 0; index < 20; index++) {
            int status = 0;
            pid_t result = waitpid(g_execPid, &status, WNOHANG);
            if (result == g_execPid || result < 0) {
                break;
            }
            usleep(50000);
        }
        kill(g_execPid, SIGKILL);
        waitpid(g_execPid, nullptr, WNOHANG);
    }
    g_execPid = -1;
    g_execStarted = false;
    if (!g_execGeneratedConfigPath.empty()) {
        unlink(g_execGeneratedConfigPath.c_str());
        g_execGeneratedConfigPath.clear();
    }
}

bool WriteTunConfigLocked(const char* configPath, int tunFd, const std::string& outputDir, std::string& outputPath)
{
    errno = 0;
    std::ifstream input(configPath, std::ios::in | std::ios::binary);
    if (!input) {
        int savedErrno = errno == 0 ? EIO : errno;
        SetExecErrorLocked("unable to read runtime config for exec tun mode: source_config=" +
                           std::string(configPath) + " target=<unresolved> access_errno=" +
                           ErrnoMessage(savedErrno));
        return false;
    }

    std::ostringstream buffer;
    buffer << input.rdbuf();
    outputPath = JoinPath(outputDir, FileName(configPath) + ".tun.generated.yaml");

    errno = 0;
    std::ofstream output(outputPath, std::ios::out | std::ios::binary | std::ios::trunc);
    if (!output) {
        int savedErrno = errno == 0 ? EIO : errno;
        SetExecErrorLocked("unable to write generated tun config for exec mode: source_config=" +
                           std::string(configPath) + " target=" + outputPath + " write_errno=" +
                           ErrnoMessage(savedErrno));
        return false;
    }
    output << buffer.str();
    output << "\n";
    output << "tun:\n";
    output << "  enable: true\n";
    output << "  stack: gvisor\n";
    output << "  auto-route: false\n";
    output << "  auto-detect-interface: true\n";
    output << "  file-descriptor: " << tunFd << "\n";
    output.flush();
    if (!output) {
        int savedErrno = errno == 0 ? EIO : errno;
        SetExecErrorLocked("failed to flush generated tun config for exec mode: source_config=" +
                           std::string(configPath) + " target=" + outputPath + " write_errno=" +
                           ErrnoMessage(savedErrno));
        return false;
    }
    return true;
}

int StartExecLocked(const char* configPath, int tunFd, bool enableTun)
{
    StopExecLocked();
    g_started = false;

    std::string configToUse = configPath;
    std::string generatedConfigPath;
    if (enableTun) {
        std::string configDir = ParentDir(configToUse);
        if (!WriteTunConfigLocked(configPath, tunFd, configDir, generatedConfigPath)) {
            return -11;
        }
        configToUse = generatedConfigPath;
    }

    std::string execSourcePath = ResolveExecSourcePathLocked();
    if (execSourcePath.empty()) {
        if (!generatedConfigPath.empty()) {
            unlink(generatedConfigPath.c_str());
        }
        SetExecErrorLocked("mihomo exec fallback source path could not be resolved: source=<unresolved> config=" +
                           configToUse + " access_errno=" + ErrnoMessage(ENOENT));
        return -10;
    }
    if (access(execSourcePath.c_str(), R_OK) != 0) {
        int savedErrno = errno;
        if (!generatedConfigPath.empty()) {
            unlink(generatedConfigPath.c_str());
        }
        SetExecErrorLocked("mihomo exec fallback source not readable: source=" + execSourcePath + " config=" +
                           configToUse + " access_errno=" + ErrnoMessage(savedErrno));
        return savedErrno == ENOENT ? -10 : -14;
    }

    std::ostringstream failures;
    int attemptResult = ForkExecAttemptLocked("bundle-path", execSourcePath, execSourcePath, configToUse, tunFd,
                                              enableTun, ExecLaunchKind::PATH, -1, g_lastError);
    if (attemptResult == 0) {
        if (!generatedConfigPath.empty()) {
            g_execGeneratedConfigPath = generatedConfigPath;
        }
        return 0;
    }
    failures << g_lastError << "; ";

    std::string execCopySourcePath;
    std::string execCopyPath;
    std::string execCopyDir;
    int missingErrno = 0;
    if (PrepareExecPathLocked(configPath, execCopySourcePath, execCopyPath, execCopyDir, missingErrno)) {
        std::string detail;
        attemptResult = ForkExecAttemptLocked("copied-path", execCopySourcePath, execCopyPath, configToUse, tunFd,
                                              enableTun, ExecLaunchKind::PATH, -1, detail);
        if (attemptResult == 0) {
            if (!generatedConfigPath.empty()) {
                g_execGeneratedConfigPath = generatedConfigPath;
            }
            return 0;
        }
        failures << detail << "; ";
    } else {
        failures << g_lastError << "; ";
    }

    std::string detail;
    int sourceFd = OpenExecFdLocked(execSourcePath, "bundle-fexec", detail);
    if (sourceFd >= 0) {
        attemptResult = ForkExecAttemptLocked("bundle-fexec", execSourcePath, execSourcePath, configToUse, tunFd,
                                              enableTun, ExecLaunchKind::FD, sourceFd, detail);
        close(sourceFd);
        if (attemptResult == 0) {
            if (!generatedConfigPath.empty()) {
                g_execGeneratedConfigPath = generatedConfigPath;
            }
            return 0;
        }
    }
    failures << detail << "; ";

    if (!execCopyPath.empty()) {
        int copyFd = OpenExecFdLocked(execCopyPath, "copied-fexec", detail);
        if (copyFd >= 0) {
            attemptResult = ForkExecAttemptLocked("copied-fexec", execSourcePath, execCopyPath, configToUse, tunFd,
                                                  enableTun, ExecLaunchKind::FD, copyFd, detail);
            close(copyFd);
            if (attemptResult == 0) {
                if (!generatedConfigPath.empty()) {
                    g_execGeneratedConfigPath = generatedConfigPath;
                }
                return 0;
            }
        }
        failures << detail << "; ";
    }

    int memfd = CreateMemfdExecLocked(execSourcePath, detail);
    if (memfd >= 0) {
        attemptResult = ForkExecAttemptLocked("memfd-fexec", execSourcePath, "mihomo_exec_memfd", configToUse,
                                              tunFd, enableTun, ExecLaunchKind::FD, memfd, detail);
        close(memfd);
        if (attemptResult == 0) {
            if (!generatedConfigPath.empty()) {
                g_execGeneratedConfigPath = generatedConfigPath;
            }
            return 0;
        }
    }
    failures << detail << "; ";

    if (!generatedConfigPath.empty()) {
        unlink(generatedConfigPath.c_str());
    }
    SetExecErrorLocked("mihomo exec fallback failed across all launch methods: source=" + execSourcePath +
                       " config=" + configToUse + " failures=" + failures.str());
    return -15;
}

void* LoadSymbol(const char* name)
{
    void* symbol = dlsym(g_realAdapterHandle, name);
    if (symbol == nullptr) {
        g_lastError = std::string("missing symbol ") + name;
    }
    return symbol;
}

void* LoadOptionalSymbol(const char* name)
{
    return dlsym(g_realAdapterHandle, name);
}

bool EnsureRealAdapterLoadedLocked()
{
    if (g_loadAttempted) {
        return HasRealAdapterLocked();
    }

    g_loadAttempted = true;
    AdapterLogInfo("dlopen real adapter start: %s", REAL_ADAPTER_LIBRARY);
    g_realAdapterHandle = dlopen(REAL_ADAPTER_LIBRARY, RTLD_NOW | RTLD_GLOBAL);
    if (g_realAdapterHandle == nullptr) {
        const char* error = dlerror();
        g_realLoadError = error == nullptr ? "libmihomo_ohos.so not found" : error;
        g_lastError = g_realLoadError;
        AdapterLogError("dlopen real adapter failed: %s", g_realLoadError.c_str());
        return false;
    }
    AdapterLogInfo("dlopen real adapter succeeded");

    g_realStart = reinterpret_cast<StartFn>(LoadSymbol("MihomoStart"));
    g_realStop = reinterpret_cast<StopFn>(LoadSymbol("MihomoStop"));
    g_realVersion = reinterpret_cast<StringFn>(LoadSymbol("MihomoVersion"));
    g_realLastError = reinterpret_cast<StringFn>(LoadSymbol("MihomoLastError"));
    if (!HasRealAdapterLocked()) {
        g_realLoadError = g_lastError.empty() ? "libmihomo_ohos.so missing required symbols" : g_lastError;
        g_lastError = g_realLoadError;
        AdapterLogError("real adapter required symbol check failed: %s", g_realLoadError.c_str());
        ResetRealAdapterLocked();
        return false;
    }

    g_realStartCore = reinterpret_cast<StartCoreFn>(LoadOptionalSymbol("MihomoStartCore"));
    g_realAttachTun = reinterpret_cast<AttachTunFn>(LoadOptionalSymbol("MihomoAttachTun"));
    g_realDetachTun = reinterpret_cast<DetachTunFn>(LoadOptionalSymbol("MihomoDetachTun"));
    g_realAdapterInfo = reinterpret_cast<StringFn>(LoadOptionalSymbol("MihomoAdapterInfo"));
    g_realFreeCString = reinterpret_cast<FreeCStringFn>(LoadOptionalSymbol("MihomoFreeCString"));
    g_realLoadError.clear();
    g_lastError.clear();
    AdapterLogInfo("real adapter symbols loaded: startCore=%s attachTun=%s adapterInfo=%s freeCString=%s",
                   g_realStartCore == nullptr ? "no" : "yes",
                   g_realAttachTun == nullptr ? "no" : "yes",
                   g_realAdapterInfo == nullptr ? "no" : "yes",
                   g_realFreeCString == nullptr ? "no" : "yes");
    AdapterLogInfo("waiting after real adapter dlopen for Go runtime initialization");
    usleep(1000 * 1000);
    return true;
}

std::string CopyRealStringLocked(StringFn fn)
{
    if (fn == nullptr) {
        return "";
    }
    const char* value = fn();
    if (value == nullptr) {
        return "";
    }
    std::string copied(value);
    if (g_realFreeCString != nullptr) {
        g_realFreeCString(const_cast<char*>(value));
    }
    return copied;
}

std::string SafeRealLastErrorLocked()
{
    return CopyRealStringLocked(g_realLastError);
}

} // namespace

int MihomoStart(const char* configPath, int tunFd)
{
    std::lock_guard<std::mutex> lock(g_adapterMutex);
    if (configPath == nullptr || configPath[0] == '\0') {
        g_started = false;
        g_lastError = "config path is empty";
        return -1;
    }
    if (tunFd < 0) {
        g_started = false;
        g_lastError = "tun fd is invalid";
        return -2;
    }

    if (EnsureRealAdapterLoadedLocked()) {
        int result = g_realStart(configPath, tunFd);
        g_started = result == 0;
        if (result != 0) {
            std::string realError = SafeRealLastErrorLocked();
            g_lastError = realError.empty() ? "real mihomo adapter start failed" : realError;
        } else {
            g_lastError.clear();
        }
        return result;
    }

    int execResult = StartExecLocked(configPath, tunFd, true);
    if (execResult == -10) {
        // Keep host tests and no-prebuilt development builds usable when no real adapter is packaged.
        g_started = true;
        g_lastError = g_realLoadError;
        return 0;
    }
    return execResult;
}

int MihomoStartCore(const char* configPath)
{
    std::lock_guard<std::mutex> lock(g_adapterMutex);
    if (configPath == nullptr || configPath[0] == '\0') {
        g_started = false;
        g_lastError = "config path is empty";
        return -1;
    }
    PrepareGoRuntimeStderrCaptureLocked(configPath);
    if (!EnsureRealAdapterLoadedLocked()) {
        return StartExecLocked(configPath, -1, false);
    }
    if (g_realStartCore == nullptr) {
        g_started = false;
        g_lastError = "real mihomo adapter does not support controller-only mode";
        return -3;
    }
    AdapterLogInfo("calling real MihomoStartCore on worker: config=%s", configPath);
    int result = CallRealStartCoreOnWorker(g_realStartCore, configPath);
    AdapterLogInfo("real MihomoStartCore returned: result=%d", result);
    g_started = result == 0;
    if (result != 0) {
        std::string realError = SafeRealLastErrorLocked();
        g_lastError = realError.empty() ? "real mihomo controller-only start failed" : realError;
        AdapterLogError("real MihomoStartCore failed: %s", g_lastError.c_str());
    } else {
        g_lastError.clear();
    }
    return result;
}

int MihomoAttachTun(int tunFd)
{
    std::lock_guard<std::mutex> lock(g_adapterMutex);
    if (tunFd < 0) {
        g_lastError = "tun fd is invalid";
        return -1;
    }
    if (!EnsureRealAdapterLoadedLocked()) {
        return -2;
    }
    if (g_realAttachTun == nullptr) {
        g_lastError = "real mihomo adapter does not support attaching TUN";
        return -3;
    }
    int result = g_realAttachTun(tunFd);
    if (result != 0) {
        std::string realError = SafeRealLastErrorLocked();
        g_lastError = realError.empty() ? "real mihomo attach tun failed" : realError;
    } else {
        g_lastError.clear();
    }
    return result;
}

int MihomoDetachTun(void)
{
    std::lock_guard<std::mutex> lock(g_adapterMutex);
    if (!EnsureRealAdapterLoadedLocked()) {
        return -2;
    }
    if (g_realDetachTun == nullptr) {
        g_lastError = "real mihomo adapter does not support detaching TUN";
        return -3;
    }
    int result = g_realDetachTun();
    if (result != 0) {
        std::string realError = SafeRealLastErrorLocked();
        g_lastError = realError.empty() ? "real mihomo detach tun failed" : realError;
    } else {
        g_lastError.clear();
    }
    return result;
}

int MihomoStop(void)
{
    std::lock_guard<std::mutex> lock(g_adapterMutex);
    int result = 0;
    if (g_realStop != nullptr) {
        result = g_realStop();
    }
    StopExecLocked();
    g_started = false;
    return result;
}

const char* MihomoVersion(void)
{
    std::lock_guard<std::mutex> lock(g_adapterMutex);
    if (g_started && g_realVersion != nullptr) {
        g_stringScratch = CopyRealStringLocked(g_realVersion);
        return g_stringScratch.c_str();
    }
    if (g_execStarted) {
        return "mihomo-exec";
    }
    return g_started ? "adapter-stub" : "";
}

const char* MihomoLastError(void)
{
    std::lock_guard<std::mutex> lock(g_adapterMutex);
    if (g_realLastError != nullptr) {
        std::string realError = SafeRealLastErrorLocked();
        if (!realError.empty()) {
            g_lastError = realError;
            return g_lastError.c_str();
        }
    }
    return g_lastError.c_str();
}

const char* MihomoAdapterMode(void)
{
    std::lock_guard<std::mutex> lock(g_adapterMutex);
    if (HasRealAdapterLocked()) {
        return "real";
    }
    if (g_execStarted) {
        return "exec";
    }
    if (g_loadAttempted) {
        return "stub";
    }
    return "unloaded";
}

const char* MihomoAdapterKind(void)
{
    std::lock_guard<std::mutex> lock(g_adapterMutex);
    if (HasRealAdapterLocked()) {
        if (g_realAdapterInfo != nullptr) {
            std::string info = CopyRealStringLocked(g_realAdapterInfo);
            if (info.find("\"implementation\":\"mihomo\"") != std::string::npos) {
                return "mihomo";
            }
        }
        return "real";
    }
    if (g_execStarted) {
        return "mihomo";
    }
    if (g_loadAttempted) {
        return "stub";
    }
    return "unknown";
}

const char* MihomoAdapterInfo(void)
{
    std::lock_guard<std::mutex> lock(g_adapterMutex);
    if (HasRealAdapterLocked() && g_realAdapterInfo != nullptr) {
        g_stringScratch = CopyRealStringLocked(g_realAdapterInfo);
        return g_stringScratch.c_str();
    }
    if (g_execStarted) {
        g_stringScratch = "{\"implementation\":\"mihomo-exec\",\"supportsControllerOnly\":true,\"supportsTunAttach\":false}";
        return g_stringScratch.c_str();
    }
    if (HasRealAdapterLocked()) {
        g_stringScratch = "{\"implementation\":\"real\",\"supportsControllerOnly\":false,\"supportsTunAttach\":false}";
        return g_stringScratch.c_str();
    }
    if (g_loadAttempted) {
        g_stringScratch = "{\"implementation\":\"stub\",\"supportsControllerOnly\":false,\"supportsTunAttach\":false}";
        return g_stringScratch.c_str();
    }
    g_stringScratch = "{\"implementation\":\"unknown\",\"supportsControllerOnly\":false,\"supportsTunAttach\":false}";
    return g_stringScratch.c_str();
}

const char* MihomoAdapterLoadError(void)
{
    std::lock_guard<std::mutex> lock(g_adapterMutex);
    if (HasRealAdapterLocked()) {
        return "";
    }
    if (g_execStarted) {
        return "";
    }
    return g_lastError.c_str();
}

bool MihomoSupportsControllerOnly(void)
{
    std::lock_guard<std::mutex> lock(g_adapterMutex);
    return (HasRealAdapterLocked() && g_realStartCore != nullptr) || FileReadable(ResolveExecSourcePathLocked());
}

bool MihomoSupportsTunAttach(void)
{
    std::lock_guard<std::mutex> lock(g_adapterMutex);
    return HasRealAdapterLocked() && g_realAttachTun != nullptr && g_realDetachTun != nullptr;
}
