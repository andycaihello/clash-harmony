import { util } from '@kit.ArkTS';
import { ClashConfigParserService, ParsedProxyNode } from './ClashConfigParserService';

export interface ConvertedSubscription {
  ok: boolean;
  message: string;
  text: string;
  nodeCount: number;
  converted: boolean;
}

interface ShadowsocksNode {
  name: string;
  server: string;
  port: number;
  cipher: string;
  password: string;
  plugin: string;
  pluginMode: string;
  pluginHost: string;
}

export class GenericSubscriptionConverterService {
  static normalizeToClashYaml(rawText: string): ConvertedSubscription {
    const trimmed: string = rawText.trim();
    if (GenericSubscriptionConverterService.looksLikeClashYaml(trimmed)) {
      const nodes: ParsedProxyNode[] = ClashConfigParserService.parseProxyNodes(trimmed);
      return {
        ok: true,
        message: 'Clash YAML',
        text: trimmed,
        nodeCount: nodes.length,
        converted: false
      };
    }

    const decoded: string = GenericSubscriptionConverterService.tryDecodeBase64(trimmed);
    const candidates: string[] = decoded.length > 0 ? [trimmed, decoded] : [trimmed];
    for (let index = 0; index < candidates.length; index++) {
      const nodes: ShadowsocksNode[] = GenericSubscriptionConverterService.parseShadowsocksNodes(candidates[index]);
      if (nodes.length > 0) {
        return {
          ok: true,
          message: `已将通用 Shadowsocks 订阅转换为 Clash YAML`,
          text: GenericSubscriptionConverterService.buildClashYaml(nodes),
          nodeCount: nodes.length,
          converted: true
        };
      }
    }

    return {
      ok: false,
      message: '订阅内容不是 Clash/Mihomo YAML，也未识别到可转换的 Shadowsocks 节点',
      text: '',
      nodeCount: 0,
      converted: false
    };
  }

  private static parseShadowsocksNodes(text: string): ShadowsocksNode[] {
    const nodes: ShadowsocksNode[] = [];
    const lines: string[] = text.split('\n');
    for (let index = 0; index < lines.length; index++) {
      const node: ShadowsocksNode | undefined = GenericSubscriptionConverterService.parseShadowsocksUri(lines[index].trim(), nodes.length + 1);
      if (node) {
        nodes.push(node);
      }
    }
    return nodes;
  }

  private static parseShadowsocksUri(uri: string, fallbackIndex: number): ShadowsocksNode | undefined {
    if (!uri.startsWith('ss://')) {
      return undefined;
    }

    let body: string = uri.substring(5);
    let name: string = `SS-${fallbackIndex}`;
    const hashIndex: number = body.indexOf('#');
    if (hashIndex >= 0) {
      name = GenericSubscriptionConverterService.safeDecodeURIComponent(body.substring(hashIndex + 1));
      body = body.substring(0, hashIndex);
    }

    let query: string = '';
    const queryIndex: number = body.indexOf('?');
    if (queryIndex >= 0) {
      query = body.substring(queryIndex + 1);
      body = body.substring(0, queryIndex);
    }

    let userInfo: string = '';
    let hostPort: string = '';
    const atIndex: number = body.lastIndexOf('@');
    if (atIndex >= 0) {
      const encodedUserInfo: string = body.substring(0, atIndex);
      hostPort = body.substring(atIndex + 1);
      userInfo = encodedUserInfo.indexOf(':') >= 0 ?
        GenericSubscriptionConverterService.safeDecodeURIComponent(encodedUserInfo) :
        GenericSubscriptionConverterService.tryDecodeBase64(encodedUserInfo);
    } else {
      const decoded: string = GenericSubscriptionConverterService.tryDecodeBase64(body);
      const decodedAtIndex: number = decoded.lastIndexOf('@');
      if (decodedAtIndex < 0) {
        return undefined;
      }
      userInfo = decoded.substring(0, decodedAtIndex);
      hostPort = decoded.substring(decodedAtIndex + 1);
    }

    const userColonIndex: number = userInfo.indexOf(':');
    const hostPortIndex: number = GenericSubscriptionConverterService.findHostPortSeparator(hostPort);
    if (userColonIndex <= 0 || hostPortIndex <= 0) {
      return undefined;
    }

    const port: number = Number.parseInt(hostPort.substring(hostPortIndex + 1), 10);
    if (Number.isNaN(port) || port <= 0) {
      return undefined;
    }

    const plugin: PluginInfo = GenericSubscriptionConverterService.parsePlugin(query);
    return {
      name: name.length > 0 ? name : `SS-${fallbackIndex}`,
      server: GenericSubscriptionConverterService.cleanHost(hostPort.substring(0, hostPortIndex)),
      port: port,
      cipher: userInfo.substring(0, userColonIndex),
      password: userInfo.substring(userColonIndex + 1),
      plugin: plugin.plugin,
      pluginMode: plugin.mode,
      pluginHost: plugin.host
    };
  }

  private static findHostPortSeparator(hostPort: string): number {
    if (hostPort.startsWith('[')) {
      const end: number = hostPort.indexOf(']');
      if (end > 0 && hostPort.length > end + 2 && hostPort[end + 1] === ':') {
        return end + 1;
      }
      return -1;
    }
    return hostPort.lastIndexOf(':');
  }

