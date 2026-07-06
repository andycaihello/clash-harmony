import { common } from '@kit.AbilityKit';
import { ClashConfigParserService } from './ClashConfigParserService';

export interface EnhanceArtifact {
  uid: string;
  type: 'merge' | 'rules' | 'proxies' | 'groups';
  name: string;
  content: string;
  enabled: boolean;
  scope: 'global' | 'profile';
}

export interface EnhanceStep {
  name: string;
  apply: (baseYaml: string, artifacts: EnhanceArtifact[]) => string;
}

export interface EnhanceResult {
  ok: boolean;
  yaml: string;
  message: string;
  step: string;
}

const TOP_LEVEL_KEYS: string[] = [
  'proxies',
  'proxy-groups',
  'rules',
  'proxy-providers',
  'rule-providers'
];

export class EnhanceService {
  static async enhance(baseYaml: string, context: common.Context, profileUid: string): Promise<EnhanceResult> {
    try {
      const mergeSteps: EnhanceStep[] = [
        EnhanceService.createMergeStep(),
        EnhanceService.createRulesStep(),
        EnhanceService.createProxiesStep(),
        EnhanceService.createGroupsStep()
      ];

      let current: string = baseYaml;
      for (let index = 0; index < mergeSteps.length; index++) {
        const step: EnhanceStep = mergeSteps[index];
        const artifacts: EnhanceArtifact[] = [];
        current = step.apply(current, artifacts);
      }

      return {
        ok: true,
        yaml: current,
        message: '增强配置完成',
        step: 'done'
      };
    } catch (err) {
      return {
        ok: false,
        yaml: baseYaml,
        message: '增强过程发生错误',
        step: 'error'
      };
    }
  }

  static applyMerge(baseYaml: string, artifact: EnhanceArtifact): string {
    if (!artifact.enabled) {
      return baseYaml;
    }

    const baseParsed: Record<string, string[]> = EnhanceService.parseTopLevelSections(baseYaml);
    const artifactParsed: Record<string, string[]> = EnhanceService.parseTopLevelSections(artifact.content);

    const resultSections: string[] = [];

    const handledKeys: string[] = [];
    const baseKeys: string[] = Object.keys(baseParsed);
    for (let index = 0; index < baseKeys.length; index++) {
      const key: string = baseKeys[index];
      const baseSection: string[] = baseParsed[key];
      const artifactSection: string[] | undefined = artifactParsed[key];

      if (artifactSection) {
        handledKeys.push(key);
        const merged: string[] = EnhanceService.mergeSection(baseSection, artifactSection, key);
        resultSections.push(`${key}:`);
        for (let lineIndex = 0; lineIndex < merged.length; lineIndex++) {
          resultSections.push(merged[lineIndex]);
        }
      } else {
        resultSections.push(`${key}:`);
        for (let lineIndex = 0; lineIndex < baseSection.length; lineIndex++) {
          resultSections.push(baseSection[lineIndex]);
        }
      }
    }

    const artifactKeys: string[] = Object.keys(artifactParsed);
    for (let index = 0; index < artifactKeys.length; index++) {
      const key: string = artifactKeys[index];
      let alreadyHandled: boolean = false;
      for (let handledIndex = 0; handledIndex < handledKeys.length; handledIndex++) {
        if (handledKeys[handledIndex] === key) {
          alreadyHandled = true;
          break;
        }
      }
      if (!alreadyHandled) {
        const section: string[] = artifactParsed[key];
        resultSections.push(`${key}:`);
        for (let lineIndex = 0; lineIndex < section.length; lineIndex++) {
          resultSections.push(section[lineIndex]);
        }
      }
    }

    return resultSections.join('\n');
  }

  static applyRules(baseYaml: string, artifact: EnhanceArtifact): string {
    if (!artifact.enabled || artifact.content.trim().length === 0) {
      return baseYaml;
    }

    const lines: string[] = baseYaml.split('\n');
    const rules: string[] = artifact.content.split('\n').filter((line: string) => line.trim().length > 0);

    let rulesIndex: number = -1;
    for (let index = 0; index < lines.length; index++) {
      const trimmed: string = lines[index].trim();
      if (trimmed === 'rules:' && !lines[index].startsWith(' ')) {
        rulesIndex = index;
        break;
      }
    }

    if (rulesIndex < 0) {
      lines.push('rules:');
      for (let index = 0; index < rules.length; index++) {
        lines.push(rules[index]);
      }
      return lines.join('\n');
    }

    lines.splice(rulesIndex + 1, 0, ...rules);
    return lines.join('\n');
  }

  static applyProxies(baseYaml: string, artifact: EnhanceArtifact): string {
    if (!artifact.enabled || artifact.content.trim().length === 0) {
      return baseYaml;
    }

    const lines: string[] = baseYaml.split('\n');
    const proxies: string[] = artifact.content.split('\n').filter((line: string) => line.trim().length > 0);

    let proxiesIndex: number = -1;
    for (let index = 0; index < lines.length; index++) {
      const trimmed: string = lines[index].trim();
      if (trimmed === 'proxies:' && !lines[index].startsWith(' ')) {
        proxiesIndex = index;
        break;
      }
    }

    if (proxiesIndex < 0) {
      lines.push('proxies:');
      for (let index = 0; index < proxies.length; index++) {
        lines.push(proxies[index]);
      }
      return lines.join('\n');
    }

    lines.splice(proxiesIndex + 1, 0, ...proxies);
    return lines.join('\n');
  }

