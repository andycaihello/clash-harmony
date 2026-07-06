export type ProfileType = 'remote' | 'local';

export interface ClashProfile {
  uid: string;
  type: ProfileType;
  name: string;
  source: string;
  filePath: string;
  updatedAt: number;
  nodeCount: number;
  traffic: string;
}

export interface ProfileState {
  currentUid: string;
  items: ClashProfile[];
}

export function createEmptyProfileState(): ProfileState {
  return {
    currentUid: '',
    items: []
  };
}

export function createRemoteProfile(name: string, url: string): ClashProfile {
  const now: number = Date.now();
  return {
    uid: `remote_${now}`,
    type: 'remote',
    name: name,
    source: url,
    filePath: '',
    updatedAt: now,
    nodeCount: 0,
    traffic: '未知'
  };
}

export function createLocalProfile(name: string, filePath: string, nodeCount: number, traffic: string): ClashProfile {
  const now: number = Date.now();
  return {
    uid: `local_${now}`,
    type: 'local',
    name: name,
    source: filePath,
    filePath: filePath,
    updatedAt: now,
    nodeCount: nodeCount,
    traffic: traffic
  };
}

export function formatProfileUpdatedAt(updatedAt: number): string {
  if (updatedAt <= 0) {
    return '未更新';
  }

  const date: Date = new Date(updatedAt);
  const month: number = date.getMonth() + 1;
  const day: number = date.getDate();
  const hour: number = date.getHours();
  const minute: number = date.getMinutes();
  return `${month}/${day} ${pad2(hour)}:${pad2(minute)}`;
}

function pad2(value: number): string {
  if (value < 10) {
    return `0${value}`;
  }
  return `${value}`;
}
