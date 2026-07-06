import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { ClashProfile, ProfileState } from '../models/Profile';
import { CoreService } from './CoreService';

export interface ParsedProxyNode {
  name: string;
  type: string;
  udp: boolean;
  server: string;
  port: number;
}

export interface ParsedConfigSummary {
  ok: boolean;
  message: string;
  nodes: ParsedProxyNode[];
}

export class ClashConfigParserService {
  static async parseCurrentProfile(context: common.Context, state: ProfileState): Promise<ParsedConfigSummary> {
    const current: ClashProfile | undefined = CoreService.getCurrentProfile(state);
    if (!current || current.filePath.length === 0) {
      return {
        ok: false,
        message: '当前配置尚未下载',
        nodes: []
      };
    }

    try {
      const text: string = await fileIo.readText(current.filePath);
      const nodes: ParsedProxyNode[] = ClashConfigParserService.parseProxyNodes(text);
      return {
        ok: nodes.length > 0,
        message: nodes.length > 0 ? `解析到 ${nodes.length} 个节点` : '未解析到 proxies 节点',
        nodes: nodes
      };
    } catch (err) {
      return {
        ok: false,
        message: '读取当前配置失败',
        nodes: []
      };
    }
  }

  static parseProxyNodes(text: string): ParsedProxyNode[] {
    const lines: string[] = text.split('\n');
    const nodes: ParsedProxyNode[] = [];
    let inProxies: boolean = false;
    let currentName: string = '';
    let currentType: string = '';
    let currentUdp: boolean = false;
    let currentServer: string = '';
    let currentPort: number = 0;

    for (let index = 0; index < lines.length; index++) {
      const rawLine: string = lines[index];
      const trimmed: string = rawLine.trim();
      if (trimmed.length === 0 || trimmed.startsWith('#')) {
        continue;
      }

      if (!rawLine.startsWith(' ') && !rawLine.startsWith('\t')) {
        if (inProxies) {
          ClashConfigParserService.pushNode(nodes, currentName, currentType, currentUdp, currentServer, currentPort);
          currentName = '';
          currentType = '';
          currentUdp = false;
          currentServer = '';
          currentPort = 0;
        }
        inProxies = trimmed === 'proxies:';
        continue;
      }

      if (!inProxies) {
        continue;
      }

      if (trimmed.startsWith('- ')) {
        ClashConfigParserService.pushNode(nodes, currentName, currentType, currentUdp, currentServer, currentPort);
        currentName = ClashConfigParserService.readInlineValue(trimmed, 'name');
        currentType = ClashConfigParserService.readInlineValue(trimmed, 'type');
        currentUdp = ClashConfigParserService.readInlineValue(trimmed, 'udp') === 'true';
        currentServer = ClashConfigParserService.readInlineValue(trimmed, 'server');
        const portStr: string = ClashConfigParserService.readInlineValue(trimmed, 'port');
        currentPort = portStr.length > 0 ? parseInt(portStr) : 0;
        continue;
      }

      if (currentName.length >= 0 && trimmed.startsWith('name:')) {
        currentName = ClashConfigParserService.cleanValue(trimmed.substring(5));
      } else if (trimmed.startsWith('type:')) {
        currentType = ClashConfigParserService.cleanValue(trimmed.substring(5));
      } else if (trimmed.startsWith('udp:')) {
        currentUdp = ClashConfigParserService.cleanValue(trimmed.substring(4)) === 'true';
      } else if (trimmed.startsWith('server:')) {
        currentServer = ClashConfigParserService.cleanValue(trimmed.substring(7));
      } else if (trimmed.startsWith('port:')) {
        const portVal: string = ClashConfigParserService.cleanValue(trimmed.substring(5));
        currentPort = portVal.length > 0 ? parseInt(portVal) : 0;
      }
    }

    if (inProxies) {
      ClashConfigParserService.pushNode(nodes, currentName, currentType, currentUdp, currentServer, currentPort);
    }
    return nodes;
  }

  private static pushNode(nodes: ParsedProxyNode[], name: string, type: string, udp: boolean, server: string, port: number): void {
    if (name.length === 0) {
      return;
    }
    nodes.push({
      name: name,
      type: type.length > 0 ? type : 'proxy',
      udp: udp,
      server: server,
      port: port
    });
  }

  private static readInlineValue(line: string, key: string): string {
    const token: string = `${key}:`;
    const index: number = line.indexOf(token);
    if (index < 0) {
      return '';
    }

    let end: number = line.indexOf(',', index);
    if (end < 0) {
      end = line.length;
    }
    return ClashConfigParserService.cleanValue(line.substring(index + token.length, end));
  }

  private static cleanValue(value: string): string {
    let text: string = value.trim();
    if (text.startsWith('"') && text.endsWith('"') && text.length >= 2) {
      text = text.substring(1, text.length - 1);
    }
    if (text.startsWith("'") && text.endsWith("'") && text.length >= 2) {
      text = text.substring(1, text.length - 1);
    }
    return text;
  }
}
