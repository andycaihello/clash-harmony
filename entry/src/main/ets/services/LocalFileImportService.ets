import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { ClashProfile, createLocalProfile, ProfileState } from '../models/Profile';
import { ClashConfigParserService, ParsedProxyNode } from './ClashConfigParserService';
import { GenericSubscriptionConverterService, ConvertedSubscription } from './GenericSubscriptionConverterService';
import { ProfileStore } from './ProfileStore';

export interface FileImportResult {
  ok: boolean;
  message: string;
  state: ProfileState;
}

export class LocalFileImportService {
  static async pickAndImport(context: common.Context): Promise<FileImportResult> {
    const state: ProfileState = await ProfileStore.load(context);
    try {
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const uris: string[] = await documentPicker.select({
        maxSelectNumber: 1,
        fileSuffixFilters: ['YAML|.yaml,.yml', 'Text|.txt,.conf', 'All|.*']
      });
      if (uris.length === 0) {
        return LocalFileImportService.failure('未选择文件', state);
      }

      const uri: string = uris[0];
      const content: string = await fileIo.readText(uri);
      return LocalFileImportService.importFromContent(context, content, uri);
    } catch (err) {
      return LocalFileImportService.failure('本地文件导入失败，请确认文件可访问且为文本 YAML', state);
    }
  }

  static async importFromContent(context: common.Context, content: string, fileName: string): Promise<FileImportResult> {
    const state: ProfileState = await ProfileStore.load(context);
    if (content.trim().length === 0) {
      return LocalFileImportService.failure('文件内容为空', state);
    }

    const converted: ConvertedSubscription = GenericSubscriptionConverterService.normalizeToClashYaml(content);
    if (!converted.ok) {
      return LocalFileImportService.failure(converted.message, state);
    }

    const uid: string = `file_${Date.now()}`;
    const dir: string = `${context.filesDir}/profiles`;
    await LocalFileImportService.ensureDir(dir);
    const path: string = `${dir}/${uid}.yaml`;
    await LocalFileImportService.writeText(path, converted.text);

    const nodes: ParsedProxyNode[] = ClashConfigParserService.parseProxyNodes(converted.text);
    const profileName: string = LocalFileImportService.cleanFileName(fileName);
    const profile: ClashProfile = createLocalProfile(
      profileName,
      path,
      nodes.length,
      LocalFileImportService.formatBytes(converted.text.length)
    );
    const nextState: ProfileState = await ProfileStore.replace(context, profile);

    const message: string = converted.converted ?
      `已将文件转换为 Clash YAML，解析 ${nodes.length} 个节点` :
      `已导入文件，解析 ${nodes.length} 个节点`;

    return {
      ok: true,
      message: message,
      state: nextState
    };
  }

  static async importYamlText(context: common.Context, yaml: string, profileName: string): Promise<FileImportResult> {
    const state: ProfileState = await ProfileStore.load(context);
    if (yaml.trim().length === 0) {
      return LocalFileImportService.failure('YAML 内容为空', state);
    }

    const isClashFormat: boolean = yaml.indexOf('proxies:') >= 0 ||
      yaml.indexOf('proxy-providers:') >= 0 ||
      yaml.indexOf('proxy-groups:') >= 0 ||
      yaml.indexOf('rules:') >= 0;

    if (!isClashFormat) {
      return LocalFileImportService.failure('文件内容不是 Clash/Mihomo YAML 格式', state);
    }

    const uid: string = `file_${Date.now()}`;
    const dir: string = `${context.filesDir}/profiles`;
    await LocalFileImportService.ensureDir(dir);
    const path: string = `${dir}/${uid}.yaml`;
    await LocalFileImportService.writeText(path, yaml);

    const nodes: ParsedProxyNode[] = ClashConfigParserService.parseProxyNodes(yaml);
    const name: string = profileName.length > 0 ? profileName : '本地文件';
    const profile: ClashProfile = createLocalProfile(
      name,
      path,
      nodes.length,
      LocalFileImportService.formatBytes(yaml.length)
    );
    const nextState: ProfileState = await ProfileStore.replace(context, profile);

    return {
      ok: true,
      message: `已导入本地配置，解析 ${nodes.length} 个节点`,
      state: nextState
    };
  }

  private static cleanFileName(fileName: string): string {
    if (fileName.length === 0) {
      return '本地文件';
    }

    let name: string = fileName;

    const lastSlash: number = Math.max(name.lastIndexOf('/'), name.lastIndexOf('\\'));
    if (lastSlash >= 0) {
      name = name.substring(lastSlash + 1);
    }

    const lastDot: number = name.lastIndexOf('.');
    if (lastDot > 0) {
      name = name.substring(0, lastDot);
    }

    return name.length > 0 ? name : '本地文件';
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

  private static formatBytes(length: number): string {
    if (length < 1024) {
      return `${length} B`;
    }
    if (length < 1024 * 1024) {
      return `${Math.round(length / 1024)} KB`;
    }
    return `${Math.round(length / 1024 / 1024)} MB`;
  }

  private static failure(message: string, state: ProfileState): FileImportResult {
    return {
      ok: false,
      message: message,
      state: state
    };
  }
}
