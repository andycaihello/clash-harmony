# mihomo Native 集成计划

版本：0.1  
日期：2026-07-02

## 目标

把当前 `VpnExtensionAbility -> CoreBridgeService -> libentry.so` 的占位链路推进到可验证的 mihomo 集成闭环：

1. runtime YAML 可被 mihomo 加载。
2. VPN Extension 创建的 TUN fd 能被 native 层接管。
3. mihomo controller 在 `127.0.0.1:9090` 可用。
4. 停止 VPN 后 native fd、core、controller 均被释放。

当前阶段不切默认路由，继续使用 `198.18.0.0/16` 低风险路由验证 native/core 生命周期。

## 当前基线

- `RuntimeConfigService` 生成 `runtime/current.yaml`，注入 `mixed-port: 7890`、`external-controller: 127.0.0.1:9090`。
- `ClashVpnExtensionAbility` 创建 TUN fd，并调用 `CoreBridgeService.startTun(configPath, tunFd)`。
- `libentry.so` 已通过 NAPI 暴露 `startTun`、`stopTun`、`getState`。
- native 层已实现 fd probe：`startTun` 会 `dup(tunFd)`，`stopTun` 会关闭 native dup fd。
- `entry/src/main/cpp/mihomo_adapter.h` 已定义 `MihomoStart/MihomoStop/MihomoVersion/MihomoLastError` C ABI。
- 当前 `mihomo_adapter.cpp` 会优先动态加载 `libmihomo_ohos.so` 并解析同名 C ABI；真实库缺失时回退到 `adapter-stub`，用于验证 NAPI 到 adapter 的链接与生命周期。
- native 状态已暴露 `adapterMode`、`adapterVersion`、`adapterLoadError`、`controllerReady` 与 `controllerVersion`，诊断页可分别判断 adapter 链路和 controller 链路。
- `MihomoControllerService` 已封装 `/version`、`/configs`、`/proxies`、代理选择、delay、connections 等基础 REST 入口。
- 预编译库约定放在 `entry/src/main/cpp/prebuilt/<OHOS_ARCH>/libmihomo_ohos.so`；缺失时继续构建 stub，存在时由 CMake imported target 链接并打包。

## 推荐路线

MVP 默认走 native library 方案，保留 child process 作为技术 spike。

### native library

目标产物：

- `libmihomo_ohos.so` 或 `libmihomo_adapter.a`
- `mihomo_adapter.h`

建议 C ABI：

```c
int MihomoStart(const char* config_path, int tun_fd);
int MihomoStop(void);
const char* MihomoVersion(void);
const char* MihomoLastError(void);
```

集成步骤：

1. 将真实 `libmihomo_ohos.so` 放到 `entry/src/main/cpp/prebuilt/<OHOS_ARCH>/`，例如 `arm64-v8a` 或 `x86_64`，并打进 HAP native library 目录，确保运行时可被 `dlopen("libmihomo_ohos.so")` 找到。
2. 真实库导出 `MihomoStart`、`MihomoStop`、`MihomoVersion`、`MihomoLastError`。
3. 在 `napi_init.cpp` 的 fd probe 成功后调用 `MihomoStart(configPath, nativeFd)`。
4. `stopTun()` 先调用 `MihomoStop()`，再关闭 native fd。
5. ArkTS 侧轮询 `MihomoControllerService.checkVersion()`，以 `/version` 成功作为 core ready 判据。

预编译库接入验收：

- 没有 `prebuilt/<OHOS_ARCH>/libmihomo_ohos.so` 时，HAP 构建成功，诊断页显示 `Adapter = stub` 或 `unloaded` 后转 `stub`。
- 放入真实库后，`node tests/verify-mihomo-prebuilt-abi.mjs` 确认 `MihomoStart/MihomoStop/MihomoVersion/MihomoLastError` 已导出；构建日志显示使用对应 ABI 的 prebuilt adapter；`node tests/verify-mihomo-prebuilt-packaging.mjs` 确认 intermediates 和最终 HAP 均包含 `libmihomo_ohos.so`。
- `node tests/mihomo-adapter-native.test.mjs` 用 fake adapter 验证本地 `dlopen/dlsym`、`real/stub` 状态切换、缺符号回退和错误上报逻辑。
- `node tests/verify-fake-mihomo-prebuilt-hap.mjs` 用 OHOS 目标 fake adapter 验证正向打包链路：生成 fake `libmihomo_ohos.so`、运行 ABI 检查、构建 HAP、确认 HAP 包含该库并清理。
- `node tests/verify-hap-contents.mjs --evidence-dir artifacts/mihomo-hap` 确认 HAP 包含 `libentry.so`、VPN Extension、INTERNET 权限；无真实 prebuilt 时也会确认 HAP 没有缓存残留的 `libmihomo_ohos.so`；有真实 prebuilt 时会记录 source/intermediate/stripped/HAP entry 的 SHA256，并解析最终 HAP 内 native `.so` 的 `DT_NEEDED`，要求非系统依赖由同 ABI HAP entry 解析，证据写入 `dependencies.json`。
- 真机启动 VPN 后，诊断页显示 `Adapter = real`、`adapterVersion` 非空、`adapterLoadError` 为空，`Controller Ready = ready`、`controllerVersion` 非空。
- `node tests/verify-device-mihomo.mjs --observe-ms 45000 --evidence-dir artifacts/mihomo-device` 安装并启动 HAP，抓取 hilog，要求出现 `VPN TUN created`、`Native core bridge started: mode=mihomo-adapter adapter=real ...` 和 `Controller ready: controllerVersion=...`，并保存 HAP hash、设备 ABI、hilog 和 `/version` 原始响应。
- 删除或替换为缺符号库时，native 不崩溃，`adapterLoadError` 能显示 `dlopen` 或缺失符号原因。

