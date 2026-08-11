import { timingSafeEqual } from 'node:crypto';
import { readFile, readFileSync } from 'node:fs';
import { promisify } from 'node:util';

const readFileAsync = promisify(readFile);

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

type ProfileUpdate = { display_name?: string; preferred_language?: string | null; version?: number };

let cachedSecret: string | undefined;

const config = () => {
  const baseUrl = (process.env.TILERUN_PROFILE_API_URL || 'http://192.168.1.2:8081/api/v1/integrations/foto').replace(
    /\/$/,
    '',
  );
  if (cachedSecret === undefined) {
    cachedSecret = process.env.TILERUN_PROFILE_SECRET?.trim() || '';
    const file = process.env.TILERUN_PROFILE_SECRET_FILE?.trim();
    if (!cachedSecret && file) {
      cachedSecret = readFileSync(file, 'utf8').trim();
    }
  }
  if (!cachedSecret) {
    throw new Error('TileRun profile integration secret is not configured');
  }
  return { baseUrl, secret: cachedSecret };
};

export const validateTileRunServiceToken = (candidate: string | undefined) => {
  const { secret } = config();
  if (!candidate) {
    return false;
  }
  const actual = Buffer.from(candidate);
  const expected = Buffer.from(secret);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
};

const call = async <T>(path: string, init: RequestInit = {}): Promise<T> => {
  const { baseUrl, secret } = config();
  const response = await fetch(`${baseUrl}${path}`, {
    ...init,
    signal: AbortSignal.timeout(5000),
    headers: { Authorization: `Bearer ${secret}`, Accept: 'application/json', ...init.headers },
  });
  const payload = (await response.json().catch(() => ({}))) as { data?: T; error?: { message?: string } };
  if (!response.ok || !payload.data) {
    throw new Error(payload.error?.message || `TileRun profile request failed (${response.status})`);
  }
  return payload.data;
};

export const getTileRunProfile = (email: string) =>
  call<TileRunProfile>(`/profile?email=${encodeURIComponent(email.toLowerCase())}`);

export const updateTileRunProfile = (email: string, update: ProfileUpdate) =>
  call<TileRunProfile>('/profile', {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: email.toLowerCase(), ...update }),
  });

export const uploadTileRunAvatar = async (email: string, path: string, contentType: string) => {
  const data = await readFileAsync(path);
  const form = new FormData();
  form.set('email', email.toLowerCase());
  form.set('file', new Blob([data], { type: contentType }), 'avatar');
  return call<TileRunProfile>('/profile/avatar', { method: 'POST', body: form });
};

export const deleteTileRunAvatar = (email: string) =>
  call<TileRunProfile>('/profile/avatar', {
    method: 'DELETE',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: email.toLowerCase() }),
  });
