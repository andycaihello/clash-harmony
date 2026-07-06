@Component
export struct MetricTile {
  @Prop label: string = '';
  @Prop value: string = '';

  build() {
    Column() {
      Text(this.label)
        .fontSize(12)
        .fontColor('#64748B')
      Text(this.value)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#0F172A')
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .padding(10)
    .backgroundColor('#F8FAFC')
    .borderRadius(8)
    .border({ width: 1, color: '#E2E8F0' })
  }
}
