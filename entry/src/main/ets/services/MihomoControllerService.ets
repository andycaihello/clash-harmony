import { http } from '@kit.NetworkKit';

const DEFAULT_BASE_URL: string = 'http://127.0.0.1:9090';
const PATCH_METHOD: http.RequestMethod = 'PATCH' as http.RequestMethod;

export interface ControllerStatus {
  available: boolean;
  version: string;
  message: string;
  raw: string;
}

export interface ControllerTextResult {
  ok: boolean;
  message: string;
  raw: string;
}

export interface ConnectionMetadata {
  network: string;
  type: string;
  sourceIP: string;
  sourcePort: string;
  destinationIP: string;
  destinationPort: string;
  host: string;
  dnsMode: string;
}

export interface ConnectionInfo {
  id: string;
  metadata: ConnectionMetadata;
  upload: number;
  download: number;
  start: string;
  chains: string[];
  rule: string;
}

export interface ProxyDelayRecord {
  time: string;
  delay: number;
}

export interface ProxyGroupInfo {
  name: string;
  type: string;
  now: string;
  all: string[];
  history: ProxyDelayRecord[];
}

export interface ProxyNodeDetail {
  name: string;
  type: string;
  delay: number;
  alive: boolean;
}

export class MihomoControllerService {
  static async checkVersion(): Promise<ControllerStatus> {
    const result: ControllerResponse = await MihomoControllerService.requestText('/version', http.RequestMethod.GET, '');
    if (!result.ok) {
      return {
        available: false,
        version: '',
        message: result.message,
        raw: result.raw
      };
    }

    const version: string = MihomoControllerService.extractStringField(result.raw, 'version');
    return {
      available: true,
      version: version.length > 0 ? version : 'unknown',
      message: 'mihomo controller 已连接',
      raw: result.raw
    };
  }

  static async waitForVersion(maxAttempts: number = 10, intervalMs: number = 300): Promise<ControllerStatus> {
    let latest: ControllerStatus = {
      available: false,
      version: '',
      message: 'mihomo controller 尚未就绪',
      raw: ''
    };

    for (let index = 0; index < maxAttempts; index++) {
      latest = await MihomoControllerService.checkVersion();
      if (latest.available) {
        return latest;
      }
      if (index < maxAttempts - 1) {
        await MihomoControllerService.sleep(intervalMs);
      }
    }
    return latest;
  }

  static async setMode(mode: 'rule' | 'global' | 'direct'): Promise<boolean> {
    const result: ControllerResponse = await MihomoControllerService.requestText(
      '/configs',
      PATCH_METHOD,
      JSON.stringify({ mode: mode })
    );
    return result.ok;
  }

  static async getConfig(): Promise<ControllerTextResult> {
    return MihomoControllerService.toTextResult(
      await MihomoControllerService.requestText('/configs', http.RequestMethod.GET, '')
    );
  }

  static async getProxies(): Promise<ControllerTextResult> {
    return MihomoControllerService.toTextResult(
      await MihomoControllerService.requestText('/proxies', http.RequestMethod.GET, '')
    );
  }

  static async selectProxy(groupName: string, proxyName: string): Promise<boolean> {
    const path: string = `/proxies/${MihomoControllerService.encodePathSegment(groupName)}`;
    const result: ControllerResponse = await MihomoControllerService.requestText(
      path,
      http.RequestMethod.PUT,
      JSON.stringify({ name: proxyName })
    );
    return result.ok;
  }

  static async testDelay(proxyName: string, timeoutMs: number = 5000, url: string = 'https://www.gstatic.com/generate_204'): Promise<ControllerTextResult> {
    const path: string = `/proxies/${MihomoControllerService.encodePathSegment(proxyName)}/delay?timeout=${timeoutMs}&url=${MihomoControllerService.encodeQueryValue(url)}`;
    return MihomoControllerService.toTextResult(
      await MihomoControllerService.requestText(path, http.RequestMethod.GET, '', timeoutMs + 1500)
    );
  }

  static async getConnections(): Promise<ControllerTextResult> {
    return MihomoControllerService.toTextResult(
      await MihomoControllerService.requestText('/connections', http.RequestMethod.GET, '')
    );
  }

  static async closeAllConnections(): Promise<boolean> {
    const result: ControllerResponse = await MihomoControllerService.requestText('/connections', http.RequestMethod.DELETE, '');
    return result.ok;
  }

  static async closeConnection(id: string): Promise<boolean> {
    const result: ControllerResponse = await MihomoControllerService.requestText(
      `/connections/${MihomoControllerService.encodePathSegment(id)}`,
      http.RequestMethod.DELETE,
      ''
    );
    return result.ok;
  }

  static async getRules(): Promise<ControllerTextResult> {
    return MihomoControllerService.toTextResult(
      await MihomoControllerService.requestText('/rules', http.RequestMethod.GET, '')
    );
  }