  static applyGroups(baseYaml: string, artifact: EnhanceArtifact): string {
    if (!artifact.enabled || artifact.content.trim().length === 0) {
      return baseYaml;
    }

    const lines: string[] = baseYaml.split('\n');
    const groups: string[] = artifact.content.split('\n').filter((line: string) => line.trim().length > 0);

    let groupsIndex: number = -1;
    for (let index = 0; index < lines.length; index++) {
      const trimmed: string = lines[index].trim();
      if (trimmed === 'proxy-groups:' && !lines[index].startsWith(' ')) {
        groupsIndex = index;
        break;
      }
    }

    if (groupsIndex < 0) {
      lines.push('proxy-groups:');
      for (let index = 0; index < groups.length; index++) {
        lines.push(groups[index]);
      }
      return lines.join('\n');
    }

    lines.splice(groupsIndex + 1, 0, ...groups);
    return lines.join('\n');
  }

  private static parseTopLevelSections(yaml: string): Record<string, string[]> {
    const sections: Record<string, string[]> = {};
    const lines: string[] = yaml.split('\n');
    let currentKey: string = '';

    for (let index = 0; index < lines.length; index++) {
      const line: string = lines[index];
      const trimmed: string = line.trim();

      if (trimmed.length === 0) {
        if (currentKey.length > 0) {
          sections[currentKey].push(line);
        }
        continue;
      }

      if (!line.startsWith(' ') && !line.startsWith('\t') && line.indexOf(':') >= 0) {
        const colonIndex: number = line.indexOf(':');
        const key: string = line.substring(0, colonIndex).trim();
        currentKey = key;
        for (let topIndex = 0; topIndex < TOP_LEVEL_KEYS.length; topIndex++) {
          if (key === TOP_LEVEL_KEYS[topIndex]) {
            if (!sections[currentKey]) {
              sections[currentKey] = [];
            }
          }
        }
        continue;
      }

      if (currentKey.length > 0 && sections[currentKey]) {
        sections[currentKey].push(line);
      }
    }

    return sections;
  }

  private static mergeSection(baseLines: string[], artifactLines: string[], key: string): string[] {
    const isArraySection: boolean = key === 'proxies' || key === 'proxy-groups' || key === 'rules';

    if (isArraySection) {
      const merged: string[] = [];
      for (let index = 0; index < baseLines.length; index++) {
        merged.push(baseLines[index]);
      }
      for (let index = 0; index < artifactLines.length; index++) {
        merged.push(artifactLines[index]);
      }
      return merged;
    }

    const result: string[] = [];
    const artifactIndent: string[] = [];
    for (let index = 0; index < artifactLines.length; index++) {
      if (artifactLines[index].trim().length > 0) {
        artifactIndent.push(artifactLines[index]);
      }
    }

    const replacedKeys: string[] = [];
    for (let index = 0; index < artifactIndent.length; index++) {
      const trimmed: string = artifactIndent[index].trim();
      const colonIndex: number = trimmed.indexOf(':');
      if (colonIndex > 0 && !trimmed.startsWith('-')) {
        replacedKeys.push(trimmed.substring(0, colonIndex).trim());
      }
    }

    for (let index = 0; index < baseLines.length; index++) {
      const baseTrimmed: string = baseLines[index].trim();
      const baseColonIndex: number = baseTrimmed.indexOf(':');
      let shouldSkip: boolean = false;

      if (baseColonIndex > 0 && !baseTrimmed.startsWith('-')) {
        const baseKey: string = baseTrimmed.substring(0, baseColonIndex).trim();
        for (let repIndex = 0; repIndex < replacedKeys.length; repIndex++) {
          if (baseKey === replacedKeys[repIndex]) {
            shouldSkip = true;
            break;
          }
        }
      }

      if (!shouldSkip) {
        result.push(baseLines[index]);
      }
    }

    for (let index = 0; index < artifactIndent.length; index++) {
      result.push(artifactIndent[index]);
    }

    return result;
  }

  private static createMergeStep(): EnhanceStep {
    return {
      name: 'merge',
      apply: (baseYaml: string, artifacts: EnhanceArtifact[]): string => {
        let result: string = baseYaml;
        for (let index = 0; index < artifacts.length; index++) {
          if (artifacts[index].type === 'merge') {
            result = EnhanceService.applyMerge(result, artifacts[index]);
          }
        }
        return result;
      }
    };
  }

  private static createRulesStep(): EnhanceStep {
    return {
      name: 'rules',
      apply: (baseYaml: string, artifacts: EnhanceArtifact[]): string => {
        let result: string = baseYaml;
        for (let index = 0; index < artifacts.length; index++) {
          if (artifacts[index].type === 'rules') {
            result = EnhanceService.applyRules(result, artifacts[index]);
          }
        }
        return result;
      }
    };
  }

  private static createProxiesStep(): EnhanceStep {
    return {
      name: 'proxies',
      apply: (baseYaml: string, artifacts: EnhanceArtifact[]): string => {
        let result: string = baseYaml;
        for (let index = 0; index < artifacts.length; index++) {
          if (artifacts[index].type === 'proxies') {
            result = EnhanceService.applyProxies(result, artifacts[index]);
          }
        }
        return result;
      }
    };
  }

  private static createGroupsStep(): EnhanceStep {
    return {
      name: 'groups',
      apply: (baseYaml: string, artifacts: EnhanceArtifact[]): string => {
        let result: string = baseYaml;
        for (let index = 0; index < artifacts.length; index++) {
          if (artifacts[index].type === 'groups') {
            result = EnhanceService.applyGroups(result, artifacts[index]);
          }
        }
        return result;
      }
    };
  }
}
