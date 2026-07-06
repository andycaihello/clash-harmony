import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';

const RUNTIME_DIR_NAME: string = 'runtime';
const CURRENT: string = 'current.yaml';
const PREVIOUS_GOOD: string = 'previous-good.yaml';
const PENDING: string = 'pending.yaml';

export type RuntimeVersionStatus = 'pending' | 'current' | 'previous-good' | 'failed';

export interface RuntimeVersion {
  versionId: string;
  configPath: string;
  profileName: string;
  nodeCount: number;
  size: string;
  status: RuntimeVersionStatus;
  createdAt: number;
  validatedAt: number;
  validationError: string;
}

export interface VersionHistoryEntry {
  versionId: string;
  status: RuntimeVersionStatus;
  profileName: string;
  createdAt: number;
  validatedAt: number;
}

export class RuntimeConfigVersionService {
  static async prepare(context: common.Context, yaml: string): Promise<RuntimeVersion> {
    const runtimeDir: string = `${context.filesDir}/${RUNTIME_DIR_NAME}`;
    await RuntimeConfigVersionService.ensureDir(runtimeDir);
    const pendingPath: string = `${runtimeDir}/${PENDING}`;
    await RuntimeConfigVersionService.writeText(pendingPath, yaml);

    const versionId: string = `v${Date.now()}`;
    const version: RuntimeVersion = {
      versionId: versionId,
      configPath: pendingPath,
      profileName: '',
      nodeCount: RuntimeConfigVersionService.estimateNodeCount(yaml),
      size: RuntimeConfigVersionService.formatBytes(yaml.length),
      status: 'pending',
      createdAt: Date.now(),
      validatedAt: 0,
      validationError: ''
    };
    await RuntimeConfigVersionService.appendVersionHistory(context, version);
    return version;
  }

  static async validate(context: common.Context): Promise<RuntimeVersion> {
    const pendingPath: string = `${context.filesDir}/${RUNTIME_DIR_NAME}/${PENDING}`;
    const version: RuntimeVersion = {
      versionId: `v${Date.now()}`,
      configPath: pendingPath,
      profileName: '',
      nodeCount: 0,
      size: '',
      status: 'pending',
      createdAt: Date.now(),
      validatedAt: 0,
      validationError: ''
    };

    try {
      const exists: boolean = await fileIo.access(pendingPath);
      if (!exists) {
        version.status = 'failed';
        version.validationError = '待验证文件不存在';
        version.validatedAt = Date.now();
        return version;
      }

      const text: string = await fileIo.readText(pendingPath);
      if (text.trim().length === 0) {
        version.status = 'failed';
        version.validationError = '待验证文件内容为空';
        version.validatedAt = Date.now();
        return version;
      }

      const hasProxies: boolean = text.indexOf('proxies:') >= 0;
      const hasRules: boolean = text.indexOf('rules:') >= 0;
      if (!hasProxies && !hasRules) {
        version.status = 'failed';
        version.validationError = 'YAML 缺少 proxies 或 rules 关键字段';
        version.validatedAt = Date.now();
        return version;
      }

      version.status = 'pending';
      version.size = RuntimeConfigVersionService.formatBytes(text.length);
      version.nodeCount = RuntimeConfigVersionService.estimateNodeCount(text);
      version.validatedAt = Date.now();
      return version;
    } catch (err) {
      version.status = 'failed';
      version.validationError = '验证过程发生异常';
      version.validatedAt = Date.now();
      return version;
    }
  }

  static async activate(context: common.Context): Promise<RuntimeVersion> {
    const runtimeDir: string = `${context.filesDir}/${RUNTIME_DIR_NAME}`;
    const pendingPath: string = `${runtimeDir}/${PENDING}`;
    const currentPath: string = `${runtimeDir}/${CURRENT}`;
    const previousPath: string = `${runtimeDir}/${PREVIOUS_GOOD}`;

    try {
      const pendingExists: boolean = await fileIo.access(pendingPath);
      if (!pendingExists) {
        return RuntimeConfigVersionService.versionFailure('没有待激活的配置');
      }

      const currentExists: boolean = await fileIo.access(currentPath);
      if (currentExists) {
        await fileIo.copyFile(currentPath, previousPath);
      }

      await fileIo.copyFile(pendingPath, currentPath);
      try {
        await fileIo.unlink(pendingPath);
      } catch (err) {
      }

      const version: RuntimeVersion = {
        versionId: `v${Date.now()}`,
        configPath: currentPath,
        profileName: '',
        nodeCount: 0,
        size: '',
        status: 'current',
        createdAt: Date.now(),
        validatedAt: Date.now(),
        validationError: ''
      };
      await RuntimeConfigVersionService.appendVersionHistory(context, version);
      return version;
    } catch (err) {
      return RuntimeConfigVersionService.versionFailure('激活配置失败');
    }
  }

