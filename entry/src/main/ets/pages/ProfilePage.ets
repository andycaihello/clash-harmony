import { ClashProfile, ProfileState, createEmptyProfileState } from '../models/Profile';
import { ImportPanel } from '../components/ImportPanel';
import { SectionTitle } from '../components/SectionTitle';
import { MetricTile } from '../components/MetricTile';
import { EmptyState } from '../components/EmptyState';
import { ProfileRow } from '../components/ProfileRow';

@Component
export struct ProfilePage {
  @Prop profileState: ProfileState = createEmptyProfileState();
  @Prop proxyNodeCount: number = 0;
  @Prop runtimeConfigInfo: string = '尚未生成运行配置';
  @State showImportPanel: boolean = false;
  @State importName: string = '';
  @State importUrl: string = '';
  onAddRemoteProfile?: (name: string, url: string) => void;
  onImportFromClipboard?: () => void;
  onImportLocalFile?: () => void;
  onActivateProfile?: (uid: string) => void;
  onRemoveProfile?: (uid: string) => void;
  onUpdateProfile?: (uid: string) => void;
  onUpdateAllProfiles?: () => void;

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          Button('导入订阅')
            .layoutWeight(1)
            .height(38)
            .fontColor('#FFFFFF')
            .backgroundColor('#0F766E')
            .borderRadius(8)
            .onClick(() => {
              this.showImportPanel = !this.showImportPanel;
            })
          Button('本地文件')
            .layoutWeight(1)
            .height(38)
            .fontColor('#0F172A')
            .backgroundColor('#EEF2F7')
            .borderRadius(8)
            .onClick(() => {
              if (this.onImportLocalFile) {
                this.onImportLocalFile();
              }
            })
          Button('剪贴板')
            .layoutWeight(1)
            .height(38)
            .fontColor('#0F172A')
            .backgroundColor('#EEF2F7')
            .borderRadius(8)
            .onClick(() => {
              if (this.onImportFromClipboard) {
                this.onImportFromClipboard();
              }
            })
        }

        if (this.showImportPanel) {
          ImportPanel({
            importName: this.importName,
            importUrl: this.importUrl,
            onNameChange: (value: string) => {
              this.importName = value;
            },
            onUrlChange: (value: string) => {
              this.importUrl = value;
            },
            onSave: () => {
              if (this.onAddRemoteProfile) {
                this.onAddRemoteProfile(this.importName, this.importUrl);
              }
              this.showImportPanel = false;
              this.importUrl = '';
              this.importName = '';
            },
            onCancel: () => {
              this.showImportPanel = false;
            }
          })
        }

        Column({ space: 8 }) {
          SectionTitle({
            title: `配置列表 · ${this.profileState.items.length}`,
            action: '全量更新',
            onAction: () => {
              if (this.onUpdateAllProfiles) {
                this.onUpdateAllProfiles();
              }
            }
          })
          if (this.profileState.items.length === 0) {
            EmptyState({ title: '还没有配置', subtitle: '先导入一个订阅 URL，后续会接入本地 YAML 和备份包。' })
          } else {
            ForEach(this.profileState.items, (item: ClashProfile) => {
              ProfileRow({
                profile: item,
                isCurrent: item.uid === this.profileState.currentUid,
                onActivate: () => {
                  if (this.onActivateProfile) {
                    this.onActivateProfile(item.uid);
                  }
                },
                onUpdate: () => {
                  if (this.onUpdateProfile) {
                    this.onUpdateProfile(item.uid);
                  }
                },
                onRemove: () => {
                  if (this.onRemoveProfile) {
                    this.onRemoveProfile(item.uid);
                  }
                }
              })
            }, (item: ClashProfile) => item.uid)
          }
        }
        .padding(12)
        .backgroundColor('#FFFFFF')
        .borderRadius(8)
        .border({ width: 1, color: '#DBE3EF' })

        Column({ space: 10 }) {
          SectionTitle({ title: '配置摘要', action: '' })
          Row({ space: 8 }) {
            MetricTile({ label: '订阅', value: `${this.profileState.items.length}` })
            MetricTile({ label: '节点', value: `${this.proxyNodeCount}` })
            MetricTile({ label: '运行配置', value: this.runtimeConfigInfo === '尚未生成运行配置' ? '未准备' : '已准备' })
          }
        }
        .padding(12)
        .backgroundColor('#FFFFFF')
        .borderRadius(8)
        .border({ width: 1, color: '#DBE3EF' })
      }
      .padding(16)
    }
    .layoutWeight(1)
  }
}
