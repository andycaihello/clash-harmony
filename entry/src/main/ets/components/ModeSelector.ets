@Component
export struct ModeSelector {
  @Prop currentMode: string = 'rule';
  onModeChange?: (mode: string) => void;

  build() {
    Row({ space: 6 }) {
      ModeButton({ text: '规则', active: this.currentMode === 'rule', onClick: () => { if (this.onModeChange) { this.onModeChange('rule'); } } })
      ModeButton({ text: '全局', active: this.currentMode === 'global', onClick: () => { if (this.onModeChange) { this.onModeChange('global'); } } })
      ModeButton({ text: '直连', active: this.currentMode === 'direct', onClick: () => { if (this.onModeChange) { this.onModeChange('direct'); } } })
    }
  }
}

@Component
struct ModeButton {
  @Prop text: string = '';
  @Prop active: boolean = false;
  onClick?: () => void;

  build() {
    Text(this.text)
      .layoutWeight(1)
      .height(34)
      .textAlign(TextAlign.Center)
      .fontSize(13)
      .fontWeight(this.active ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(this.active ? '#0F172A' : '#64748B')
      .backgroundColor(this.active ? '#FFFFFF' : '#EEF2F7')
      .borderRadius(6)
      .onClick(() => {
        if (this.onClick) {
          this.onClick();
        }
      })
  }
}
