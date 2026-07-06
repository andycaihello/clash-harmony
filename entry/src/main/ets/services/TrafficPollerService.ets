import { ControllerTextResult, MihomoControllerService } from './MihomoControllerService';

export interface TrafficSnapshot {
  downloadSpeed: string;
  uploadSpeed: string;
  totalDownload: number;
  totalUpload: number;
  activeConnections: number;
  memoryUsage: string;
  uptimeSeconds: number;
  mode: string;
  controllerAvailable: boolean;
  message: string;
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

export interface ConnectionMetadata {
  network: string;
  type: string;
  sourceIP: string;
  destIP: string;
  host: string;
}

export interface LogEntry {
  timestamp: number;
  level: string;
  payload: string;
}

interface ConnectionPayload {
  connections: ConnectionInfo[];
  totalDownload: number;
  totalUpload: number;
  memoryUsage: string;
}

export class TrafficPollerService {
  private static intervalId: number | undefined = undefined;
  private static lastDownload: number = 0;
  private static lastUpload: number = 0;
  private static lastPollTime: number = 0;
  private static hasBaseline: boolean = false;
  private static callback: ((snapshot: TrafficSnapshot, connections: ConnectionInfo[], logs: LogEntry[]) => void) | undefined = undefined;

  static start(callback: (snapshot: TrafficSnapshot, connections: ConnectionInfo[], logs: LogEntry[]) => void): void {
    TrafficPollerService.stop();
    TrafficPollerService.callback = callback;
    TrafficPollerService.lastDownload = 0;
    TrafficPollerService.lastUpload = 0;
    TrafficPollerService.lastPollTime = Date.now();
    TrafficPollerService.hasBaseline = false;
    TrafficPollerService.poll();
    TrafficPollerService.intervalId = setInterval(() => {
      TrafficPollerService.poll();
    }, 1000);
  }

  static stop(): void {
    if (TrafficPollerService.intervalId !== undefined) {
      clearInterval(TrafficPollerService.intervalId);
      TrafficPollerService.intervalId = undefined;
    }
    TrafficPollerService.callback = undefined;
  }

  static async poll(): Promise<void> {
    try {
      const pollResults: ControllerTextResult[] = await Promise.all([
        MihomoControllerService.getConnections(),
        MihomoControllerService.getConfig()
      ]);
      const connectionsResult: ControllerTextResult = pollResults[0];
      const configResult: ControllerTextResult = pollResults[1];
      if (!connectionsResult.ok || !configResult.ok) {
        TrafficPollerService.emitUnavailable(connectionsResult.ok ? configResult.message : connectionsResult.message);
        return;
      }

      const payload: ConnectionPayload = TrafficPollerService.parseConnectionPayload(connectionsResult.raw);
      const connections: ConnectionInfo[] = payload.connections;
      const mode: string = TrafficPollerService.parseMode(configResult.raw);

      const now: number = Date.now();
      const elapsedSeconds: number = (now - TrafficPollerService.lastPollTime) / 1000;

      let downloadSpeed: number = 0;
      let uploadSpeed: number = 0;
      if (TrafficPollerService.hasBaseline && elapsedSeconds > 0) {
        downloadSpeed = Math.max(0, (payload.totalDownload - TrafficPollerService.lastDownload) / elapsedSeconds);
        uploadSpeed = Math.max(0, (payload.totalUpload - TrafficPollerService.lastUpload) / elapsedSeconds);
      }

      TrafficPollerService.lastDownload = payload.totalDownload;
      TrafficPollerService.lastUpload = payload.totalUpload;
      TrafficPollerService.lastPollTime = now;
      TrafficPollerService.hasBaseline = true;

      const snapshot: TrafficSnapshot = {
        downloadSpeed: TrafficPollerService.formatSpeed(downloadSpeed),
        uploadSpeed: TrafficPollerService.formatSpeed(uploadSpeed),
        totalDownload: payload.totalDownload,
        totalUpload: payload.totalUpload,
        activeConnections: connections.length,
        memoryUsage: payload.memoryUsage,
        uptimeSeconds: 0,
        mode: mode,
        controllerAvailable: true,
        message: 'controller 正常'
      };

      if (TrafficPollerService.callback) {
        TrafficPollerService.callback(snapshot, connections, []);
      }
    } catch (err) {
      TrafficPollerService.emitUnavailable('实时状态刷新失败');
    }
  }

