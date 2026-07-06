import { ClashProfile, formatProfileUpdatedAt } from '../models/Profile';
import { PillBadge } from './PillBadge';

@Component
export struct ProfileRow {
  @Prop profile: ClashProfile = {
    uid: '',
    type: 'remote',
    name: '',
    source: '',
    filePath: '',
    updatedAt: 0,
    nodeCount: 0,
    traffic: ''
  };
  @Prop isCurrent: boolean = false;
  onActivate?: () => void;
  onUpdate?: () => void;
  onRemove?: () => void;

  build() {
    Row() {
      Column() {
        Text(this.profile.name)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#0F172A')
        Text(`${this.profile.type === 'remote' ? '远程订阅' : '本地配置'} · ${formatProfileUpdatedAt(this.profile.updatedAt)} · ${this.profile.traffic}`)
          .fontSize(12)
          .fontColor('#64748B')
          .margin({ top: 3 })
        Text(`${this.profile.nodeCount} 个节点 · ${this.profile.filePath.length > 0 ? '已下载' : '未下载'}`)
          .fontSize(11)
          .fontColor('#94A3B8')
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.isCurrent) {
        PillBadge({ text: '当前', color: '#0F766E', backgroundColor: '#E6FFFB' })
        Button('更新')
          .height(30)
          .fontSize(12)
          .fontColor('#2563EB')
          .backgroundColor('#EFF6FF')
          .borderRadius(8)
          .onClick(() => {
            if (this.onUpdate) {
              this.onUpdate();
            }
          })
      } else {
        Button('启用')
          .height(30)
          .fontSize(12)
          .fontColor('#2563EB')
          .backgroundColor('#EFF6FF')
          .borderRadius(8)
          .onClick(() => {
            if (this.onActivate) {
              this.onActivate();
            }
          })
      }

      Button('删')
        .height(30)
        .fontSize(12)
        .fontColor('#DC2626')
        .backgroundColor('#FEF2F2')
        .borderRadius(8)
        .onClick(() => {
          if (this.onRemove) {
            this.onRemove();
          }
        })
    }
    .padding(10)
    .backgroundColor(this.isCurrent ? '#E6FFFB' : '#FFFFFF')
    .borderRadius(8)
    .border({ width: 1, color: this.isCurrent ? '#99F6E4' : '#E2E8F0' })
  }
}
