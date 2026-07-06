@Component
export struct SwitchRow {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop enabled: boolean = false;
  onToggle?: () => void;

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

      Text(this.enabled ? '开' : '关')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.enabled ? '#FFFFFF' : '#64748B')
        .width(44)
        .height(26)
        .textAlign(TextAlign.Center)
        .backgroundColor(this.enabled ? '#0F766E' : '#E2E8F0')
        .borderRadius(13)
        .onClick(() => {
          if (this.onToggle) {
            this.onToggle();
          }
        })
    }
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .border({ width: 1, color: '#E2E8F0' })
  }
}
