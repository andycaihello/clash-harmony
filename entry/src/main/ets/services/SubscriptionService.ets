import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { ClashProfile, ProfileState } from '../models/Profile';
import { ClashConfigParserService, ParsedProxyNode } from './ClashConfigParserService';
import { ConvertedSubscription, GenericSubscriptionConverterService } from './GenericSubscriptionConverterService';
import { ProfileStore } from './ProfileStore';

export interface SubscriptionUpdateResult {
  ok: boolean;
  message: string;
  state: ProfileState;
}

export class SubscriptionService {
  static async updateProfile(context: common.Context, uid: string): Promise<SubscriptionUpdateResult> {
    const state: ProfileState = await ProfileStore.load(context);
    const profile: ClashProfile | undefined = SubscriptionService.findProfile(state, uid);
    if (!profile) {
      return {
        ok: false,
        message: '没有找到要更新的配置',
        state: state
      };
    }
    if (profile.type !== 'remote') {
      return {
        ok: false,
        message: '当前只支持更新远程订阅',
        state: state
      };
    }

    const payload: FetchResult = await SubscriptionService.fetchText(profile.source);
    if (!payload.ok) {
      return {
        ok: false,
        message: payload.message,
        state: state
      };
    }

    const converted: ConvertedSubscription = GenericSubscriptionConverterService.normalizeToClashYaml(payload.text);
    if (!converted.ok) {
      return {
        ok: false,
        message: converted.message,
        state: state
      };
    }

    const filePath: string = await SubscriptionService.writeProfileYaml(context, profile.uid, converted.text);
    const nextProfile: ClashProfile = {
      uid: profile.uid,
      type: profile.type,
      name: profile.name,
      source: profile.source,
      filePath: filePath,
      updatedAt: Date.now(),
      nodeCount: converted.nodeCount > 0 ? converted.nodeCount : SubscriptionService.estimateNodeCount(converted.text),
      traffic: SubscriptionService.formatBytes(converted.text.length)
    };
    const nextState: ProfileState = await ProfileStore.replace(context, nextProfile);

    return {
      ok: true,
      message: converted.converted ? `订阅已转换，保存 ${nextProfile.nodeCount} 个节点` : `订阅已更新，保存 ${nextProfile.nodeCount} 个节点`,
      state: nextState
    };
  }

  private static findProfile(state: ProfileState, uid: string): ClashProfile | undefined {
    for (let index = 0; index < state.items.length; index++) {
      if (state.items[index].uid === uid) {
        return state.items[index];
      }
    }
    return undefined;
  }

  private static async fetchText(url: string): Promise<FetchResult> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        readTimeout: 15000,
        connectTimeout: 8000,
        usingCache: false
      });

      const code: number = response.responseCode as number;
      if (code < 200 || code >= 300) {
        return {
          ok: false,
          message: `订阅服务器返回 HTTP ${code}`,
          text: ''
        };
      }

      const text: string = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
      if (text.length === 0) {
        return {
          ok: false,
          message: '订阅内容为空',
          text: ''
        };
      }

      return {
        ok: true,
        message: 'ok',
        text: text
      };
    } catch (err) {
      return {
        ok: false,
        message: '订阅下载失败，请检查网络、URL 或证书配置',
        text: ''
      };
    } finally {
      request.destroy();
    }
  }

  private static async writeProfileYaml(context: common.Context, uid: string, text: string): Promise<string> {
    const dir: string = `${context.filesDir}/profiles`;
    try {
      await fileIo.mkdir(dir, true);
    } catch (err) {
    }

    const path: string = `${dir}/${uid}.yaml`;
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
    return path;
  }

  private static estimateNodeCount(text: string): number {
    const nodes: ParsedProxyNode[] = ClashConfigParserService.parseProxyNodes(text);
    if (nodes.length > 0) {
      return nodes.length;
    }
    return SubscriptionService.countOccurrences(text, '- name:');
  }

  private static countOccurrences(text: string, keyword: string): number {
    let count: number = 0;
    let start: number = 0;
    while (start < text.length) {
      const index: number = text.indexOf(keyword, start);
      if (index < 0) {
        break;
      }
      count++;
      start = index + keyword.length;
    }
    return count;
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
}

interface FetchResult {
  ok: boolean;
  message: string;
  text: string;
}
