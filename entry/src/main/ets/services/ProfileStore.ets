import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ClashProfile, createEmptyProfileState, ProfileState } from '../models/Profile';

const STORE_NAME: string = 'clash_harmony_profiles';
const KEY_STATE: string = 'profile_state';

export class ProfileStore {
  static async load(context: common.Context): Promise<ProfileState> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
      const raw = await store.get(KEY_STATE, '');
      if (typeof raw !== 'string' || raw.length === 0) {
        return createEmptyProfileState();
      }
      return ProfileStore.parse(raw);
    } catch (err) {
      return createEmptyProfileState();
    }
  }

  static async save(context: common.Context, state: ProfileState): Promise<boolean> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
      await store.put(KEY_STATE, JSON.stringify(state));
      await store.flush();
      return true;
    } catch (err) {
      return false;
    }
  }

  static async addRemote(context: common.Context, profile: ClashProfile): Promise<ProfileState> {
    const state: ProfileState = await ProfileStore.load(context);
    const items: ClashProfile[] = [];
    for (let index = 0; index < state.items.length; index++) {
      items.push(state.items[index]);
    }
    items.push(profile);

    const next: ProfileState = {
      currentUid: state.currentUid.length > 0 ? state.currentUid : profile.uid,
      items: items
    };
    await ProfileStore.save(context, next);
    return next;
  }

  static async activate(context: common.Context, uid: string): Promise<ProfileState> {
    const state: ProfileState = await ProfileStore.load(context);
    let found: boolean = false;
    for (let index = 0; index < state.items.length; index++) {
      if (state.items[index].uid === uid) {
        found = true;
        break;
      }
    }

    if (!found) {
      return state;
    }

    const next: ProfileState = {
      currentUid: uid,
      items: state.items
    };
    await ProfileStore.save(context, next);
    return next;
  }

  static async remove(context: common.Context, uid: string): Promise<ProfileState> {
    const state: ProfileState = await ProfileStore.load(context);
    const items: ClashProfile[] = [];
    for (let index = 0; index < state.items.length; index++) {
      if (state.items[index].uid !== uid) {
        items.push(state.items[index]);
      }
    }

    let nextCurrentUid: string = state.currentUid;
    if (nextCurrentUid === uid) {
      nextCurrentUid = items.length > 0 ? items[0].uid : '';
    }

    const next: ProfileState = {
      currentUid: nextCurrentUid,
      items: items
    };
    await ProfileStore.save(context, next);
    return next;
  }

  static async replace(context: common.Context, profile: ClashProfile): Promise<ProfileState> {
    const state: ProfileState = await ProfileStore.load(context);
    const items: ClashProfile[] = [];
    let replaced: boolean = false;
    for (let index = 0; index < state.items.length; index++) {
      if (state.items[index].uid === profile.uid) {
        items.push(profile);
        replaced = true;
      } else {
        items.push(state.items[index]);
      }
    }

    if (!replaced) {
      items.push(profile);
    }

    const next: ProfileState = {
      currentUid: state.currentUid.length > 0 ? state.currentUid : profile.uid,
      items: items
    };
    await ProfileStore.save(context, next);
    return next;
  }

  private static parse(raw: string): ProfileState {
    const parsed = JSON.parse(raw) as ProfileState;
    if (!parsed || !parsed.items) {
      return createEmptyProfileState();
    }

    const items: ClashProfile[] = [];
    for (let index = 0; index < parsed.items.length; index++) {
      const item: ClashProfile = parsed.items[index];
      if (item.uid.length > 0 && item.name.length > 0) {
        items.push({
          uid: item.uid,
          type: item.type === 'local' ? 'local' : 'remote',
          name: item.name,
          source: item.source,
          filePath: item.filePath ? item.filePath : '',
          updatedAt: item.updatedAt,
          nodeCount: item.nodeCount,
          traffic: item.traffic
        });
      }
    }

    let currentUid: string = parsed.currentUid;
    let hasCurrent: boolean = false;
    for (let index = 0; index < items.length; index++) {
      if (items[index].uid === currentUid) {
        hasCurrent = true;
        break;
      }
    }
    if (!hasCurrent) {
      currentUid = items.length > 0 ? items[0].uid : '';
    }

    return {
      currentUid: currentUid,
      items: items
    };
  }
}
