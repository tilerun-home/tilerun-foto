import { eventManager } from '$lib/managers/event-manager.svelte';
import {
  getTileRunProfile,
  updateTileRunProfile,
  type TileRunProfile,
  type TileRunProfileUpdate,
} from '$lib/utils/tilerun-profile';

export class TileRunProfileManager {
  profile = $state<TileRunProfile>();
  loading = $state(false);

  #attemptedFor = '';
  #request?: Promise<TileRunProfile | undefined>;

  constructor() {
    eventManager.on({
      AuthLogout: () => this.reset(),
      AuthUserLoaded: (user) => void this.load(user.email),
    });
  }

  async load(email: string): Promise<TileRunProfile | undefined> {
    const normalizedEmail = email.trim().toLowerCase();
    if (!normalizedEmail) {
      return;
    }
    if (this.#attemptedFor === normalizedEmail) {
      return this.#request ?? this.profile;
    }

    this.#attemptedFor = normalizedEmail;
    this.loading = true;
    this.#request = getTileRunProfile()
      .then((profile) => (this.profile = profile))
      .catch(() => undefined)
      .finally(() => {
        this.loading = false;
        this.#request = undefined;
      });
    return this.#request;
  }

  async refresh(): Promise<TileRunProfile | undefined> {
    const email = this.#attemptedFor;
    this.#attemptedFor = '';
    return email ? this.load(email) : undefined;
  }

  async update(update: TileRunProfileUpdate): Promise<TileRunProfile> {
    const profile = await updateTileRunProfile(update);
    this.profile = profile;
    this.#attemptedFor = profile.email.trim().toLowerCase();
    return profile;
  }

  reset() {
    this.profile = undefined;
    this.loading = false;
    this.#attemptedFor = '';
    this.#request = undefined;
  }
}

export const tileRunProfileManager = new TileRunProfileManager();
