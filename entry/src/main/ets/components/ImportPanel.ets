@Component
export struct ImportPanel {
  @Prop importName: string = '';
  @Prop importUrl: string = '';
  onSave?: () => void;
  onCancel?: () => void;
  onNameChange?: (value: string) => void;
  onUrlChange?: (value: string) => void;

  build() {
    Column({ space: 10 }) {
      Text('导入远程订阅')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor('#0F172A')
      TextInput({ placeholder: '订阅名称，可留空', text: this.importName })
        .height(40)
        .backgroundColor('#F8FAFC')
        .borderRadius(8)
        .onChange((value: string) => {
          if (this.onNameChange) {
            this.onNameChange(value);
          }
        })
      TextInput({ placeholder: 'https://example.com/sub.yaml', text: this.importUrl })
        .height(40)
        .backgroundColor('#F8FAFC')
        .borderRadius(8)
        .onChange((value: string) => {
          if (this.onUrlChange) {
            this.onUrlChange(value);
          }
        })
      Row({ space: 8 }) {
        Button('取消')
          .layoutWeight(1)
          .height(36)
          .fontColor('#0F172A')
          .backgroundColor('#EEF2F7')
          .borderRadius(8)
          .onClick(() => {
            if (this.onCancel) {
              this.onCancel();
            }
          })
        Button('保存')
          .layoutWeight(1)
          .height(36)
          .fontColor('#FFFFFF')
          .backgroundColor('#0F766E')
          .borderRadius(8)
          .onClick(() => {
            if (this.onSave) {
              this.onSave();
            }
          })
      }
    }
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .border({ width: 1, color: '#99F6E4' })
  }
}
