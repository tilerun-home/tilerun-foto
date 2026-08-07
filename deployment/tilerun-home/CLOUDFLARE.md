# Cloudflare Access en Tunnel

Maak in Cloudflare Access een Generic OIDC SaaS-app met de naam `TileRun / Foto`. Deze handeling blijft bewust een eigenaarshandeling: Cloudflare toont het clientsecret maar eenmaal en dat secret hoort rechtstreeks in `secrets/oidc_client_secret`, niet in Git of terminallogs.

Gebruik deze redirect-URI's:

- `https://foto.tilerun.net/auth/login`
- `https://foto.tilerun.net/user-settings`
- `app.immich:///oauth-callback`
- `https://foto.tilerun.net/api/oauth/mobile-redirect`

Gebruik scopes `openid email profile`. Zet de door Cloudflare verstrekte issuer en client-ID in `.env`. De TileRun Access-worker beheert de groep `TileRun / Foto gebruikers`; koppel uitsluitend die groep aan de SaaS-app. De sectiesleutel is `foto` en het interne rechtpad is `/foto`.

Als Cloudflare de aangepaste mobiele URI `app.immich:///oauth-callback` weigert, registreer dan uitsluitend de HTTPS-callback `https://foto.tilerun.net/api/oauth/mobile-redirect`. De gegenereerde Immich-configuratie gebruikt deze route als mobiele redirect-override.

Activeer SSO op de NAS na het aanmaken van de SaaS-app met `sudo sh scripts/enable-tilerun-sso.sh`. Het script vraagt Client ID en Client secret interactief op, toont het secret niet, maakt zo nodig het technische interne beheerprofiel aan en schakelt daarna wachtwoordlogin uit.

Voeg `cloudflared.example.yml` als ingress toe aan de bestaande Tunnel. Het origin is rechtstreeks `http://192.168.1.2:2283`; maak geen `/foto`-route en geen router-portforwarding. Cloudflare Tunnel transporteert WebSockets automatisch. Controleer vóór acceptatie de uploadlimiet van het actieve Cloudflare-abonnement met een testvideo die groter is dan een normale foto.

Na de eerste SSO-login van de TileRun-superbeheerder:

1. Maak in TileRun Foto een API-key met uitsluitend `adminUser.read`, `adminSession.read` en `adminSession.delete`.
2. Plaats de sleutel op de TileRun-deployment in `secrets/immich_admin_api_key` met modus `0600`.
3. Voer een intrekking met een testgebruiker uit en bevestig dat web- en mobiele sessies stoppen terwijl profiel, albums en foto's blijven bestaan.
4. Test web, officiële mobiele callback en noodherstel. Zet pas daarna `TILERUN_FOTO_PASSWORD_LOGIN=false` en render de configuratie opnieuw.

De Tunnel en SaaS-app kunnen pas live worden aangemaakt wanneer de eigenaar bij Cloudflare is ingelogd; de repository bevat geen Cloudflare-account-ID, tokens of credentials.
