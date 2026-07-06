@Component
export struct PillBadge {
  @Prop text: string = '';
  @Prop color: string = '#0F766E';
  @Prop backgroundColor: string = '#E6FFFB';

  build() {
    Text(this.text)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.color)
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .backgroundColor(this.backgroundColor)
      .borderRadius(12)
  }
}