  static parseConnections(raw: string): ConnectionInfo[] {
    try {
      const data = JSON.parse(raw) as Record<string, Object>;
      const rawConnections: Object[] = data['connections'] as Object[];
      if (!rawConnections || !Array.isArray(rawConnections)) {
        return [];
      }
      const result: ConnectionInfo[] = [];
      for (let i = 0; i < rawConnections.length; i++) {
        const conn = rawConnections[i] as Record<string, Object>;
        const metadata = conn['metadata'] as Record<string, Object>;
        result.push({
          id: (conn['id'] as string) || '',
          metadata: {
            network: metadata ? (metadata['network'] as string) || '' : '',
            type: metadata ? (metadata['type'] as string) || '' : '',
            sourceIP: metadata ? (metadata['sourceIP'] as string) || '' : '',
            sourcePort: metadata ? String(metadata['sourcePort'] || '') : '',
            destinationIP: metadata ? (metadata['destinationIP'] as string) || '' : '',
            destinationPort: metadata ? String(metadata['destinationPort'] || '') : '',
            host: metadata ? (metadata['host'] as string) || '' : '',
            dnsMode: metadata ? (metadata['dnsMode'] as string) || '' : ''
          },
          upload: (conn['upload'] as number) || 0,
          download: (conn['download'] as number) || 0,
          start: (conn['start'] as string) || '',
          chains: Array.isArray(conn['chains']) ? conn['chains'] as string[] : [],
          rule: (conn['rule'] as string) || ''
        });
      }
      return result;
    } catch (err) {
      return [];
    }
  }

  static parseProxyGroups(raw: string): ProxyGroupInfo[] {
    try {
      const data = JSON.parse(raw) as Record<string, Object>;
      const proxies = data['proxies'] as Record<string, Object>;
      if (!proxies) {
        return [];
      }
      const groupTypes: string[] = ['Selector', 'URLTest', 'Fallback', 'LoadBalance'];
      const result: ProxyGroupInfo[] = [];
      const keys: string[] = Object.keys(proxies);
      for (let i = 0; i < keys.length; i++) {
        const key = keys[i];
        const proxy = proxies[key] as Record<string, Object>;
        const type: string = (proxy['type'] as string) || '';
        if (groupTypes.indexOf(type) >= 0) {
          const now: string = (proxy['now'] as string) || '';
          const all: string[] = Array.isArray(proxy['all']) ? proxy['all'] as string[] : [];
          const rawHistory: Object[] = Array.isArray(proxy['history']) ? proxy['history'] as Object[] : [];
          const history: ProxyDelayRecord[] = [];
          for (let j = 0; j < rawHistory.length; j++) {
            const record = rawHistory[j] as Record<string, Object>;
            history.push({
              time: (record['time'] as string) || '',
              delay: (record['delay'] as number) || 0
            });
          }
          result.push({
            name: key,
            type: type,
            now: now,
            all: all,
            history: history
          });
        }
      }
      return result;
    } catch (err) {
      return [];
    }
  }

  private static async requestText(path: string, method: http.RequestMethod, body: string, readTimeoutMs: number = 1500): Promise<ControllerResponse> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(`${DEFAULT_BASE_URL}${path}`, {
        method: method,
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        readTimeout: readTimeoutMs,
        connectTimeout: 1500,
        usingCache: false,
        usingProxy: false,
        header: {
          'Content-Type': 'application/json'
        }
      });

      const raw: string = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
      const code: number = response.responseCode as number;
      if (code >= 200 && code < 300) {
        return {
          ok: true,
          message: 'ok',
          raw: raw
        };
      }

      return {
        ok: false,
        message: `controller HTTP ${code}`,
        raw: raw
      };
    } catch (err) {
      return {
        ok: false,
        message: '无法连接 127.0.0.1:9090，核心尚未启动或 external-controller 未开启',
        raw: ''
      };
    } finally {
      request.destroy();
    }
  }

  private static extractStringField(raw: string, field: string): string {
    try {
      const parsed = JSON.parse(raw) as Record<string, string>;
      const value: string | undefined = parsed[field];
      return value ? value : '';
    } catch (err) {
      return '';
    }
  }

  private static toTextResult(response: ControllerResponse): ControllerTextResult {
    return {
      ok: response.ok,
      message: response.message,
      raw: response.raw
    };
  }

  private static encodePathSegment(value: string): string {
    return encodeURIComponent(value);
  }

  private static encodeQueryValue(value: string): string {
    return encodeURIComponent(value);
  }

  private static sleep(durationMs: number): Promise<void> {
    return new Promise((resolve: () => void) => {
      setTimeout(resolve, durationMs);
    });
  }
}

interface ControllerResponse {
  ok: boolean;
  message: string;
  raw: string;
}
