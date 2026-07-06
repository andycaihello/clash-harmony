@Component
export struct LogLine {
  @Prop time: string = '--:--';
  @Prop level: string = 'info';
  @Prop message: string = '';

  build() {
    Row({ space: 8 }) {
      Text(this.time)
        .fontSize(11)
        .fontColor('#64748B')
      Text(this.level)
        .fontSize(11)
        .fontColor(this.level === 'warn' ? '#D97706' : '#2563EB')
      Text(this.message)
        .fontSize(11)
        .fontColor('#0F172A')
        .layoutWeight(1)
    }
    .padding({ top: 6, bottom: 6 })
  }
}
