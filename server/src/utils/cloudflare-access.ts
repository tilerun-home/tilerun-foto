import { createRemoteJWKSet, jwtVerify } from 'jose';

export type CloudflareAccessIdentity = {
  email: string;
  subject: string;
};

let cachedIssuer = '';
let cachedJwks: ReturnType<typeof createRemoteJWKSet> | undefined;

const getAccessConfig = () => {
  const issuer = (process.env.TILERUN_CF_ACCESS_ISSUER || '').trim().replace(/\/$/, '');
  const audience = (process.env.TILERUN_CF_ACCESS_AUD || '').trim();

  if (!/^https:\/\/[a-z0-9-]+\.cloudflareaccess\.com$/i.test(issuer)) {
    throw new Error('TileRun Cloudflare Access issuer is not configured');
  }
  if (!/^[A-Za-z0-9_-]{32,128}$/.test(audience)) {
    throw new Error('TileRun Cloudflare Access audience is not configured');
  }

  return { issuer, audience };
};

export const validateCloudflareAccessJwt = async (token: string | undefined): Promise<CloudflareAccessIdentity> => {
  if (!token) {
    throw new Error('Cloudflare Access assertion is missing');
  }

  const { issuer, audience } = getAccessConfig();
  if (!cachedJwks || cachedIssuer !== issuer) {
    cachedIssuer = issuer;
    cachedJwks = createRemoteJWKSet(new URL(`${issuer}/cdn-cgi/access/certs`));
  }

  const { payload } = await jwtVerify(token, cachedJwks, {
    issuer,
    audience,
    algorithms: ['RS256'],
  });

  const email = typeof payload.email === 'string' ? payload.email.trim().toLowerCase() : '';
  if (payload.type !== 'app' || !email || typeof payload.sub !== 'string' || !payload.sub) {
    throw new Error('Cloudflare Access assertion does not contain a valid user identity');
  }

  return { email, subject: payload.sub };
};
