import nativeCore from 'libentry.so';

export interface CoreBridgeState {
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

function fallbackState(configPath: string, tunFd: number, error: string): CoreBridgeState {
  return {
    running: false,
    tunFd: tunFd,
    nativeFd: -1,
    startCount: 0,
    stopCount: 0,
    controllerReady: false,
    controllerOnly: false,
    tunAttached: false,
    supportsControllerOnly: false,
    supportsTunAttach: false,
    realConnectionReady: false,
    configPath: configPath,
    coreMode: 'fallback',
    adapterMode: 'fallback',
    adapterKind: 'fallback',
    adapterInfo: '',
    adapterLoadError: error,
    adapterVersion: '',
    controllerVersion: '',
    version: '',
    lastError: error,
    packetsRead: 0,
    packetsWritten: 0,
    bytesRead: 0,
    bytesWritten: 0,
    readErrors: 0,
    writeErrors: 0,
    forwarderActive: false
  };
}

let lastKnownState: CoreBridgeState = fallbackState('', -1, '');

function normalizeState(state: CoreBridgeState): CoreBridgeState {
  const adapterVersion: string = state.adapterVersion ? state.adapterVersion : (!state.controllerReady ? state.version : '');
  const controllerVersion: string = state.controllerVersion ? state.controllerVersion : (state.controllerReady ? state.version : '');
  const version: string = state.version ? state.version : (state.controllerReady ? controllerVersion : '');
  return {
    running: state.running,
    tunFd: state.tunFd,
    nativeFd: state.nativeFd,
    startCount: state.startCount,
    stopCount: state.stopCount,
    controllerReady: state.controllerReady,
    controllerOnly: state.controllerOnly || false,
    tunAttached: state.tunAttached || false,
    supportsControllerOnly: state.supportsControllerOnly || false,
    supportsTunAttach: state.supportsTunAttach || false,
    realConnectionReady: state.realConnectionReady || false,
    configPath: state.configPath,
    coreMode: state.coreMode,
    adapterMode: state.adapterMode,
    adapterKind: state.adapterKind ? state.adapterKind : 'unknown',
    adapterInfo: state.adapterInfo ? state.adapterInfo : '',
    adapterLoadError: state.adapterLoadError,
    adapterVersion: adapterVersion,
    controllerVersion: controllerVersion,
    version: version,
    lastError: state.lastError,
    packetsRead: state.packetsRead || 0,
    packetsWritten: state.packetsWritten || 0,
    bytesRead: state.bytesRead || 0,
    bytesWritten: state.bytesWritten || 0,
    readErrors: state.readErrors || 0,
    writeErrors: state.writeErrors || 0,
    forwarderActive: state.forwarderActive || false
  };
}

function rememberState(state: CoreBridgeState): CoreBridgeState {
  lastKnownState = normalizeState(state);
  return lastKnownState;
}

function fallbackControllerMarkState(ready: boolean, version: string, error: string): CoreBridgeState {
  const effectiveReady: boolean = ready;
  return {
    running: lastKnownState.running,
    tunFd: lastKnownState.tunFd,
    nativeFd: lastKnownState.nativeFd,
    startCount: lastKnownState.startCount,
    stopCount: lastKnownState.stopCount,
    controllerReady: effectiveReady,
    controllerOnly: lastKnownState.controllerOnly,
    tunAttached: lastKnownState.tunAttached,
    supportsControllerOnly: lastKnownState.supportsControllerOnly,
    supportsTunAttach: lastKnownState.supportsTunAttach,
    realConnectionReady: lastKnownState.realConnectionReady,
    configPath: lastKnownState.configPath,
    coreMode: effectiveReady && !lastKnownState.running ? 'external-controller' : lastKnownState.coreMode,
    adapterMode: lastKnownState.adapterMode,
    adapterKind: lastKnownState.adapterKind,
    adapterInfo: lastKnownState.adapterInfo,
    adapterLoadError: lastKnownState.adapterLoadError,
    adapterVersion: lastKnownState.adapterVersion,
    controllerVersion: effectiveReady ? version : '',
    version: effectiveReady ? version : '',
    lastError: error,
    packetsRead: lastKnownState.packetsRead,
    packetsWritten: lastKnownState.packetsWritten,
    bytesRead: lastKnownState.bytesRead,
    bytesWritten: lastKnownState.bytesWritten,
    readErrors: lastKnownState.readErrors,
    writeErrors: lastKnownState.writeErrors,
    forwarderActive: lastKnownState.forwarderActive
  };
}

function stringifyError(err: Object): string {
  if (err instanceof Error) {
    return err.message;
  }
  return JSON.stringify(err);
}

export class CoreBridgeService {
  static startTun(configPath: string, tunFd: number): CoreBridgeState {
    try {
      return rememberState(nativeCore.startTun(configPath, tunFd) as CoreBridgeState);
    } catch (err) {
      return rememberState(fallbackState(configPath, tunFd, stringifyError(err)));
    }
  }

  static stopTun(): CoreBridgeState {
    try {
      return rememberState(nativeCore.stopTun() as CoreBridgeState);
    } catch (err) {
      return rememberState(fallbackState('', -1, stringifyError(err)));
    }
  }

  static startCore(configPath: string): CoreBridgeState {
    try {
      return rememberState(nativeCore.startCore(configPath) as CoreBridgeState);
    } catch (err) {
      return rememberState(fallbackState(configPath, -1, stringifyError(err)));
    }
  }

  static stopCore(): CoreBridgeState {
    try {
      return rememberState(nativeCore.stopCore() as CoreBridgeState);
    } catch (err) {
      return rememberState(fallbackState('', -1, stringifyError(err)));
    }
  }

  static getState(): CoreBridgeState {
    try {
      return rememberState(nativeCore.getState() as CoreBridgeState);
    } catch (err) {
      return fallbackState('', -1, stringifyError(err));
    }
  }

  static markControllerReady(ready: boolean, version: string): CoreBridgeState {
    try {
      return rememberState(nativeCore.setControllerReady(ready, version) as CoreBridgeState);
    } catch (err) {
      return rememberState(fallbackControllerMarkState(ready, version, stringifyError(err)));
    }
  }

  static setControllerReady(ready: boolean, version: string): CoreBridgeState {
    return CoreBridgeService.markControllerReady(ready, version);
  }

  static protectSocket(fd: number): boolean {
    try {
      nativeCore.protectSocket(fd);
      return true;
    } catch (err) {
      return false;
    }
  }
}
