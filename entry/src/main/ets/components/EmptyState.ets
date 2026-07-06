@Component
export struct EmptyState {
  @Prop title: string = '';
  @Prop subtitle: string = '';

  build() {
    Column({ space: 6 }) {
      Text(this.title)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor('#0F172A')
      Text(this.subtitle)
        .fontSize(12)
        .fontColor('#64748B')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding(18)
    .backgroundColor('#F8FAFC')
    .borderRadius(8)
    .border({ width: 1, color: '#E2E8F0' })
  }
}
