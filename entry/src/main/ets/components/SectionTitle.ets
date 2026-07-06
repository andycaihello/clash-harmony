@Component
export struct SectionTitle {
  @Prop title: string = '';
  @Prop action: string = '';
  onAction?: () => void;

  build() {
    Row() {
      Text(this.title)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor('#0F172A')
      if (this.action.length > 0) {
        Text(this.action)
          .fontSize(12)
          .fontColor('#2563EB')
          .onClick(() => {
            if (this.onAction) {
              this.onAction();
            }
          })
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
  }
}