### child process spike

只用于验证 HarmonyOS 是否允许从 app sandbox 拉起 mihomo 可执行文件，以及 controller-only 能否工作。

通过条件：

- app sandbox 内 executable 可启动。
- 能读取 runtime YAML。
- `127.0.0.1:9090/version` 可访问。
- 停止 VPN 后进程退出。

child process 不能单独证明 TUN fd 数据通路成立；只有它能消费或继承 VPN fd 时，才可作为主路线。

## 第一阶段验收

1. 真机点击连接后，VPN Extension 创建 TUN fd。
2. native `dup(tunFd)` 成功，`getState()` 返回 `nativeFd >= 0`、`coreMode = adapter-stub` 或 `mihomo-adapter`。
3. 接入 mihomo 后，诊断页 `Adapter = real`，`adapterVersion` 非空，`adapterLoadError` 为空，`Controller Ready = ready`，`controllerVersion` 与 `/version` 返回版本一致。
4. 停止 VPN 后，native fd 关闭，controller 不再可用。
5. 连续启停 20 次无 fd 泄漏、无残留 VPN 状态。

设备侧命令证据：

```bash
node tests/verify-mihomo-prebuilt-abi.mjs --require-abi arm64-v8a
'/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw' assembleHap --no-daemon --stacktrace
node tests/verify-hap-contents.mjs --require-abi arm64-v8a --evidence-dir artifacts/mihomo-hap
node tests/verify-mihomo-prebuilt-packaging.mjs --require-abi arm64-v8a
node tests/verify-device-mihomo.mjs --observe-ms 45000 --evidence-dir artifacts/mihomo-device
node tests/verify-device-mihomo.mjs --observe-ms 60000 --require-stop --evidence-dir artifacts/mihomo-device-stop
node tests/verify-device-mihomo.mjs --observe-ms 300000 --cycles 20 --evidence-dir artifacts/mihomo-device-cycles
```

设备脚本会打印 `const.product.cpu.abilist` 和 `const.product.software.version`，用于把设备 ABI、HAP 内库和真实 prebuilt 对齐。`--require-stop` 要求 stop 后 `nativeFd=-1` 且 `controllerReady=false`；`--cycles 20` 要求 20 轮 start/controller/stop 完整配对，并把 `cycles[]` 与 `leakCheck` 写入 `lifecycle.json`。无设备 dry run 只能使用：

```bash
node tests/verify-device-mihomo.mjs --allow-no-device --allow-stub --observe-ms 0 --evidence-dir /private/tmp/mihomo-device-dry-run
```

dry run 不证明真实 mihomo 集成。

## 风险

- Go/cgo 交叉编译到 HarmonyOS `.so` 可能受 sysroot、pthread、resolver、netpoll 限制。
- stock mihomo 未必能直接消费由 VPN Extension 创建的 TUN fd，可能需要 adapter 层。
- 默认路由会带来自环风险；必须先确认出站 socket bypass/protect 方案。
- core 崩溃可能带崩 Extension 进程，native 层需要错误上报和幂等清理。

## 下一步代码切片

1. 产出真实 `libmihomo_ohos.so`，放入 `entry/src/main/cpp/prebuilt/<OHOS_ARCH>/` 并打包到 HAP，验证 `mihomo_adapter.cpp` 动态加载真实符号而不是进入 `adapter-stub`。
2. 用 `verify-device-mihomo.mjs` 在真机记录 adapter/TUN/controller 三条链路证据。
3. 引入最小 mihomo adapter 外部产物并做真机验证。
4. 增加 TUN packet loop 的可观测 counters，证明真实流量被 adapter 消费。
5. 验证 socket 防环路后，再把 VPN route 从 `198.18.0.0/16` 切到可配置默认路由。