  static async rollback(context: common.Context): Promise<RuntimeVersion> {
    const runtimeDir: string = `${context.filesDir}/${RUNTIME_DIR_NAME}`;
    const currentPath: string = `${runtimeDir}/${CURRENT}`;
    const previousPath: string = `${runtimeDir}/${PREVIOUS_GOOD}`;

    try {
      const previousExists: boolean = await fileIo.access(previousPath);
      if (!previousExists) {
        return RuntimeConfigVersionService.versionFailure('没有可回滚的上一个稳定配置');
      }

      await fileIo.copyFile(previousPath, currentPath);

      const version: RuntimeVersion = {
        versionId: `v${Date.now()}`,
        configPath: currentPath,
        profileName: '',
        nodeCount: 0,
        size: '',
        status: 'current',
        createdAt: Date.now(),
        validatedAt: Date.now(),
        validationError: ''
      };
      await RuntimeConfigVersionService.appendVersionHistory(context, version);
      return version;
    } catch (err) {
      return RuntimeConfigVersionService.versionFailure('回滚配置失败');
    }
  }

  static async confirmGood(context: common.Context): Promise<boolean> {
    const runtimeDir: string = `${context.filesDir}/${RUNTIME_DIR_NAME}`;
    const currentPath: string = `${runtimeDir}/${CURRENT}`;
    const previousPath: string = `${runtimeDir}/${PREVIOUS_GOOD}`;

    try {
      const currentExists: boolean = await fileIo.access(currentPath);
      if (!currentExists) {
        return false;
      }

      await fileIo.copyFile(currentPath, previousPath);
      const version: RuntimeVersion = {
        versionId: `v${Date.now()}`,
        configPath: previousPath,
        profileName: '',
        nodeCount: 0,
        size: '',
        status: 'previous-good',
        createdAt: Date.now(),
        validatedAt: Date.now(),
        validationError: ''
      };
      await RuntimeConfigVersionService.appendVersionHistory(context, version);
      return true;
    } catch (err) {
      return false;
    }
  }

  static async getVersionHistory(context: common.Context): Promise<VersionHistoryEntry[]> {
    try {
      const historyPath: string = `${context.filesDir}/${RUNTIME_DIR_NAME}/version_history.json`;
      const exists: boolean = await fileIo.access(historyPath);
      if (!exists) {
        return [];
      }

      const text: string = await fileIo.readText(historyPath);
      const entries = JSON.parse(text) as VersionHistoryEntry[];
      if (!Array.isArray(entries)) {
        return [];
      }
      return entries;
    } catch (err) {
      return [];
    }
  }

  static getCurrentConfigPath(context: common.Context): string {
    return `${context.filesDir}/${RUNTIME_DIR_NAME}/${CURRENT}`;
  }

  static getPreviousGoodPath(context: common.Context): string {
    return `${context.filesDir}/${RUNTIME_DIR_NAME}/${PREVIOUS_GOOD}`;
  }

  static getPendingPath(context: common.Context): string {
    return `${context.filesDir}/${RUNTIME_DIR_NAME}/${PENDING}`;
  }

  private static async appendVersionHistory(context: common.Context, version: RuntimeVersion): Promise<void> {
    try {
      const historyPath: string = `${context.filesDir}/${RUNTIME_DIR_NAME}/version_history.json`;
      let entries: VersionHistoryEntry[] = [];

      try {
        const exists: boolean = await fileIo.access(historyPath);
        if (exists) {
          const text: string = await fileIo.readText(historyPath);
          entries = JSON.parse(text) as VersionHistoryEntry[];
          if (!Array.isArray(entries)) {
            entries = [];
          }
        }
      } catch (err) {
      }

      const entry: VersionHistoryEntry = {
        versionId: version.versionId,
        status: version.status,
        profileName: version.profileName,
        createdAt: version.createdAt,
        validatedAt: version.validatedAt
      };
      entries.push(entry);

      if (entries.length > 50) {
        entries = entries.slice(entries.length - 50);
      }

      await RuntimeConfigVersionService.writeText(historyPath, JSON.stringify(entries));
    } catch (err) {
    }
  }

  private static async ensureDir(path: string): Promise<void> {
    try {
      await fileIo.mkdir(path, true);
    } catch (err) {
    }
  }

  private static async writeText(path: string, text: string): Promise<void> {
    let file: fileIo.File | undefined = undefined;
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      await fileIo.write(file.fd, text);
    } finally {
      if (file) {
        try {
          fileIo.closeSync(file);
        } catch (err) {
        }
      }
    }
  }

  private static estimateNodeCount(text: string): number {
    let count: number = 0;
    let index: number = 0;
    const keyword: string = '- name:';
    while (index < text.length) {
      const found: number = text.indexOf(keyword, index);
      if (found < 0) {
        break;
      }
      count++;
      index = found + keyword.length;
    }
    return count;
  }

  private static formatBytes(length: number): string {
    if (length < 1024) {
      return `${length} B`;
    }
    if (length < 1024 * 1024) {
      return `${Math.round(length / 1024)} KB`;
    }
    return `${Math.round(length / 1024 / 1024)} MB`;
  }

  private static versionFailure(message: string): RuntimeVersion {
    return {
      versionId: '',
      configPath: '',
      profileName: '',
      nodeCount: 0,
      size: '',
      status: 'failed',
      createdAt: Date.now(),
      validatedAt: 0,
      validationError: message
    };
  }
}
