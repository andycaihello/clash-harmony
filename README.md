# Clash Harmony

Clash Harmony 是一个 HarmonyOS / ArkTS Stage 工程，用于在鸿蒙设备上运行 Clash/mihomo 风格的代理与 VPN 工作流。当前版本已经接入真实 `arm64-v8a` mihomo native 库，支持订阅导入、节点测速、策略切换、VPN 启停、controller 诊断和首页实时状态刷新。

## 当前状态

更新时间：2026-07-06

- 真机包名：`io.github.clashharmony.app`
- 主入口：`EntryAbility`
- VPN 扩展：`ClashVpnExtensionAbility`
- 已接入真实 `arm64-v8a/libmihomo_ohos.so`
- 已打包 `arm64-v8a/libmihomo_exec.so` 作为 mihomo 执行 fallback
- `x86_64` 仍使用内置 fake/stub adapter，主要用于模拟器界面与构建验证
- 真机验证过 VPN 可建立，controller 端口、TUN 网卡和代理访问链路可用
- 首页状态刷新已修复：连接状态、运行时长、下载/上传速度、连接数、当前链路会直接绑定 live 状态刷新

## 功能清单

### 首页

- VPN 连接/断开圆形主按钮
- 左上角连接状态：`未连接` / `已连接`
- 右上角运行时长：秒级刷新，60 秒内显示 `Xs`
- 下载速度、上传速度、连接数实时展示
- 运行模式切换：规则 / 全局 / 直连
- 当前链路展示：配置名、模式、策略组、运行配置状态
- 最近状态：配置状态、运行配置、核心状态、实时流量

### 代理页

- 展示订阅解析出的全部节点
- 支持搜索节点
- 支持同步 controller 策略组
- 支持节点选择并写入 mihomo controller
- 支持全量测速，状态直接展示在每个节点后面
- 测速中有 UI 反馈和进度文本

### 配置页

- 支持远程订阅导入
- 支持剪贴板导入
- 支持本地 YAML / 文本文件导入
- 支持订阅更新、启用、删除
- 支持 Shadowsocks 通用订阅转换
- 支持 runtime YAML 生成
- 支持 hosts 预解析、DNS 配置注入、IPv6 关闭等运行配置修正

### 诊断页

- controller `/version`、`/configs`、`/proxies`、`/connections`、`/rules` 检查
- native adapter 状态展示
- TUN fd、native fd、controllerReady、adapterVersion、lastError 展示
- VPN TUN 转发统计展示
- runtime 配置、DNS、规则、连接列表查看

## 技术实现

### ArkTS 层

- `Index.ets`：当前主 UI 与运行状态编排
- `ProfileStore.ets`：配置持久化
- `SubscriptionService.ets`：订阅更新
- `ClashConfigParserService.ets`：Clash YAML 解析
- `GenericSubscriptionConverterService.ets`：通用订阅格式转换
- `RuntimeConfigService.ets`：生成 mihomo 运行配置
- `MihomoControllerService.ets`：mihomo REST controller 封装
- `TrafficPollerService.ets`：实时流量轮询
- `VpnService.ets`：VPN Extension 启停入口
- `TcpDelayTestService.ets`：节点 TCP 延迟测试

### Native 层

- `napi_init.cpp`：NAPI 入口
- `mihomo_adapter.cpp`：动态加载 `libmihomo_ohos.so`
- `tun_forwarder.cpp`：TUN 转发循环
- `socket_protector.cpp`：socket 防环路保护
- `health_monitor.cpp`：native 健康监控

真实 mihomo adapter 需要导出以下 C ABI：

```text
MihomoStart
MihomoStop
MihomoVersion
MihomoLastError
```

当前真实库位置：

```text
entry/src/main/cpp/prebuilt/arm64-v8a/libmihomo_ohos.so
entry/src/main/cpp/prebuilt/arm64-v8a/libmihomo_exec.so
```

## 项目结构

```text
AppScope/
entry/
  src/main/
    cpp/
      fake_mihomo/
      prebuilt/
        arm64-v8a/
          libmihomo_ohos.so
          libmihomo_exec.so
      health_monitor.cpp
      mihomo_adapter.cpp
      napi_init.cpp
      socket_protector.cpp
      tun_forwarder.cpp
    ets/
      components/
      entryability/
      models/
      pages/
      services/
      vpnextensionability/
    module.json5
docs/
tests/
```

## 构建

推荐使用 DevEco Studio 自带的 hvigor wrapper：

```bash
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p module=entry@default -p product=default
```

构建产物：

```text
entry/build/default/outputs/default/entry-default-signed.hap
```

## 安装到真机

```bash
HDC=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc
SERIAL=<device-serial>
HAP=entry/build/default/outputs/default/entry-default-signed.hap

$HDC -t "$SERIAL" shell "aa force-stop io.github.clashharmony.app" || true
$HDC -t "$SERIAL" install -r "$HAP"
$HDC -t "$SERIAL" shell "aa start -b io.github.clashharmony.app -m entry -a EntryAbility"
```

查看已连接设备：

```bash
$HDC list targets
```

## 验证

基础脚本：

```bash
node tests/app-flow.test.mjs
node --check tests/app-flow.test.mjs
node --check tests/verify-hap-contents.mjs
node --check tests/verify-device-mihomo.mjs
```

HAP 内容校验：

```bash
node tests/verify-hap-contents.mjs entry/build/default/outputs/default/entry-default-signed.hap
```

真实 mihomo ABI 校验：

```bash
node tests/verify-mihomo-prebuilt-abi.mjs --require-abi arm64-v8a
node tests/verify-mihomo-prebuilt-packaging.mjs --require-abi arm64-v8a
```

真机 mihomo 验收：

```bash
node tests/verify-device-mihomo.mjs --observe-ms 45000 --evidence-dir artifacts/mihomo-device
```

如果 `hdc` 不在 PATH，可使用环境变量：

```bash
HDC=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc node tests/verify-device-mihomo.mjs --observe-ms 45000
```

## controller 验证

VPN 启动后，可通过 hdc 端口转发验证 mihomo controller 与 HTTP 代理：

```bash
HDC=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc
SERIAL=<device-serial>

$HDC -t "$SERIAL" fport tcp:29092 tcp:9090
$HDC -t "$SERIAL" fport tcp:27890 tcp:7890

curl http://127.0.0.1:29092/version
curl http://127.0.0.1:29092/connections
curl -x http://127.0.0.1:27890 https://www.gstatic.com/generate_204 -I
```

## 当前限制

- 真机 VPN 权限弹窗仍需要系统确认。
- 自动化 UI 验证容易受真机锁屏影响；关键链路以 controller、TUN、HAP 内容和日志验证为主。
- `x86_64` 未接入真实 mihomo 库，模拟器主要用于界面和构建验证。
- DevEco / HarmonyOS SDK 版本差异可能产生 ArkTS deprecation warning，目前不影响构建。

## 相关文档

- [产品规划](docs/harmonyos-product-design.md)
- [界面原型](docs/harmonyos-ui-prototype.md)
- [mihomo native 集成计划](docs/mihomo-native-integration-plan.md)

## 常用命令

```bash
# 构建
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p module=entry@default -p product=default

# HAP 内容校验
node tests/verify-hap-contents.mjs entry/build/default/outputs/default/entry-default-signed.hap

# 真机安装
HDC=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc
$HDC list targets
$HDC -t <device-serial> install -r entry/build/default/outputs/default/entry-default-signed.hap
```
