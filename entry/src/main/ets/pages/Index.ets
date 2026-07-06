import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ClashConfigParserService, ParsedConfigSummary, ParsedProxyNode } from '../services/ClashConfigParserService';
import { ClipboardImportResult, ClipboardImportService } from '../services/ClipboardImportService';
import { CoreBridgeService, CoreBridgeState } from '../services/CoreBridgeService';
import { CoreService, CoreSummary } from '../services/CoreService';
import { ClashProfile, createEmptyProfileState, createRemoteProfile, formatProfileUpdatedAt, ProfileState } from '../models/Profile';
import {
  ConnectionInfo as ControllerConnectionInfo,
  ControllerStatus,
  ControllerTextResult,
  MihomoControllerService,
  ProxyGroupInfo
} from '../services/MihomoControllerService';
import { FileImportResult, LocalFileImportService } from '../services/LocalFileImportService';
import { ProfileStore } from '../services/ProfileStore';
import { RuntimeConfigResult, RuntimeConfigService } from '../services/RuntimeConfigService';
import { SubscriptionService, SubscriptionUpdateResult } from '../services/SubscriptionService';
import {
  ConnectionInfo as PollerConnectionInfo,
  TrafficPollerService,
  TrafficSnapshot
} from '../services/TrafficPollerService';
import { VpnService } from '../services/VpnService';
import { TcpDelayTestService } from '../services/TcpDelayTestService';

interface NavItem {
  key: string;
  label: string;
  shortLabel: string;
}

interface ProxyNode {
  name: string;
  meta: string;
  delay: string;
  selected?: boolean;
  status?: string;
  server?: string;
  port?: number;
}

interface SpeedTestBlockedState {
  nodeDelay: string;
  nodeStatus: string;
  statusMessage: string;
  progress: string;
  summary: string;
}

interface RuntimeConnectionRow {
  id: string;
  target: string;
  chain: string;
  rule: string;
  upload: string;
  download: string;
}

interface RuntimeTunStatus {
  ready: boolean;
  message: string;
  raw: string;
  enabled: boolean;
  fileDescriptor: number;
  stack: string;
}

interface AppLogEntry {
  time: string;
  level: string;
  message: string;
}

const NAV_ITEMS: NavItem[] = [
  { key: 'home', label: '首页', shortLabel: 'H' },
  { key: 'proxies', label: '代理', shortLabel: 'P' },
  { key: 'profiles', label: '配置', shortLabel: 'C' },
  { key: 'diagnostics', label: '诊断', shortLabel: 'D' }
];
const LOG_DOMAIN: number = 0x0001;
const LOG_TAG: string = 'ClashHarmonyIndex';

const EMPTY_CORE_BRIDGE_STATE: CoreBridgeState = {
  running: false,
  tunFd: -1,
  nativeFd: -1,
  startCount: 0,
  stopCount: 0,
  controllerReady: false,
  controllerOnly: false,
  tunAttached: false,
  supportsControllerOnly: false,
  supportsTunAttach: false,
  realConnectionReady: false,
  configPath: '',
  coreMode: 'idle',
  adapterMode: 'unloaded',
  adapterKind: 'unknown',
  adapterInfo: '',
  adapterLoadError: '',
  adapterVersion: '',
  controllerVersion: '',
  version: '',
  lastError: '',
  packetsRead: 0,
  packetsWritten: 0,
  bytesRead: 0,
  bytesWritten: 0,
  readErrors: 0,
  writeErrors: 0,
  forwarderActive: false
};

@Entry
@Component
struct Index {
  @State private currentTab: string = 'home';
  @State private showSettings: boolean = false;
  @State private profileState: ProfileState = createEmptyProfileState();
  @State private summary: CoreSummary = CoreService.createSummary(createEmptyProfileState(), false);
  @State private vpnActionText: string = '连接';
  @State private showImportPanel: boolean = false;
  @State private importUrl: string = '';
  @State private importName: string = '';
  @State private statusMessage: string = '请先导入或启用一个配置';
  @State private runtimeConfigPath: string = '';
  @State private runtimeConfigInfo: string = '尚未生成运行配置';
  @State private proxyStatus: string = '当前配置尚未下载';
  @State private proxyNodes: ProxyNode[] = [];
  @State private proxySearchText: string = '';
  @State private proxyGroups: ProxyGroupInfo[] = [];
  @State private proxyGroupsSynced: boolean = false;
  @State private selectedProxyGroup: string = '';
  @State private pendingProxyGroup: string = '';
  @State private pendingProxyName: string = '';
  @State private isSpeedTesting: boolean = false;
  @State private speedTestProgress: string = '';
  @State private speedTestSummary: string = '';
  @State private diagSegment: string = '连接';
  @State private controllerStatus: ControllerStatus = {
    available: false,
    version: '',
    message: '尚未检查 controller',
    raw: ''
  };
  @State private coreBridgeState: CoreBridgeState = EMPTY_CORE_BRIDGE_STATE;
  @State private proxyMode: string = 'rule';
  @State private runtimeConnections: RuntimeConnectionRow[] = [];
  @State private rulesStatus: string = '尚未读取规则';
  @State private ruleLines: string[] = [];
  @State private dnsStatus: string = '尚未读取 DNS 配置';
  @State private dnsLines: string[] = [];
  @State private appLogs: AppLogEntry[] = [];
  @State private liveConnected: boolean = false;
  @State private liveUptime: string = '未连接';
  @State private liveDownloadSpeed: string = '0 KB/s';
  @State private liveUploadSpeed: string = '0 KB/s';
  @State private liveConnections: number = 0;
  @State private liveProfileName: string = '未选择配置';
  @State private liveProxyName: string = '未连接';
  @State private liveRuntimeConfigState: string = '未准备';
  @State private liveRefreshToken: number = 0;
  private connectedAt: number = 0;
  private lastToggleAt: number = 0;
  private toggling: boolean = false;
  private runtimePollTick: number = 0;
  private homeRefreshIntervalId: number | undefined = undefined;
  private homeRefreshInFlight: boolean = false;
  private homeRefreshFailures: number = 0;
  private homeLastDownloadTotal: number = 0;
  private homeLastUploadTotal: number = 0;
  private homeLastPollAt: number = 0;
  private homeTrafficBaselineReady: boolean = false;

