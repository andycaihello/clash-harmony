import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { ClashProfile, ProfileState } from '../models/Profile';
import { ProfileStore } from './ProfileStore';
import { EnhanceArtifact } from './EnhanceService';
import { EnhanceStore } from './EnhanceStore';
import { RuntimeConfigVersionService, VersionHistoryEntry } from './RuntimeConfigVersionService';

export interface BackupBundle {
  version: number;
  createdAt: number;
  profiles: ProfileState;
  enhanceArtifacts: EnhanceArtifact[];
  runtimeVersions: VersionHistoryEntry[];
}

export class BackupService {
  static async createBackup(context: common.Context): Promise<BackupBundle> {
    const profileState: ProfileState = await ProfileStore.load(context);
    const enhanceArtifacts: EnhanceArtifact[] = await EnhanceStore.loadAll(context);
    const runtimeVersions: VersionHistoryEntry[] = await RuntimeConfigVersionService.getVersionHistory(context);

    const bundle: BackupBundle = {
      version: 1,
      createdAt: Date.now(),
      profiles: profileState,
      enhanceArtifacts: enhanceArtifacts,
      runtimeVersions: runtimeVersions
    };

    const backupDir: string = `${context.filesDir}/backups`;
    try {
      await fileIo.mkdir(backupDir, true);
    } catch (err) {
    }

    const dateStr: string = BackupService.formatDate(new Date());
    const filename: string = `clash-harmony-backup-${dateStr}.json`;
    const path: string = `${backupDir}/${filename}`;

    const json: string = JSON.stringify(bundle);
    let file: fileIo.File | undefined = undefined;
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      await fileIo.write(file.fd, json);
      return bundle;
    } finally {
      if (file) {
        try {
          fileIo.closeSync(file);
        } catch (err) {
        }
      }
    }
  }

  static async exportBackup(context: common.Context): Promise<string> {
    const backupDir: string = `${context.filesDir}/backups`;
    try {
      const filenames: string[] = await fileIo.listFile(backupDir);
      if (filenames.length === 0) {
        return '';
      }

      let latest: string = filenames[0];
      let latestTime: number = 0;
      for (let index = 0; index < filenames.length; index++) {
        const filepath: string = `${backupDir}/${filenames[index]}`;
        try {
          const stat = await fileIo.stat(filepath);
          if (stat.mtime > latestTime) {
            latestTime = stat.mtime;
            latest = filenames[index];
          }
        } catch (err) {
        }
      }

      return `${backupDir}/${latest}`;
    } catch (err) {
      return '';
    }
  }

  static async restore(context: common.Context, bundleJson: string): Promise<boolean> {
    try {
      const bundle: BackupBundle = JSON.parse(bundleJson) as BackupBundle;

      if (!bundle.profiles) {
        return false;
      }

      if (bundle.profiles.items && Array.isArray(bundle.profiles.items)) {
        await ProfileStore.save(context, bundle.profiles);
      }

      if (bundle.enhanceArtifacts && Array.isArray(bundle.enhanceArtifacts)) {
        for (let index = 0; index < bundle.enhanceArtifacts.length; index++) {
          await EnhanceStore.save(context, bundle.enhanceArtifacts[index]);
        }
      }

      return true;
    } catch (err) {
      return false;
    }
  }

  static async listBackups(context: common.Context): Promise<string[]> {
    const backupDir: string = `${context.filesDir}/backups`;
    try {
      const filenames: string[] = await fileIo.listFile(backupDir);
      const result: string[] = [];
      for (let index = 0; index < filenames.length; index++) {
        if (filenames[index].endsWith('.json')) {
          result.push(`${backupDir}/${filenames[index]}`);
        }
      }
      return result;
    } catch (err) {
      return [];
    }
  }

  static async deleteBackup(context: common.Context, filename: string): Promise<boolean> {
    const backupDir: string = `${context.filesDir}/backups`;
    try {
      const path: string = `${backupDir}/${filename}`;
      const exists: boolean = await fileIo.access(path);
      if (!exists) {
        return true;
      }
      await fileIo.unlink(path);
      return true;
    } catch (err) {
      return false;
    }
  }

  private static formatDate(date: Date): string {
    const year: number = date.getFullYear();
    const month: number = date.getMonth() + 1;
    const day: number = date.getDate();
    const hour: number = date.getHours();
    const minute: number = date.getMinutes();
    return `${year}${BackupService.pad2(month)}${BackupService.pad2(day)}-${BackupService.pad2(hour)}${BackupService.pad2(minute)}`;
  }

  private static pad2(value: number): string {
    if (value < 10) {
      return `0${value}`;
    }
    return `${value}`;
  }
}
