import { PillBadge } from './PillBadge';

@Component
export struct StatusLine {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop status: string = '';

  build() {
    Row() {
      Column() {
        Text(this.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#0F172A')
        Text(this.subtitle)
          .fontSize(12)
          .fontColor('#64748B')
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      PillBadge({
        text: this.status,
        color: this.status === '正常' ? '#0F766E' : '#2563EB',
        backgroundColor: this.status === '正常' ? '#E6FFFB' : '#EFF6FF'
      })
    }
    .padding(10)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .border({ width: 1, color: '#E2E8F0' })
  }
}
