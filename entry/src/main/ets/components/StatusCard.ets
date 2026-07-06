import { PillBadge } from './PillBadge';
import { MetricTile } from './MetricTile';
import { CoreSummary } from '../services/CoreService';

@Component
export struct StatusCard {
  @Prop summary: CoreSummary = {
    state: 'stopped',
    mode: 'rule',
    profileName: '',
    proxyName: '',
    uptime: '未连接',
    downloadSpeed: '0 KB/s',
    uploadSpeed: '0 KB/s',
    connections: 0
  };
  @Prop vpnActionText: string = '连接';
  @Prop statusMessage: string = '请先导入或启用一个配置';
  onToggleVpn?: () => void;

  build() {
    Column({ space: 14 }) {
      Row() {
        PillBadge({
          text: this.summary.state === 'running' ? '已连接' : '未连接',
          color: this.summary.state === 'running' ? '#0F766E' : '#D97706',
          backgroundColor: this.summary.state === 'running' ? '#E6FFFB' : '#FFF7ED'
        })
        PillBadge({ text: this.summary.uptime, color: '#2563EB', backgroundColor: '#EFF6FF' })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Button(this.vpnActionText)
        .width(124)
        .height(124)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .backgroundColor('#0F766E')
        .borderRadius(62)
        .onClick(() => {
          if (this.onToggleVpn) {
            this.onToggleVpn();
          }
        })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Up) {
            if (this.onToggleVpn) {
              this.onToggleVpn();
            }
          }
        })

      Row({ space: 8 }) {
        MetricTile({ label: '下载', value: this.summary.downloadSpeed })
        MetricTile({ label: '上传', value: this.summary.uploadSpeed })
        MetricTile({ label: '连接', value: `${this.summary.connections}` })
      }
      .width('100%')

      Text(this.statusMessage)
        .width('100%')
        .fontSize(12)
        .fontColor('#475569')
        .textAlign(TextAlign.Center)
    }
    .alignItems(HorizontalAlign.Center)
    .padding(14)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .border({ width: 1, color: '#DBE3EF' })
  }
}
