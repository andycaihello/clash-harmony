import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { ClashProfile, createLocalProfile, createRemoteProfile, ProfileState } from '../models/Profile';
import { ClashConfigParserService, ParsedProxyNode } from './ClashConfigParserService';
import { ProfileStore } from './ProfileStore';

export interface ClipboardImportResult {
  ok: boolean;
  message: string;
  state: ProfileState;
}

export class ClipboardImportService {
  static async importProfile(context: common.Context): Promise<ClipboardImportResult> {
    const state: ProfileState = await ProfileStore.load(context);
    try {
      const systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      const data: pasteboard.PasteData = await systemPasteboard.getData();
      const text: string = data.getPrimaryText().trim();
      if (text.length === 0) {
        return ClipboardImportService.failure('剪贴板没有可导入的文本内容', state);
      }

      if (text.startsWith('http://') || text.startsWith('https://')) {
        const name: string = ClipboardImportService.createProfileNameFromUrl(text);
        const next: ProfileState = await ProfileStore.addRemote(context, createRemoteProfile(name, text));
        return {
          ok: true,
          message: `已从剪贴板导入订阅：${name}`,
          state: next
        };
      }

      if (!ClipboardImportService.looksLikeClashYaml(text)) {
        return ClipboardImportService.failure('剪贴板内容不是订阅 URL 或 Clash YAML', state);
      }

      const uid: string = `clipboard_${Date.now()}`;
      const dir: string = `${context.filesDir}/profiles`;
      await ClipboardImportService.ensureDir(dir);
      const path: string = `${dir}/${uid}.yaml`;
      await ClipboardImportService.writeText(path, text);
      const nodes: ParsedProxyNode[] = ClashConfigParserService.parseProxyNodes(text);
      const profile: ClashProfile = createLocalProfile('剪贴板配置', path, nodes.length, ClipboardImportService.formatBytes(text.length));
      const nextState: ProfileState = await ProfileStore.replace(context, profile);
      return {
        ok: true,
        message: `已从剪贴板导入本地配置，解析 ${nodes.length} 个节点`,
        state: nextState
      };
    } catch (err) {
      return ClipboardImportService.failure('剪贴板导入失败，请确认已复制文本并授权读取', state);
    }
  }

  private static looksLikeClashYaml(text: string): boolean {
    return text.indexOf('proxies:') >= 0 ||
      text.indexOf('proxy-providers:') >= 0 ||
      text.indexOf('proxy-groups:') >= 0 ||
      text.indexOf('rules:') >= 0;
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

  private static createProfileNameFromUrl(url: string): string {
    let value: string = url.replace('https://', '').replace('http://', '');
    const slashIndex: number = value.indexOf('/');
    if (slashIndex > 0) {
      value = value.substring(0, slashIndex);
    }
    return value.length > 0 ? value : '远程订阅';
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

  private static failure(message: string, state: ProfileState): ClipboardImportResult {
    return {
      ok: false,
      message: message,
      state: state
    };
  }
}
