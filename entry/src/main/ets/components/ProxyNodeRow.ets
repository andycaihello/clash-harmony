@Component
export struct ProxyNodeRow {
  @Prop name: string = '';
  @Prop meta: string = '';
  @Prop delay: string = '待测';
  @Prop selected: boolean = false;
  @Prop status: string = '';
  onSelect?: () => void;

  build() {
    Row() {
      Column() {
        Text(this.name)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#0F172A')
        Text(this.meta)
          .fontSize(12)
          .fontColor('#64748B')
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(this.delay)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.status === 'dead' ? '#DC2626' : this.status === 'slow' ? '#D97706' : '#0F766E')
    }
    .padding(10)
    .backgroundColor(this.selected ? '#E6FFFB' : '#FFFFFF')
    .borderRadius(8)
    .border({ width: 1, color: this.selected ? '#99F6E4' : '#E2E8F0' })
    .onClick(() => {
      if (this.onSelect) {
        this.onSelect();
      }
    })
  }
}
