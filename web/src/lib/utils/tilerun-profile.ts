export type TileRunProfile = {
  user_id: number;
  email: string;
  display_name: string;
  preferred_language: string | null;
  effective_language: string;
  home_name: string;
  home_default_language: string;
  home_version: number;
  avatar_url: string | null;
  avatar_version: number;
  version: number;
};

const call = async <T>(init?: RequestInit): Promise<T> => {
  const response = await fetch('/api/tilerun/profile', {
    ...init,
    headers: { Accept: 'application/json', 'Content-Type': 'application/json', ...init?.headers },
  });
  const payload = (await response.json().catch(() => ({}))) as T & { message?: string };
  if (!response.ok) {
    throw new Error(payload.message || `TileRun-profiel kon niet worden geladen (${response.status})`);
  }
  return payload;
};

export const getTileRunProfile = () => call<TileRunProfile>();

export type TileRunProfileUpdate = {
  displayName?: string;
  preferredLanguage?: string | null;
  version: number;
};

export const updateTileRunProfile = (update: TileRunProfileUpdate) =>
  call<TileRunProfile>({ method: 'PATCH', body: JSON.stringify(update) });
