import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const indexSource = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/Index.ets'), 'utf8');
const subscriptionSource = fs.readFileSync(path.join(root, 'entry/src/main/ets/services/SubscriptionService.ets'), 'utf8');
const converterSource = fs.readFileSync(path.join(root, 'entry/src/main/ets/services/GenericSubscriptionConverterService.ets'), 'utf8');
const vpnExtensionSource = fs.readFileSync(path.join(root, 'entry/src/main/ets/vpnextensionability/ClashVpnExtensionAbility.ets'), 'utf8');
const vpnServiceSource = fs.readFileSync(path.join(root, 'entry/src/main/ets/services/VpnService.ets'), 'utf8');
const coreBridgeSource = fs.readFileSync(path.join(root, 'entry/src/main/ets/services/CoreBridgeService.ets'), 'utf8');
const localFileImportSource = fs.readFileSync(path.join(root, 'entry/src/main/ets/services/LocalFileImportService.ets'), 'utf8');
const mihomoControllerSource = fs.readFileSync(path.join(root, 'entry/src/main/ets/services/MihomoControllerService.ets'), 'utf8');
const runtimeConfigSource = fs.readFileSync(path.join(root, 'entry/src/main/ets/services/RuntimeConfigService.ets'), 'utf8');
const nativeSource = fs.readFileSync(path.join(root, 'entry/src/main/cpp/napi_init.cpp'), 'utf8');
const nativeTypeSource = fs.readFileSync(path.join(root, 'entry/src/main/cpp/types/libentry/Index.d.ts'), 'utf8');
const adapterHeaderSource = fs.readFileSync(path.join(root, 'entry/src/main/cpp/mihomo_adapter.h'), 'utf8');
const adapterSource = fs.readFileSync(path.join(root, 'entry/src/main/cpp/mihomo_adapter.cpp'), 'utf8');
const cmakeSource = fs.readFileSync(path.join(root, 'entry/src/main/cpp/CMakeLists.txt'), 'utf8');
const abiCheckSource = fs.readFileSync(path.join(root, 'tests/verify-mihomo-prebuilt-abi.mjs'), 'utf8');
const packagingCheckSource = fs.readFileSync(path.join(root, 'tests/verify-mihomo-prebuilt-packaging.mjs'), 'utf8');
const nativeAdapterTestSource = fs.readFileSync(path.join(root, 'tests/mihomo-adapter-native.test.mjs'), 'utf8');
const fakePrebuiltHapCheckSource = fs.readFileSync(path.join(root, 'tests/verify-fake-mihomo-prebuilt-hap.mjs'), 'utf8');
const hapContentsCheckSource = fs.readFileSync(path.join(root, 'tests/verify-hap-contents.mjs'), 'utf8');
const deviceMihomoCheckSource = fs.readFileSync(path.join(root, 'tests/verify-device-mihomo.mjs'), 'utf8');
const moduleSource = fs.readFileSync(path.join(root, 'entry/src/main/module.json5'), 'utf8');
const homePageSource = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/HomePage.ets'), 'utf8');
const proxyPageSource = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/ProxyPage.ets'), 'utf8');
const profilePageSource = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/ProfilePage.ets'), 'utf8');
const diagnosticsPageSource = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/DiagnosticsPage.ets'), 'utf8');
const enhanceServiceSource = fs.readFileSync(path.join(root, 'entry/src/main/ets/services/EnhanceService.ets'), 'utf8');
const runtimeVersionServiceSource = fs.readFileSync(path.join(root, 'entry/src/main/ets/services/RuntimeConfigVersionService.ets'), 'utf8');
const trafficPollerSource = fs.readFileSync(path.join(root, 'entry/src/main/ets/services/TrafficPollerService.ets'), 'utf8');
const tunForwarderSource = fs.readFileSync(path.join(root, 'entry/src/main/cpp/tun_forwarder.cpp'), 'utf8');

