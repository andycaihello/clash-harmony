import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CoreBridgeService, CoreBridgeState } from '../services/CoreBridgeService';
import { CoreService, CoreSummary } from '../services/CoreService';
import { ClashProfile, createEmptyProfileState, ProfileState } from '../models/Profile';
import { ControllerStatus, MihomoControllerService } from '../services/MihomoControllerService';
import { ProfileStore } from '../services/ProfileStore';
import { RuntimeConfigResult, RuntimeConfigService } from '../services/RuntimeConfigService';
import { SubscriptionService, SubscriptionUpdateResult } from '../services/SubscriptionService';
import { VpnService } from '../services/VpnService';
import { ClashConfigParserService, ParsedConfigSummary, ParsedProxyNode } from '../services/ClashConfigParserService';
import { StatusCard } from '../components/StatusCard';
import { ModeSelector } from '../components/ModeSelector';
import { SectionTitle } from '../components/SectionTitle';
import { StatusLine } from '../components/StatusLine';
import { PillBadge } from '../components/PillBadge';
import { MetricTile } from '../components/MetricTile';

interface ProxyNode {
  name: string;
  meta: string;
  delay: string;
  selected?: boolean;
  status?: string;
}

const LOG_DOMAIN: number = 0x0001;
const LOG_TAG: string = 'ClashHarmonyHomePage';

@Component
export struct HomePage {
  @Prop summary: CoreSummary = CoreService.createSummary(createEmptyProfileState(), false);
  @Prop vpnActionText: string = '连接';
  @Prop statusMessage: string = '请先导入或启用一个配置';
  @Prop runtimeConfigInfo: string = '尚未生成运行配置';
  @Prop profileState: ProfileState = createEmptyProfileState();
  onToggleVpn?: () => void;
  onNavigateToTab?: (tab: string) => void;

  build() {
    Scroll() {
      Column({ space: 12 }) {
        this.buildStatusCard()
        this.buildModeCard()
        this.buildCurrentRouteCard()
        this.buildRecentStatusCard()
      }
      .padding(16)
    }
    .layoutWeight(1)
  }

  @Builder
  private buildStatusCard() {
    StatusCard({
      summary: this.summary,
      vpnActionText: this.vpnActionText,
      statusMessage: this.statusMessage,
      onToggleVpn: () => {
        if (this.onToggleVpn) {
          this.onToggleVpn();
        }
      }
    })
  }

  @Builder
  private buildModeCard() {
    Column({ space: 10 }) {
      SectionTitle({ title: '运行模式', action: '' })
      ModeSelector({
        currentMode: this.summary.mode,
        onModeChange: (mode: string) => {
        }
      })
    }
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .border({ width: 1, color: '#DBE3EF' })
  }

  @Builder
  private buildCurrentRouteCard() {
    Column({ space: 10 }) {
      Row() {
        Text('当前链路')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
        Button('切换')
          .height(30)
          .fontSize(12)
          .backgroundColor('#EEF2F7')
          .fontColor('#0F172A')
          .borderRadius(8)
          .onClick(() => {
            if (this.onNavigateToTab) {
              this.onNavigateToTab('proxies');
            }
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      this.buildInfoRow('配置', this.summary.profileName)
      this.buildInfoRow('策略组', this.summary.proxyName)
      this.buildInfoRow('运行配置', this.runtimeConfigInfo === '尚未生成运行配置' ? '未准备' : '已准备')
    }
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .border({ width: 1, color: '#DBE3EF' })
  }

  @Builder
  private buildRecentStatusCard() {
    Column({ space: 8 }) {
      SectionTitle({ title: '最近状态', action: '查看', onAction: () => {
          if (this.onNavigateToTab) {
            this.onNavigateToTab('diagnostics');
          }
        }
      })
      StatusLine({
        title: '配置状态',
        subtitle: this.profileState.currentUid.length > 0 ? '已选择当前配置' : '等待导入订阅',
        status: this.profileState.currentUid.length > 0 ? '正常' : '待处理'
      })
      StatusLine({
        title: '运行配置',
        subtitle: this.runtimeConfigInfo,
        status: this.runtimeConfigInfo === '尚未生成运行配置' ? '待处理' : '正常'
      })
      StatusLine({
        title: '核心状态',
        subtitle: 'VPN TUN 已接入，mihomo native 桥待接入',
        status: '计划'
      })
    }
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .border({ width: 1, color: '#DBE3EF' })
  }

  @Builder
  private buildInfoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor('#64748B')
      Text(value)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#0F172A')
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
  }
}
