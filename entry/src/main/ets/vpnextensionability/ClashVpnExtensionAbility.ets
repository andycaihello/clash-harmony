import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { VpnExtensionAbility, vpnExtension } from '@kit.NetworkKit';
import { CoreBridgeService, CoreBridgeState } from '../services/CoreBridgeService';
import { ControllerStatus, MihomoControllerService } from '../services/MihomoControllerService';
import nativeCore from 'libentry.so';

const DOMAIN: number = 0x0001;
const TAG: string = 'ClashVpnExtension';
const PARAM_CONFIG_PATH: string = 'configPath';

export default class ClashVpnExtensionAbility extends VpnExtensionAbility {
  private connection?: vpnExtension.VpnConnection;
  private tunFd: number = -1;
  private configPath: string = '';
  private starting: boolean = false;

  onCreate(want: Want): void {
    hilog.info(DOMAIN, TAG, 'VPN extension created');
    this.connection = vpnExtension.createVpnConnection(this.context);
    try {
      nativeCore.protectSocket(-1);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Socket protection setup check: %{public}s', JSON.stringify(err));
    }
    this.captureWant(want);
    this.startTunnel();
  }

  onRequest(want: Want, startId: number): void {
    hilog.info(DOMAIN, TAG, 'VPN extension requested: %{public}d', startId);
    this.captureWant(want);
    this.startTunnel();
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'VPN extension destroyed');
    this.stopTunnel();
  }

  private captureWant(want: Want): void {
    if (!want.parameters) {
      return;
    }

    const value: Object | undefined = want.parameters[PARAM_CONFIG_PATH];
    if (typeof value === 'string') {
      this.configPath = value;
    }
  }

  private async startTunnel(): Promise<void> {
    if (this.starting || this.tunFd >= 0) {
      return;
    }
    if (!this.connection) {
      hilog.error(DOMAIN, TAG, 'VPN connection is not ready');
      return;
    }

    this.starting = true;
    try {
      const config: vpnExtension.VpnConfig = this.createSafeTunConfig();
      this.tunFd = await this.connection.create(config);
      hilog.info(DOMAIN, TAG, 'VPN TUN created, fd=%{public}d, config=%{public}s', this.tunFd, this.configPath);
      try {
        await this.connection.protectProcessNet();
        hilog.info(DOMAIN, TAG, 'VPN process network protected for native core outbound sockets');
      } catch (protectErr) {
        hilog.warn(DOMAIN, TAG, 'VPN process network protection failed: %{public}s', JSON.stringify(protectErr));
      }
      const coreState: CoreBridgeState = CoreBridgeService.startTun(this.configPath, this.tunFd);
      if (!coreState.running) {
        hilog.error(DOMAIN, TAG, 'Native core bridge failed: error=%{public}s adapter=%{public}s adapterKind=%{public}s loadError=%{public}s nativeFd=%{public}d',
          coreState.lastError, coreState.adapterMode, coreState.adapterKind, coreState.adapterLoadError, coreState.nativeFd);
      } else {
        hilog.info(DOMAIN, TAG, 'Native core bridge started: mode=%{public}s adapter=%{public}s adapterVersion=%{public}s nativeFd=%{public}d adapterKind=%{public}s realReady=%{public}s supportsControllerOnly=%{public}s',
          coreState.coreMode, coreState.adapterMode, coreState.adapterVersion, coreState.nativeFd,
          coreState.adapterKind, coreState.realConnectionReady ? 'true' : 'false',
          coreState.supportsControllerOnly ? 'true' : 'false');
        hilog.info(DOMAIN, TAG, 'Forwarder stats: packetsRead=%{public}d packetsWritten=%{public}d bytesRead=%{public}d bytesWritten=%{public}d readErrors=%{public}d writeErrors=%{public}d forwarderActive=%{public}s',
          coreState.packetsRead, coreState.packetsWritten, coreState.bytesRead, coreState.bytesWritten,
          coreState.readErrors, coreState.writeErrors, coreState.forwarderActive ? 'true' : 'false');
        await this.markControllerReadyInVpnProcess();
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to create VPN TUN: %{public}s', JSON.stringify(err));
      this.tunFd = -1;
    } finally {
      this.starting = false;
    }
  }

  private async markControllerReadyInVpnProcess(): Promise<void> {
    const controllerReady: ControllerStatus = await MihomoControllerService.waitForVersion(10, 300);
    if (controllerReady.available) {
      const readyState: CoreBridgeState = CoreBridgeService.markControllerReady(true, controllerReady.version);
      hilog.info(DOMAIN, TAG, 'Controller ready: controllerVersion=%{public}s adapter=%{public}s adapterVersion=%{public}s nativeFd=%{public}d realReady=%{public}s forwarderActive=%{public}s',
        controllerReady.version, readyState.adapterMode, readyState.adapterVersion, readyState.nativeFd,
        readyState.realConnectionReady ? 'true' : 'false', readyState.forwarderActive ? 'true' : 'false');
      return;
    }

    const notReadyState: CoreBridgeState = CoreBridgeService.markControllerReady(false, '');
    hilog.warn(DOMAIN, TAG, 'Controller readiness failed: message=%{public}s adapter=%{public}s adapterVersion=%{public}s nativeFd=%{public}d',
      controllerReady.message, notReadyState.adapterMode, notReadyState.adapterVersion, notReadyState.nativeFd);
  }

  private async stopTunnel(): Promise<void> {
    if (!this.connection) {
      this.tunFd = -1;
      return;
    }

    try {
      // Cleanup order: stop forwarder -> stop mihomo via native bridge, then destroy VPN
      const coreState: CoreBridgeState = CoreBridgeService.stopTun();
      hilog.info(DOMAIN, TAG, 'Native core bridge stopped: mode=%{public}s nativeFd=%{public}d controllerReady=%{public}s stopCount=%{public}d',
        coreState.coreMode, coreState.nativeFd, coreState.controllerReady ? 'true' : 'false', coreState.stopCount);
      await this.connection.destroy();
      hilog.info(DOMAIN, TAG, 'VPN connection destroyed');
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Destroy VPN connection failed: %{public}s', JSON.stringify(err));
    } finally {
      this.tunFd = -1;
    }
  }

  private createSafeTunConfig(): vpnExtension.VpnConfig {
    return {
      addresses: [
        {
          address: {
            address: '198.18.0.1',
            family: 1
          },
          prefixLength: 16
        }
      ],
      routes: [
        {
          interface: '',
          destination: {
            address: {
              address: '0.0.0.0',
              family: 1
            },
            prefixLength: 0
          },
          gateway: {
            address: '0.0.0.0',
            family: 1
          },
          hasGateway: false,
          isDefaultRoute: true
        }
      ],
      dnsAddresses: [
        '223.5.5.5',
        '119.29.29.29'
      ],
      mtu: 1500,
      isIPv4Accepted: true,
      isIPv6Accepted: false,
      isInternal: false,
      isBlocking: false
    };
  }
}
