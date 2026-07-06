import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { ClashProfile, ProfileState } from '../models/Profile';
import { CoreService } from './CoreService';
import { ConvertedSubscription, GenericSubscriptionConverterService } from './GenericSubscriptionConverterService';
import { ProfileStore } from './ProfileStore';

const RUNTIME_DIR_NAME: string = 'runtime';
const RUNTIME_CONFIG_NAME: string = 'current.yaml';

export interface RuntimeConfigResult {
  ok: boolean;
  message: string;
  configPath: string;
  profileName: string;
  nodeCount: number;
  size: string;
}

export class RuntimeConfigService {
  static async prepareCurrentProfile(context: common.Context, state?: ProfileState): Promise<RuntimeConfigResult> {
    const profileState: ProfileState = state ? state : await ProfileStore.load(context);
    const current: ClashProfile | undefined = CoreService.getCurrentProfile(profileState);
    if (!current) {
      return RuntimeConfigService.failure('请先导入并启用一个配置');
    }

    if (current.filePath.length === 0) {
      return RuntimeConfigService.failure('请先更新订阅，生成本地 YAML 配置');
    }

    try {
      const exists: boolean = await fileIo.access(current.filePath);
      if (!exists) {
        return RuntimeConfigService.failure('当前配置文件不存在，请重新更新订阅');
      }

      const sourceText: string = await fileIo.readText(current.filePath);
      const converted: ConvertedSubscription = GenericSubscriptionConverterService.normalizeToClashYaml(sourceText);
      const resolved: ConfigTextResult = converted.ok ? RuntimeConfigService.configText(converted.text) : RuntimeConfigService.resolveConfigText(sourceText);
      if (!resolved.ok) {
        return RuntimeConfigService.failure(resolved.message);
      }

      const runtimeDir: string = `${context.filesDir}/${RUNTIME_DIR_NAME}`;
      await RuntimeConfigService.ensureDir(runtimeDir);
      const runtimePath: string = `${runtimeDir}/${RUNTIME_CONFIG_NAME}`;
      const runtimeText: string = await RuntimeConfigService.normalize(resolved.text);
      await RuntimeConfigService.writeText(runtimePath, runtimeText);

      return {
        ok: true,
        message: `运行配置已生成：${current.name}`,
        configPath: runtimePath,
        profileName: current.name,
        nodeCount: converted.ok && converted.nodeCount > 0 ? converted.nodeCount : current.nodeCount,
        size: RuntimeConfigService.formatBytes(runtimeText.length)
      };
    } catch (err) {
      return RuntimeConfigService.failure('生成运行配置失败，请重新更新订阅或检查文件权限');
    }
  }

  static getRuntimeConfigPath(context: common.Context): string {
    return `${context.filesDir}/${RUNTIME_DIR_NAME}/${RUNTIME_CONFIG_NAME}`;
  }

  private static async normalize(text: string): Promise<string> {
    const stripped: string = RuntimeConfigService.removeManagedTopLevelKeys(text);
    const base: string = RuntimeConfigService.trimTrailingWhitespace(stripped);
    const managed: string[] = [
      'mixed-port: 7890',
      'allow-lan: false',
      'ipv6: false',
      'mode: rule',
      'log-level: info',
      'external-controller: 127.0.0.1:9090',
      'secret: ""'
    ];
    const dns: string[] = [
      'dns:',
      '  enable: true',
      '  listen: 127.0.0.1:1053',
      '  ipv6: false',
      '  use-hosts: false',
      '  enhanced-mode: redir-host',
      '  default-nameserver:',
      '    - 223.5.5.5',
      '    - 119.29.29.29',
      '    - 8.8.8.8',
      '  nameserver:',
      '    - 223.5.5.5',
      '    - 119.29.29.29',
      '  proxy-server-nameserver:',
      '    - 223.5.5.5',
      '    - 119.29.29.29'
    ];
    const sections: string[] = [base, managed.join('\n'), dns.join('\n')];
    return `${sections.join('\n\n')}\n`;
  }

  private static removeManagedTopLevelKeys(text: string): string {
    const managedKeys: string[] = [
      'mixed-port',
      'redir-port',
      'tproxy-port',
      'allow-lan',
      'ipv6',
      'mode',
      'log-level',
      'external-controller',
      'secret'
    ];
    const managedBlockKeys: string[] = [
      'dns',
      'hosts'
    ];
    const lines: string[] = text.split('\n');
    const kept: string[] = [];
    let skippingManagedBlock: boolean = false;
    for (let index = 0; index < lines.length; index++) {
      const line: string = lines[index];
      if (skippingManagedBlock) {
        if (!RuntimeConfigService.isTopLevelConfigLine(line)) {
          continue;
        }
        skippingManagedBlock = false;
      }
      if (RuntimeConfigService.isManagedTopLevelLine(line, managedKeys)) {
        continue;
      }
      if (RuntimeConfigService.isManagedTopLevelLine(line, managedBlockKeys)) {
        skippingManagedBlock = true;
        continue;
      }
      kept.push(line);
    }
    return kept.join('\n');
  }

  private static isTopLevelConfigLine(line: string): boolean {
    if (line.length === 0 || line.startsWith(' ') || line.startsWith('\t') || line.startsWith('#')) {
      return false;
    }
    return line.indexOf(':') > 0;
  }

  private static isManagedTopLevelLine(line: string, keys: string[]): boolean {
    if (line.length === 0 || line.startsWith(' ') || line.startsWith('\t') || line.startsWith('#')) {
      return false;
    }

    const colonIndex: number = line.indexOf(':');
    if (colonIndex <= 0) {
      return false;
    }

    const key: string = line.substring(0, colonIndex).trim();
    for (let index = 0; index < keys.length; index++) {
      if (key === keys[index]) {
        return true;
      }
    }
    return false;
  }

