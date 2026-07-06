import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { EnhanceArtifact } from './EnhanceService';

const ENHANCE_DIR: string = 'enhancements';

export class EnhanceStore {
  static async loadAll(context: common.Context): Promise<EnhanceArtifact[]> {
    const directory: string = `${context.filesDir}/${ENHANCE_DIR}`;
    try {
      await EnhanceStore.ensureDir(directory);
      const filenames: string[] = await fileIo.listFile(directory);
      const artifacts: EnhanceArtifact[] = [];

      for (let index = 0; index < filenames.length; index++) {
        const filename: string = filenames[index];
        if (!filename.endsWith('.json')) {
          continue;
        }

        try {
          const text: string = await fileIo.readText(`${directory}/${filename}`);
          const artifact: EnhanceArtifact = JSON.parse(text) as EnhanceArtifact;
          if (artifact.uid && artifact.name) {
            artifacts.push({
              uid: artifact.uid,
              type: EnhanceStore.normalizeType(artifact.type),
              name: artifact.name,
              content: artifact.content,
              enabled: artifact.enabled,
              scope: artifact.scope
            });
          }
        } catch (err) {
        }
      }

      return artifacts;
    } catch (err) {
      return [];
    }
  }

  static async save(context: common.Context, artifact: EnhanceArtifact): Promise<boolean> {
    const directory: string = `${context.filesDir}/${ENHANCE_DIR}`;
    try {
      await EnhanceStore.ensureDir(directory);
      const path: string = `${directory}/${artifact.uid}.json`;
      const json: string = JSON.stringify({
        uid: artifact.uid,
        type: artifact.type,
        name: artifact.name,
        content: artifact.content,
        enabled: artifact.enabled,
        scope: artifact.scope
      });

      let file: fileIo.File | undefined = undefined;
      try {
        file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
        await fileIo.write(file.fd, json);
        return true;
      } finally {
        if (file) {
          try {
            fileIo.closeSync(file);
          } catch (err) {
          }
        }
      }
    } catch (err) {
      return false;
    }
  }

  static async remove(context: common.Context, uid: string): Promise<boolean> {
    const directory: string = `${context.filesDir}/${ENHANCE_DIR}`;
    try {
      const path: string = `${directory}/${uid}.json`;
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

  static async setEnabled(context: common.Context, uid: string, enabled: boolean): Promise<boolean> {
    const directory: string = `${context.filesDir}/${ENHANCE_DIR}`;
    try {
      const path: string = `${directory}/${uid}.json`;
      const exists: boolean = await fileIo.access(path);
      if (!exists) {
        return false;
      }

      const text: string = await fileIo.readText(path);
      const artifact: EnhanceArtifact = JSON.parse(text) as EnhanceArtifact;
      artifact.enabled = enabled;

      let file: fileIo.File | undefined = undefined;
      try {
        file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
        await fileIo.write(file.fd, JSON.stringify(artifact));
        return true;
      } finally {
        if (file) {
          try {
            fileIo.closeSync(file);
          } catch (err) {
          }
        }
      }
    } catch (err) {
      return false;
    }
  }

  private static normalizeType(type: string): 'merge' | 'rules' | 'proxies' | 'groups' {
    if (type === 'merge' || type === 'rules' || type === 'proxies' || type === 'groups') {
      return type;
    }
    return 'merge';
  }

  private static async ensureDir(path: string): Promise<void> {
    try {
      await fileIo.mkdir(path, true);
    } catch (err) {
    }
  }
}
