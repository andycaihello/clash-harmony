import { ClashProfile, ProfileState } from '../models/Profile';

export type CoreRunningState = 'stopped' | 'starting' | 'running' | 'error';

export interface CoreSummary {
  state: CoreRunningState;
  mode: 'rule' | 'global' | 'direct';
  profileName: string;
  proxyName: string;
  uptime: string;
  downloadSpeed: string;
  uploadSpeed: string;
  connections: number;
}

export interface TrafficSnapshot {
  downloadSpeed: number;
  uploadSpeed: number;
  connections: number;
  uptimeSeconds: number;
}

export class CoreService {
  static createSummary(profileState: ProfileState, connected: boolean, trafficSnapshot?: TrafficSnapshot): CoreSummary {
    const current: ClashProfile | undefined = CoreService.getCurrentProfile(profileState);
    const profileName: string = current ? current.name : '未选择配置';

    if (connected && trafficSnapshot) {
      return {
        state: 'running',
        mode: 'rule',
        profileName: profileName,
        proxyName: current ? '已连接' : '等待核心连接',
        uptime: CoreService.formatUptime(trafficSnapshot.uptimeSeconds),
        downloadSpeed: CoreService.formatSpeed(trafficSnapshot.downloadSpeed),
        uploadSpeed: CoreService.formatSpeed(trafficSnapshot.uploadSpeed),
        connections: trafficSnapshot.connections
      };
    }

    return {
      state: connected ? 'running' : 'stopped',
      mode: 'rule',
      profileName: profileName,
      proxyName: connected && current ? '等待核心连接' : '未连接',
      uptime: connected ? '刚刚启动' : '未连接',
      downloadSpeed: connected ? '0 KB/s' : '0 KB/s',
      uploadSpeed: connected ? '0 KB/s' : '0 KB/s',
      connections: 0
    };
  }

  static getCurrentProfile(profileState: ProfileState): ClashProfile | undefined {
    for (let index = 0; index < profileState.items.length; index++) {
      if (profileState.items[index].uid === profileState.currentUid) {
        return profileState.items[index];
      }
    }
    return undefined;
  }

  static formatUptime(seconds: number): string {
    if (seconds <= 0) {
      return '刚刚启动';
    }
    if (seconds < 60) {
      return `${Math.floor(seconds)}s`;
    }
    const hours: number = Math.floor(seconds / 3600);
    const minutes: number = Math.floor((seconds % 3600) / 60);
    if (hours > 0) {
      return `${hours}h ${minutes}m`;
    }
    return `${minutes}m`;
  }

  static formatSpeed(bytesPerSecond: number): string {
    if (bytesPerSecond < 1024) {
      return `${bytesPerSecond.toFixed(1)} B/s`;
    }
    const kbPerSecond: number = bytesPerSecond / 1024;
    if (kbPerSecond < 1024) {
      return `${kbPerSecond.toFixed(1)} KB/s`;
    }
    const mbPerSecond: number = kbPerSecond / 1024;
    return `${mbPerSecond.toFixed(1)} MB/s`;
  }
}