  private static cleanHost(host: string): string {
    let value: string = host;
    if (value.startsWith('[') && value.endsWith(']')) {
      value = value.substring(1, value.length - 1);
    }
    return GenericSubscriptionConverterService.safeDecodeURIComponent(value);
  }

  private static parsePlugin(query: string): PluginInfo {
    const rawPlugin: string = GenericSubscriptionConverterService.readQueryParam(query, 'plugin');
    const decodedPlugin: string = GenericSubscriptionConverterService.safeDecodeURIComponent(rawPlugin);
    if (decodedPlugin.length === 0) {
      return {
        plugin: '',
        mode: '',
        host: ''
      };
    }

    const parts: string[] = decodedPlugin.split(';');
    if (parts.length === 0 || parts[0] !== 'simple-obfs') {
      return {
        plugin: '',
        mode: '',
        host: ''
      };
    }

    return {
      plugin: 'obfs',
      mode: GenericSubscriptionConverterService.readPluginOption(parts, 'obfs'),
      host: GenericSubscriptionConverterService.readPluginOption(parts, 'obfs-host')
    };
  }

  private static readQueryParam(query: string, key: string): string {
    if (query.length === 0) {
      return '';
    }
    const pairs: string[] = query.split('&');
    for (let index = 0; index < pairs.length; index++) {
      const pair: string = pairs[index];
      const equalIndex: number = pair.indexOf('=');
      const pairKey: string = equalIndex >= 0 ? pair.substring(0, equalIndex) : pair;
      if (pairKey === key) {
        return equalIndex >= 0 ? pair.substring(equalIndex + 1) : '';
      }
    }
    return '';
  }

  private static readPluginOption(parts: string[], key: string): string {
    const prefix: string = `${key}=`;
    for (let index = 1; index < parts.length; index++) {
      if (parts[index].startsWith(prefix)) {
        return parts[index].substring(prefix.length);
      }
    }
    return '';
  }

  private static buildClashYaml(nodes: ShadowsocksNode[]): string {
    const lines: string[] = [
      'mixed-port: 7890',
      'allow-lan: false',
      'mode: rule',
      'log-level: info',
      'external-controller: 127.0.0.1:9090',
      'secret: ""',
      'proxies:'
    ];

    for (let index = 0; index < nodes.length; index++) {
      const node: ShadowsocksNode = nodes[index];
      lines.push(`  - name: ${GenericSubscriptionConverterService.yamlString(node.name)}`);
      lines.push('    type: ss');
      lines.push(`    server: ${GenericSubscriptionConverterService.yamlString(node.server)}`);
      lines.push(`    port: ${node.port}`);
      lines.push(`    cipher: ${GenericSubscriptionConverterService.yamlString(node.cipher)}`);
      lines.push(`    password: ${GenericSubscriptionConverterService.yamlString(node.password)}`);
      lines.push('    udp: true');
      if (node.plugin.length > 0) {
        lines.push(`    plugin: ${GenericSubscriptionConverterService.yamlString(node.plugin)}`);
        lines.push('    plugin-opts:');
        if (node.pluginMode.length > 0) {
          lines.push(`      mode: ${GenericSubscriptionConverterService.yamlString(node.pluginMode)}`);
        }
        if (node.pluginHost.length > 0) {
          lines.push(`      host: ${GenericSubscriptionConverterService.yamlString(node.pluginHost)}`);
        }
      }
    }

    lines.push('proxy-groups:');
    lines.push('  - name: Proxy');
    lines.push('    type: select');
    lines.push('    proxies:');
    for (let index = 0; index < nodes.length; index++) {
      lines.push(`      - ${GenericSubscriptionConverterService.yamlString(nodes[index].name)}`);
    }
    lines.push('rules:');
    lines.push('  - MATCH,Proxy');
    lines.push('');
    return lines.join('\n');
  }

  private static yamlString(value: string): string {
    return `'${value.replace(/'/g, "''")}'`;
  }

  private static looksLikeClashYaml(text: string): boolean {
    return text.indexOf('proxies:') >= 0 ||
      text.indexOf('proxy-providers:') >= 0 ||
      text.indexOf('proxy-groups:') >= 0 ||
      text.indexOf('rules:') >= 0;
  }

  private static tryDecodeBase64(text: string): string {
    const compact: string = GenericSubscriptionConverterService.padBase64(text.replace(/\r/g, '').replace(/\n/g, '').trim());
    if (compact.length < 4 || !GenericSubscriptionConverterService.looksLikeBase64(compact)) {
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

  private static padBase64(text: string): string {
    const remainder: number = text.length % 4;
    if (remainder === 2) {
      return `${text}==`;
    }
    if (remainder === 3) {
      return `${text}=`;
    }
    return text;
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

  private static safeDecodeURIComponent(value: string): string {
    try {
      return decodeURIComponent(value);
    } catch (err) {
      return value;
    }
  }
}

interface PluginInfo {
  plugin: string;
  mode: string;
  host: string;
}
