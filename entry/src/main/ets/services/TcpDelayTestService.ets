import { http } from '@kit.NetworkKit';

export interface DelayResult {
  nodeName: string;
  delay: string;
  status: string;
}

export class TcpDelayTestService {
  static async testNode(server: string, port: number): Promise<number> {
    if (server.length === 0 || port <= 0) {
      return -1;
    }
    const request: http.HttpRequest = http.createHttp();
    const startTime: number = Date.now();
    try {
      await request.request('http://' + server + ':' + port + '/', {
        method: http.RequestMethod.GET,
        readTimeout: 3000,
        connectTimeout: 3000,
        usingCache: false,
        usingProxy: false
      });
      const delay: number = Date.now() - startTime;
      request.destroy();
      return delay;
    } catch (err) {
      request.destroy();
      return -1;
    }
  }

  static formatDelay(delay: number): DelayResult {
    if (delay === -1) {
      return { nodeName: '', delay: 'timeout', status: 'dead' };
    }
    if (delay === -2) {
      return { nodeName: '', delay: 'timeout', status: 'dead' };
    }
    if (delay < 100) {
      return { nodeName: '', delay: delay + ' ms', status: 'fast' };
    }
    if (delay < 500) {
      return { nodeName: '', delay: delay + ' ms', status: 'normal' };
    }
    return { nodeName: '', delay: delay + ' ms', status: 'slow' };
  }
}