  private static looksLikeClashYaml(text: string): boolean {
    return text.indexOf('proxies:') >= 0 ||
      text.indexOf('proxy-providers:') >= 0 ||
      text.indexOf('proxy-groups:') >= 0 ||
      text.indexOf('rules:') >= 0;
  }

  private static resolveConfigText(text: string): ConfigTextResult {
    const trimmed: string = text.trim();
    if (RuntimeConfigService.looksLikeClashYaml(trimmed)) {
      return RuntimeConfigService.configText(trimmed);
    }

    if (RuntimeConfigService.containsProxyUri(trimmed)) {
      return RuntimeConfigService.configFailure('检测到通用节点订阅，请使用 Clash/Mihomo YAML 订阅链接或先转换为 YAML');
    }

    if (RuntimeConfigService.looksLikeHtml(trimmed)) {
      return RuntimeConfigService.configFailure('订阅返回的是网页或错误页，请检查订阅链接是否为 Clash YAML 地址');
    }

    const decoded: string = RuntimeConfigService.tryDecodeBase64(trimmed);
    if (decoded.length > 0) {
      if (RuntimeConfigService.looksLikeClashYaml(decoded)) {
        return RuntimeConfigService.configText(decoded);
      }
      if (RuntimeConfigService.containsProxyUri(decoded)) {
        return RuntimeConfigService.configFailure('检测到 base64 通用节点订阅，请使用 Clash/Mihomo YAML 订阅链接或先转换为 YAML');
      }
    }

    return RuntimeConfigService.configFailure('订阅内容不是 Clash/Mihomo YAML，请检查订阅类型或转换后再导入');
  }

  private static containsProxyUri(text: string): boolean {
    return text.indexOf('ss://') >= 0 ||
      text.indexOf('ssr://') >= 0 ||
      text.indexOf('vmess://') >= 0 ||
      text.indexOf('trojan://') >= 0 ||
      text.indexOf('vless://') >= 0 ||
      text.indexOf('hysteria://') >= 0 ||
      text.indexOf('hysteria2://') >= 0 ||
      text.indexOf('hy2://') >= 0 ||
      text.indexOf('tuic://') >= 0;
  }

  private static looksLikeHtml(text: string): boolean {
    const lower: string = text.toLowerCase();
    return lower.startsWith('<!doctype') ||
      lower.startsWith('<html') ||
      lower.indexOf('<body') >= 0 ||
      lower.indexOf('</html>') >= 0;
  }

  private static tryDecodeBase64(text: string): string {
    const compact: string = text.replace(/\r/g, '').replace(/\n/g, '').trim();
    if (compact.length < 16 || !RuntimeConfigService.looksLikeBase64(compact)) {
      return '';
    }

    try {
      const helper: util.Base64Helper = new util.Base64Helper();
      const bytes: Uint8Array = helper.decodeSync(compact, util.Type.BASIC);
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      return decoder.decode(bytes).trim();
    } catch (err) {
      try {
        const helper: util.Base64Helper = new util.Base64Helper();
        const bytes: Uint8Array = helper.decodeSync(compact, util.Type.BASIC_URL_SAFE);
        const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
        return decoder.decode(bytes).trim();
      } catch (innerErr) {
        return '';
      }
    }
  }

  private static looksLikeBase64(text: string): boolean {
    for (let index = 0; index < text.length; index++) {
      const code: number = text.charCodeAt(index);
      const isUpper: boolean = code >= 65 && code <= 90;
      const isLower: boolean = code >= 97 && code <= 122;
      const isDigit: boolean = code >= 48 && code <= 57;
      const isSymbol: boolean = text[index] === '+' || text[index] === '/' || text[index] === '-' || text[index] === '_' || text[index] === '=';
      if (!isUpper && !isLower && !isDigit && !isSymbol) {
        return false;
      }
    }
    return true;
  }

  private static configText(text: string): ConfigTextResult {
    return {
      ok: true,
      message: 'ok',
      text: text
    };
  }

  private static configFailure(message: string): ConfigTextResult {
    return {
      ok: false,
      message: message,
      text: ''
    };
  }

  private static async ensureDir(path: string): Promise<void> {
    try {
      await fileIo.mkdir(path, true);
    } catch (err) {
    }
  }

  private static async writeText(path: string, text: string): Promise<void> {
    let file: fileIo.File | undefined = undefined;
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      await fileIo.write(file.fd, text);
    } finally {
      if (file) {
        try {
          fileIo.closeSync(file);
        } catch (err) {
        }
      }
    }
  }

  private static trimTrailingWhitespace(text: string): string {
    let end: number = text.length;
    while (end > 0) {
      const char: string = text.substring(end - 1, end);
      if (char !== '\n' && char !== '\r' && char !== ' ' && char !== '\t') {
        break;
      }
      end--;
    }
    return text.substring(0, end);
  }

  private static formatBytes(length: number): string {
    if (length < 1024) {
      return `${length} B`;
    }
    if (length < 1024 * 1024) {
      return `${Math.round(length / 1024)} KB`;
    }
    return `${Math.round(length / 1024 / 1024)} MB`;
  }

  private static failure(message: string): RuntimeConfigResult {
    return {
      ok: false,
      message: message,
      configPath: '',
      profileName: '',
      nodeCount: 0,
      size: ''
    };
  }
}

interface ConfigTextResult {
  ok: boolean;
  message: string;
  text: string;
}
