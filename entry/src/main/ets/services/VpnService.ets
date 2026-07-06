import { Want } from '@kit.AbilityKit';
import { vpnExtension } from '@kit.NetworkKit';
import nativeCore from 'libentry.so';

const BUNDLE_NAME: string = 'io.github.clashharmony.app';
const VPN_ABILITY_NAME: string = 'ClashVpnExtensionAbility';
function createVpnWant(configPath?: string): Want {
  const want: Want = {
    bundleName: BUNDLE_NAME,
    abilityName: VPN_ABILITY_NAME
  };
  if (configPath && configPath.length > 0) {
    want.parameters = {
      configPath: configPath
    };
  }
  return want;
}

export class VpnService {
  static async start(configPath: string): Promise<boolean> {
    try {
      const result = await Promise.race([
        vpnExtension.startVpnExtensionAbility(createVpnWant(configPath)),
        VpnService.timeout(5000)
      ]);
      if (result === 'timeout') {
        return false;
      }
      return true;
    } catch (err) {
      return false;
    }
  }

  static async stop(): Promise<boolean> {
    try {
      const result = await Promise.race([
        vpnExtension.stopVpnExtensionAbility(createVpnWant()),
        VpnService.timeout(3000)
      ]);
      if (result === 'timeout') {
        return false;
      }
      return true;
    } catch (err) {
      return false;
    }
  }

  private static timeout(ms: number): Promise<string> {
    return new Promise<string>((resolve: (value: string) => void) => {
      setTimeout(() => { resolve('timeout') }, ms);
    });
  }

  static async protectSocket(fd: number): Promise<boolean> {
    try {
      nativeCore.protectSocket(fd);
      return true;
    } catch (err) {
      return false;
    }
  }
}
