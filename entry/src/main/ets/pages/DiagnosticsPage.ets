import { CoreSummary, CoreService } from '../services/CoreService';
import { CoreBridgeState, CoreBridgeService } from '../services/CoreBridgeService';
import { ControllerStatus, MihomoControllerService } from '../services/MihomoControllerService';
import { createEmptyProfileState } from '../models/Profile';
import { ModeSelector } from '../components/ModeSelector';
import { SectionTitle } from '../components/SectionTitle';
import { MetricTile } from '../components/MetricTile';
import { StatusLine } from '../components/StatusLine';
import { EmptyState } from '../components/EmptyState';
import { LogLine } from '../components/LogLine';

@Component
export struct DiagnosticsPage {
  @Prop summary: CoreSummary = CoreService.createSummary(createEmptyProfileState(), false);
  @Prop controllerStatus: ControllerStatus = {
    available: false,
    version: '',
    message: '尚未检查 controller',
    raw: ''
  };
  @Prop coreBridgeState: CoreBridgeState = {
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
  @Prop runtimeConfigInfo: string = '尚未生成运行配置';
  @Prop runtimeConfigPath: string = '';
  @Prop statusMessage: string = '';
  @State currentSegment: string = '连接';
  onRefreshController?: () => void;
  onSectionAction?: (action: string) => void;

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Row({ space: 6 }) {
          this.buildSegmentButton('连接', this.currentSegment === '连接')
          this.buildSegmentButton('日志', this.currentSegment === '日志')
          this.buildSegmentButton('规则', this.currentSegment === '规则')
          this.buildSegmentButton('DNS', this.currentSegment === 'DNS')
        }
        .padding(4)
        .backgroundColor('#EEF2F7')
        .borderRadius(8)

        if (this.currentSegment === '连接') {
          this.buildConnectionSegment()
        } else if (this.currentSegment === '日志') {
          this.buildLogSegment()
        } else if (this.currentSegment === '规则') {
          this.buildRulesSegment()
        } else {
          this.buildDnsSegment()
        }
      }
      .padding(16)
    }
    .layoutWeight(1)
  }

  @Builder
  private buildConnectionSegment() {
    Column({ space: 12 }) {
      Column({ space: 10 }) {
        SectionTitle({ title: '连接概览', action: '关闭全部' })
        Row({ space: 8 }) {
          MetricTile({ label: '活跃', value: `${this.summary.connections}` })
          MetricTile({ label: '下载', value: this.summary.downloadSpeed })
          MetricTile({ label: '上传', value: this.summary.uploadSpeed })
        }
      }
      .padding(12)
      .backgroundColor('#FFFFFF')
      .borderRadius(8)
      .border({ width: 1, color: '#DBE3EF' })

      Column({ space: 8 }) {
        Row() {
          Text('核心 Controller')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#0F172A')
          Button('刷新')
            .height(30)
            .fontSize(12)
            .fontColor('#FFFFFF')
            .backgroundColor('#2563EB')
            .borderRadius(8)
            .onClick(() => {
              if (this.onRefreshController) {
                this.onRefreshController();
              }
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        StatusLine({
          title: this.controllerStatus.available ? '已连接' : '未连接',
          subtitle: this.controllerStatus.available ? `mihomo ${this.controllerStatus.version}` : this.controllerStatus.message,
          status: this.controllerStatus.available ? '正常' : '待接入'
        })
      }
      .padding(12)
      .backgroundColor('#FFFFFF')
      .borderRadius(8)
      .border({ width: 1, color: '#DBE3EF' })

      Column({ space: 8 }) {
        SectionTitle({ title: 'Native Bridge', action: '' })
        StatusLine({ title: '桥接状态', subtitle: this.coreBridgeState.coreMode, status: this.coreBridgeState.running ? '运行' : '待接入' })
        StatusLine({
          title: 'Adapter',
          subtitle: this.coreBridgeState.adapterVersion.length > 0 ? `${this.coreBridgeState.adapterMode} ${this.coreBridgeState.adapterVersion}` : this.coreBridgeState.adapterMode,
          status: this.coreBridgeState.adapterMode === 'real' ? '真实核心' : 'Stub'
        })
        if (this.coreBridgeState.adapterLoadError.length > 0) {
          StatusLine({
            title: '加载信息',
            subtitle: this.coreBridgeState.adapterLoadError,
            status: this.coreBridgeState.adapterMode === 'real' ? '正常' : '待接入'
          })
        }
        StatusLine({
          title: 'TUN FD',
          subtitle: `system ${this.coreBridgeState.tunFd} / native ${this.coreBridgeState.nativeFd}`,
          status: this.coreBridgeState.nativeFd >= 0 ? '正常' : '等待'
        })
        StatusLine({
          title: 'Controller Ready',
          subtitle: this.coreBridgeState.controllerReady ? `ready ${this.coreBridgeState.controllerVersion}` : 'not ready',
          status: this.coreBridgeState.controllerReady ? '正常' : '等待'
        })
        StatusLine({
          title: '生命周期',
          subtitle: `start ${this.coreBridgeState.startCount} / stop ${this.coreBridgeState.stopCount}`,
          status: this.coreBridgeState.lastError.length > 0 ? '异常' : '正常'
        })
        if (this.coreBridgeState.lastError.length > 0) {
          StatusLine({ title: '最近错误', subtitle: this.coreBridgeState.lastError, status: '异常' })
        }
      }
      .padding(12)
      .backgroundColor('#FFFFFF')
      .borderRadius(8)
      .border({ width: 1, color: '#DBE3EF' })

      Column({ space: 8 }) {
        SectionTitle({ title: '运行配置', action: '' })
        StatusLine({
          title: this.runtimeConfigInfo,
          subtitle: this.runtimeConfigPath.length > 0 ? this.runtimeConfigPath : '等待生成',
          status: this.runtimeConfigInfo === '尚未生成运行配置' ? '待处理' : '正常'
        })
        StatusLine({ title: 'VPN 路由', subtitle: '默认路由，接管 IPv4 流量', status: '正常' })
      }
      .padding(12)
      .backgroundColor('#FFFFFF')
      .borderRadius(8)
      .border({ width: 1, color: '#DBE3EF' })

      Column({ space: 8 }) {
        SectionTitle({ title: '活跃连接', action: '' })
        if (this.controllerStatus.available) {
          EmptyState({ title: '等待连接数据', subtitle: 'controller 已连接，连接列表接口将在下一步接入。' })
        } else {
          EmptyState({ title: '暂无连接数据', subtitle: '启动 mihomo controller 后可同步活跃连接。' })
        }
      }
      .padding(12)
      .backgroundColor('#FFFFFF')
      .borderRadius(8)
      .border({ width: 1, color: '#DBE3EF' })
    }
  }

  @Builder
  private buildLogSegment() {
    Column({ space: 6 }) {
      SectionTitle({ title: '最近日志', action: '导出', onAction: () => {
          if (this.onSectionAction) {
            this.onSectionAction('导出');
          }
        }
      })
      LogLine({ time: '--:--', level: 'info', message: this.statusMessage })
      LogLine({ time: '--:--', level: 'info', message: this.controllerStatus.message })
    }
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .border({ width: 1, color: '#DBE3EF' })
  }

  @Builder
  private buildRulesSegment() {
    Column({ space: 6 }) {
      SectionTitle({ title: '规则列表', action: '' })
      EmptyState({ title: '暂无规则数据', subtitle: '启动 mihomo controller 后可查看规则列表。' })
    }
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .border({ width: 1, color: '#DBE3EF' })
  }

  @Builder
  private buildDnsSegment() {
    Column({ space: 6 }) {
      SectionTitle({ title: 'DNS 配置', action: '' })
      EmptyState({ title: '暂无 DNS 数据', subtitle: '启动 mihomo controller 后可查看 DNS 配置与缓存。' })
    }
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .border({ width: 1, color: '#DBE3EF' })
  }

  @Builder
  private buildSegmentButton(text: string, active: boolean) {
    Text(text)
      .layoutWeight(1)
      .height(34)
      .textAlign(TextAlign.Center)
      .fontSize(13)
      .fontWeight(active ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(active ? '#0F172A' : '#64748B')
      .backgroundColor(active ? '#FFFFFF' : '#EEF2F7')
      .borderRadius(6)
      .onClick(() => {
        this.currentSegment = text;
      })
  }
}
