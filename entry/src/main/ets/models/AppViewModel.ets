import { CoreBridgeState } from '../services/CoreBridgeService';
import { TrafficSnapshot, ConnectionInfo, LogEntry } from '../services/TrafficPollerService';
import { ProfileState, createEmptyProfileState } from './Profile';
import { ControllerStatus } from '../services/MihomoControllerService';

export type ConnectionState = 'disconnected' | 'connecting' | 'connected' | 'disconnecting';

export interface AppState {
  connectionState: ConnectionState;
  controllerStatus: ControllerStatus;
  coreBridgeState: CoreBridgeState;
  trafficSnapshot: TrafficSnapshot;
  profileState: ProfileState;
  connections: ConnectionInfo[];
  logs: LogEntry[];
  proxyGroups: ProxyGroupEntry[];
}

export interface ProxyGroupEntry {
  name: string;
  type: string;
  now: string;
  all: string[];
}

export type AppStateListener = (state: AppState) => void;

export class AppViewModel {
  private listeners: AppStateListener[] = [];
  private state: AppState;

  constructor() {
    this.state = {
      connectionState: 'disconnected',
      controllerStatus: {
        available: false,
        version: '',
        message: '',
        raw: ''
      },
      coreBridgeState: {
        running: false,
        tunFd: -1,
        nativeFd: -1,
        startCount: 0,
        stopCount: 0,
        controllerReady: false,
        controllerOnly: false,
        tunAttached: false,
        supportsControllerOnly: false,
        supportsTunAttach: false,
        realConnectionReady: false,
        configPath: '',
        coreMode: '',
        adapterMode: '',
        adapterKind: 'unknown',
        adapterInfo: '',
        adapterLoadError: '',
        adapterVersion: '',
        controllerVersion: '',
        version: '',
        lastError: '',
        packetsRead: 0,
        packetsWritten: 0,
        bytesRead: 0,
        bytesWritten: 0,
        readErrors: 0,
        writeErrors: 0,
        forwarderActive: false
      },
      trafficSnapshot: {
        downloadSpeed: '0 KB/s',
        uploadSpeed: '0 KB/s',
        totalDownload: 0,
        totalUpload: 0,
        activeConnections: 0,
        memoryUsage: '',
        uptimeSeconds: 0,
        mode: 'rule'
      },
      profileState: createEmptyProfileState(),
      connections: [],
      logs: [],
      proxyGroups: []
    };
  }

  subscribe(listener: AppStateListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index < 0) {
      this.listeners.push(listener);
    }
  }

  unsubscribe(listener: AppStateListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  getState(): AppState {
    return this.state;
  }

  updateConnectionState(connectionState: ConnectionState): void {
    this.state.connectionState = connectionState;
    this.notify();
  }

  updateControllerStatus(status: ControllerStatus): void {
    this.state.controllerStatus = status;
    this.notify();
  }

  updateCoreBridgeState(coreBridgeState: CoreBridgeState): void {
    this.state.coreBridgeState = coreBridgeState;
    this.notify();
  }

  updateTrafficSnapshot(snapshot: TrafficSnapshot): void {
    this.state.trafficSnapshot = snapshot;
    this.notify();
  }

  updateProfileState(profileState: ProfileState): void {
    this.state.profileState = profileState;
    this.notify();
  }

  updateConnections(connections: ConnectionInfo[]): void {
    this.state.connections = connections;
    this.notify();
  }

  updateLogs(logs: LogEntry[]): void {
    this.state.logs = logs;
    this.notify();
  }

  updateProxyGroups(proxyGroups: ProxyGroupEntry[]): void {
    this.state.proxyGroups = proxyGroups;
    this.notify();
  }

  updateTrafficAndConnections(snapshot: TrafficSnapshot, connections: ConnectionInfo[]): void {
    this.state.trafficSnapshot = snapshot;
    this.state.connections = connections;
    this.notify();
  }

  addLog(entry: LogEntry): void {
    this.state.logs.push(entry);
    if (this.state.logs.length > 200) {
      this.state.logs = this.state.logs.slice(this.state.logs.length - 200);
    }
    this.notify();
  }

  clearLogs(): void {
    this.state.logs = [];
    this.notify();
  }

  private notify(): void {
    const snapshot: AppState = this.state;
    for (let index = 0; index < this.listeners.length; index++) {
      try {
        this.listeners[index](snapshot);
      } catch (err) {
      }
    }
  }
}

export const appViewModel: AppViewModel = new AppViewModel();