// Index.ets shell assertions (orchestration logic still in Index)
assert.match(indexSource, /private async prepareRuntimeForConnection/);
assert.match(indexSource, /import \{ hilog \} from '@kit\.PerformanceAnalysisKit'/);
assert.match(indexSource, /current\.type === 'remote' && current\.filePath\.length === 0/);
assert.match(indexSource, /SubscriptionService\.updateProfile\(context, current\.uid\)/);
assert.match(indexSource, /import \{ CoreBridgeService, CoreBridgeState \}/);
assert.match(indexSource, /coreBridgeState: CoreBridgeState/);
assert.match(indexSource, /MihomoControllerService\.waitForVersion\(/);
assert.match(indexSource, /CoreBridgeService\.markControllerReady\(true, controllerReady\.version\)/);
assert.match(indexSource, /CoreBridgeService\.markControllerReady\(false, ''\)/);
assert.match(indexSource, /CoreBridgeService\.markControllerReady\(status\.available, status\.version\)/);
assert.match(indexSource, /TrafficPollerService\.stop/);
assert.match(indexSource, /resumeRuntimeIfControllerAvailable/);
assert.match(indexSource, /handleRuntimeUnavailable/);
assert.match(indexSource, /startHomeRefreshLoop/);
assert.match(indexSource, /refreshLiveRuntimeSnapshot/);
assert.match(indexSource, /readJsonNumber\(connectionsResult\.raw, 'downloadTotal'\)/);
assert.match(indexSource, /readJsonNumber\(connectionsResult\.raw, 'uploadTotal'\)/);
assert.match(indexSource, /liveRefreshToken/);
assert.match(indexSource, /已连接 · \$\{version\} · \$\{connections\.length\} 连接/);
assert.match(indexSource, /Text\(this\.modeLabel\(this\.proxyMode\)\)/);
assert.match(indexSource, /Text\(this\.liveProfileName\)/);
assert.match(indexSource, /Text\(this\.liveProxyName\)/);
assert.match(indexSource, /this\.StatusLine\('实时流量'/);
assert.match(indexSource, /LocalFileImportService\.pickAndImport/);
assert.match(indexSource, /proxySearchText/);
assert.match(indexSource, /refreshControllerProxies/);
assert.match(indexSource, /selectProxyNode/);
assert.match(indexSource, /MihomoControllerService\.selectProxy/);
assert.match(indexSource, /getVisibleProxyNodeIndexes/);
assert.match(indexSource, /getAllProxyNodeIndexes/);
assert.match(indexSource, /ensureControllerReadyForProxyActions/);
assert.match(indexSource, /CoreBridgeService\.startCore\(runtime\.configPath\)/);
assert.match(indexSource, /CoreBridgeService\.stopCore\(\)/);
assert.match(indexSource, /restoreProxySelection/);
assert.match(indexSource, /targetIndexes\.length/);
assert.match(indexSource, /measureProxyNodeDelay/);

const ensureControllerReadyBlock = indexSource.match(/private async ensureControllerReadyForProxyActions\(action: string\): Promise<boolean> \{[\s\S]*?\n  \}/);
assert.ok(ensureControllerReadyBlock, 'ensureControllerReadyForProxyActions should exist');
const ensureControllerReadySource = ensureControllerReadyBlock[0];
assert.match(ensureControllerReadySource, /if \(this\.isRuntimeConnected\(\)\)/);
assert.match(ensureControllerReadySource, /this\.statusMessage = `\$\{action\}：正在准备运行配置\.\.\.`;/);
assert.match(ensureControllerReadySource, /this\.statusMessage = `\$\{action\}：正在启动测速核心\.\.\.`;/);
assert.match(ensureControllerReadySource, /this\.coreBridgeState = CoreBridgeService\.startCore\(runtime\.configPath\);/);
assert.match(ensureControllerReadySource, /!this\.coreBridgeState\.running \|\| !this\.coreBridgeState\.controllerOnly/);
assert.match(ensureControllerReadySource, /MihomoControllerService\.waitForVersion\(10,\s*500\)/);
assert.match(ensureControllerReadySource, /await MihomoControllerService\.setMode\(this\.normalizeProxyMode\(this\.proxyMode\)\);/);
assert.match(ensureControllerReadySource, /await this\.refreshControllerProxies\(\);/);
assert.ok(
  ensureControllerReadySource.indexOf('CoreBridgeService.startCore(runtime.configPath)') >
    ensureControllerReadySource.indexOf('if (this.isRuntimeConnected())'),
  'unconnected proxy actions should fall through to controller-only startCore instead of requiring VPN'
);

const changeProxyModeBlock = indexSource.match(/private async changeProxyMode\(mode: 'rule' \| 'global' \| 'direct'\): Promise<void> \{[\s\S]*?\n  \}/);
assert.ok(changeProxyModeBlock, 'changeProxyMode should exist');
const changeProxyModeSource = changeProxyModeBlock[0];
assert.match(changeProxyModeSource, /this\.proxyMode = mode;/);
assert.match(changeProxyModeSource, /this\.controllerStatus\.available \|\| this\.coreBridgeState\.controllerReady \|\| this\.proxyGroupsSynced/);
assert.match(changeProxyModeSource, /连接或测速启动核心后生效/);
assert.ok(
  changeProxyModeSource.indexOf('this.proxyMode = mode;') <
    changeProxyModeSource.indexOf('MihomoControllerService.setMode(mode)'),
  'mode changes should update local selection before waiting on the controller'
);

const refreshProxyNodesBlock = indexSource.match(/private async refreshProxyNodes\(state\?: ProfileState\): Promise<void> \{[\s\S]*?\n  \}/);
assert.ok(refreshProxyNodesBlock, 'refreshProxyNodes should exist');
const refreshProxyNodesSource = refreshProxyNodesBlock[0];
assert.match(refreshProxyNodesSource, /for \(let index = 0; index < parsed\.nodes\.length; index\+\+\)/);
assert.doesNotMatch(refreshProxyNodesSource, /slice\(0,\s*\d+\)|parsed\.nodes\.length > \d+|limit/);

const proxyModeOptionBlock = indexSource.match(/private ProxyModeOption\(text: string, mode: 'rule' \| 'global' \| 'direct'\) \{[\s\S]*?\n  \}/);
assert.ok(proxyModeOptionBlock, 'ProxyModeOption should exist');
const proxyModeOptionSource = proxyModeOptionBlock[0];
assert.match(proxyModeOptionSource, /this\.proxyMode === mode/);
assert.match(proxyModeOptionSource, /\.onClick\(\(\) => \{ this\.changeProxyMode\(mode\) \}\)/);

const proxyScreenBlock = indexSource.match(/private ProxyScreen\(\) \{[\s\S]*?\n  \}/);
assert.ok(proxyScreenBlock, 'ProxyScreen should exist');
const proxyScreenSource = proxyScreenBlock[0];
assert.match(proxyScreenSource, /`节点列表 · \$\{this\.getVisibleProxyNodes\(\)\.length\}\/\$\{this\.proxyNodes\.length\}`/);
assert.match(proxyScreenSource, /Text\(this\.isSpeedTesting \? '测速中' : '测速'\)/);
assert.match(proxyScreenSource, /backgroundColor\(this\.isSpeedTesting \? '#64748B' : '#2563EB'\)/);
assert.match(proxyScreenSource, /if \(this\.speedTestProgress\.length > 0\)/);
assert.match(proxyScreenSource, /ForEach\(this\.getVisibleProxyNodes\(\),/);
assert.doesNotMatch(proxyScreenSource, /getVisibleProxyNodes\(\)\.slice|slice\(0,\s*\d+\)|this\.proxyNodes\.length > \d+/);

const runRealSpeedTestBlock = indexSource.match(/private async runRealSpeedTest\(\): Promise<void> \{[\s\S]*?\n  \}/);
assert.ok(runRealSpeedTestBlock, 'runRealSpeedTest should exist');
const runRealSpeedTestSource = runRealSpeedTestBlock[0];
assert.match(indexSource, /\.onClick\(async \(\) => \{ await this\.runRealSpeedTest\(\) \}\)/);
assert.match(runRealSpeedTestSource, /if \(this\.isSpeedTesting\) \{[\s\S]*?return;/);
assert.match(runRealSpeedTestSource, /let targetIndexes: number\[\] = this\.getAllProxyNodeIndexes\(\);/);
assert.doesNotMatch(runRealSpeedTestSource, /getVisibleProxyNodeIndexes\(\)/);
assert.match(runRealSpeedTestSource, /ensureControllerReadyForProxyActions\('测速'\)/);
assert.match(runRealSpeedTestSource, /targetIndexes\.length === 0/);
assert.match(runRealSpeedTestSource, /this\.isSpeedTesting = true;/);
assert.match(runRealSpeedTestSource, /finally \{[\s\S]*?this\.isSpeedTesting = false;/);
assert.match(runRealSpeedTestSource, /准备测速核心/);
assert.match(runRealSpeedTestSource, /this\.speedTestProgress = `测速中 0\/\$\{targetIndexes\.length\} · 0 可达`;/);
assert.match(runRealSpeedTestSource, /this\.updateProxyNodeDelay\(nodeIndex, node\.name, '测试中\.\.\.', 'testing'\);/);
assert.match(runRealSpeedTestSource, /tasks\.push\(this\.measureProxyNodeDelay\(this\.proxyNodes\[nodeIndex\]\)\);/);
assert.match(runRealSpeedTestSource, /this\.speedTestProgress = '测速中 ' \+ tested \+ '\/' \+ targetIndexes\.length/);
assert.doesNotMatch(runRealSpeedTestSource, /slice\(0,\s*8\)|targetIndexes\.length > 8|parsed\.nodes\.length > 8/);

const measureProxyNodeDelayBlock = indexSource.match(/private async measureProxyNodeDelay\(node: ProxyNode\): Promise<number> \{[\s\S]*?\n  \}/);
assert.ok(measureProxyNodeDelayBlock, 'measureProxyNodeDelay should exist');
const measureProxyNodeDelaySource = measureProxyNodeDelayBlock[0];
assert.match(measureProxyNodeDelaySource, /if \(!this\.controllerStatus\.available && !this\.coreBridgeState\.controllerReady\) \{[\s\S]*?return -1;/);
assert.doesNotMatch(measureProxyNodeDelaySource, /this\.summary\.state !== 'running'/);
assert.ok(
  measureProxyNodeDelaySource.indexOf('MihomoControllerService.testDelay(node.name, 5000)') >
    measureProxyNodeDelaySource.indexOf('!this.controllerStatus.available && !this.coreBridgeState.controllerReady'),
  'proxy speed test should call MihomoControllerService.testDelay only after controller is ready'
);
assert.match(measureProxyNodeDelaySource, /MihomoControllerService\.testDelay\(node\.name,\s*5000\)/);
assert.doesNotMatch(measureProxyNodeDelaySource, /TcpDelayTestService\.testNode\(/);
assert.doesNotMatch(indexSource, /TcpDelayTestService\.testNode\(/);

const speedTestBlockedStateBlock = indexSource.match(/private getSpeedTestBlockedState\(targetCount: number\): SpeedTestBlockedState \| undefined \{[\s\S]*?\n  \}/);
assert.ok(speedTestBlockedStateBlock, 'getSpeedTestBlockedState should exist');
const speedTestBlockedStateSource = speedTestBlockedStateBlock[0];
assert.match(speedTestBlockedStateSource, /if \(!this\.controllerStatus\.available && !this\.coreBridgeState\.controllerReady\)/);
assert.doesNotMatch(speedTestBlockedStateSource, /this\.summary\.state !== 'running'/);
assert.doesNotMatch(speedTestBlockedStateSource, /!this\.proxyGroupsSynced \|\| this\.proxyGroups\.length === 0/);
assert.doesNotMatch(speedTestBlockedStateSource, /nodeDelay:\s*'timeout'|nodeStatus:\s*'dead'/);

assert.match(indexSource, /\$\{node\.name\}-\$\{node\.delay\}-\$\{node\.status \? node\.status : ''\}/);
assert.doesNotMatch(indexSource, /parsed\.nodes\.length > 8 \? 8 : parsed\.nodes\.length/);
assert.match(indexSource, /DiagnosticsConnectionSegment/);
assert.match(indexSource, /DiagnosticsLogSegment/);
assert.match(indexSource, /DiagnosticsRulesSegment/);
assert.match(indexSource, /DiagnosticsDnsSegment/);
assert.match(indexSource, /MihomoControllerService\.getRules/);
assert.match(indexSource, /MihomoControllerService\.getConfig/);
assert.match(indexSource, /MihomoControllerService\.closeAllConnections/);
assert.match(indexSource, /核心未响应/);
assert.match(indexSource, /await VpnService\.stop\(\)/);
assert.match(indexSource, /CoreBridgeService\.getState\(\)/);
// Monolithic Index.ets — no page component imports needed

// Monolithic Index.ets — Native Bridge section inline

const runtimeFailureBlock = indexSource.match(/if \(!runtime\.ok\) \{[\s\S]*?return;\n    \}/);
assert.ok(runtimeFailureBlock, 'runtime failure block should exist');
assert.ok(
  !runtimeFailureBlock[0].includes("this.currentTab = 'profiles'"),
  'connection runtime failures should not bounce the user to Profiles'
);

// Verify toggleVpn has key operations in correct order
assert.match(indexSource, /VpnService\.start\(runtime\.configPath\)/);
assert.match(indexSource, /VpnService\.stop\(\)/);
assert.match(indexSource, /MihomoControllerService\.waitForVersion\(/);
assert.match(indexSource, /CoreBridgeService\.markControllerReady\(true,/);
assert.match(indexSource, /CoreBridgeService\.markControllerReady\(false,/);
assert.match(indexSource, /CoreService\.createSummary\(this\.profileState, true\)/);
assert.match(indexSource, /toggling = false/);
assert.match(indexSource, /toggling = true/);

// Monolithic Index.ets — all UI inline

// Index.ets business logic assertions
assert.match(indexSource, /已保存订阅：\$\{name\}，正在下载/);

// New service assertions
assert.match(enhanceServiceSource, /applyMerge/);
assert.match(enhanceServiceSource, /applyRules/);
assert.match(enhanceServiceSource, /applyProxies/);
assert.match(enhanceServiceSource, /applyGroups/);
assert.match(runtimeVersionServiceSource, /prepare/);
assert.match(runtimeVersionServiceSource, /activate/);
assert.match(runtimeVersionServiceSource, /rollback/);
assert.match(runtimeVersionServiceSource, /confirmGood/);
assert.match(trafficPollerSource, /start\(callback/);
assert.match(trafficPollerSource, /stop\(\)/);
assert.match(trafficPollerSource, /downloadTotal/);
assert.match(trafficPollerSource, /uploadTotal/);
assert.match(trafficPollerSource, /controllerAvailable/);
assert.match(trafficPollerSource, /hasBaseline/);
assert.match(localFileImportSource, /picker\.DocumentViewPicker/);
assert.match(localFileImportSource, /fileIo\.readText\(uri\)/);
assert.match(localFileImportSource, /importFromContent\(context, content, uri\)/);

// TunForwarder C++ assertions
assert.match(tunForwarderSource, /TunForwarder/);
assert.match(tunForwarderSource, /WorkerLoop/);
assert.match(tunForwarderSource, /ForwarderStats/);
assert.match(tunForwarderSource, /read\(m_tunFd/);
assert.match(tunForwarderSource, /write\(m_tunFd/);
assert.match(subscriptionSource, /GenericSubscriptionConverterService\.normalizeToClashYaml\(payload\.text\)/);
assert.match(subscriptionSource, /订阅已转换/);
assert.match(converterSource, /simple-obfs/);
assert.match(converterSource, /plugin-opts:/);
assert.match(converterSource, /MATCH,Proxy/);
assert.match(converterSource, /findHostPortSeparator/);
assert.match(converterSource, /cleanHost/);
assert.match(converterSource, /BASIC_URL_SAFE/);
assert.match(vpnServiceSource, /startVpnExtensionAbility\(createVpnWant\(configPath\)\)/);
assert.match(vpnServiceSource, /stopVpnExtensionAbility\(createVpnWant\(\)\)/);
assert.match(vpnServiceSource, /protectSocket/);
assert.match(vpnServiceSource, /nativeCore\.protectSocket/);
assert.match(vpnExtensionSource, /CoreBridgeService\.startTun\(this\.configPath, this\.tunFd\)/);
assert.match(vpnExtensionSource, /this\.connection\.protectProcessNet\(\)/);
assert.match(vpnExtensionSource, /VPN process network protected for native core outbound sockets/);
assert.match(vpnExtensionSource, /CoreBridgeService\.stopTun\(\)/);
assert.match(vpnExtensionSource, /Native core bridge started: mode=/);
assert.match(vpnExtensionSource, /adapterVersion=%\{public\}s nativeFd=%\{public\}d/);
assert.match(vpnExtensionSource, /Native core bridge stopped: mode=/);
assert.match(vpnExtensionSource, /stopCount=%\{public\}d/);
assert.match(vpnExtensionSource, /address: '0\.0\.0\.0'/);
assert.match(vpnExtensionSource, /prefixLength: 0/);
assert.match(vpnExtensionSource, /isDefaultRoute: true/);
assert.match(vpnExtensionSource, /isIPv6Accepted: false/);
assert.match(runtimeConfigSource, /connection\.getAddressesByName\(host\)/);
assert.match(runtimeConfigSource, /collectProxyServerHosts/);
assert.match(runtimeConfigSource, /buildHostsBlock/);
assert.match(runtimeConfigSource, /'  use-hosts: true'/);
assert.match(coreBridgeSource, /import nativeCore from 'libentry\.so'/);
assert.match(coreBridgeSource, /nativeFd: number/);
assert.match(coreBridgeSource, /coreMode: string/);
assert.match(coreBridgeSource, /adapterMode: string/);
assert.match(coreBridgeSource, /adapterKind: string/);
assert.match(coreBridgeSource, /adapterInfo: string/);
assert.match(coreBridgeSource, /controllerOnly: boolean/);
assert.match(coreBridgeSource, /supportsControllerOnly: boolean/);
assert.match(coreBridgeSource, /realConnectionReady: boolean/);
assert.match(coreBridgeSource, /adapterLoadError: string/);
assert.match(coreBridgeSource, /adapterVersion: string/);
assert.match(coreBridgeSource, /controllerVersion: string/);
assert.match(coreBridgeSource, /version: string/);
assert.match(coreBridgeSource, /controllerReady: boolean/);
assert.match(coreBridgeSource, /let lastKnownState: CoreBridgeState/);
assert.match(coreBridgeSource, /function normalizeState\(state: CoreBridgeState\): CoreBridgeState/);
assert.match(coreBridgeSource, /state\.adapterVersion \? state\.adapterVersion : \(!state\.controllerReady \? state\.version : ''\)/);
assert.match(coreBridgeSource, /state\.controllerVersion \? state\.controllerVersion : \(state\.controllerReady \? state\.version : ''\)/);
assert.match(coreBridgeSource, /function rememberState\(state: CoreBridgeState\): CoreBridgeState/);
assert.match(coreBridgeSource, /lastKnownState = normalizeState\(state\)/);
assert.match(coreBridgeSource, /return lastKnownState/);
assert.match(coreBridgeSource, /function fallbackControllerMarkState\(ready: boolean, version: string, error: string\): CoreBridgeState/);
assert.match(coreBridgeSource, /effectiveReady: boolean = ready/);
assert.match(coreBridgeSource, /static markControllerReady\(ready: boolean, version: string\): CoreBridgeState/);
assert.match(coreBridgeSource, /nativeCore\.setControllerReady\(ready, version\)/);
assert.match(coreBridgeSource, /static startCore\(configPath: string\): CoreBridgeState/);
assert.match(coreBridgeSource, /nativeCore\.startCore\(configPath\)/);
assert.match(coreBridgeSource, /static stopCore\(\): CoreBridgeState/);
assert.match(coreBridgeSource, /nativeCore\.stopCore\(\)/);
assert.match(coreBridgeSource, /adapterVersion: lastKnownState\.adapterVersion/);
assert.match(coreBridgeSource, /controllerVersion: effectiveReady \? version : ''/);
assert.match(mihomoControllerSource, /usingProxy: false/);
assert.match(mihomoControllerSource, /http:\/\/127\.0\.0\.1:9090/);
assert.doesNotMatch(mihomoControllerSource, /static async setMode[\s\S]*?return false;/);
assert.match(mihomoControllerSource, /static async waitForVersion\(maxAttempts: number = 10, intervalMs: number = 300\)/);
assert.match(mihomoControllerSource, /await MihomoControllerService\.sleep\(intervalMs\)/);
assert.match(mihomoControllerSource, /setTimeout\(resolve, durationMs\)/);
assert.match(mihomoControllerSource, /PATCH_METHOD[\s\S]*?['"]PATCH['"]/);
assert.match(mihomoControllerSource, /requestText\(\s*['"]\/configs['"],\s*PATCH_METHOD,/);
assert.match(mihomoControllerSource, /JSON\.stringify\(\{\s*mode: mode\s*\}\)/);
assert.match(mihomoControllerSource, /static async getConfig\(\)/);
assert.match(mihomoControllerSource, /requestText\(\s*['"]\/configs['"],\s*http\.RequestMethod\.GET,/);
assert.match(mihomoControllerSource, /static async getProxies\(\)/);
assert.match(mihomoControllerSource, /requestText\(\s*['"]\/proxies['"],\s*http\.RequestMethod\.GET,/);
assert.match(mihomoControllerSource, /static async selectProxy\(groupName: string, proxyName: string\)/);
assert.match(mihomoControllerSource, /http\.RequestMethod\.PUT/);
assert.match(mihomoControllerSource, /JSON\.stringify\(\{\s*name: proxyName\s*\}\)/);
assert.match(mihomoControllerSource, /static async testDelay/);
assert.match(mihomoControllerSource, /\/delay\?timeout=/);
assert.match(mihomoControllerSource, /static async getConnections\(\)/);
assert.match(mihomoControllerSource, /requestText\(\s*['"]\/connections['"],\s*http\.RequestMethod\.GET,/);
assert.match(mihomoControllerSource, /static async closeAllConnections\(\)/);
assert.match(mihomoControllerSource, /static async closeConnection\(id: string\)/);
assert.match(mihomoControllerSource, /static async getRules\(\)/);
assert.match(mihomoControllerSource, /static parseConnections\(raw: string\): ConnectionInfo/);
assert.match(mihomoControllerSource, /static parseProxyGroups\(raw: string\): ProxyGroupInfo/);
assert.match(mihomoControllerSource, /ConnectionInfo/);
assert.match(mihomoControllerSource, /ProxyGroupInfo/);
assert.match(mihomoControllerSource, /requestText\(\s*['"]\/connections['"],\s*http\.RequestMethod\.DELETE,/);
assert.match(nativeSource, /"startTun"/);
assert.match(nativeSource, /"stopTun"/);
assert.match(nativeSource, /"startCore"/);
assert.match(nativeSource, /"stopCore"/);
assert.match(nativeSource, /"setControllerReady"/);
assert.match(nativeSource, /"getState"/);
assert.match(nativeSource, /invalid configPath or tunFd/);
assert.match(nativeSource, /invalid controllerReady or version/);
assert.match(nativeSource, /#include <unistd\.h>/);
assert.match(nativeSource, /#include "mihomo_adapter\.h"/);
assert.match(nativeSource, /dup\(tunFd\)/);
assert.match(nativeSource, /MihomoStart\(configPath\.c_str\(\), g_state\.nativeFd\)/);
assert.match(nativeSource, /MihomoStop\(\)/);
assert.match(nativeSource, /MihomoVersion\(\)/);
assert.match(nativeSource, /MihomoLastError\(\)/);
assert.match(nativeSource, /MihomoAdapterMode\(\)/);
assert.match(nativeSource, /MihomoAdapterKind\(\)/);
assert.match(nativeSource, /MihomoAdapterInfo\(\)/);
assert.match(nativeSource, /MihomoSupportsControllerOnly\(\)/);
assert.match(nativeSource, /MihomoStartCore\(configPath\.c_str\(\)\)/);
assert.match(nativeSource, /MihomoAdapterLoadError\(\)/);
assert.match(nativeSource, /napi_get_value_bool\(env, args\[0\], &ready\)/);
assert.match(nativeSource, /!g_state\.running/);
assert.match(nativeSource, /std::string adapterVersion/);
assert.match(nativeSource, /std::string adapterKind/);
assert.match(nativeSource, /bool controllerOnly/);
assert.match(nativeSource, /bool realConnectionReady/);
assert.match(nativeSource, /std::string controllerVersion/);
assert.match(nativeSource, /std::string version/);
assert.match(nativeSource, /"version", snapshot\.version/);
assert.match(nativeSource, /"adapterVersion"/);
assert.match(nativeSource, /"controllerVersion"/);
assert.match(nativeSource, /g_state\.adapterVersion = MihomoVersion\(\)/);
assert.match(nativeSource, /g_state\.version = g_state\.adapterVersion/);
assert.match(nativeSource, /g_state\.controllerReady = true/);
assert.match(nativeSource, /g_state\.controllerReady = false/);
assert.match(nativeSource, /g_state\.controllerVersion = version/);
assert.match(nativeSource, /g_state\.version = version/);
assert.match(nativeSource, /g_state\.version\.clear\(\)/);
assert.match(nativeSource, /g_state\.controllerVersion\.clear\(\)/);
assert.match(nativeSource, /"adapterMode"/);
assert.match(nativeSource, /"adapterLoadError"/);
assert.match(nativeSource, /"mihomo-adapter"/);
assert.match(nativeSource, /close\(g_state\.nativeFd\)/);
assert.match(nativeSource, /"nativeFd"/);
assert.match(nativeSource, /"adapter-stub"/);
assert.match(nativeSource, /"protectSocket"/);
assert.match(nativeSource, /"setProtectCallback"/);
assert.match(nativeSource, /"getForwarderStats"/);
assert.match(nativeTypeSource, /adapterVersion: string;/);
assert.match(nativeTypeSource, /controllerVersion: string;/);
assert.match(nativeTypeSource, /export const setControllerReady/);
assert.match(nativeTypeSource, /packetsRead: number;/);
assert.match(nativeTypeSource, /bytesRead: number;/);
assert.match(nativeTypeSource, /forwarderActive: boolean;/);
assert.match(nativeTypeSource, /protectSocket/);
assert.match(nativeTypeSource, /getForwarderStats/);
assert.match(coreBridgeSource, /packetsRead: number/);
assert.match(coreBridgeSource, /forwarderActive: boolean/);
assert.match(adapterHeaderSource, /int MihomoStart\(const char\* configPath, int tunFd\)/);
assert.match(adapterHeaderSource, /int MihomoStop\(void\)/);
assert.match(adapterHeaderSource, /const char\* MihomoVersion\(void\)/);
assert.match(adapterHeaderSource, /const char\* MihomoLastError\(void\)/);
assert.match(adapterHeaderSource, /const char\* MihomoAdapterMode\(void\)/);
assert.match(adapterHeaderSource, /const char\* MihomoAdapterLoadError\(void\)/);
assert.match(adapterSource, /#include <dlfcn\.h>/);
assert.match(adapterSource, /libmihomo_ohos\.so/);
assert.match(adapterSource, /dlopen\(REAL_ADAPTER_LIBRARY, RTLD_NOW \| RTLD_GLOBAL\)/);
assert.match(adapterSource, /dlsym\(g_realAdapterHandle, name\)/);
assert.match(adapterSource, /bool HasRealAdapterLocked\(\)/);
assert.match(adapterSource, /g_realStart != nullptr && g_realStop != nullptr[\s\S]*g_realVersion != nullptr && g_realLastError != nullptr/);
assert.match(adapterSource, /void ResetRealAdapterLocked\(\)/);
assert.match(adapterSource, /ResetRealAdapterLocked\(\)/);
assert.match(adapterSource, /LoadSymbol\("MihomoStart"\)/);
assert.match(adapterSource, /LoadSymbol\("MihomoStop"\)/);
assert.match(adapterSource, /LoadSymbol\("MihomoVersion"\)/);
assert.match(adapterSource, /LoadSymbol\("MihomoLastError"\)/);
assert.match(adapterSource, /if \(!HasRealAdapterLocked\(\)\)/);
assert.match(adapterSource, /dlclose\(g_realAdapterHandle\)/);
assert.match(adapterSource, /g_realVersion = nullptr/);
assert.match(adapterSource, /g_realLastError = nullptr/);
assert.match(adapterSource, /g_lastError = std::string\("missing symbol "\) \+ name/);
assert.match(adapterSource, /MihomoAdapterMode/);
assert.match(adapterSource, /return "real"/);
assert.match(adapterSource, /return "stub"/);
assert.match(adapterSource, /MihomoAdapterLoadError/);
assert.match(adapterSource, /adapter-stub/);
assert.match(cmakeSource, /add_library\(entry SHARED napi_init\.cpp mihomo_adapter\.cpp tun_forwarder\.cpp socket_protector\.cpp health_monitor\.cpp\)/);
assert.match(cmakeSource, /prebuilt\/\$\{OHOS_ARCH\}\/libmihomo_ohos\.so/, 'CMake should look for the mihomo prebuilt library by OHOS arch');
assert.match(cmakeSource, /file\(GLOB MIHOMO_OHOS_PREBUILT_LIBS/, 'CMake should collect same-ABI mihomo sidecar libraries');
assert.match(cmakeSource, /add_library\(\s*mihomo_ohos\s+(?:SHARED|UNKNOWN)\s+IMPORTED(?:\s+GLOBAL)?\s*\)/, 'CMake should declare mihomo_ohos as an imported target');
assert.match(cmakeSource, /set_target_properties\(\s*mihomo_ohos\s+PROPERTIES[^)]*IMPORTED_LOCATION/, 'CMake should set mihomo_ohos IMPORTED_LOCATION');
assert.doesNotMatch(cmakeSource, /target_link_libraries\(\s*entry\s+PUBLIC[^)]*\bmihomo_ohos\b[^)]*\)/, 'entry must not NEEDED-link mihomo_ohos; adapter loads it with dlopen at runtime');
const entryLinkCalls = Array.from(cmakeSource.matchAll(/target_link_libraries\(\s*entry\b[^)]*\)/g), (match) => match[0]);
assert.ok(
  entryLinkCalls.every((call) => !/\bmihomo_ohos\b/.test(call)),
  'entry must not target_link_libraries mihomo_ohos in any scope; libentry.so must dlopen it at runtime'
);
assert.match(cmakeSource, /add_dependencies\(\s*entry\s+mihomo_ohos\s*\)/, 'fake mihomo target should still build before entry when used');
assert.match(cmakeSource, /LINK_DEPENDS[^)]*MIHOMO_OHOS_PREBUILT_LIB/, 'entry should relink when any mihomo prebuilt bundle library changes');
assert.match(cmakeSource, /add_custom_command\(\s*TARGET\s+entry\s+POST_BUILD/, 'entry should copy the mihomo prebuilt after native build');
assert.match(cmakeSource, /copy_if_different[\s\S]*libmihomo_ohos\.so/, 'CMake should copy libmihomo_ohos.so into the native output directory');
assert.match(cmakeSource, /MIHOMO_OHOS_PREBUILT_LIB_NAME/, 'CMake should copy each prebuilt sidecar library by filename');
assert.match(cmakeSource, /remove -f[\s\S]*libmihomo_ohos\.so/, 'CMake should remove stale mihomo prebuilts when none is configured');
assert.match(cmakeSource, /message\(\s*STATUS[^)]*(?:prebuilt|libmihomo_ohos\.so)[^)]*(?:adapter-stub|stub fallback|stub)[^)]*\)/i, 'CMake should announce adapter-stub fallback when the mihomo prebuilt library is missing');
assert.match(abiCheckSource, /verify-mihomo-prebuilt-abi/);
assert.match(abiCheckSource, /entry\/src\/main\/cpp\/prebuilt/);
assert.match(abiCheckSource, /entry\/build-profile\.json5/);
assert.match(abiCheckSource, /abiFilters/);
assert.match(abiCheckSource, /libmihomo_ohos\.so/);
assert.match(abiCheckSource, /mihomo prebuilt ABI check skipped/);
assert.match(abiCheckSource, /MIHOMO_PREBUILT_ROOT/);
assert.match(abiCheckSource, /OHOS_LLVM_NM/);
assert.match(abiCheckSource, /OHOS_LLVM_READELF/);
assert.match(abiCheckSource, /--require-abi/);
assert.match(abiCheckSource, /MihomoStart/);
assert.match(abiCheckSource, /MihomoStop/);
assert.match(abiCheckSource, /MihomoVersion/);
assert.match(abiCheckSource, /MihomoLastError/);
assert.match(abiCheckSource, /arm64-v8a[\s\S]*EM_AARCH64/);
assert.match(abiCheckSource, /x86_64[\s\S]*EM_X86_64/);
assert.match(abiCheckSource, /ET_DYN/);
assert.match(abiCheckSource, /--dynamic/);
assert.match(abiCheckSource, /--format=just-symbols/);
assert.match(abiCheckSource, /llvm-readelf/);
assert.match(abiCheckSource, /SONAME/);
assert.match(abiCheckSource, /NEEDED/);
assert.match(abiCheckSource, /host\/Linux NEEDED dependencies/);
assert.match(abiCheckSource, /libstdc/);
assert.match(abiCheckSource, /missing symbol/i);
assert.match(packagingCheckSource, /verify-mihomo-prebuilt-packaging/);
assert.match(packagingCheckSource, /--require-abi/);
assert.match(packagingCheckSource, /intermediates\/libs\/default/);
assert.match(packagingCheckSource, /libs\/\$\{abi\}\/\$\{bundledLibraryName\}/);
assert.match(packagingCheckSource, /readPrebuiltLibraries/);
assert.match(packagingCheckSource, /bundledLibraryName/);
assert.match(packagingCheckSource, /libmihomo_exec\.so/);
assert.match(packagingCheckSource, /mihomo exec fallback/);
assert.match(packagingCheckSource, /mihomo prebuilt packaging check skipped/);
assert.match(nativeAdapterTestSource, /mihomo-adapter-native/);
assert.match(nativeAdapterTestSource, /mihomo_adapter\.cpp/);
assert.match(nativeAdapterTestSource, /libmihomo_ohos\.so/);
assert.match(nativeAdapterTestSource, /stub-no-library/);
assert.match(nativeAdapterTestSource, /real-library/);
assert.match(nativeAdapterTestSource, /missing-start-symbol/);
assert.match(nativeAdapterTestSource, /missing-stop-symbol/);
assert.match(nativeAdapterTestSource, /missing-version-symbol/);
assert.match(nativeAdapterTestSource, /missing-last-error-symbol/);
assert.match(nativeAdapterTestSource, /fake-mihomo-1\.0/);
assert.match(nativeAdapterTestSource, /missing symbol MihomoStart/);
assert.match(nativeAdapterTestSource, /missing symbol MihomoStop/);
assert.match(nativeAdapterTestSource, /missing symbol MihomoVersion/);
assert.match(nativeAdapterTestSource, /missing symbol MihomoLastError/);
assert.match(nativeAdapterTestSource, /DYLD_LIBRARY_PATH/);
assert.match(fakePrebuiltHapCheckSource, /verify-fake-mihomo-prebuilt-hap/);
assert.match(fakePrebuiltHapCheckSource, /aarch64-linux-ohos/);
assert.match(fakePrebuiltHapCheckSource, /x86_64-linux-ohos/);
assert.match(fakePrebuiltHapCheckSource, /libmihomo_ohos\.so/);
assert.match(fakePrebuiltHapCheckSource, /MihomoStart/);
assert.match(fakePrebuiltHapCheckSource, /MihomoStop/);
assert.match(fakePrebuiltHapCheckSource, /MihomoVersion/);
assert.match(fakePrebuiltHapCheckSource, /MihomoLastError/);
assert.match(fakePrebuiltHapCheckSource, /refusing to overwrite/);
assert.match(fakePrebuiltHapCheckSource, /verify-mihomo-prebuilt-abi\.mjs/);
assert.match(fakePrebuiltHapCheckSource, /verify-hap-contents\.mjs/);
assert.match(fakePrebuiltHapCheckSource, /clean[\s\S]*assembleHap/);
assert.match(fakePrebuiltHapCheckSource, /assembleHap/);
assert.match(fakePrebuiltHapCheckSource, /verify-mihomo-prebuilt-packaging\.mjs/);
assert.match(fakePrebuiltHapCheckSource, /OHOS_LLVM_READELF/);
assert.match(fakePrebuiltHapCheckSource, /--require-abi/);
assert.match(fakePrebuiltHapCheckSource, /finally/);
assert.match(fakePrebuiltHapCheckSource, /assertDefaultHapRestoredWithoutGeneratedPrebuilt/);
assert.match(fakePrebuiltHapCheckSource, /built-in fake/);
assert.match(hapContentsCheckSource, /verify-hap-contents/);
assert.match(hapContentsCheckSource, /crypto from 'node:crypto'/);
assert.match(hapContentsCheckSource, /os from 'node:os'/);
assert.match(hapContentsCheckSource, /libs\/\$\{abi\}\/libentry\.so/);
assert.match(hapContentsCheckSource, /libs\/\$\{abi\}\/libc\+\+_shared\.so/);
assert.match(hapContentsCheckSource, /Unexpected stale mihomo library/);
assert.match(hapContentsCheckSource, /fakeMihomoSourcePath/);
assert.match(hapContentsCheckSource, /built-in fake mihomo adapter/);
assert.match(hapContentsCheckSource, /Mihomo prebuilt hash mismatch/);
assert.match(hapContentsCheckSource, /Mihomo HAP hash mismatch/);
assert.match(hapContentsCheckSource, /readPrebuiltLibraries/);
assert.match(hapContentsCheckSource, /mihomoPrebuiltBundle/);
assert.match(hapContentsCheckSource, /libmihomo_exec\.so/);
assert.match(hapContentsCheckSource, /mihomoExecFallbackHapEntry/);
assert.match(hapContentsCheckSource, /--require-abi/);
assert.match(hapContentsCheckSource, /--evidence-dir/);
assert.match(hapContentsCheckSource, /OHOS_LLVM_READELF/);
assert.match(hapContentsCheckSource, /llvm-readelf/);
assert.match(hapContentsCheckSource, /verifyNativeDependencyClosure/);
assert.match(hapContentsCheckSource, /readDynamicValues\(dynamicOutput, 'NEEDED'\)/);
assert.match(hapContentsCheckSource, /libentry\.so must dlopen/);
assert.match(hapContentsCheckSource, /allowExecutableWithoutDynamicSection/);
assert.match(hapContentsCheckSource, /libs\/\$\{abi\}\/\$\{dependency\}/);
assert.match(hapContentsCheckSource, /host\/Linux NEEDED dependencies/);
assert.match(hapContentsCheckSource, /missing non-system NEEDED dependencies/);
assert.match(hapContentsCheckSource, /libc\+\+_shared\.so/);
assert.match(hapContentsCheckSource, /libace_napi\.z\.so/);
assert.match(hapContentsCheckSource, /summary\.json/);
assert.match(hapContentsCheckSource, /hap-entries\.txt/);
assert.match(hapContentsCheckSource, /hashes\.json/);
assert.match(hapContentsCheckSource, /dependencies\.json/);
assert.match(hapContentsCheckSource, /dependencyClosure/);
assert.match(hapContentsCheckSource, /bundleName/);
assert.match(hapContentsCheckSource, /ClashVpnExtensionAbility/);
assert.match(hapContentsCheckSource, /ohos\.permission\.INTERNET/);
assert.match(deviceMihomoCheckSource, /verify-device-mihomo/);
assert.match(deviceMihomoCheckSource, /crypto from 'node:crypto'/);
assert.match(deviceMihomoCheckSource, /libmihomo_ohos\.so/);
assert.match(deviceMihomoCheckSource, /--allow-no-device/);
assert.match(deviceMihomoCheckSource, /--allow-stub/);
assert.match(deviceMihomoCheckSource, /--evidence-dir/);
assert.match(deviceMihomoCheckSource, /--controller-port/);
assert.match(deviceMihomoCheckSource, /--require-stop/);
assert.match(deviceMihomoCheckSource, /--min-cycles/);
assert.match(deviceMihomoCheckSource, /--cycles/);
assert.match(deviceMihomoCheckSource, /hdc/);
assert.match(deviceMihomoCheckSource, /list', 'targets'/);
assert.match(deviceMihomoCheckSource, /install', '-r'/);
assert.match(deviceMihomoCheckSource, /aa', 'start'/);
assert.match(deviceMihomoCheckSource, /const\.product\.cpu\.abilist/);
assert.match(deviceMihomoCheckSource, /const\.product\.software\.version/);
assert.match(deviceMihomoCheckSource, /device ABI list does not match packaged mihomo prebuilt ABI/);
assert.match(deviceMihomoCheckSource, /VPN TUN created, fd=\\d\+/);
assert.match(deviceMihomoCheckSource, /Native core bridge started: mode=/);
assert.match(deviceMihomoCheckSource, /Controller ready: controllerVersion=/);
assert.match(deviceMihomoCheckSource, /probeControllerVersion/);
assert.match(deviceMihomoCheckSource, /controller-version\.json/);
assert.match(deviceMihomoCheckSource, /hilog\.raw\.log/);
assert.match(deviceMihomoCheckSource, /hilog\.relevant\.log/);
assert.match(deviceMihomoCheckSource, /lifecycle\.json/);
assert.match(deviceMihomoCheckSource, /summary\.json/);
assert.match(deviceMihomoCheckSource, /hashes\.json/);
assert.match(deviceMihomoCheckSource, /assertStopEvidence/);
assert.match(deviceMihomoCheckSource, /assertCycleEvidence/);
assert.match(deviceMihomoCheckSource, /assertNoFailureLines/);
assert.match(deviceMihomoCheckSource, /assertRealAdapterEvidence/);
assert.match(deviceMihomoCheckSource, /buildLifecycleCycles/);
assert.match(deviceMihomoCheckSource, /adapterVersion/);
assert.match(deviceMihomoCheckSource, /controllerVersion/);
assert.match(moduleSource, /"type": "vpn"/);
assert.match(moduleSource, /"ohos\.permission\.INTERNET"/);

const yaml = `
mixed-port: 8888
allow-lan: true
ipv6: true
mode: global
external-controller: 0.0.0.0:9090
hosts:
  old.example.com: 192.0.2.1
dns:
  enable: false
  nameserver:
    - 1.1.1.1
proxies:
  - name: "JP-01"
    type: trojan
    server: node.example.com
    udp: true
  - { name: HK-02, type: ss, server: inline.example.com, udp: false }
proxy-groups:
  - name: Auto
    type: select
    proxies:
      - JP-01
      - HK-02
rules:
  - MATCH,Auto
`;

const nodes = parseProxyNodes(yaml);
assert.deepEqual(nodes, [
  { name: 'JP-01', type: 'trojan', udp: true },
  { name: 'HK-02', type: 'ss', udp: false }
]);

const runtime = normalize(yaml, new Map([
  ['node.example.com', '203.0.113.10'],
  ['inline.example.com', '203.0.113.11']
]));
assert.ok(!runtime.includes('mixed-port: 8888'));
assert.ok(!runtime.includes('allow-lan: true'));
assert.ok(!runtime.includes('ipv6: true'));
assert.ok(!runtime.includes('mode: global'));
assert.ok(!runtime.includes('external-controller: 0.0.0.0:9090'));
assert.ok(!runtime.includes('old.example.com: 192.0.2.1'));
assert.ok(!runtime.includes('enable: false'));
assert.ok(!runtime.includes('    - 1.1.1.1'));
assert.ok(runtime.includes('mixed-port: 7890'));
assert.ok(runtime.includes('allow-lan: false'));
assert.ok(runtime.includes('ipv6: false'));
assert.ok(runtime.includes('mode: rule'));
assert.ok(runtime.includes('external-controller: 127.0.0.1:9090'));
assert.ok(runtime.includes('hosts:\n  \'node.example.com\': \'203.0.113.10\''));
assert.ok(runtime.includes('  \'inline.example.com\': \'203.0.113.11\''));
assert.ok(runtime.includes('dns:\n  enable: true'));
assert.ok(runtime.includes('  use-hosts: true'));
assert.ok(runtime.includes('  enhanced-mode: redir-host'));
assert.ok(runtime.includes('  proxy-server-nameserver:'));
assert.ok(runtime.includes('proxy-groups:'));

const nestedManagedKeysYaml = `
proxies:
  - name: "Nested"
    type: ss
    udp: true
    plugin-opts:
      mode: websocket
      external-controller: preserved.example
rules:
  - MATCH,Nested
`;
const nestedRuntime = normalize(nestedManagedKeysYaml);
assert.ok(nestedRuntime.includes('      mode: websocket'));
assert.ok(nestedRuntime.includes('      external-controller: preserved.example'));
assert.ok(nestedRuntime.includes('mode: rule'));
assert.ok(nestedRuntime.includes('external-controller: 127.0.0.1:9090'));

const ssFixture = [
  "ss://YWVzLTEyOC1nY206cGFzc0BleGFtcGxlLmNvbTo4NDQz?plugin=simple-obfs%3Bobfs%3Dhttp%3Bobfs-host%3Dedge.example.com#Demo"
].join('\n');
const ssYaml = convertFixtureSsSubscription(ssFixture);
assert.ok(ssYaml.includes("name: 'Demo'"));
assert.ok(ssYaml.includes("type: ss"));
assert.ok(ssYaml.includes("cipher: 'aes-128-gcm'"));
assert.ok(ssYaml.includes("plugin: 'obfs'"));
assert.ok(ssYaml.includes("mode: 'http'"));
assert.ok(ssYaml.includes("host: 'edge.example.com'"));

const encodedSsFixture = Buffer.from(ssFixture, 'utf8').toString('base64url');
const encodedSsYaml = convertFixtureSsSubscription(encodedSsFixture);
assert.ok(encodedSsYaml.includes("name: 'Demo'"));
assert.ok(encodedSsYaml.includes("type: ss"));

console.log('app-flow fixtures passed');

function parseProxyNodes(text) {
  const lines = text.split('\n');
  const nodes = [];
  let inProxies = false;
  let currentName = '';
  let currentType = '';
  let currentUdp = false;

  for (const rawLine of lines) {
    const trimmed = rawLine.trim();
    if (trimmed.length === 0 || trimmed.startsWith('#')) {
      continue;
    }

    if (!rawLine.startsWith(' ') && !rawLine.startsWith('\t')) {
      if (inProxies) {
        pushNode(nodes, currentName, currentType, currentUdp);
        currentName = '';
        currentType = '';
        currentUdp = false;
      }
      inProxies = trimmed === 'proxies:';
      continue;
    }

    if (!inProxies) {
      continue;
    }

    if (trimmed.startsWith('- ')) {
      pushNode(nodes, currentName, currentType, currentUdp);
      currentName = readInlineValue(trimmed, 'name');
      currentType = readInlineValue(trimmed, 'type');
      currentUdp = readInlineValue(trimmed, 'udp') === 'true';
      continue;
    }

    if (currentName.length === 0 && trimmed.startsWith('name:')) {
      currentName = cleanValue(trimmed.substring(5));
    } else if (currentType.length === 0 && trimmed.startsWith('type:')) {
      currentType = cleanValue(trimmed.substring(5));
    } else if (trimmed.startsWith('udp:')) {
      currentUdp = cleanValue(trimmed.substring(4)) === 'true';
    }
  }

  if (inProxies) {
    pushNode(nodes, currentName, currentType, currentUdp);
  }
  return nodes;
}

function pushNode(nodes, name, type, udp) {
  if (name.length === 0) {
    return;
  }
  nodes.push({
    name,
    type: type.length > 0 ? type : 'proxy',
    udp
  });
}

function readInlineValue(line, key) {
  const token = `${key}:`;
  const index = line.indexOf(token);
  if (index < 0) {
    return '';
  }
  let end = line.indexOf(',', index);
  if (end < 0) {
    end = line.length;
  }
  return cleanValue(line.substring(index + token.length, end));
}

function cleanValue(value) {
  let text = value.trim();
  if (text.startsWith('"') && text.endsWith('"') && text.length >= 2) {
    text = text.substring(1, text.length - 1);
  }
  if (text.startsWith("'") && text.endsWith("'") && text.length >= 2) {
    text = text.substring(1, text.length - 1);
  }
  return text;
}

function normalize(text, hostMap = new Map()) {
  const stripped = removeManagedTopLevelKeys(text);
  const base = trimTrailingWhitespace(stripped);
  const hosts = buildHostsBlock(collectProxyServerHosts(stripped), hostMap);
  const managed = [
    'mixed-port: 7890',
    'allow-lan: false',
    'ipv6: false',
    'mode: rule',
    'log-level: info',
    'external-controller: 127.0.0.1:9090',
    'secret: ""'
  ];
  const dns = [
    'dns:',
    '  enable: true',
    '  listen: 127.0.0.1:1053',
    '  ipv6: false',
    '  use-hosts: true',
    '  enhanced-mode: redir-host',
    '  default-nameserver:',
    '    - 223.5.5.5',
    '    - 119.29.29.29',
    '    - 8.8.8.8',
    '  nameserver:',
    '    - 223.5.5.5',
    '    - 119.29.29.29',
    '  proxy-server-nameserver:',
    '    - 223.5.5.5',
    '    - 119.29.29.29'
  ];
  const sections = [base, managed.join('\n'), dns.join('\n')];
  if (hosts.length > 0) {
    sections.splice(1, 0, hosts.join('\n'));
  }
  return `${sections.join('\n\n')}\n`;
}

function collectProxyServerHosts(text) {
  const hosts = [];
  let inProxies = false;
  for (const line of text.split('\n')) {
    const trimmed = line.trim();
    if (trimmed.length === 0 || trimmed.startsWith('#')) continue;
    if (!line.startsWith(' ') && !line.startsWith('\t')) {
      inProxies = trimmed === 'proxies:';
      continue;
    }
    if (!inProxies) continue;
    let host = '';
    if (trimmed.startsWith('server:')) {
      host = cleanValue(trimmed.substring(7));
    } else if (trimmed.startsWith('- {') && trimmed.includes('server:')) {
      host = cleanValue(readInlineValue(trimmed, 'server'));
    }
    if (host.includes('.') && !hosts.includes(host)) hosts.push(host);
  }
  return hosts;
}

function buildHostsBlock(hosts, hostMap) {
  const lines = [];
  for (const host of hosts) {
    const address = hostMap.get(host);
    if (address) {
      lines.push(`  ${yamlString(host)}: ${yamlString(address)}`);
    }
  }
  return lines.length > 0 ? ['hosts:', ...lines] : [];
}

function removeManagedTopLevelKeys(text) {
  const managedKeys = [
    'mixed-port',
    'redir-port',
    'tproxy-port',
    'allow-lan',
    'ipv6',
    'mode',
    'log-level',
    'external-controller',
    'secret'
  ];
  const managedBlockKeys = [
    'dns',
    'hosts'
  ];
  const kept = [];
  let skippingManagedBlock = false;
  for (const line of text.split('\n')) {
    if (skippingManagedBlock) {
      if (!isTopLevelConfigLine(line)) {
        continue;
      }
      skippingManagedBlock = false;
    }
    if (isManagedTopLevelLine(line, managedKeys)) {
      continue;
    }
    if (isManagedTopLevelLine(line, managedBlockKeys)) {
      skippingManagedBlock = true;
      continue;
    }
    kept.push(line);
  }
  return kept.join('\n');
}

function isTopLevelConfigLine(line) {
  if (line.length === 0 || line.startsWith(' ') || line.startsWith('\t') || line.startsWith('#')) {
    return false;
  }
  return line.indexOf(':') > 0;
}

function isManagedTopLevelLine(line, keys) {
  if (line.length === 0 || line.startsWith(' ') || line.startsWith('\t') || line.startsWith('#')) {
    return false;
  }
  const colonIndex = line.indexOf(':');
  if (colonIndex <= 0) {
    return false;
  }
  return keys.includes(line.substring(0, colonIndex).trim());
}

function trimTrailingWhitespace(text) {
  let end = text.length;
  while (end > 0) {
    const char = text.substring(end - 1, end);
    if (char !== '\n' && char !== '\r' && char !== ' ' && char !== '\t') {
      break;
    }
    end--;
  }
  return text.substring(0, end);
}

function convertFixtureSsSubscription(text) {
  const nodes = [];
  const decoded = tryDecodeBase64Fixture(text.trim());
  const candidates = decoded.length > 0 ? [text, decoded] : [text];
  for (const candidate of candidates) {
    for (const line of candidate.split('\n')) {
      const node = parseFixtureSs(line.trim(), nodes.length + 1);
      if (node) nodes.push(node);
    }
    if (nodes.length > 0) break;
  }
  const lines = ['proxies:'];
  for (const node of nodes) {
    lines.push(`  - name: ${yamlString(node.name)}`);
    lines.push('    type: ss');
    lines.push(`    server: ${yamlString(node.server)}`);
    lines.push(`    port: ${node.port}`);
    lines.push(`    cipher: ${yamlString(node.cipher)}`);
    lines.push(`    password: ${yamlString(node.password)}`);
    lines.push(`    plugin: ${yamlString(node.plugin)}`);
    lines.push('    plugin-opts:');
    lines.push(`      mode: ${yamlString(node.pluginMode)}`);
    lines.push(`      host: ${yamlString(node.pluginHost)}`);
  }
  lines.push('rules:');
  lines.push('  - MATCH,Proxy');
  return lines.join('\n');
}

function tryDecodeBase64Fixture(text) {
  const compact = padBase64Fixture(text.replace(/\r/g, '').replace(/\n/g, '').trim());
  if (compact.length < 4 || !/^[A-Za-z0-9+/=_-]+$/.test(compact)) {
    return '';
  }
  try {
    return Buffer.from(compact, 'base64').toString('utf8').trim();
  } catch {
    return '';
  }
}

function padBase64Fixture(text) {
  const remainder = text.length % 4;
  if (remainder === 2) return `${text}==`;
  if (remainder === 3) return `${text}=`;
  return text;
}

function parseFixtureSs(uri, fallbackIndex) {
  if (!uri.startsWith('ss://')) return undefined;
  let body = uri.slice(5);
  let name = `SS-${fallbackIndex}`;
  const hash = body.indexOf('#');
  if (hash >= 0) {
    name = decodeURIComponent(body.slice(hash + 1));
    body = body.slice(0, hash);
  }
  let query = '';
  const q = body.indexOf('?');
  if (q >= 0) {
    query = body.slice(q + 1);
    body = body.slice(0, q);
  }
  const at = body.lastIndexOf('@');
  const userinfo = Buffer.from(body.slice(0, at), 'base64').toString('utf8');
  const hostport = body.slice(at + 1);
  const userColon = userinfo.indexOf(':');
  const hostColon = hostport.lastIndexOf(':');
  const plugin = decodeURIComponent(new URLSearchParams(query).get('plugin') || '');
  const parts = plugin.split(';');
  return {
    name,
    cipher: userinfo.slice(0, userColon),
    password: userinfo.slice(userColon + 1),
    server: hostport.slice(0, hostColon),
    port: Number(hostport.slice(hostColon + 1)),
    plugin: 'obfs',
    pluginMode: (parts.find((part) => part.startsWith('obfs=')) || '').slice(5),
    pluginHost: (parts.find((part) => part.startsWith('obfs-host=')) || '').slice(10)
  };
}

function yamlString(value) {
  return `'${value.replace(/'/g, "''")}'`;
}