  private static emitUnavailable(message: string): void {
    if (!TrafficPollerService.callback) {
      return;
    }

    TrafficPollerService.callback({
      downloadSpeed: '0 B/s',
      uploadSpeed: '0 B/s',
      totalDownload: TrafficPollerService.lastDownload,
      totalUpload: TrafficPollerService.lastUpload,
      activeConnections: 0,
      memoryUsage: '',
      uptimeSeconds: 0,
      mode: 'rule',
      controllerAvailable: false,
      message: message
    }, [], [{
      timestamp: Date.now(),
      level: 'warn',
      payload: message
    }]);
  }

  private static parseConnectionPayload(raw: string): ConnectionPayload {
    try {
      const parsed = JSON.parse(raw) as Record<string, Object>;
      const connectionsArr = parsed['connections'] as Record<string, Object>[];
      if (!Array.isArray(connectionsArr)) {
        return {
          connections: [],
          totalDownload: 0,
          totalUpload: 0,
          memoryUsage: TrafficPollerService.formatBytesValue(TrafficPollerService.readNumber(parsed['memory']))
        };
      }

      const result: ConnectionInfo[] = [];
      for (let index = 0; index < connectionsArr.length; index++) {
        const item: Record<string, Object> = connectionsArr[index];
        const metadata: Record<string, Object> = (item['metadata'] || {}) as Record<string, Object>;
        const chainsArr: string[] = Array.isArray(item['chains']) ? item['chains'] as string[] : [];
        const startStr: string = typeof item['start'] === 'string' ? item['start'] as string : '';

        result.push({
          id: typeof item['id'] === 'string' ? item['id'] as string : '',
          metadata: {
            network: typeof metadata['network'] === 'string' ? metadata['network'] as string : '',
            type: typeof metadata['type'] === 'string' ? metadata['type'] as string : '',
            sourceIP: typeof metadata['sourceIP'] === 'string' ? metadata['sourceIP'] as string : '',
            destIP: typeof metadata['destinationIP'] === 'string' ? metadata['destinationIP'] as string : '',
            host: typeof metadata['host'] === 'string' ? metadata['host'] as string : ''
          },
          upload: typeof item['upload'] === 'number' ? item['upload'] as number : 0,
          download: typeof item['download'] === 'number' ? item['download'] as number : 0,
          start: startStr,
          chains: chainsArr,
          rule: typeof item['rule'] === 'string' ? item['rule'] as string : ''
        });
      }
      return {
        connections: result,
        totalDownload: TrafficPollerService.readNumber(parsed['downloadTotal']),
        totalUpload: TrafficPollerService.readNumber(parsed['uploadTotal']),
        memoryUsage: TrafficPollerService.formatBytesValue(TrafficPollerService.readNumber(parsed['memory']))
      };
    } catch (err) {
      return {
        connections: [],
        totalDownload: 0,
        totalUpload: 0,
        memoryUsage: ''
      };
    }
  }

  private static parseMode(raw: string): string {
    try {
      const parsed = JSON.parse(raw) as Record<string, Object>;
      const modeValue: string | undefined = parsed['mode'] as string;
      return modeValue ? modeValue : 'rule';
    } catch (err) {
      return 'rule';
    }
  }

  private static formatSpeed(bytesPerSecond: number): string {
    if (bytesPerSecond < 1024) {
      return `${bytesPerSecond.toFixed(1)} B/s`;
    }
    if (bytesPerSecond < 1024 * 1024) {
      return `${(bytesPerSecond / 1024).toFixed(1)} KB/s`;
    }
    return `${(bytesPerSecond / 1024 / 1024).toFixed(1)} MB/s`;
  }

  private static readNumber(value: Object | undefined): number {
    return typeof value === 'number' ? value as number : 0;
  }

  private static formatBytesValue(bytes: number): string {
    if (bytes <= 0) {
      return '0 B';
    }
    if (bytes < 1024) {
      return `${bytes} B`;
    }
    if (bytes < 1024 * 1024) {
      return `${(bytes / 1024).toFixed(1)} KB`;
    }
    return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  }
}
