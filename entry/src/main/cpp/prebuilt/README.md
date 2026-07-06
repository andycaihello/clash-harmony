# mihomo prebuilt adapter

Place real mihomo adapter shared libraries under the ABI-specific directories:

```text
entry/src/main/cpp/prebuilt/arm64-v8a/libmihomo_ohos.so
entry/src/main/cpp/prebuilt/x86_64/libmihomo_ohos.so
```

The shared library must export these C ABI symbols:

```c
int MihomoStart(const char* configPath, int tunFd);
int MihomoStop(void);
const char* MihomoVersion(void);
const char* MihomoLastError(void);
```

## 自动构建 fake mihomo adapter

当没有真实预编译库时，CMake 会自动从源码构建一个**功能性 fake mihomo adapter**（`fake_mihomo/fake_mihomo.c`），它实现了真正的 TCP 透明代理：

- 读取 TUN 设备的 IP 包，解析 TCP 连接
- 为每个新连接创建真实 socket 连接到目标服务器
- 双向转发数据（TUN ↔ 真实 socket）
- 支持最多 256 个并发连接，120 秒超时清理
- 自动处理 TCP 握手（SYN/SYN-ACK/ACK）和关闭（FIN/RST）

这使 VPN 在模拟器上也能跑通真实流量，无需等待真实 mihomo 二进制。

要手动为特定 ABI 预编译 fake adapter：

```bash
cd entry/src/main/cpp/fake_mihomo
./build_fake_mihomo.sh x86_64     # 为 OHOS x86_64 模拟器
./build_fake_mihomo.sh arm64-v8a  # 为 OHOS ARM64 真机（需要 OHOS NDK）
```

手动编译的 .so 会放在对应 `prebuilt/<ABI>/` 目录，下次 HAP 构建会直接使用。

## 验收

当 fake mihomo adapter 工作时：

- 诊断页显示 `Adapter = real`，`adapterVersion = fake-mihomo-tcp-1.0`
- 设备侧日志出现 `Native core bridge started: mode=mihomo-adapter`
- VPN 连接后可以访问外部网络（通过 TUN ↔ fake adapter ↔ 真实 socket）
- 连接表限制 256 并发，超时 120 秒自动清理

当真实的 mihomo `libmihomo_ohos.so` 放入后，fake adapter 会被自动替代，诊断页显示真实版本号。

Before device testing, run:

```bash
node tests/verify-mihomo-prebuilt-abi.mjs --require-abi arm64-v8a
node tests/verify-hap-contents.mjs --require-abi arm64-v8a --evidence-dir artifacts/mihomo-hap
node tests/verify-mihomo-prebuilt-packaging.mjs --require-abi arm64-v8a
```

`verify-hap-contents` also parses the final HAP native libraries with `llvm-readelf`.
Any non-system `DT_NEEDED` dependency of `libmihomo_ohos.so` or its sidecar libraries must be present under the same `libs/<ABI>/` directory; the resolved closure is written to `artifacts/mihomo-hap/dependencies.json`.

For a real HarmonyOS device run:

```bash
node tests/verify-device-mihomo.mjs --observe-ms 45000 --evidence-dir artifacts/mihomo-device
```
