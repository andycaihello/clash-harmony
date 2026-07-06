import { SwitchRow } from '../components/SwitchRow';
import { StatusLine } from '../components/StatusLine';

@Component
export struct SettingsPage {
  onExportLogs?: () => void;

  build() {
    Scroll() {
      Column({ space: 12 }) {
        SwitchRow({ title: '后台持续运行', subtitle: '连接后显示系统可见状态', enabled: true })
        SwitchRow({ title: 'IPv6', subtitle: '跟随配置，异常时提示', enabled: false })
        StatusLine({ title: 'DNS 模式', subtitle: 'fake-ip . 增强模式', status: '配置' })
        StatusLine({ title: 'mihomo 核心', subtitle: 'Alpha 通道关闭 . 日志 info', status: '正常' })
        SwitchRow({ title: '外部控制器', subtitle: '仅本机访问，默认关闭局域网', enabled: false })
        SwitchRow({ title: '诊断包脱敏', subtitle: '隐藏订阅 token、节点密码、secret', enabled: true })
        StatusLine({
          title: '本地备份',
          subtitle: '最近备份：今天 10:21',
          status: '导出'
        })
      }
      .padding(16)
    }
    .layoutWeight(1)
  }
}