  aboutToAppear(): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Index aboutToAppear, loading profiles');
    this.loadProfiles();
    this.startHomeRefreshLoop();
  }

  aboutToDisappear(): void {
    TrafficPollerService.stop();
    this.stopHomeRefreshLoop();
  }

  private async loadProfiles(): Promise<void> {
    const context = getContext(this) as common.Context;
    const state: ProfileState = await ProfileStore.load(context);
    this.runtimeConfigPath = RuntimeConfigService.getRuntimeConfigPath(context);
    this.applyProfileState(state);
    await this.refreshProxyNodes(state);
    await this.resumeRuntimeIfControllerAvailable();
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Profiles loaded: %{public}d items, currentUid=%{public}s',
      state.items.length, state.currentUid);
  }

  private async toggleVpn(): Promise<void> {
    this.toggling = true;
    hilog.info(LOG_DOMAIN, LOG_TAG, 'toggleVpn: start, state=%{public}s', this.summary.state);
    try {
      if (this.isRuntimeConnected()) {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'toggleVpn: stopping');
        TrafficPollerService.stop();
        this.runtimePollTick = 0;
        this.connectedAt = 0;
        this.runtimeConnections = [];
        this.clearControllerProxyGroups();
        this.coreBridgeState = CoreBridgeService.markControllerReady(false, '');
        await VpnService.stop();
        this.summary = CoreService.createSummary(this.profileState, false);
        this.vpnActionText = '连接';
        this.coreBridgeState = CoreBridgeService.getState();
        this.controllerStatus = { available: false, version: '', message: 'VPN 已停止', raw: '' };
        this.statusMessage = 'VPN 已停止';
        this.syncHomeRuntimeFields();
        this.recordLog('info', 'VPN 已停止，运行状态已清理');
        return;
      }

      if (this.profileState.currentUid.length === 0) {
        this.statusMessage = '请先在配置页导入并启用一个配置';
        this.currentTab = 'profiles';
        return;
      }

      const context = getContext(this) as common.Context;
      this.statusMessage = '正在准备运行配置...';
      const runtime: RuntimeConfigResult = await this.prepareRuntimeForConnection(context);
      if (!runtime.ok) {
        this.summary = CoreService.createSummary(this.profileState, false);
        this.statusMessage = runtime.message;
        hilog.error(LOG_DOMAIN, LOG_TAG, 'toggleVpn: runtime failed: %{public}s', runtime.message);
        return;
      }

      this.runtimeConfigPath = runtime.configPath;
      this.runtimeConfigInfo = `${runtime.profileName} · ${runtime.size}`;
      const restoreGroup: string = this.pendingProxyGroup.length > 0 ? this.pendingProxyGroup : this.selectedProxyGroup;
      const selectedNode: string = this.pendingProxyName.length > 0 ? this.pendingProxyName : this.getSelectedProxyNodeName();
      const restoreNode: string = selectedNode.length > 0 ? selectedNode : this.pendingProxyName;
      this.statusMessage = '正在释放本地测速核心，准备启动 VPN...';
      this.coreBridgeState = CoreBridgeService.stopCore();
      this.controllerStatus = { available: false, version: '', message: '本地测速核心已停止', raw: '' };
      await this.waitForUiUpdate(500);
      this.statusMessage = '正在启动 VPN...';

      hilog.info(LOG_DOMAIN, LOG_TAG, 'toggleVpn: calling VpnService.start');
      const started: boolean = await VpnService.start(runtime.configPath);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'toggleVpn: VpnService.start returned %{public}s', started ? 'true' : 'false');

      if (!started) {
        this.summary = CoreService.createSummary(this.profileState, false);
        this.statusMessage = 'VPN 启动失败：模拟器可能不支持 VPN Extension，请使用真机';
        this.recordLog('warn', this.statusMessage);
        return;
      }

      this.statusMessage = 'VPN 已启动，等待核心...';
      this.coreBridgeState = CoreBridgeService.getState();
      hilog.info(LOG_DOMAIN, LOG_TAG, 'toggleVpn: waiting for controller');
      const controllerReady: ControllerStatus = await MihomoControllerService.waitForVersion(3, 800);
      this.controllerStatus = controllerReady;
      hilog.info(LOG_DOMAIN, LOG_TAG, 'toggleVpn: controller ready=%{public}s', controllerReady.available ? 'true' : 'false');

      if (!controllerReady.available) {
        TrafficPollerService.stop();
        this.connectedAt = 0;
        this.clearControllerProxyGroups();
        this.coreBridgeState = CoreBridgeService.markControllerReady(false, '');
        await VpnService.stop();
        this.summary = CoreService.createSummary(this.profileState, false);
        this.vpnActionText = '连接';
        this.coreBridgeState = CoreBridgeService.getState();
        this.statusMessage = `核心未响应：${controllerReady.message}`;
        this.recordLog('warn', this.statusMessage);
        return;
      }

      const tunReady: RuntimeTunStatus = await this.waitForVpnTunReady(8, 500);
      if (!tunReady.ready) {
        TrafficPollerService.stop();
        this.connectedAt = 0;
        this.clearControllerProxyGroups();
        this.coreBridgeState = CoreBridgeService.markControllerReady(false, '');
        await VpnService.stop();
        this.summary = CoreService.createSummary(this.profileState, false);
        this.vpnActionText = '连接';
        this.coreBridgeState = CoreBridgeService.getState();
        this.statusMessage = tunReady.message;
        this.recordLog('warn', tunReady.message);
        return;
      }

      this.coreBridgeState = CoreBridgeService.markControllerReady(true, controllerReady.version);
      await MihomoControllerService.setMode(this.normalizeProxyMode(this.proxyMode));
      this.summary = CoreService.createSummary(this.profileState, true);
      this.vpnActionText = '断开';
      this.statusMessage = `已连接 · ${controllerReady.version}`;
      this.connectedAt = Date.now();
      this.syncHomeRuntimeFields();
      this.startRuntimePolling();
      await this.refreshControllerProxies();
      await this.restoreProxySelection(restoreGroup, restoreNode);
      await this.refreshConnections();
      this.syncHomeRuntimeFields();
      this.recordLog('info', `VPN 已连接，controller=${controllerReady.version}`);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'toggleVpn: connected');
    } catch (err) {
      TrafficPollerService.stop();
      hilog.error(LOG_DOMAIN, LOG_TAG, 'toggleVpn: exception=%{public}s', JSON.stringify(err));
      this.statusMessage = '连接异常，请查看诊断页';
      this.summary = CoreService.createSummary(this.profileState, false);
      this.clearControllerProxyGroups();
      this.syncHomeRuntimeFields();
      this.recordLog('warn', this.statusMessage);
    } finally {
      this.toggling = false;
    }
  }

  private requestToggleVpn(): void {
    if (this.toggling) {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'toggleVpn skipped: already toggling');
      return;
    }
    const now: number = Date.now();
    if (now - this.lastToggleAt < 1500) {
      return;
    }
    this.lastToggleAt = now;
    this.toggleVpn();
  }

  private async prepareRuntimeForConnection(context: common.Context): Promise<RuntimeConfigResult> {
    let targetState: ProfileState = this.profileState;
    const current: ClashProfile | undefined = CoreService.getCurrentProfile(targetState);
    if (!current) {
      this.currentTab = 'profiles';
      return this.createRuntimeFailure('请先在配置页导入并启用一个配置');
    }

    if (current.type === 'remote' && current.filePath.length === 0) {
      this.statusMessage = '首次连接正在下载订阅...';
      const updateResult: SubscriptionUpdateResult = await SubscriptionService.updateProfile(context, current.uid);
      this.applyProfileState(updateResult.state);
      await this.refreshProxyNodes(updateResult.state);
      if (!updateResult.ok) {
        return this.createRuntimeFailure(updateResult.message);
      }
      targetState = updateResult.state;
    }

    let runtime: RuntimeConfigResult = await RuntimeConfigService.prepareCurrentProfile(context, targetState);
    if (!runtime.ok) {
      const latestCurrent: ClashProfile | undefined = CoreService.getCurrentProfile(targetState);
      if (latestCurrent && latestCurrent.type === 'remote') {
        this.statusMessage = '本地配置不可用，正在重新更新订阅...';
        const updateResult: SubscriptionUpdateResult = await SubscriptionService.updateProfile(context, latestCurrent.uid);
        this.applyProfileState(updateResult.state);
        await this.refreshProxyNodes(updateResult.state);
        if (!updateResult.ok) {
          return this.createRuntimeFailure(updateResult.message);
        }
        runtime = await RuntimeConfigService.prepareCurrentProfile(context, updateResult.state);
      }
    }

    return runtime;
  }

  private createRuntimeFailure(message: string): RuntimeConfigResult {
    return { ok: false, message: message, configPath: '', profileName: '', nodeCount: 0, size: '' };
  }

  private applyProfileState(state: ProfileState): void {
    const connected: boolean = this.isRuntimeConnected();
    const current: ClashProfile | undefined = CoreService.getCurrentProfile(state);
    this.profileState = state;
    const nextSummary: CoreSummary = CoreService.createSummary(state, connected);
    this.summary = connected ? {
      state: this.summary.state,
      mode: this.summary.mode,
      profileName: nextSummary.profileName,
      proxyName: this.summary.proxyName,
      uptime: this.summary.uptime,
      downloadSpeed: this.summary.downloadSpeed,
      uploadSpeed: this.summary.uploadSpeed,
      connections: this.summary.connections
    } : nextSummary;
    if (!connected) {
      this.statusMessage = current ? '配置已加载' : '请先导入或启用一个配置';
    }
    this.syncHomeRuntimeFields(state);
    this.liveProfileName = nextSummary.profileName;
    if (!connected) {
      this.liveProxyName = nextSummary.proxyName;
    }
    this.liveRefreshToken = this.liveRefreshToken + 1;
  }

  private async resumeRuntimeIfControllerAvailable(): Promise<void> {
    const status: ControllerStatus = await MihomoControllerService.checkVersion();
    if (!status.available) {
      if (this.isRuntimeConnected()) {
        this.handleRuntimeUnavailable(status.message);
      }
      return;
    }

    this.controllerStatus = status;
    this.coreBridgeState = CoreBridgeService.markControllerReady(true, status.version);
    if (this.connectedAt <= 0) {
      this.connectedAt = Date.now();
    }
    this.vpnActionText = '断开';
    await this.refreshControllerProxies();
    this.summary = this.createLiveSummary({
      downloadSpeed: this.summary.downloadSpeed,
      uploadSpeed: this.summary.uploadSpeed,
      totalDownload: 0,
      totalUpload: 0,
      activeConnections: this.summary.connections,
      memoryUsage: '',
      uptimeSeconds: 0,
      mode: this.proxyMode,
      controllerAvailable: true,
      message: 'controller 正常'
    });
    this.statusMessage = `已连接 · ${status.version}`;
    this.startRuntimePolling();
    await this.refreshConnections();
    this.syncHomeRuntimeFields();
  }

  private async addRemoteProfile(): Promise<void> {
    const url: string = this.importUrl.trim();
    if (url.length === 0) {
      this.statusMessage = '订阅 URL 不能为空';
      return;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      this.statusMessage = '请输入 http 或 https 开头的订阅 URL';
      return;
    }
    const name: string = this.importName.trim().length > 0 ? this.importName.trim() : this.createProfileNameFromUrl(url);
    const context = getContext(this) as common.Context;
    const next: ProfileState = await ProfileStore.addRemote(context, createRemoteProfile(name, url));
    this.importUrl = '';
    this.importName = '';
    this.showImportPanel = false;
    this.applyProfileState(next);
    this.statusMessage = `已保存订阅：${name}，正在下载...`;
    this.recordLog('info', this.statusMessage);
    const updateResult: SubscriptionUpdateResult = await SubscriptionService.updateProfile(context, next.currentUid);
    this.applyProfileState(updateResult.state);
    await this.refreshProxyNodes(updateResult.state);
    if (!updateResult.ok) {
      this.statusMessage = updateResult.message;
      this.recordLog('warn', updateResult.message);
      return;
    }
    const runtime: RuntimeConfigResult = await RuntimeConfigService.prepareCurrentProfile(context, updateResult.state);
    if (runtime.ok) {
      this.runtimeConfigPath = runtime.configPath;
      this.runtimeConfigInfo = `${runtime.profileName} · ${runtime.size}`;
      this.statusMessage = `${updateResult.message}，运行配置已准备`;
    } else {
      this.statusMessage = `${updateResult.message}，${runtime.message}`;
    }
    this.syncHomeRuntimeFields();
    this.recordLog(runtime.ok ? 'info' : 'warn', this.statusMessage);
  }

  private async importFromClipboard(): Promise<void> {
    this.statusMessage = '正在读取剪贴板...';
    const context = getContext(this) as common.Context;
    const result: ClipboardImportResult = await ClipboardImportService.importProfile(context);
    this.applyProfileState(result.state);
    await this.refreshProxyNodes(result.state);
    this.statusMessage = result.message;
    this.syncHomeRuntimeFields();
    this.recordLog(result.ok ? 'info' : 'warn', result.message);
  }

  private async importLocalFile(): Promise<void> {
    this.statusMessage = '请选择本地 YAML 或订阅文本文件...';
    const context = getContext(this) as common.Context;
    const result: FileImportResult = await LocalFileImportService.pickAndImport(context);
    this.applyProfileState(result.state);
    await this.refreshProxyNodes(result.state);
    this.statusMessage = result.message;
    this.syncHomeRuntimeFields();
    this.recordLog(result.ok ? 'info' : 'warn', result.message);
  }

  private async activateProfile(uid: string): Promise<void> {
    const context = getContext(this) as common.Context;
    const next: ProfileState = await ProfileStore.activate(context, uid);
    this.applyProfileState(next);
    await this.refreshProxyNodes(next);
    this.statusMessage = '已切换当前配置';
    this.syncHomeRuntimeFields();
    this.recordLog('info', this.statusMessage);
  }

  private async removeProfile(uid: string): Promise<void> {
    const context = getContext(this) as common.Context;
    const next: ProfileState = await ProfileStore.remove(context, uid);
    this.applyProfileState(next);
    await this.refreshProxyNodes(next);
    this.statusMessage = '配置已删除';
    this.syncHomeRuntimeFields();
    this.recordLog('info', this.statusMessage);
  }

  private async updateProfile(uid: string): Promise<void> {
    this.statusMessage = '正在更新订阅...';
    const context = getContext(this) as common.Context;
    const result: SubscriptionUpdateResult = await SubscriptionService.updateProfile(context, uid);
    this.applyProfileState(result.state);
    await this.refreshProxyNodes(result.state);
    if (!result.ok || result.state.currentUid !== uid) {
      this.statusMessage = result.message;
      this.recordLog('warn', result.message);
      return;
    }
    const runtime: RuntimeConfigResult = await RuntimeConfigService.prepareCurrentProfile(context, result.state);
    if (runtime.ok) {
      this.runtimeConfigPath = runtime.configPath;
      this.runtimeConfigInfo = `${runtime.profileName} · ${runtime.size}`;
      this.statusMessage = `${result.message}，运行配置已准备`;
    } else {
      this.statusMessage = `${result.message}，${runtime.message}`;
    }
    this.syncHomeRuntimeFields();
    this.recordLog(runtime.ok ? 'info' : 'warn', this.statusMessage);
  }

  private async updateAllProfiles(): Promise<void> {
    const remoteUids: string[] = [];
    for (let index = 0; index < this.profileState.items.length; index++) {
      if (this.profileState.items[index].type === 'remote') {
        remoteUids.push(this.profileState.items[index].uid);
      }
    }
    if (remoteUids.length === 0) {
      this.statusMessage = '没有可更新的远程订阅';
      return;
    }
    this.statusMessage = `正在更新 ${remoteUids.length} 个订阅...`;
    const context = getContext(this) as common.Context;
    let okCount: number = 0;
    let latestState: ProfileState = this.profileState;
    for (let index = 0; index < remoteUids.length; index++) {
      const result: SubscriptionUpdateResult = await SubscriptionService.updateProfile(context, remoteUids[index]);
      latestState = result.state;
      if (result.ok) { okCount++; }
    }
    this.applyProfileState(latestState);
    await this.refreshProxyNodes(latestState);
    const runtime: RuntimeConfigResult = await RuntimeConfigService.prepareCurrentProfile(context, latestState);
    if (runtime.ok) {
      this.runtimeConfigPath = runtime.configPath;
      this.runtimeConfigInfo = `${runtime.profileName} · ${runtime.size}`;
    }
    this.statusMessage = `全量更新完成：${okCount}/${remoteUids.length} 个订阅成功`;
    this.syncHomeRuntimeFields();
    this.recordLog(okCount === remoteUids.length ? 'info' : 'warn', this.statusMessage);
  }

  private async refreshControllerStatus(): Promise<void> {
    const status: ControllerStatus = await MihomoControllerService.checkVersion();
    this.controllerStatus = status;
    this.coreBridgeState = CoreBridgeService.markControllerReady(status.available, status.version);
    this.statusMessage = status.available ? `controller 已连接：${status.version}` : status.message;
    this.syncHomeRuntimeFields();
    this.recordLog(status.available ? 'info' : 'warn', this.statusMessage);
    if (status.available) {
      await this.refreshControllerProxies();
      if (this.summary.state !== 'running') {
        this.connectedAt = Date.now();
        this.vpnActionText = '断开';
        this.startRuntimePolling();
      }
      await this.refreshConnections();
      this.syncHomeRuntimeFields();
    }
  }

  private async ensureControllerReadyForProxyActions(action: string): Promise<boolean> {
    let status: ControllerStatus = await MihomoControllerService.checkVersion();
    if (status.available) {
      this.controllerStatus = status;
      this.coreBridgeState = CoreBridgeService.markControllerReady(true, status.version);
      if (!this.proxyGroupsSynced) {
        await this.refreshControllerProxies();
      }
      return true;
    }

    if (this.isRuntimeConnected()) {
      this.statusMessage = `${action}：等待 VPN 核心响应...`;
      status = await MihomoControllerService.waitForVersion(6, 500);
      this.controllerStatus = status;
      this.coreBridgeState = CoreBridgeService.markControllerReady(status.available, status.version);
      if (status.available) {
        await this.refreshControllerProxies();
        return true;
      }
      this.statusMessage = `${action}失败：${status.message}`;
      this.recordLog('warn', this.statusMessage);
      return false;
    }

    const context = getContext(this) as common.Context;
    this.statusMessage = `${action}：正在准备运行配置...`;
    const runtime: RuntimeConfigResult = await this.prepareRuntimeForConnection(context);
    if (!runtime.ok) {
      this.statusMessage = runtime.message;
      this.recordLog('warn', runtime.message);
      return false;
    }

    this.runtimeConfigPath = runtime.configPath;
    this.runtimeConfigInfo = `${runtime.profileName} · ${runtime.size}`;
    this.statusMessage = `${action}：正在启动测速核心...`;
    this.syncHomeRuntimeFields();
    this.coreBridgeState = CoreBridgeService.startCore(runtime.configPath);
    hilog.info(LOG_DOMAIN, LOG_TAG,
      'ensureControllerReady: action=%{public}s startCore running=%{public}s controllerOnly=%{public}s mode=%{public}s adapter=%{public}s kind=%{public}s supportsControllerOnly=%{public}s version=%{public}s error=%{public}s',
      action,
      this.coreBridgeState.running ? 'true' : 'false',
      this.coreBridgeState.controllerOnly ? 'true' : 'false',
      this.coreBridgeState.coreMode,
      this.coreBridgeState.adapterMode,
      this.coreBridgeState.adapterKind,
      this.coreBridgeState.supportsControllerOnly ? 'true' : 'false',
      this.coreBridgeState.adapterVersion,
      this.coreBridgeState.lastError);
    if (!this.coreBridgeState.running || !this.coreBridgeState.controllerOnly) {
      const reason: string = this.coreBridgeState.lastError.length > 0
        ? this.coreBridgeState.lastError
        : '当前 native 核心不支持 controller-only';
      this.statusMessage = `${action}失败：${reason}`;
      this.recordLog('warn', this.statusMessage);
      return false;
    }

    status = await MihomoControllerService.waitForVersion(10, 500);
    this.controllerStatus = status;
    this.coreBridgeState = CoreBridgeService.markControllerReady(status.available, status.version);
    this.syncHomeRuntimeFields();
    hilog.info(LOG_DOMAIN, LOG_TAG,
      'ensureControllerReady: action=%{public}s waitForVersion available=%{public}s version=%{public}s message=%{public}s nativeRunning=%{public}s controllerOnly=%{public}s error=%{public}s',
      action,
      status.available ? 'true' : 'false',
      status.version,
      status.message,
      this.coreBridgeState.running ? 'true' : 'false',
      this.coreBridgeState.controllerOnly ? 'true' : 'false',
      this.coreBridgeState.lastError);
    if (!status.available) {
      const nativeDetail: string = this.coreBridgeState.lastError.length > 0 ? `；native=${this.coreBridgeState.lastError}` : '';
      this.statusMessage = `${action}失败：${status.message}${nativeDetail}`;
      this.recordLog('warn', this.statusMessage);
      return false;
    }

    await MihomoControllerService.setMode(this.normalizeProxyMode(this.proxyMode));
    await this.refreshControllerProxies();
    this.statusMessage = `${action}：controller 已就绪`;
    this.recordLog('info', this.statusMessage);
    return true;
  }

  private async handleSectionAction(action: string): Promise<void> {
    if (action === '全量更新') {
      await this.updateAllProfiles();
    } else if (action === '查看') {
      this.currentTab = 'diagnostics';
    } else if (action === '关闭全部') {
      await this.closeAllControllerConnections();
    } else if (action === '导出') {
      this.statusMessage = '最近日志已在诊断页展示，文件导出将在分享能力接入后开放';
      this.recordLog('info', this.statusMessage);
    }
  }

  private async refreshProxyNodes(state?: ProfileState): Promise<void> {
    const context = getContext(this) as common.Context;
    const targetState: ProfileState = state ? state : this.profileState;
    const parsed: ParsedConfigSummary = await ClashConfigParserService.parseCurrentProfile(context, targetState);
    this.proxyStatus = parsed.message;
    const nodes: ProxyNode[] = [];
    for (let index = 0; index < parsed.nodes.length; index++) {
      nodes.push(this.mapParsedProxyNode(parsed.nodes[index], index));
    }
    this.proxyNodes = nodes;
    this.clearControllerProxyGroups();
  }

  private mapParsedProxyNode(node: ParsedProxyNode, index: number): ProxyNode {
    return {
      name: node.name,
      meta: `${node.type}${node.udp ? ' · UDP' : ''}`,
      delay: '待测',
      selected: index === 0,
      server: node.server,
      port: node.port
    };
  }

  private async changeProxyMode(mode: 'rule' | 'global' | 'direct'): Promise<void> {
    if (this.proxyMode === mode) {
      this.statusMessage = `当前已是${this.modeLabel(mode)}模式`;
      return;
    }

    this.proxyMode = mode;
    const controllerCanApply: boolean = this.controllerStatus.available || this.coreBridgeState.controllerReady || this.proxyGroupsSynced;
    if (!controllerCanApply) {
      this.statusMessage = `已切换到${this.modeLabel(mode)}模式，连接或测速启动核心后生效`;
      this.syncHomeRuntimeFields();
      this.recordLog('info', this.statusMessage);
      return;
    }

    const ok: boolean = await MihomoControllerService.setMode(mode);
    this.statusMessage = ok ? `已切换到${this.modeLabel(mode)}模式` : '模式切换失败，controller 未响应';
    if (ok) {
      this.summary = {
        state: this.isRuntimeConnected() ? 'running' : this.summary.state,
        mode: mode,
        profileName: this.currentProfileDisplayName(),
        proxyName: this.summary.proxyName,
        uptime: this.summary.uptime,
        downloadSpeed: this.summary.downloadSpeed,
        uploadSpeed: this.summary.uploadSpeed,
        connections: this.summary.connections
      };
      this.syncHomeRuntimeFields();
    }
    this.recordLog(ok ? 'info' : 'warn', this.statusMessage);
  }

  private async refreshControllerProxies(): Promise<void> {
    const previousSelectedGroup: string = this.selectedProxyGroup;
    this.clearControllerProxyGroups();
    const result: ControllerTextResult = await MihomoControllerService.getProxies();
    if (!result.ok) {
      this.proxyStatus = result.message;
      return;
    }

    const groups: ProxyGroupInfo[] = MihomoControllerService.parseProxyGroups(result.raw);
    this.proxyGroups = groups;
    if (groups.length === 0) {
      this.proxyStatus = 'controller 已连接，但未返回可选择策略组';
      return;
    }

    let selectedExists: boolean = false;
    for (let index = 0; index < groups.length; index++) {
      if (groups[index].name === previousSelectedGroup) {
        selectedExists = true;
        break;
      }
    }
    if (!selectedExists) {
      this.selectedProxyGroup = groups[0].name;
    } else {
      this.selectedProxyGroup = previousSelectedGroup;
    }
    this.proxyGroupsSynced = true;
    this.applySelectedProxyGroup();
  }

  private clearControllerProxyGroups(): void {
    this.proxyGroups = [];
    this.proxyGroupsSynced = false;
    this.selectedProxyGroup = '';
  }

  private applySelectedProxyGroup(): void {
    const group: ProxyGroupInfo | undefined = this.findSelectedProxyGroup();
    if (!group) {
      return;
    }

    const nodes: ProxyNode[] = [];
    for (let index = 0; index < group.all.length; index++) {
      const name: string = group.all[index];
      nodes.push({
        name: name,
        meta: `${group.name} · ${group.type}`,
        delay: this.formatGroupDelay(group, name),
        selected: name === group.now
      });
    }
    this.proxyNodes = nodes;
    this.proxyStatus = `${group.name} · 当前 ${group.now.length > 0 ? group.now : '未选择'} · ${group.all.length} 个节点`;
    this.syncHomeRuntimeFields();
  }

  private findSelectedProxyGroup(): ProxyGroupInfo | undefined {
    for (let index = 0; index < this.proxyGroups.length; index++) {
      if (this.proxyGroups[index].name === this.selectedProxyGroup) {
        return this.proxyGroups[index];
      }
    }
    return this.proxyGroups.length > 0 ? this.proxyGroups[0] : undefined;
  }

  private selectProxyGroup(groupName: string): void {
    this.selectedProxyGroup = groupName;
    this.applySelectedProxyGroup();
  }

  private async selectProxyNode(node: ProxyNode): Promise<void> {
    this.statusMessage = `正在切换节点：${node.name}`;
    let group: ProxyGroupInfo | undefined = this.findSelectedProxyGroup();
    if (!group) {
      const ready: boolean = await this.ensureControllerReadyForProxyActions('切换节点');
      if (!ready) {
        return;
      }
      group = this.findSelectedProxyGroup();
      if (!group) {
        this.statusMessage = '当前没有可选择的策略组';
        this.recordLog('warn', this.statusMessage);
        return;
      }
    }

    const ok: boolean = await MihomoControllerService.selectProxy(group.name, node.name);
    if (!ok) {
      this.statusMessage = `切换节点失败：${group.name} -> ${node.name}`;
      this.recordLog('warn', this.statusMessage);
      return;
    }

    this.statusMessage = `已切换 ${group.name} -> ${node.name}`;
    this.pendingProxyGroup = group.name;
    this.pendingProxyName = node.name;
    this.markSelectedProxyNode(node.name);
    this.recordLog('info', this.statusMessage);
    await this.refreshControllerProxies();
    this.summary = this.createLiveSummary({
      downloadSpeed: this.summary.downloadSpeed,
      uploadSpeed: this.summary.uploadSpeed,
      totalDownload: 0,
      totalUpload: 0,
      activeConnections: this.summary.connections,
      memoryUsage: '',
      uptimeSeconds: 0,
      mode: this.proxyMode,
      controllerAvailable: this.controllerStatus.available,
      message: this.controllerStatus.message
    });
    this.syncHomeRuntimeFields();
  }

  private markSelectedProxyNode(name: string): void {
    const nodes: ProxyNode[] = [];
    for (let index = 0; index < this.proxyNodes.length; index++) {
      const node: ProxyNode = this.proxyNodes[index];
      nodes.push({
        name: node.name,
        meta: node.meta,
        delay: node.delay,
        selected: node.name === name,
        status: node.status,
        server: node.server,
        port: node.port
      });
    }
    this.proxyNodes = nodes;
  }

  private getSelectedProxyNodeName(): string {
    for (let index = 0; index < this.proxyNodes.length; index++) {
      if (this.proxyNodes[index].selected) {
        return this.proxyNodes[index].name;
      }
    }
    return '';
  }

  private async restoreProxySelection(groupName: string, proxyName: string): Promise<void> {
    if (groupName.length === 0 || proxyName.length === 0) {
      return;
    }
    const ok: boolean = await MihomoControllerService.selectProxy(groupName, proxyName);
    if (!ok) {
      this.recordLog('warn', `连接后恢复节点失败：${groupName} -> ${proxyName}`);
      return;
    }
    this.pendingProxyGroup = groupName;
    this.pendingProxyName = proxyName;
    this.selectedProxyGroup = groupName;
    this.markSelectedProxyNode(proxyName);
    await this.refreshControllerProxies();
    this.recordLog('info', `连接后已恢复节点：${groupName} -> ${proxyName}`);
  }

  private getVisibleProxyNodes(): ProxyNode[] {
    const query: string = this.proxySearchText.trim().toLowerCase();
    if (query.length === 0) {
      return this.proxyNodes;
    }

    const result: ProxyNode[] = [];
    for (let index = 0; index < this.proxyNodes.length; index++) {
      const node: ProxyNode = this.proxyNodes[index];
      const haystack: string = `${node.name} ${node.meta}`.toLowerCase();
      if (haystack.indexOf(query) >= 0) {
        result.push(node);
      }
    }
    return result;
  }

  private getVisibleProxyNodeIndexes(): number[] {
    const query: string = this.proxySearchText.trim().toLowerCase();
    const indexes: number[] = [];
    for (let index = 0; index < this.proxyNodes.length; index++) {
      if (query.length === 0) {
        indexes.push(index);
        continue;
      }
      const node: ProxyNode = this.proxyNodes[index];
      const haystack: string = `${node.name} ${node.meta}`.toLowerCase();
      if (haystack.indexOf(query) >= 0) {
        indexes.push(index);
      }
    }
    return indexes;
  }

  private getAllProxyNodeIndexes(): number[] {
    const indexes: number[] = [];
    for (let index = 0; index < this.proxyNodes.length; index++) {
      indexes.push(index);
    }
    return indexes;
  }

  private startRuntimePolling(): void {
    this.runtimePollTick = 0;
    TrafficPollerService.stop();
    this.startHomeRefreshLoop();
    this.refreshLiveRuntimeSnapshot();
  }

  private startHomeRefreshLoop(): void {
    if (this.homeRefreshIntervalId !== undefined) {
      return;
    }
    this.homeLastPollAt = 0;
    this.homeTrafficBaselineReady = false;
    this.refreshLiveRuntimeSnapshot();
    this.homeRefreshIntervalId = setInterval(() => {
      this.refreshLiveRuntimeSnapshot();
    }, 1000);
  }

  private stopHomeRefreshLoop(): void {
    if (this.homeRefreshIntervalId !== undefined) {
      clearInterval(this.homeRefreshIntervalId);
      this.homeRefreshIntervalId = undefined;
    }
    this.homeRefreshInFlight = false;
  }

  private async refreshLiveRuntimeSnapshot(): Promise<void> {
    if (this.homeRefreshInFlight) {
      return;
    }
    this.homeRefreshInFlight = true;
    try {
      const connectionsResult: ControllerTextResult = await MihomoControllerService.getConnections();
      const configResult: ControllerTextResult = await MihomoControllerService.getConfig();
      if (!connectionsResult.ok || !configResult.ok) {
        this.homeRefreshFailures++;
        if (this.homeRefreshFailures >= 3 && this.isRuntimeConnected()) {
          this.handleRuntimeUnavailable(connectionsResult.ok ? configResult.message : connectionsResult.message);
        }
        return;
      }

      this.homeRefreshFailures = 0;
      this.runtimePollTick++;

      if (!this.controllerStatus.available || this.runtimePollTick % 5 === 0) {
        const status: ControllerStatus = await MihomoControllerService.checkVersion();
        if (status.available) {
          this.controllerStatus = status;
          this.coreBridgeState = CoreBridgeService.markControllerReady(true, status.version);
        }
      }

      const connections: ControllerConnectionInfo[] = MihomoControllerService.parseConnections(connectionsResult.raw);
      const totalDownload: number = this.readJsonNumber(connectionsResult.raw, 'downloadTotal');
      const totalUpload: number = this.readJsonNumber(connectionsResult.raw, 'uploadTotal');
      const now: number = Date.now();
      let downloadSpeed: number = 0;
      let uploadSpeed: number = 0;
      if (this.homeTrafficBaselineReady && this.homeLastPollAt > 0 && now > this.homeLastPollAt) {
        const elapsedSeconds: number = (now - this.homeLastPollAt) / 1000;
        downloadSpeed = Math.max(0, (totalDownload - this.homeLastDownloadTotal) / elapsedSeconds);
        uploadSpeed = Math.max(0, (totalUpload - this.homeLastUploadTotal) / elapsedSeconds);
      }
      this.homeLastDownloadTotal = totalDownload;
      this.homeLastUploadTotal = totalUpload;
      this.homeLastPollAt = now;
      this.homeTrafficBaselineReady = true;

      const controllerMode: 'rule' | 'global' | 'direct' = this.parseControllerMode(configResult.raw);
      this.proxyMode = controllerMode;
      this.runtimeConnections = this.mapControllerConnections(connections);
      this.summary = {
        state: 'running',
        mode: controllerMode,
        profileName: this.currentProfileDisplayName(),
        proxyName: this.currentProxyLabel(),
        uptime: this.formatRuntimeUptime(),
        downloadSpeed: this.formatSpeedValue(downloadSpeed),
        uploadSpeed: this.formatSpeedValue(uploadSpeed),
        connections: connections.length
      };
      this.vpnActionText = '断开';
      if (this.connectedAt <= 0) {
        this.connectedAt = Date.now();
      }
      this.syncHomeRuntimeFields();

      if (!this.isSpeedTesting && !this.toggling) {
        const version: string = this.controllerStatus.version.length > 0 ? this.controllerStatus.version : 'controller';
        this.statusMessage = `已连接 · ${version} · ${connections.length} 连接`;
      }
      if (!this.isSpeedTesting && this.runtimePollTick % 3 === 0) {
        this.refreshControllerProxies();
      }
    } finally {
      this.homeRefreshInFlight = false;
    }
  }

  private handleRuntimeUnavailable(message: string): void {
    TrafficPollerService.stop();
    this.runtimePollTick = 0;
    this.connectedAt = 0;
    this.runtimeConnections = [];
    this.controllerStatus = { available: false, version: '', message: message, raw: '' };
    this.coreBridgeState = CoreBridgeService.markControllerReady(false, '');
    this.summary = CoreService.createSummary(this.profileState, false);
    this.vpnActionText = '连接';
    this.statusMessage = message.length > 0 ? message : 'controller 已断开';
    this.syncHomeRuntimeFields();
  }

  private createLiveSummary(snapshot: TrafficSnapshot): CoreSummary {
    const current: ClashProfile | undefined = CoreService.getCurrentProfile(this.profileState);
    return {
      state: 'running',
      mode: this.normalizeProxyMode(snapshot.mode),
      profileName: current ? current.name : this.currentProfileDisplayName(),
      proxyName: this.currentProxyLabel(),
      uptime: this.formatRuntimeUptime(),
      downloadSpeed: snapshot.downloadSpeed,
      uploadSpeed: snapshot.uploadSpeed,
      connections: snapshot.activeConnections
    };
  }

  private mapPollerConnections(connections: PollerConnectionInfo[]): RuntimeConnectionRow[] {
    const result: RuntimeConnectionRow[] = [];
    const limit: number = connections.length > 50 ? 50 : connections.length;
    for (let index = 0; index < limit; index++) {
      const item: PollerConnectionInfo = connections[index];
      const target: string = item.metadata.host.length > 0
        ? item.metadata.host
        : `${item.metadata.destIP}${item.metadata.type.length > 0 ? ` · ${item.metadata.type}` : ''}`;
      result.push({
        id: item.id,
        target: target.length > 0 ? target : 'unknown',
        chain: item.chains.join(' / '),
        rule: item.rule.length > 0 ? item.rule : 'MATCH',
        upload: this.formatBytes(item.upload),
        download: this.formatBytes(item.download)
      });
    }
    return result;
  }

  private mapControllerConnections(connections: ControllerConnectionInfo[]): RuntimeConnectionRow[] {
    const result: RuntimeConnectionRow[] = [];
    const limit: number = connections.length > 50 ? 50 : connections.length;
    for (let index = 0; index < limit; index++) {
      const item: ControllerConnectionInfo = connections[index];
      const target: string = item.metadata.host.length > 0
        ? item.metadata.host
        : `${item.metadata.destinationIP}:${item.metadata.destinationPort}`;
      result.push({
        id: item.id,
        target: target.length > 0 ? target : 'unknown',
        chain: item.chains.join(' / '),
        rule: item.rule.length > 0 ? item.rule : 'MATCH',
        upload: this.formatBytes(item.upload),
        download: this.formatBytes(item.download)
      });
    }
    return result;
  }

  private async refreshConnections(): Promise<void> {
    const result: ControllerTextResult = await MihomoControllerService.getConnections();
    if (!result.ok) {
      this.recordLog('warn', result.message);
      return;
    }
    const connections: ControllerConnectionInfo[] = MihomoControllerService.parseConnections(result.raw);
    this.runtimeConnections = this.mapControllerConnections(connections);
    this.summary = {
      state: this.isRuntimeConnected() ? 'running' : this.summary.state,
      mode: this.summary.mode,
      profileName: this.currentProfileDisplayName(),
      proxyName: this.summary.proxyName,
      uptime: this.summary.uptime,
      downloadSpeed: this.summary.downloadSpeed,
      uploadSpeed: this.summary.uploadSpeed,
      connections: connections.length
    };
    this.syncHomeRuntimeFields();
  }

  private async closeAllControllerConnections(): Promise<void> {
    const ok: boolean = await MihomoControllerService.closeAllConnections();
    if (ok) {
      this.runtimeConnections = [];
      this.statusMessage = '已关闭全部 controller 连接';
    } else {
      this.statusMessage = '关闭连接失败，controller 未响应';
    }
    this.recordLog(ok ? 'info' : 'warn', this.statusMessage);
  }

  private async refreshRules(): Promise<void> {
    const result: ControllerTextResult = await MihomoControllerService.getRules();
    if (!result.ok) {
      this.rulesStatus = result.message;
      this.ruleLines = [];
      this.recordLog('warn', result.message);
      return;
    }
    this.ruleLines = this.pickJsonArrayPreview(result.raw, 'rules', 40);
    this.rulesStatus = `已同步 ${this.ruleLines.length} 条规则预览`;
    this.recordLog('info', this.rulesStatus);
  }

  private async refreshDnsConfig(): Promise<void> {
    const result: ControllerTextResult = await MihomoControllerService.getConfig();
    if (!result.ok) {
      this.dnsStatus = result.message;
      this.dnsLines = [];
      this.recordLog('warn', result.message);
      return;
    }
    this.dnsLines = this.pickJsonObjectPreview(result.raw, 'dns', 40);
    this.dnsStatus = this.dnsLines.length > 0 ? 'DNS 配置已同步' : '当前配置未返回 DNS 字段';
    this.recordLog('info', this.dnsStatus);
  }

  private pickJsonArrayPreview(raw: string, key: string, limit: number): string[] {
    try {
      const parsed = JSON.parse(raw) as Record<string, Object>;
      const array = parsed[key] as Object[];
      if (!Array.isArray(array)) {
        return [];
      }
      const result: string[] = [];
      const count: number = array.length > limit ? limit : array.length;
      for (let index = 0; index < count; index++) {
        result.push(String(array[index]));
      }
      return result;
    } catch (err) {
      return raw.split('\n').slice(0, limit);
    }
  }

  private pickJsonObjectPreview(raw: string, key: string, limit: number): string[] {
    try {
      const parsed = JSON.parse(raw) as Record<string, Object>;
      const value: Object | undefined = parsed[key];
      if (!value) {
        return [];
      }
      return JSON.stringify(value, null, 2).split('\n').slice(0, limit);
    } catch (err) {
      return raw.split('\n').slice(0, limit);
    }
  }

  private recordLog(level: string, message: string): void {
    const next: AppLogEntry[] = [{
      time: this.formatLogTime(new Date()),
      level: level,
      message: message
    }];
    for (let index = 0; index < this.appLogs.length && index < 49; index++) {
      next.push(this.appLogs[index]);
    }
    this.appLogs = next;
  }

  private formatLogTime(date: Date): string {
    const hours: string = date.getHours() < 10 ? `0${date.getHours()}` : `${date.getHours()}`;
    const minutes: string = date.getMinutes() < 10 ? `0${date.getMinutes()}` : `${date.getMinutes()}`;
    const seconds: string = date.getSeconds() < 10 ? `0${date.getSeconds()}` : `${date.getSeconds()}`;
    return `${hours}:${minutes}:${seconds}`;
  }

  private normalizeProxyMode(mode: string): 'rule' | 'global' | 'direct' {
    if (mode === 'global' || mode === 'direct') {
      return mode;
    }
    return 'rule';
  }

  private modeLabel(mode: string): string {
    if (mode === 'global') {
      return '全局';
    }
    if (mode === 'direct') {
      return '直连';
    }
    return '规则';
  }

  private formatGroupDelay(group: ProxyGroupInfo, name: string): string {
    for (let index = 0; index < group.history.length; index++) {
      if (group.now === name && group.history[index].delay > 0) {
        return `${group.history[index].delay} ms`;
      }
    }
    return name === group.now ? '当前' : '待测';
  }

  private currentProxyLabel(): string {
    const group: ProxyGroupInfo | undefined = this.findSelectedProxyGroup();
    if (group && group.now.length > 0) {
      return `${group.name} -> ${group.now}`;
    }
    if (this.pendingProxyGroup.length > 0 && this.pendingProxyName.length > 0) {
      return `${this.pendingProxyGroup} -> ${this.pendingProxyName}`;
    }
    return this.isRuntimeConnected() ? '等待策略组同步' : '未连接';
  }

  private isRuntimeConnected(): boolean {
    return this.summary.state === 'running' || this.controllerStatus.available || this.vpnActionText === '断开';
  }

  private currentProfileDisplayName(state?: ProfileState): string {
    const targetState: ProfileState = state ? state : this.profileState;
    const current: ClashProfile | undefined = CoreService.getCurrentProfile(targetState);
    if (current) {
      return current.name;
    }
    if (this.summary.profileName.length > 0 && this.summary.profileName !== '未选择配置') {
      return this.summary.profileName;
    }
    if (this.runtimeConfigInfo.length > 0 && this.runtimeConfigInfo !== '尚未生成运行配置') {
      const separator: number = this.runtimeConfigInfo.indexOf(' · ');
      return separator > 0 ? this.runtimeConfigInfo.substring(0, separator) : this.runtimeConfigInfo;
    }
    return this.isRuntimeConnected() ? '当前运行配置' : '未选择配置';
  }

  private runtimeConfigDisplayState(): string {
    if (this.runtimeConfigInfo !== '尚未生成运行配置') {
      return '已准备';
    }
    return this.isRuntimeConnected() ? '已加载' : '未准备';
  }

  private syncHomeRuntimeFields(state?: ProfileState): void {
    const connected: boolean = this.isRuntimeConnected();
    this.liveConnected = connected;
    this.liveUptime = connected ? this.summary.uptime : '未连接';
    this.liveDownloadSpeed = this.summary.downloadSpeed;
    this.liveUploadSpeed = this.summary.uploadSpeed;
    this.liveConnections = connected ? this.summary.connections : 0;
    this.liveProfileName = this.currentProfileDisplayName(state);
    this.liveProxyName = this.currentProxyLabel();
    this.liveRuntimeConfigState = this.runtimeConfigDisplayState();
    this.liveRefreshToken = this.liveRefreshToken + 1;
  }

  private parseControllerMode(raw: string): 'rule' | 'global' | 'direct' {
    try {
      const parsed = JSON.parse(raw) as Record<string, Object>;
      const mode = parsed['mode'];
      return typeof mode === 'string' ? this.normalizeProxyMode(mode as string) : 'rule';
    } catch (err) {
      return 'rule';
    }
  }

  private readJsonNumber(raw: string, key: string): number {
    try {
      const parsed = JSON.parse(raw) as Record<string, Object>;
      const value = parsed[key];
      return typeof value === 'number' ? value as number : 0;
    } catch (err) {
      return 0;
    }
  }

  private formatRuntimeUptime(): string {
    if (this.connectedAt <= 0) {
      return '刚刚启动';
    }
    const seconds: number = Math.floor((Date.now() - this.connectedAt) / 1000);
    return CoreService.formatUptime(seconds);
  }

  private formatBytes(bytes: number): string {
    if (bytes < 1024) {
      return `${bytes} B`;
    }
    if (bytes < 1024 * 1024) {
      return `${(bytes / 1024).toFixed(1)} KB`;
    }
    return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  }

  private formatSpeedValue(bytesPerSecond: number): string {
    if (bytesPerSecond < 1024) {
      return `${bytesPerSecond.toFixed(1)} B/s`;
    }
    if (bytesPerSecond < 1024 * 1024) {
      return `${(bytesPerSecond / 1024).toFixed(1)} KB/s`;
    }
    return `${(bytesPerSecond / 1024 / 1024).toFixed(1)} MB/s`;
  }

  build() {
    Column() {
      this.AppBar()
      if (this.showSettings) {
        this.SettingsScreen()
      } else {
        if (this.currentTab === 'home') {
          this.HomeScreen()
        } else if (this.currentTab === 'proxies') {
          this.ProxyScreen()
        } else if (this.currentTab === 'profiles') {
          this.ProfileScreen()
        } else {
          this.DiagnosticsScreen()
        }
        this.BottomNavigation()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F8FAFC')
  }

  // ============== AppBar ==============
  @Builder
  private AppBar() {
    Row() {
      Column() {
        Text(this.showSettings ? '设置' : 'Clash Harmony')
          .fontSize(20).fontWeight(FontWeight.Bold).fontColor('#0F172A')
        Text(this.getSubtitle()).fontSize(12).fontColor('#64748B').margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1)
      Button(this.showSettings ? '返回' : '设置')
        .height(34).fontSize(13).fontColor('#0F172A').backgroundColor('#EEF2F7').borderRadius(8)
        .onClick(() => { this.showSettings = !this.showSettings })
    }
    .height(56).width('100%').padding({ left: 16, right: 16 })
    .backgroundColor('#FFFFFF').border({ width: { bottom: 1 }, color: '#E2E8F0' })
  }

  // ============== BottomNav ==============
  @Builder
  private BottomNavigation() {
    Row() {
      ForEach(NAV_ITEMS, (item: NavItem) => {
        Column({ space: 2 }) {
          Text(item.shortLabel).fontSize(14).fontWeight(FontWeight.Bold)
            .fontColor(this.currentTab === item.key ? '#2563EB' : '#64748B')
          Text(item.label).fontSize(11)
            .fontColor(this.currentTab === item.key ? '#2563EB' : '#64748B')
        }
        .layoutWeight(1).justifyContent(FlexAlign.Center)
        .backgroundColor(this.currentTab === item.key ? '#EFF6FF' : '#FFFFFF')
        .onClick(() => { this.currentTab = item.key })
      }, (item: NavItem) => item.key)
    }
    .height(52).padding({ left: 10, right: 10, top: 2, bottom: 2 })
    .backgroundColor('#FFFFFF').border({ width: { top: 1 }, color: '#E2E8F0' })
  }

  // ============== Reusable Components ==============
  @Builder
  private Pill(text: string, color: string, bg: string) {
    Text(text).fontSize(12).fontWeight(FontWeight.Medium).fontColor(color)
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .backgroundColor(bg).borderRadius(12)
  }

  @Builder
  private Metric(label: string, value: string) {
    Column() {
      Text(label).fontSize(12).fontColor('#64748B')
      Text(value).fontSize(16).fontWeight(FontWeight.Bold).fontColor('#0F172A').margin({ top: 4 })
    }
    .layoutWeight(1).padding(10).backgroundColor('#F8FAFC')
    .borderRadius(8).border({ width: 1, color: '#E2E8F0' })
  }

  @Builder
  private ModeButton(text: string, active: boolean) {
    Text(text).width('100%').height(36).textAlign(TextAlign.Center).fontSize(13)
      .fontWeight(active ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(active ? '#FFFFFF' : '#475569')
      .backgroundColor(active ? '#0F766E' : '#F8FAFC').borderRadius(6)
      .border({ width: 1, color: active ? '#0F766E' : '#CBD5E1' })
  }

  @Builder
  private ProxyModeOption(text: string, mode: 'rule' | 'global' | 'direct') {
    Text(text).width('100%').height(36).textAlign(TextAlign.Center).fontSize(13)
      .fontWeight(this.proxyMode === mode ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(this.proxyMode === mode ? '#FFFFFF' : '#475569')
      .backgroundColor(this.proxyMode === mode ? '#0F766E' : '#F8FAFC')
      .borderRadius(6)
      .border({ width: 1, color: this.proxyMode === mode ? '#0F766E' : '#CBD5E1' })
      .layoutWeight(1)
      .onClick(() => { this.changeProxyMode(mode) })
  }

  @Builder
  private GroupButton(text: string, active: boolean) {
    Text(text).fontSize(13).fontWeight(active ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(active ? '#2563EB' : '#64748B')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor(active ? '#EFF6FF' : '#FFFFFF').borderRadius(8)
      .border({ width: 1, color: active ? '#BFDBFE' : '#DBE3EF' })
  }

  @Builder
  private SectionTitle(title: string, action: string) {
    Row() {
      Text(title).fontSize(15).fontWeight(FontWeight.Bold).fontColor('#0F172A')
      if (action.length > 0) {
        Text(action).fontSize(12).fontColor('#2563EB').onClick(() => { this.handleSectionAction(action) })
      }
    }
    .width('100%').justifyContent(FlexAlign.SpaceBetween)
  }

  @Builder
  private InfoRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(13).fontColor('#64748B')
      Text(value).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#0F172A')
    }
    .width('100%').justifyContent(FlexAlign.SpaceBetween)
  }

  @Builder
  private StatusLine(title: string, subtitle: string, status: string) {
    Row() {
      Column() {
        Text(title).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#0F172A')
        Text(subtitle).fontSize(12).fontColor('#64748B').margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1)
      this.Pill(status, status === '正常' ? '#0F766E' : '#2563EB', status === '正常' ? '#E6FFFB' : '#EFF6FF')
    }
    .padding(10).backgroundColor('#FFFFFF').borderRadius(8).border({ width: 1, color: '#E2E8F0' })
  }

  @Builder
  private ProxyNodeRow(node: ProxyNode) {
    Row() {
      Column() {
        Text(node.name).fontSize(14).fontWeight(FontWeight.Bold).fontColor('#0F172A')
        Text(node.meta).fontSize(12).fontColor('#64748B').margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1)
      Text(node.delay).fontSize(12).fontWeight(FontWeight.Bold)
        .fontColor(node.status === 'dead' ? '#DC2626' : node.status === 'testing' ? '#2563EB' : node.status === 'slow' ? '#D97706' : node.status === 'fast' || node.status === 'normal' ? '#0F766E' : '#64748B')
    }
    .padding(10).backgroundColor(node.selected ? '#E6FFFB' : '#FFFFFF')
    .borderRadius(8).border({ width: 1, color: node.selected ? '#99F6E4' : '#E2E8F0' })
    .onClick(() => { this.selectProxyNode(node) })
  }

  @Builder
  private ProfileRow(item: ClashProfile) {
    Row() {
      Column() {
        Text(item.name).fontSize(14).fontWeight(FontWeight.Bold).fontColor('#0F172A')
        Text(`${item.type === 'remote' ? '远程订阅' : '本地配置'} · ${formatProfileUpdatedAt(item.updatedAt)} · ${item.traffic}`)
          .fontSize(12).fontColor('#64748B').margin({ top: 3 })
        Text(`${item.nodeCount} 个节点 · ${item.filePath.length > 0 ? '已下载' : '未下载'}`)
          .fontSize(11).fontColor('#94A3B8').margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1)
      if (item.uid === this.profileState.currentUid) {
        this.Pill('当前', '#0F766E', '#E6FFFB')
        Button('更新').height(30).fontSize(12).fontColor('#2563EB')
          .backgroundColor('#EFF6FF').borderRadius(8)
          .onClick(() => { this.updateProfile(item.uid) })
      } else {
        Button('启用').height(30).fontSize(12).fontColor('#2563EB')
          .backgroundColor('#EFF6FF').borderRadius(8)
          .onClick(() => { this.activateProfile(item.uid) })
      }
      Button('删').height(30).fontSize(12).fontColor('#DC2626')
        .backgroundColor('#FEF2F2').borderRadius(8)
        .onClick(() => { this.removeProfile(item.uid) })
    }
    .padding(10).backgroundColor(item.uid === this.profileState.currentUid ? '#E6FFFB' : '#FFFFFF')
    .borderRadius(8).border({ width: 1, color: item.uid === this.profileState.currentUid ? '#99F6E4' : '#E2E8F0' })
  }

  @Builder
  private SwitchRow(title: string, subtitle: string, enabled: boolean) {
    Row() {
      Column() {
        Text(title).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#0F172A')
        Text(subtitle).fontSize(12).fontColor('#64748B').margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1)
      Text(enabled ? '开' : '关').fontSize(12).fontWeight(FontWeight.Bold)
        .fontColor(enabled ? '#FFFFFF' : '#64748B')
        .width(44).height(26).textAlign(TextAlign.Center)
        .backgroundColor(enabled ? '#0F766E' : '#E2E8F0').borderRadius(13)
    }
    .padding(12).backgroundColor('#FFFFFF').borderRadius(8).border({ width: 1, color: '#E2E8F0' })
  }

  @Builder
  private LogLine(time: string, level: string, message: string) {
    Row({ space: 8 }) {
      Text(time).fontSize(11).fontColor('#64748B')
      Text(level).fontSize(11).fontColor(level === 'warn' ? '#D97706' : '#2563EB')
      Text(message).fontSize(11).fontColor('#0F172A').layoutWeight(1)
    }
    .padding({ top: 6, bottom: 6 })
  }

  @Builder
  private EmptyState(title: string, subtitle: string) {
    Column({ space: 6 }) {
      Text(title).fontSize(14).fontWeight(FontWeight.Bold).fontColor('#0F172A')
      Text(subtitle).fontSize(12).fontColor('#64748B').textAlign(TextAlign.Center)
    }
    .width('100%').padding(18).backgroundColor('#F8FAFC').borderRadius(8).border({ width: 1, color: '#E2E8F0' })
  }

  // ============== HomeScreen ==============
  @Builder
  private HomeScreen() {
    Scroll() {
      Column({ space: 12 }) {
        this.HomeStatusCard()
        this.HomeModeCard()
        this.HomeCurrentRouteCard()
        this.HomeRecentStatusCard()
      }
      .padding(16)
    }
    .layoutWeight(1)
  }

  @Builder
  private HomeStatusCard() {
    Column({ space: 14 }) {
      Row() {
        Text(this.liveConnected ? '已连接' : '未连接')
          .fontSize(12).fontWeight(FontWeight.Bold)
          .fontColor(this.liveConnected ? '#0F766E' : '#D97706')
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor(this.liveConnected ? '#E6FFFB' : '#FFF7ED')
          .borderRadius(14)
        Text(this.liveUptime)
          .fontSize(12).fontWeight(FontWeight.Bold).fontColor('#2563EB')
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor('#EFF6FF').borderRadius(14)
      }
      .width('100%').justifyContent(FlexAlign.SpaceBetween)

      Button() {
        Text(this.liveConnected ? '断开' : '连接')
          .fontSize(24).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
      }
        .width(124).height(124).backgroundColor('#0F766E').borderRadius(62)
        .onClick(() => { this.requestToggleVpn() })

      Row({ space: 8 }) {
        Column() {
          Text('下载').fontSize(12).fontColor('#64748B')
          Text(this.liveDownloadSpeed).fontSize(16).fontWeight(FontWeight.Bold)
            .fontColor('#0F172A').margin({ top: 4 })
        }
        .layoutWeight(1).padding(10).backgroundColor('#F8FAFC')
        .borderRadius(8).border({ width: 1, color: '#E2E8F0' })
        Column() {
          Text('上传').fontSize(12).fontColor('#64748B')
          Text(this.liveUploadSpeed).fontSize(16).fontWeight(FontWeight.Bold)
            .fontColor('#0F172A').margin({ top: 4 })
        }
        .layoutWeight(1).padding(10).backgroundColor('#F8FAFC')
        .borderRadius(8).border({ width: 1, color: '#E2E8F0' })
        Column() {
          Text('连接').fontSize(12).fontColor('#64748B')
          Text(`${this.liveConnections}`).fontSize(16).fontWeight(FontWeight.Bold)
            .fontColor('#0F172A').margin({ top: 4 })
        }
        .layoutWeight(1).padding(10).backgroundColor('#F8FAFC')
        .borderRadius(8).border({ width: 1, color: '#E2E8F0' })
      }
      .width('100%')

      Text(this.statusMessage).width('100%').fontSize(12).fontColor('#475569').textAlign(TextAlign.Center)
      Text(`${this.liveRefreshToken}`).height(1).fontSize(1).fontColor('#FFFFFF').opacity(0)
    }
    .alignItems(HorizontalAlign.Center).padding(14)
    .backgroundColor('#FFFFFF').borderRadius(8).border({ width: 1, color: '#DBE3EF' })
  }

  @Builder
  private HomeModeCard() {
    Column({ space: 10 }) {
      this.SectionTitle('运行模式', '')
      Row({ space: 6 }) {
        this.ProxyModeOption('规则', 'rule')
        this.ProxyModeOption('全局', 'global')
        this.ProxyModeOption('直连', 'direct')
      }
      .width('100%').padding(4).backgroundColor('#EEF2F7').borderRadius(8)
    }
    .padding(12).backgroundColor('#FFFFFF').borderRadius(8).border({ width: 1, color: '#DBE3EF' })
  }

  @Builder
  private HomeCurrentRouteCard() {
    Column({ space: 10 }) {
      Row() {
        Text('当前链路').fontSize(15).fontWeight(FontWeight.Bold)
        Button('切换').height(30).fontSize(12).backgroundColor('#EEF2F7')
          .fontColor('#0F172A').borderRadius(8)
          .onClick(() => { this.currentTab = 'proxies' })
      }
      .width('100%').justifyContent(FlexAlign.SpaceBetween)
      Row() {
        Text('配置').fontSize(13).fontColor('#64748B')
        Text(this.liveProfileName).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#0F172A')
      }
      .width('100%').justifyContent(FlexAlign.SpaceBetween)
      Row() {
        Text('模式').fontSize(13).fontColor('#64748B')
        Text(this.modeLabel(this.proxyMode)).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#0F172A')
      }
      .width('100%').justifyContent(FlexAlign.SpaceBetween)
      Row() {
        Text('策略组').fontSize(13).fontColor('#64748B')
        Text(this.liveProxyName).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#0F172A')
      }
      .width('100%').justifyContent(FlexAlign.SpaceBetween)
      Row() {
        Text('运行配置').fontSize(13).fontColor('#64748B')
        Text(this.liveRuntimeConfigState).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#0F172A')
      }
      .width('100%').justifyContent(FlexAlign.SpaceBetween)
    }
    .padding(12).backgroundColor('#FFFFFF').borderRadius(8).border({ width: 1, color: '#DBE3EF' })
  }

  @Builder
  private HomeRecentStatusCard() {
    Column({ space: 8 }) {
      this.SectionTitle('最近状态', '查看')
      this.StatusLine('配置状态',
        this.profileState.currentUid.length > 0 ? '已选择当前配置' : '等待导入订阅',
        this.profileState.currentUid.length > 0 ? '正常' : '待处理')
      this.StatusLine('运行配置', this.runtimeConfigInfo,
        this.runtimeConfigInfo === '尚未生成运行配置' && !this.isRuntimeConnected() ? '待处理' : '正常')
      this.StatusLine('核心状态',
        this.controllerStatus.available ? `mihomo ${this.controllerStatus.version} · ${this.liveConnections} 连接` : this.controllerStatus.message,
        this.controllerStatus.available ? '正常' : '待接入')
      this.StatusLine('实时流量',
        `下行 ${this.liveDownloadSpeed} / 上行 ${this.liveUploadSpeed}`,
        this.liveConnected ? '实时' : '等待')
    }
    .padding(12).backgroundColor('#FFFFFF').borderRadius(8).border({ width: 1, color: '#DBE3EF' })
  }

  // ============== ProxyScreen ==============
  @Builder
  private ProxyScreen() {
    Scroll() {
      Column({ space: 12 }) {
        Row({ space: 6 }) {
          this.ProxyModeOption('规则', 'rule')
          this.ProxyModeOption('全局', 'global')
          this.ProxyModeOption('直连', 'direct')
        }
        .padding(4).backgroundColor('#EEF2F7').borderRadius(8)

        TextInput({ placeholder: '搜索节点、地区或提供者', text: this.proxySearchText })
          .height(40).backgroundColor('#FFFFFF').borderRadius(8)
          .onChange((value: string) => { this.proxySearchText = value })

        if (this.proxyGroups.length > 0) {
          Row({ space: 8 }) {
            ForEach(this.proxyGroups, (group: ProxyGroupInfo) => {
              Column() { this.GroupButton(group.name, this.selectedProxyGroup === group.name) }
                .onClick(() => { this.selectProxyGroup(group.name) })
            }, (group: ProxyGroupInfo) => group.name)
          }
        } else {
          Row({ space: 8 }) {
            this.GroupButton('本地预览', true)
            this.GroupButton('等待核心', false)
          }
        }

        Column({ space: 8 }) {
          Row() {
            Text(`节点列表 · ${this.getVisibleProxyNodes().length}/${this.proxyNodes.length}`).fontSize(15).fontWeight(FontWeight.Bold)
            Row({ space: 6 }) {
              Text('同步').height(30).width(58).fontSize(12).textAlign(TextAlign.Center)
                .fontColor('#2563EB').backgroundColor('#EFF6FF').borderRadius(8)
                .onClick(() => { this.refreshControllerProxies() })
              Text(this.isSpeedTesting ? '测速中' : '测速').height(30).width(72).fontSize(12).textAlign(TextAlign.Center)
                .fontColor('#FFFFFF').backgroundColor(this.isSpeedTesting ? '#64748B' : '#2563EB').borderRadius(8)
                .onClick(async () => { await this.runRealSpeedTest() })
            }
          }
          .width('100%').justifyContent(FlexAlign.SpaceBetween)
          if (this.speedTestProgress.length > 0) {
            Text(this.speedTestProgress).fontSize(12).fontColor(this.isSpeedTesting ? '#2563EB' : '#475569')
              .width('100%').padding({ top: 6, bottom: 6, left: 8, right: 8 })
              .backgroundColor(this.isSpeedTesting ? '#EFF6FF' : '#F8FAFC').borderRadius(8)
          }
          if (this.getVisibleProxyNodes().length === 0) {
            this.EmptyState('暂无节点', this.proxyStatus)
          } else {
            ForEach(this.getVisibleProxyNodes(), (node: ProxyNode) => {
              this.ProxyNodeRow(node)
            }, (node: ProxyNode) => `${node.name}-${node.delay}-${node.status ? node.status : ''}`)
          }
        }
        .padding(12).backgroundColor('#FFFFFF').borderRadius(8).border({ width: 1, color: '#DBE3EF' })

        this.SwitchRow('链式代理', '高级模式关闭，开启后可设置入口和出口节点', false)

        Text(this.statusMessage)
          .width('100%').fontSize(12).fontColor('#475569').textAlign(TextAlign.Center)
          .padding({ top: 4, bottom: 4 })
      }
      .padding(16)
    }
    .layoutWeight(1)
  }

  // ============== ProfileScreen ==============
  @Builder
  private ProfileScreen() {
    Scroll() {
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          Button('导入订阅').layoutWeight(1).height(38).fontColor('#FFFFFF')
            .backgroundColor('#0F766E').borderRadius(8)
            .onClick(() => { this.showImportPanel = !this.showImportPanel })
          Button('本地文件').layoutWeight(1).height(38).fontColor('#0F172A')
            .backgroundColor('#EEF2F7').borderRadius(8)
            .onClick(() => { this.importLocalFile() })
          Button('剪贴板').layoutWeight(1).height(38).fontColor('#0F172A')
            .backgroundColor('#EEF2F7').borderRadius(8)
            .onClick(() => { this.importFromClipboard() })
        }

        if (this.showImportPanel) { this.ImportPanel() }

        Column({ space: 8 }) {
          this.SectionTitle(`配置列表 · ${this.profileState.items.length}`, '全量更新')
          if (this.profileState.items.length === 0) {
            this.EmptyState('还没有配置', '先导入一个订阅 URL，后续会接入本地 YAML 和备份包。')
          } else {
            ForEach(this.profileState.items, (item: ClashProfile) => {
              this.ProfileRow(item)
            }, (item: ClashProfile) => item.uid)
          }
        }
        .padding(12).backgroundColor('#FFFFFF').borderRadius(8).border({ width: 1, color: '#DBE3EF' })

        Column({ space: 10 }) {
          this.SectionTitle('配置摘要', '')
          Row({ space: 8 }) {
            this.Metric('订阅', `${this.profileState.items.length}`)
            this.Metric('节点', `${this.proxyNodes.length}`)
            this.Metric('运行配置', this.liveRuntimeConfigState)
          }
        }
        .padding(12).backgroundColor('#FFFFFF').borderRadius(8).border({ width: 1, color: '#DBE3EF' })
      }
      .padding(16)
    }
    .layoutWeight(1)
  }

  @Builder
  private ImportPanel() {
    Column({ space: 10 }) {
      Text('导入远程订阅').fontSize(15).fontWeight(FontWeight.Bold).fontColor('#0F172A')
      TextInput({ placeholder: '订阅名称，可留空', text: this.importName }).height(40)
        .backgroundColor('#F8FAFC').borderRadius(8)
        .onChange((value: string) => { this.importName = value })
      TextInput({ placeholder: 'https://example.com/sub.yaml', text: this.importUrl }).height(40)
        .backgroundColor('#F8FAFC').borderRadius(8)
        .onChange((value: string) => { this.importUrl = value })
      Row({ space: 8 }) {
        Button('取消').layoutWeight(1).height(36).fontColor('#0F172A')
          .backgroundColor('#EEF2F7').borderRadius(8)
          .onClick(() => { this.showImportPanel = false })
        Button('保存').layoutWeight(1).height(36).fontColor('#FFFFFF')
          .backgroundColor('#0F766E').borderRadius(8)
          .onClick(() => { this.addRemoteProfile() })
      }
    }
    .padding(12).backgroundColor('#FFFFFF').borderRadius(8).border({ width: 1, color: '#99F6E4' })
  }

  // ============== DiagnosticsScreen ==============
  @Builder
  private DiagnosticsScreen() {
    Scroll() {
      Column({ space: 12 }) {
        Row({ space: 6 }) {
          Column() { this.ModeButton('连接', this.diagSegment === '连接') }
            .layoutWeight(1).onClick(() => { this.diagSegment = '连接' })
          Column() { this.ModeButton('日志', this.diagSegment === '日志') }
            .layoutWeight(1).onClick(() => { this.diagSegment = '日志' })
          Column() { this.ModeButton('规则', this.diagSegment === '规则') }
            .layoutWeight(1).onClick(() => { this.diagSegment = '规则' })
          Column() { this.ModeButton('DNS', this.diagSegment === 'DNS') }
            .layoutWeight(1).onClick(() => { this.diagSegment = 'DNS' })
        }
        .padding(4).backgroundColor('#EEF2F7').borderRadius(8)

        if (this.diagSegment === '连接') {
          this.DiagnosticsConnectionSegment()
        } else if (this.diagSegment === '日志') {
          this.DiagnosticsLogSegment()
        } else if (this.diagSegment === '规则') {
          this.DiagnosticsRulesSegment()
        } else {
          this.DiagnosticsDnsSegment()
        }
      }
      .padding(16)
    }
    .layoutWeight(1)
  }

  @Builder
  private DiagnosticsConnectionSegment() {
    Column({ space: 12 }) {
      Column({ space: 10 }) {
        this.SectionTitle('连接概览', '关闭全部')
        Row({ space: 8 }) {
          this.Metric('活跃', `${this.liveConnections}`)
          this.Metric('下载', this.liveDownloadSpeed)
          this.Metric('上传', this.liveUploadSpeed)
        }
      }
      .padding(12).backgroundColor('#FFFFFF').borderRadius(8).border({ width: 1, color: '#DBE3EF' })

      Column({ space: 8 }) {
        Row() {
          Text('核心 Controller').fontSize(15).fontWeight(FontWeight.Bold).fontColor('#0F172A')
          Button('刷新').height(30).fontSize(12).fontColor('#FFFFFF')
            .backgroundColor('#2563EB').borderRadius(8)
            .onClick(() => { this.refreshControllerStatus() })
        }
        .width('100%').justifyContent(FlexAlign.SpaceBetween)
        this.StatusLine(
          this.controllerStatus.available ? '已连接' : '未连接',
          this.controllerStatus.available ? `mihomo ${this.controllerStatus.version}` : this.controllerStatus.message,
          this.controllerStatus.available ? '正常' : '待接入'
        )
      }
      .padding(12).backgroundColor('#FFFFFF').borderRadius(8).border({ width: 1, color: '#DBE3EF' })

      Column({ space: 8 }) {
        this.SectionTitle('Native Bridge', '')
        this.StatusLine('桥接状态', this.coreBridgeState.coreMode,
          this.coreBridgeState.running ? '运行' : '待接入')
        this.StatusLine('Adapter', this.coreBridgeState.adapterVersion.length > 0
          ? `${this.coreBridgeState.adapterMode} ${this.coreBridgeState.adapterVersion}`
          : this.coreBridgeState.adapterMode,
          this.coreBridgeState.adapterMode === 'real' ? '真实核心' : 'Stub')
        if (this.coreBridgeState.adapterLoadError.length > 0) {
          this.StatusLine('加载信息', this.coreBridgeState.adapterLoadError,
            this.coreBridgeState.adapterMode === 'real' ? '正常' : '待接入')
        }
        this.StatusLine('TUN FD', `system ${this.coreBridgeState.tunFd} / native ${this.coreBridgeState.nativeFd}`,
          this.coreBridgeState.nativeFd >= 0 ? '正常' : '等待')
        this.StatusLine('Controller Ready',
          this.coreBridgeState.controllerReady ? `ready ${this.coreBridgeState.controllerVersion}` : 'not ready',
          this.coreBridgeState.controllerReady ? '正常' : '等待')
        this.StatusLine('转发统计',
          `读 ${this.coreBridgeState.packetsRead} 包 (${this.coreBridgeState.bytesRead} B) / 写 ${this.coreBridgeState.packetsWritten} 包 (${this.coreBridgeState.bytesWritten} B)`,
          this.coreBridgeState.forwarderActive ? '活跃' : '停用')
        this.StatusLine('生命周期',
          `start ${this.coreBridgeState.startCount} / stop ${this.coreBridgeState.stopCount}`,
          this.coreBridgeState.lastError.length > 0 ? '异常' : '正常')
        if (this.coreBridgeState.lastError.length > 0) {
          this.StatusLine('最近错误', this.coreBridgeState.lastError, '异常')
        }
      }
      .padding(12).backgroundColor('#FFFFFF').borderRadius(8).border({ width: 1, color: '#DBE3EF' })

      Column({ space: 8 }) {
        this.SectionTitle('运行配置', '')
        this.StatusLine(this.runtimeConfigInfo,
          this.runtimeConfigPath.length > 0 ? this.runtimeConfigPath : '等待生成',
          this.runtimeConfigInfo === '尚未生成运行配置' ? '待处理' : '正常')
        this.StatusLine('VPN 路由', '默认路由，接管 IPv4 流量', '正常')
      }
      .padding(12).backgroundColor('#FFFFFF').borderRadius(8).border({ width: 1, color: '#DBE3EF' })

      Column({ space: 8 }) {
        Row() {
          Text('活跃连接').fontSize(15).fontWeight(FontWeight.Bold).fontColor('#0F172A')
          Button('刷新').height(30).fontSize(12).fontColor('#2563EB')
            .backgroundColor('#EFF6FF').borderRadius(8)
            .onClick(() => { this.refreshConnections() })
        }
        .width('100%').justifyContent(FlexAlign.SpaceBetween)
        if (this.runtimeConnections.length === 0) {
          this.EmptyState('暂无连接数据', this.controllerStatus.available ? 'controller 已连接，等待连接产生。' : '启动 mihomo controller 后可同步活跃连接。')
        } else {
          ForEach(this.runtimeConnections, (item: RuntimeConnectionRow) => {
            this.ConnectionRow(item)
          }, (item: RuntimeConnectionRow) => item.id)
        }
      }
      .padding(12).backgroundColor('#FFFFFF').borderRadius(8).border({ width: 1, color: '#DBE3EF' })
    }
  }

  @Builder
  private DiagnosticsLogSegment() {
    Column({ space: 8 }) {
      this.SectionTitle('最近日志', '导出')
      if (this.appLogs.length === 0) {
        this.LogLine('--:--', 'info', this.statusMessage)
        this.LogLine('--:--', 'info', this.controllerStatus.message)
      } else {
        ForEach(this.appLogs, (item: AppLogEntry) => {
          this.LogLine(item.time, item.level, item.message)
        }, (item: AppLogEntry) => `${item.time}-${item.message}`)
      }
    }
    .padding(12).backgroundColor('#FFFFFF').borderRadius(8).border({ width: 1, color: '#DBE3EF' })
  }

  @Builder
  private DiagnosticsRulesSegment() {
    Column({ space: 8 }) {
      Row() {
        Text('规则').fontSize(15).fontWeight(FontWeight.Bold).fontColor('#0F172A')
        Button('刷新').height(30).fontSize(12).fontColor('#FFFFFF')
          .backgroundColor('#2563EB').borderRadius(8)
          .onClick(() => { this.refreshRules() })
      }
      .width('100%').justifyContent(FlexAlign.SpaceBetween)
      this.StatusLine('规则同步', this.rulesStatus, this.ruleLines.length > 0 ? '正常' : '待接入')
      if (this.ruleLines.length === 0) {
        this.EmptyState('暂无规则数据', '启动 mihomo controller 后可读取 /rules。')
      } else {
        ForEach(this.ruleLines, (line: string) => {
          this.MonospaceLine(line)
        }, (line: string) => line)
      }
    }
    .padding(12).backgroundColor('#FFFFFF').borderRadius(8).border({ width: 1, color: '#DBE3EF' })
  }

  @Builder
  private DiagnosticsDnsSegment() {
    Column({ space: 8 }) {
      Row() {
        Text('DNS').fontSize(15).fontWeight(FontWeight.Bold).fontColor('#0F172A')
        Button('刷新').height(30).fontSize(12).fontColor('#FFFFFF')
          .backgroundColor('#2563EB').borderRadius(8)
          .onClick(() => { this.refreshDnsConfig() })
      }
      .width('100%').justifyContent(FlexAlign.SpaceBetween)
      this.StatusLine('DNS 配置', this.dnsStatus, this.dnsLines.length > 0 ? '正常' : '待接入')
      if (this.dnsLines.length === 0) {
        this.EmptyState('暂无 DNS 数据', '启动 mihomo controller 后可查看 DNS 配置。')
      } else {
        ForEach(this.dnsLines, (line: string) => {
          this.MonospaceLine(line)
        }, (line: string) => line)
      }
    }
    .padding(12).backgroundColor('#FFFFFF').borderRadius(8).border({ width: 1, color: '#DBE3EF' })
  }

  @Builder
  private ConnectionRow(item: RuntimeConnectionRow) {
    Column({ space: 4 }) {
      Text(item.target).fontSize(13).fontWeight(FontWeight.Bold).fontColor('#0F172A')
      Text(`${item.rule} · ${item.chain.length > 0 ? item.chain : 'DIRECT'}`)
        .fontSize(11).fontColor('#64748B')
      Text(`上行 ${item.upload} / 下行 ${item.download}`).fontSize(11).fontColor('#0F766E')
    }
    .width('100%').alignItems(HorizontalAlign.Start).padding(10)
    .backgroundColor('#F8FAFC').borderRadius(8).border({ width: 1, color: '#E2E8F0' })
  }

  @Builder
  private MonospaceLine(text: string) {
    Text(text).fontSize(11).fontColor('#334155')
      .width('100%').padding({ top: 4, bottom: 4 })
      .backgroundColor('#F8FAFC')
  }

  // ============== SettingsScreen ==============
  @Builder
  private SettingsScreen() {
    Scroll() {
      Column({ space: 12 }) {
        this.SwitchRow('后台持续运行', '连接后显示系统可见状态', true)
        this.SwitchRow('IPv6', '跟随配置，异常时提示', false)
        this.StatusLine('DNS 模式', 'fake-ip · 增强模式', '配置')
        this.StatusLine('mihomo 核心', 'Alpha 通道关闭 · 日志 info', '正常')
        this.SwitchRow('外部控制器', '仅本机访问，默认关闭局域网', false)
        this.SwitchRow('诊断包脱敏', '隐藏订阅 token、节点密码、secret', true)
        this.StatusLine('本地备份', '最近备份：今天 10:21', '导出')
      }
      .padding(16)
    }
    .layoutWeight(1)
  }

  // ============== Helpers ==============
  private async runRealSpeedTest(): Promise<void> {
    if (this.isSpeedTesting) {
      this.statusMessage = '测速正在进行，请稍候';
      return;
    }

    let targetIndexes: number[] = this.getAllProxyNodeIndexes();
    if (targetIndexes.length === 0) {
      this.statusMessage = '没有节点可测';
      this.speedTestProgress = '没有节点可测';
      this.speedTestSummary = '没有节点可测';
      return;
    }

    this.isSpeedTesting = true;
    this.speedTestSummary = '';
    this.speedTestProgress = `准备测速核心 · ${targetIndexes.length} 个节点`;
    this.statusMessage = `正在准备测速 ${targetIndexes.length} 个节点...`;
    await this.waitForUiUpdate(80);

    let tested: number = 0;
    let reachable: number = 0;
    let timeout: number = 0;

    try {
      const ready: boolean = await this.ensureControllerReadyForProxyActions('测速');
      if (!ready) {
        this.speedTestProgress = '测速未开始：controller 未就绪';
        this.speedTestSummary = this.speedTestProgress;
        return;
      }

      targetIndexes = this.getAllProxyNodeIndexes();
      if (targetIndexes.length === 0) {
        this.speedTestProgress = '没有节点可测';
        this.speedTestSummary = '没有节点可测';
        this.statusMessage = '没有节点可测';
        return;
      }

      const blocked: SpeedTestBlockedState | undefined = this.getSpeedTestBlockedState(targetIndexes.length);
      if (blocked) {
        this.updateVisibleProxyNodeDelay(targetIndexes, blocked.nodeDelay, blocked.nodeStatus);
        this.statusMessage = blocked.statusMessage;
        this.speedTestProgress = blocked.progress;
        this.speedTestSummary = blocked.summary;
        this.recordLog('warn', blocked.statusMessage);
        return;
      }

      this.speedTestProgress = `测速中 0/${targetIndexes.length} · 0 可达`;
      this.statusMessage = `正在测速 0/${targetIndexes.length}...`;
      for (let index = 0; index < targetIndexes.length; index++) {
        const nodeIndex: number = targetIndexes[index];
        const node: ProxyNode = this.proxyNodes[nodeIndex];
        this.updateProxyNodeDelay(nodeIndex, node.name, '测试中...', 'testing');
      }

      await this.waitForUiUpdate(80);

      const batchSize: number = 12;
      for (let offset = 0; offset < targetIndexes.length; offset += batchSize) {
        const batchIndexes: number[] = [];
        const tasks: Promise<number>[] = [];
        const end: number = offset + batchSize > targetIndexes.length ? targetIndexes.length : offset + batchSize;
        for (let cursor = offset; cursor < end; cursor++) {
          const nodeIndex: number = targetIndexes[cursor];
          batchIndexes.push(nodeIndex);
          tasks.push(this.measureProxyNodeDelay(this.proxyNodes[nodeIndex]));
        }

        const delays: number[] = await Promise.all(tasks);
        for (let index = 0; index < delays.length; index++) {
          const nodeIndex: number = batchIndexes[index];
          const node: ProxyNode = this.proxyNodes[nodeIndex];
          const result = TcpDelayTestService.formatDelay(delays[index]);
          this.updateProxyNodeDelay(nodeIndex, node.name, result.delay, result.status);
          tested = tested + 1;
          if (delays[index] > 0) {
            reachable = reachable + 1;
          } else {
            timeout = timeout + 1;
          }
        }
        this.speedTestProgress = '测速中 ' + tested + '/' + targetIndexes.length + ' · ' + reachable + ' 可达 · ' + timeout + ' timeout';
        this.statusMessage = '测速: ' + tested + '/' + targetIndexes.length + ' (' + reachable + ' 可达)';
      }
      this.speedTestSummary = '测速完成 ' + tested + '/' + targetIndexes.length + ' · ' + reachable + ' 可达 · ' + timeout + ' timeout';
      this.speedTestProgress = this.speedTestSummary;
      this.statusMessage = '测速完成: ' + tested + ' 个节点, ' + reachable + ' 可达';
    } finally {
      this.isSpeedTesting = false;
    }
  }

  private waitForUiUpdate(durationMs: number): Promise<void> {
    return new Promise((resolve: () => void) => {
      setTimeout(resolve, durationMs);
    });
  }

  private async measureProxyNodeDelay(node: ProxyNode): Promise<number> {
    if (!this.controllerStatus.available && !this.coreBridgeState.controllerReady) {
      return -1;
    }

    const result: ControllerTextResult = await MihomoControllerService.testDelay(node.name, 5000);
    return this.parseControllerDelay(result);
  }

  private getSpeedTestBlockedState(targetCount: number): SpeedTestBlockedState | undefined {
    if (!this.controllerStatus.available && !this.coreBridgeState.controllerReady) {
      return {
        nodeDelay: '核心未就绪',
        nodeStatus: 'pending',
        statusMessage: `controller 未就绪，未对 ${targetCount} 个节点发起测速`,
        progress: `未开始：controller 未就绪，未对 ${targetCount} 个节点发起测速`,
        summary: '测速未开始：controller 未就绪；节点未标记 timeout'
      };
    }

    return undefined;
  }

  private parseControllerDelay(result: ControllerTextResult): number {
    if (!result.ok) {
      return -1;
    }
    try {
      const parsed = JSON.parse(result.raw) as Record<string, number>;
      const delay: number = parsed['delay'];
      return delay > 0 ? delay : -1;
    } catch (err) {
      return -1;
    }
  }

  private async waitForVpnTunReady(maxAttempts: number, intervalMs: number): Promise<RuntimeTunStatus> {
    let latest: RuntimeTunStatus = {
      ready: false,
      message: 'VPN TUN 尚未就绪',
      raw: '',
      enabled: false,
      fileDescriptor: 0,
      stack: ''
    };

    for (let index = 0; index < maxAttempts; index++) {
      const result: ControllerTextResult = await MihomoControllerService.getConfig();
      if (result.ok) {
        latest = this.parseRuntimeTunStatus(result.raw);
      } else {
        latest = {
          ready: false,
          message: `读取 TUN 状态失败：${result.message}`,
          raw: result.raw,
          enabled: false,
          fileDescriptor: 0,
          stack: ''
        };
      }

      if (latest.ready) {
        return latest;
      }
      if (index < maxAttempts - 1) {
        await this.waitForUiUpdate(intervalMs);
      }
    }
    return latest;
  }

  private parseRuntimeTunStatus(raw: string): RuntimeTunStatus {
    try {
      const parsed = JSON.parse(raw) as Record<string, Object>;
      const tun = parsed['tun'] as Record<string, Object>;
      if (!tun) {
        return {
          ready: false,
          message: 'VPN TUN 未启用：controller 未返回 tun 配置',
          raw: raw,
          enabled: false,
          fileDescriptor: 0,
          stack: ''
        };
      }

      const enabled: boolean = tun['enable'] === true;
      const fdValue: Object = tun['file-descriptor'];
      const fileDescriptor: number = typeof fdValue === 'number' ? fdValue as number : 0;
      const stackValue: Object = tun['stack'];
      const stack: string = typeof stackValue === 'string' ? stackValue as string : '';
      const ready: boolean = enabled && fileDescriptor > 0;
      return {
        ready: ready,
        message: ready ? `VPN TUN 已启用：fd=${fileDescriptor} stack=${stack}` :
          `VPN TUN 未启用：enable=${enabled ? 'true' : 'false'} fd=${fileDescriptor} stack=${stack}`,
        raw: raw,
        enabled: enabled,
        fileDescriptor: fileDescriptor,
        stack: stack
      };
    } catch (err) {
      return {
        ready: false,
        message: 'VPN TUN 状态解析失败',
        raw: raw,
        enabled: false,
        fileDescriptor: 0,
        stack: ''
      };
    }
  }

  private updateProxyNodeDelay(targetIndex: number, targetName: string, delay: string, status: string): void {
    const nodes: ProxyNode[] = [];
    for (let index = 0; index < this.proxyNodes.length; index++) {
      const node: ProxyNode = this.proxyNodes[index];
      if (index === targetIndex && node.name === targetName) {
        nodes.push(this.copyProxyNodeWithDelay(node, delay, status));
      } else {
        nodes.push(this.copyProxyNodeWithDelay(node, node.delay, node.status ? node.status : ''));
      }
    }
    this.proxyNodes = nodes;
  }

  private updateVisibleProxyNodeDelay(targetIndexes: number[], delay: string, status: string): void {
    const nodes: ProxyNode[] = [];
    for (let index = 0; index < this.proxyNodes.length; index++) {
      const node: ProxyNode = this.proxyNodes[index];
      if (targetIndexes.indexOf(index) >= 0) {
        nodes.push(this.copyProxyNodeWithDelay(node, delay, status));
      } else {
        nodes.push(this.copyProxyNodeWithDelay(node, node.delay, node.status ? node.status : ''));
      }
    }
    this.proxyNodes = nodes;
  }

  private copyProxyNodeWithDelay(node: ProxyNode, delay: string, status: string): ProxyNode {
    return {
      name: node.name,
      meta: node.meta,
      delay: delay,
      selected: node.selected,
      status: status,
      server: node.server ? node.server : '',
      port: node.port ? node.port : 0
    };
  }

  private getSubtitle(): string {
    if (this.showSettings) { return 'VPN · DNS · 核心' }
    if (this.currentTab === 'proxies') {
      return this.profileState.currentUid.length > 0 ? '节点列表 · 等待核心同步' : '请先导入配置'
    }
    if (this.currentTab === 'profiles') { return `${this.profileState.items.length} 个配置` }
    if (this.currentTab === 'diagnostics') {
      return this.controllerStatus.available ? `controller ${this.controllerStatus.version}` : '诊断与运行配置'
    }
    return this.liveConnected ? `已连接 · ${this.modeLabel(this.proxyMode)}模式` : '未连接'
  }

  private createProfileNameFromUrl(url: string): string {
    let value: string = url;
    value = value.replace('https://', '').replace('http://', '');
    const slashIndex: number = value.indexOf('/');
    if (slashIndex > 0) { value = value.substring(0, slashIndex) }
    return value.length > 0 ? value : '远程订阅';
  }
}
