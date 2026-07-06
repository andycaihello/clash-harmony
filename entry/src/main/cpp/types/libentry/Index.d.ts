export interface NativeCoreState {
  running: boolean;
  tunFd: number;
  nativeFd: number;
  startCount: number;
  stopCount: number;
  controllerReady: boolean;
  controllerOnly: boolean;
  tunAttached: boolean;
  supportsControllerOnly: boolean;
  supportsTunAttach: boolean;
  realConnectionReady: boolean;
  configPath: string;
  coreMode: string;
  adapterMode: string;
  adapterKind: string;
  adapterInfo: string;
  adapterLoadError: string;
  adapterVersion: string;
  controllerVersion: string;
  version: string;
  lastError: string;
  packetsRead: number;
  packetsWritten: number;
  bytesRead: number;
  bytesWritten: number;
  readErrors: number;
  writeErrors: number;
  forwarderActive: boolean;
}

export interface ForwarderStats {
  packetsRead: number;
  packetsWritten: number;
  bytesRead: number;
  bytesWritten: number;
  readErrors: number;
  writeErrors: number;
  active: boolean;
}

export const startTun: (configPath: string, tunFd: number) => NativeCoreState;
export const stopTun: () => NativeCoreState;
export const startCore: (configPath: string) => NativeCoreState;
export const stopCore: () => NativeCoreState;
export const getState: () => NativeCoreState;
export const setControllerReady: (ready: boolean, version: string) => NativeCoreState;
export const protectSocket: (fd: number) => void;
export const setProtectCallback: (callback: (fd: number) => void) => void;
export const getForwarderStats: () => ForwarderStats;
