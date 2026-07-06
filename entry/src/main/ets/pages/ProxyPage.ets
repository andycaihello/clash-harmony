import { ModeSelector } from '../components/ModeSelector';
import { SwitchRow } from '../components/SwitchRow';
import { EmptyState } from '../components/EmptyState';
import { ProxyNodeRow } from '../components/ProxyNodeRow';

interface ProxyNode {
  name: string;
  meta: string;
  delay: string;
  selected?: boolean;
  status?: string;
}

@Component
export struct ProxyPage {
  @Prop proxyNodes: ProxyNode[] = [];
  @Prop proxyStatus: string = '当前配置尚未下载';
  @Prop currentMode: string = 'rule';
  onModeChange?: (mode: string) => void;
  onDelayTest?: () => void;
  onSelectNode?: (node: ProxyNode) => void;

  build() {
    Scroll() {
      Column({ space: 12 }) {
        ModeSelector({
          currentMode: this.currentMode,
          onModeChange: (mode: string) => {
            if (this.onModeChange) {
              this.onModeChange(mode);
            }
          }
        })

        Row({ space: 8 }) {
          this.buildGroupButton('Auto', true)
          this.buildGroupButton('Streaming', false)
          this.buildGroupButton('AI', false)
          this.buildGroupButton('Fallback', false)
        }

        TextInput({ placeholder: '搜索节点、地区或提供者' })
          .height(40)
          .backgroundColor('#FFFFFF')
          .borderRadius(8)

        Column({ space: 8 }) {
          Row() {
            Text(`节点列表 · ${this.proxyNodes.length}`)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
            Button('测速')
              .height(30)
              .fontSize(12)
              .fontColor('#FFFFFF')
              .backgroundColor('#2563EB')
              .borderRadius(8)
              .onClick(() => {
                if (this.onDelayTest) {
                  this.onDelayTest();
                }
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
          if (this.proxyNodes.length === 0) {
            EmptyState({ title: '暂无节点', subtitle: this.proxyStatus })
          } else {
            ForEach(this.proxyNodes, (node: ProxyNode) => {
              this.buildProxyRow(node)
            }, (node: ProxyNode) => node.name)
          }
        }
        .padding(12)
        .backgroundColor('#FFFFFF')
        .borderRadius(8)
        .border({ width: 1, color: '#DBE3EF' })

        SwitchRow({ title: '链式代理', subtitle: '高级模式关闭，开启后可设置入口和出口节点', enabled: false })
      }
      .padding(16)
    }
    .layoutWeight(1)
  }

  @Builder
  private buildGroupButton(text: string, active: boolean) {
    Text(text)
      .fontSize(13)
      .fontWeight(active ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(active ? '#2563EB' : '#64748B')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor(active ? '#EFF6FF' : '#FFFFFF')
      .borderRadius(8)
      .border({ width: 1, color: active ? '#BFDBFE' : '#DBE3EF' })
  }

  @Builder
  private buildProxyRow(node: ProxyNode) {
    ProxyNodeRow({
      name: node.name,
      meta: node.meta,
      delay: node.delay,
      selected: node.selected ? node.selected : false,
      status: node.status ? node.status : ''
    })
  }
}
