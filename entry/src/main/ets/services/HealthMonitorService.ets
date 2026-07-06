import { CoreBridgeService, CoreBridgeState } from './CoreBridgeService';
import { MihomoControllerService, ControllerStatus } from './MihomoControllerService';
import { VpnService } from './VpnService';

const CHECK_INTERVAL_MS: number = 5000;
const MAX_CONSECUTIVE_FAILURES: number = 3;

export class HealthMonitorService {
  private static intervalId: number | undefined = undefined;
  private static consecutiveFailures: number = 0;
  private static onUnhealthy: ((reason: string) => void) | undefined = undefined;
  private static running: boolean = false;

  static start(onUnhealthy: (reason: string) => void): void {
    if (HealthMonitorService.running) {
      return;
    }

    HealthMonitorService.running = true;
    HealthMonitorService.consecutiveFailures = 0;
    HealthMonitorService.onUnhealthy = onUnhealthy;

    HealthMonitorService.check();

    HealthMonitorService.intervalId = setInterval(() => {
      HealthMonitorService.check();
    }, CHECK_INTERVAL_MS);
  }

  static stop(): void {
    HealthMonitorService.running = false;
    if (HealthMonitorService.intervalId !== undefined) {
      clearInterval(HealthMonitorService.intervalId);
      HealthMonitorService.intervalId = undefined;
    }
    HealthMonitorService.onUnhealthy = undefined;
    HealthMonitorService.consecutiveFailures = 0;
  }

  static async check(): Promise<boolean> {
    try {
      const state: CoreBridgeState = CoreBridgeService.getState();
      if (!state.running) {
        return true;
      }

      const controllerStatus: ControllerStatus = await MihomoControllerService.checkVersion();
      if (!controllerStatus.available) {
        HealthMonitorService.consecutiveFailures++;
        if (HealthMonitorService.consecutiveFailures >= MAX_CONSECUTIVE_FAILURES) {
          await HealthMonitorService.recover('核心控制器连续无响应');
        }
        return false;
      }

      HealthMonitorService.consecutiveFailures = 0;
      return true;
    } catch (err) {
      HealthMonitorService.consecutiveFailures++;
      if (HealthMonitorService.consecutiveFailures >= MAX_CONSECUTIVE_FAILURES) {
        await HealthMonitorService.recover('健康检查连续异常');
      }
      return false;
    }
  }

  static async recover(reason: string): Promise<void> {
    HealthMonitorService.stop();

    try {
      await VpnService.stop();
    } catch (err) {
    }

    try {
      CoreBridgeService.stopTun();
    } catch (err) {
    }

    if (HealthMonitorService.onUnhealthy) {
      HealthMonitorService.onUnhealthy(reason);
    }
  }

  static isRunning(): boolean {
    return HealthMonitorService.running;
  }

  static getConsecutiveFailures(): number {
    return HealthMonitorService.consecutiveFailures;
  }
}
