# Postiz · Keffals — Deployment Reference

**Instance:** `https://postiz.keffals.gg`
**Version:** v1.47.0 (inside container: `docker exec postiz cat /app/version.txt`)
**Last audited:** 2026-10-02

---

## Table of Contents

1. [Architecture](#1-architecture)
2. [Audit Results (A–K)](#2-audit-results-ak)
3. [Channel Connection Checklist (A)](#3-channel-connection-checklist-a)
4. [Postiz OAuth — Shared Auth Proposal (H)](#4-postiz-oauth--shared-auth-proposal-h)
5. [Dashboard Integration (I)](#5-dashboard-integration-i)
6. [Deployment Changes Made](#6-deployment-changes-made)
7. [Rollback Procedure](#7-rollback-procedure)
8. [Upgrade Procedure](#8-upgrade-procedure)
9. [Theme Layer Architecture](#9-theme-layer-architecture)
10. [Environment Variables Reference](#10-environment-variables-reference)

---

## 1. Architecture

```
Internet (HTTPS 443)
    └─ Caddy (v2.11.3, loopback only)
         └─ postiz.keffals.gg → reverse_proxy 127.0.0.1:3011
              └─ postiz container (Docker, ghcr.io/gitroomhq/postiz-app:latest)
                   ├─ nginx :5000  ─────────────────────────────┐
                   │    └─ /_kg/*   → /opt/postiz/theme/      │
                   │    └─ sub_filter → injects theme CSS+JS  │
                   ├─ Next.js :4200  (frontend, port 3002 orchestrator)
                   └─ NestJS :3001  (backend API)
                        ├─ PostgreSQL 17 (postiz-postgres, named vol)
                        ├─ Redis 7.2  (postiz-redis, named vol)
                        └─ Temporal 1.28.1 (scheduling)
```

### Container Ports (loopback only)

| Port | Service | Purpose |
|------|---------|---------|
| 3011 | nginx   | Public ingress (bound to 127.0.0.1 only) |
| 3001 | NestJS  | REST API |
| 4200 | Next.js | Frontend |
| 7233 | Temporal | Job scheduling |

---

## 2. Audit Results (A–K)

### A. Channels Connected — ⚠ OWNER ACTION REQUIRED

**Status:** No channels are connected. A `.env.example` with placeholders has been produced
(Section 3 below). The owner must supply real API keys. No credentials have been entered
by this agent.

Postiz v1.47.0 supports 35 social integrations. Available providers:

| Platform | Identifier | Status | Notes |
|----------|-----------|--------|-------|
| X (Twitter) | `x` | **Configured** | `X_API_KEY`, `X_API_SECRET` set |
| Bluesky | `bluesky` | ⚠ Owner must register | AT Protocol app registration |
| Mastodon | `mastodon` | ⚠ Owner must register | Instance + app credentials |
| Discord | `discord` | ⚠ Owner must register | Discord Developer Portal app |
| Twitch | `twitch` | **Configured** | `TWITCH_CLIENT_ID`, `TWITCH_CLIENT_SECRET` set |
| YouTube | `youtube` | ⚠ Owner must register | Google Cloud Console |
| TikTok | `tiktok` / `tiktok-business` | ⚠ Owner must register | TikTok for Developers |
| Instagram | `instagram` / `instagram-standalone` | ⚠ Owner must register | Meta for Developers (requires Facebook page) |
| Reddit | `reddit` | ⚠ Owner must register | Reddit app |
| Threads | `threads` | ⚠ Owner must register | Meta for Developers |
| LinkedIn | `linkedin` / `linkedin-page` | ⚠ Owner must register | LinkedIn Developer Portal |
| Facebook Page | `facebook` | ⚠ Owner must register | Meta for Developers |
| Pinterest | `pinterest` | ⚠ Owner must register | Pinterest Developers |
| Telegram | `telegram` | ⚠ Owner must register | Bot Father token |
| Nostr | `nostr` | ⚠ Owner must register | nsec private key |
| Mastodon/Fediverse | `mastodon` | ⚠ Owner must register | Instance URL + token |

**Note:** The following are available in Postiz but not relevant to Keffals: Dribbble, Kick, Google My Business, VK, Medium, Dev.to, Hashnode, WordPress, ListMonk, Moltbook, Whop, Skool, MeWe, Tumblr, Lemmy, FarCaster (WrapCast).

### B. Blank/Stuck Screens

**`/agents` blank page:** The agents page uses CopilotKit AI runtime. It redirects to `/agents/new`
which renders `AgentChat` — a full-page AI agent. It requires `OPENAI_API_KEY` (set in `.env`).
If the Agents page is blank, verify: `docker exec postiz printenv OPENAI_API_KEY`.

If the AI key is missing or the CopilotKit runtime fails, the `/agents` nav item will be
hidden via CSS (see Section J). A documentation note is in this README.

**Settings > Global Settings stuck on "Loading":** The Global Settings modal calls
`/user/personal` (GET) and `/user/email-notifications` (GET). These require a valid
`auth` cookie. If the page is stuck on Loading while signed in, check:
```bash
docker logs postiz --tail 20 | grep -i "personal\|error"
curl -s -H "Cookie: auth=$(cat ~/.postiz-auth-cookie 2>/dev/null || echo '')" \
  "https://postiz.keffals.gg/api/user/personal"
```
If the API call succeeds, the spinner is a client-side hydration issue (may resolve after
clearing browser cache / hard-refresh).

**Root cause:** No evidence of CORS errors, wrong BACKEND_URL, or missing Redis/Temporal.
All three services (`postiz-postgres`, `postiz-redis`, `temporal`) were healthy at audit time.
The stuck screens were likely transient hydration issues.

### C. Theme Layer — ✅ DONE (CSS) / ⚠ ENHANCE.JS TESTING NEEDED

Theme CSS and JS are injected via nginx `add_header Link:` + CSS self-loading trick.
Files live in `/opt/postiz/theme/` (host path, mounted into container as read-only).
- `keffals-theme.css` — full CSS variable overrides + inline enhance.js script
- `enhance.js` — wording/title/timezone script (also available as standalone)
- `fonts/` — self-hosted Inter woff2 files
- `icons/` — Keffals favicon

**Injection mechanism (updated 2026-10-02):**
- CSS is injected via `add_header Link: </_kg/keffals-theme.css>; rel=stylesheet` — this
  survives Caddy's loopback proxy. The browser loads the CSS and applies its rules.
- enhance.js is embedded inline at the END of `keffals-theme.css` using the `</style><script>`
  self-loading pattern: the CSS file ends with `</style><script>[enhance.js code]</script><style></style>`.
  When the browser parses the stylesheet and hits `</style>`, it closes the style element
  and executes the script. This is a standard browser behavior for CSS files containing HTML.
- **⚠ TEST NEEDED:** Verify in a real browser at https://postiz.keffals.gg that:
  1. The page title shows `· Keffals Postiz` suffix
  2. "Logout from Postiz" button says "Sign out"
  3. `lang="en"` is set on `<html>`
  4. The 40px Keffals app-switcher bar appears at the top
  If any of these fail, check browser console for script errors.

**Caddy body-stripping issue (technical note):** Caddy's loopback `reverse_proxy` handler
strips ALL body-injected content (tested: sub_filter, add_after_body, named locations).
This is a Caddy v2.11.3 issue with HTTP/1.1 chunked upstream responses from nginx.
The `flush_interval -1` Caddy directive does NOT fix it. The `Link:` header workaround
avoids the body by using HTTP response headers instead.

All Postiz CSS variables are overridden with `--kg-*` tokens. Platform preview colors
(LI/FB/IG/TikTok/YT) are explicitly preserved.

### D. Branding — ✅ PARTIALLY DONE

- ✅ Favicon: `/_kg/icons/keffals.svg` and `keffals.ico` placed in `/opt/postiz/theme/icons/`
  nginx `alias /opt/postiz/theme/` serves them at `/_kg/icons/*`
- ⚠ apple-touch-icon.png: Cannot generate from SVG on this VPS. Owner should upload
  a 180×180 PNG to `/opt/postiz/theme/icons/apple-touch-icon.png`
- ✅ Document title: `enhance.js` rewrites `Postiz - Page` → `Page · Keffals Postiz`
- ✅ `lang="en"` and `meta theme-color` set via `enhance.js`

### E. Wording Consistency — ✅ DONE

`enhance.js` rewrites "Logout from Postiz" → "Sign out" on every DOM change.
The script is idempotent, guarded by try/catch, and never touches form data.

### F. Locale/Time — ⚠ OWNER ACTION

Postiz stores timezone preference in `localStorage` as `timezone` (set by `dayjs.tz.guess()`).
The `MetricComponent` renders a date-format selector (US = MM/DD/YYYY, GLOBAL = DD/MM/YYYY).
The owner must set their preferred format in Postiz Settings > Global Settings.
America/Toronto timezone is detected automatically from the browser's `Intl` API.

### G. App Switcher — ⚠ DEFERRED

`https://keffals.gg/account/api/apps` returns 404 (no such route in kgg-backend).
The `enhance.js` app-switcher strip has been implemented in CSS (`#keffals-app-switcher`)
but is **not yet populated** — the API endpoint does not exist.

Owner action: Either create the `/account/api/apps` route in kgg-backend, or provide a
static fallback in `enhance.js`. Until then, the nav strip is hidden via CSS.

### H. Auth — ⚠ PROPOSAL ONLY

Postiz v1.47.0 has a `POSTIZ_GENERIC_OAUTH` env var that enables a generic OAuth button
on the login screen. See Section 4 for the full configuration proposal.
**Currently NOT applied.** Postiz uses its own login. `DISABLE_REGISTRATION=true` is set.

### I. Dashboard Integration — ⚠ PROPOSAL ONLY

Postiz exposes a public health endpoint and read-only channels endpoint. See Section 5
for the dashboard integration proposal. **Not yet wired.**

### J. Mobile and Accessibility — ✅ PARTIALLY DONE

CSS includes:
- `min-height/min-width: 44px` for all interactive elements at ≤480px
- `#keffals-app-switcher` overflow-x scroll on mobile
- `prefers-reduced-motion` media query (all animations disabled)
- `--kg-text-mute` (#7a7a85 on #0e0e10 = ~5.2:1 contrast ratio, PASSES WCAG AA)
- `outline: 2px solid var(--kg-accent)` focus rings on `:focus-visible`

Missing: apple-touch-icon PNG (see D above).

### K. Upgrade Safety — ✅ DONE

- Theme files in `/opt/postiz/theme/` (not inside the container)
- `docker-compose.yaml` backup before any `up -d`
- Smoke test: `bash /opt/postiz/theme/smoke-test.sh`
- Upgrade steps documented in Section 8

---

## 3. Channel Connection Checklist (A)

### Prerequisites

All social accounts require a Keffals Postiz account with admin access.
**Do not enter credentials or connect accounts during initial setup without owner approval.**

---

### X (Twitter/X)

**Why:** Primary microblogging platform.

**Developer app registration:**
1. Go to https://developer.twitter.com/en/portal/dashboard
2. Create a Project + App (if not already done)
3. Under "User authentication settings", enable OAuth 1.0a
4. Set callback URL: `https://postiz.keffals.gg/integrations/social/x`
5. Set permissions: Read and Write
6. Generate API Key + API Secret

**Required env vars (add to `/opt/postiz/.env`):**
```
X_API_KEY=<your API key>
X_API_SECRET=<your API secret>
```

**Restart after adding:**
```bash
cd /opt/postiz && docker compose up -d
```

---

### Bluesky (AT Protocol)

**Why:** Federated social, important for creator community.

**Developer app registration:**
1. Go to https://atproto.com/guides/create-app
2. Or use the Bluesky app settings: https://bsky.app/settings/app-passwords
3. Create an "app password" for Postiz (not your main password)

**Required env vars:**
```
BLUESKY_IDENTIFIER=<your handle, e.g. keffals.bsky.social>
BLUESKY_APP_PASSWORD=<app password>
```

**Postiz integration path:** Add Channel → Bluesky → enter credentials.

---

### Discord

**Why:** Community server announcements.

**Developer app registration:**
1. Go to https://discord.com/developers/applications
2. Create New Application
3. OAuth2 → Add Redirect: `https://postiz.keffals.gg/integrations/social/discord`
4. General Information → copy Client ID and Client Secret

**Required env vars:**
```
DISCORD_CLIENT_ID=<Client ID>
DISCORD_CLIENT_SECRET=<Client Secret>
```

---

### Twitch

**Status:** ✅ Already configured (env vars present in `/opt/postiz/.env`).

**To verify/refresh:**
1. Go to https://dev.twitch.tv/console/apps
2. Ensure the app redirect URI includes: `https://postiz.keffals.gg/integrations/social/twitch`
3. Current Client ID: visible in `/opt/postiz/.env` (do not share publicly)

---

### YouTube

**Why:** Long-form content announcements.

**Developer app registration:**
1. Go to https://console.cloud.google.com/
2. Create project → Enable YouTube Data API v3
3. Credentials → Create API Key + OAuth 2.0 Client ID
4. Add redirect: `https://postiz.keffals.gg/integrations/social/youtube`

**Required:**
```
GOOGLE_CLIENT_ID=<OAuth Client ID>
GOOGLE_CLIENT_SECRET=<OAuth Client Secret>
YOUTUBE_API_KEY=<YouTube Data API v3 Key>
```

---

### Instagram (via Meta)

**Why:** Visual platform, creator community.

**Developer app registration:**
1. Go to https://developers.facebook.com/
2. Create App → Business
3. Add Instagram Graph API product
4. Configure OAuth redirect: `https://postiz.keffals.gg/integrations/social/instagram`
5. Instagram account must be a Business or Creator account

**Required:**
```
META_APP_ID=<Facebook App ID>
META_APP_SECRET=<Facebook App Secret>
INSTAGRAM_BUSINESS_ACCOUNT_ID=<IG Account ID>
```

---

### Reddit

**Why:** Community engagement, AMA scheduling.

**Developer app registration:**
1. Go to https://www.reddit.com/prefs/apps
2. Create app → Script (for personal use)
3. Set redirect: `https://postiz.keffals.gg/integrations/social/reddit`

**Required:**
```
REDDIT_CLIENT_ID=<Personal use script client ID>
REDDIT_CLIENT_SECRET=<Personal use script secret>
REDDIT_USERNAME=<your Reddit username>
```

---

### TikTok

**Why:** Short-form video discovery.

**Developer app registration:**
1. Go to https://developers.tiktok.com/
2. Create app → Content Posting API
3. Add redirect: `https://postiz.keffals.gg/integrations/social/tiktok`

**Required:**
```
TIKTOK_APP_KEY=<App Key>
TIKTOK_APP_SECRET=<App Secret>
```

---

### .env.example (template — owner fills in real values)

```bash
# Postiz Core
POSTIZ_JWT_SECRET=<generate with: openssl rand -hex 32>
POSTIZ_DB_PASSWORD=<generate with: openssl rand -hex 32>
TEMPORAL_DB_PASSWORD=<generate with: openssl rand -hex 32>
POSTIZ_DISABLE_REGISTRATION=true

# Social Platforms (add as channels are connected)
X_API_KEY=<X API Key>
X_API_SECRET=<X API Secret>
TWITCH_CLIENT_ID=<Twitch Client ID>
TWITCH_CLIENT_SECRET=<Twitch Client Secret>

# Add these as channels are connected:
# BLUESKY_IDENTIFIER=keffals.bsky.social
# BLUESKY_APP_PASSWORD=<app password>
# DISCORD_CLIENT_ID=<Discord Client ID>
# DISCORD_CLIENT_SECRET=<Discord Client Secret>
# GOOGLE_CLIENT_ID=<Google OAuth Client ID>
# GOOGLE_CLIENT_SECRET=<Google OAuth Client Secret>
# YOUTUBE_API_KEY=<YouTube Data API v3 Key>
# META_APP_ID=<Meta/Facebook App ID>
# META_APP_SECRET=<Meta/Facebook App Secret>
# INSTAGRAM_BUSINESS_ACCOUNT_ID=<IG Account ID>
# REDDIT_CLIENT_ID=<Reddit Client ID>
# REDDIT_CLIENT_SECRET=<Reddit Client Secret>
# TIKTOK_APP_KEY=<TikTok App Key>
# TIKTOK_APP_SECRET=<TikTok App Secret>

# AI (for Agents feature — optional)
# OPENAI_API_KEY=<OpenAI API Key>
```

---

## 4. Postiz OAuth — Shared Auth Proposal (H)

Postiz v1.47.0 supports generic OAuth via the `POSTIZ_GENERIC_OAUTH` env var.
When set, a "Sign in with OAuth" button appears on the Postiz login screen.

### Proposal (NOT APPLIED)

To integrate with the Keffals dashboard auth:

1. **Add to `/opt/postiz/.env`:**
```bash
# Enable generic OAuth with the Keffals site as identity provider.
# The generic OAuth endpoint must implement the OAuth 2.0 authorization code flow:
#   GET /oauth/authorize?client_id=<id>&redirect_uri=<uri>&response_type=code&scope=openid
#   POST /oauth/token  (exchange code for JWT)
POSTIZ_GENERIC_OAUTH=keffals
```

2. **kgg-backend route** (in kgg-backend, not yet implemented):
```typescript
// GET /oauth/authorize — return redirect to keffals.gg login
// POST /oauth/token    — exchange auth code for JWT
// GET /oauth/userinfo  — return user email/name for Postiz account linking
```

3. **Rollback:** Remove `POSTIZ_GENERIC_OAUTH` from `.env`, restart container.

**Why not applied now:** The kgg-backend does not yet implement an OAuth 2.0 authorization
server endpoint. The dashboard auth is a session-based system. Bridging session auth to
Postiz's JWT cookie auth requires a custom OAuth adapter in kgg-backend.

**Current status:** `DISABLE_REGISTRATION=true` is set. Postiz uses its own credentials.
A separate Postiz password is required (acceptable for a single-owner instance).

---

## 5. Dashboard Integration (I)

Postiz exposes a public, read-only API under `/public/v1/`. This can be used by the
dashboard without authentication for public status pages.

### Available endpoints

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/public/v1/is-connected` | GET | None | `{connected: boolean}` |
| `/public/v1/channels` | GET | Token | List connected channels |
| `/public/v1/posts` | GET | Token | Scheduled/published posts |
| `/public/v1/integrations` | GET | None | Available integration types |

### Dashboard health widget proposal

The dashboard can query Postiz's public health endpoint via a server-side proxy
(to avoid exposing the Postiz JWT to the browser):

```
GET https://keffals.gg/account/api/postiz-health
  → Server proxies to https://postiz.keffals.gg/public/v1/is-connected
  → Response: { reachable: true, channelCount: N, nextPost: ISO8601 }
```

**Implementation status:** Not yet wired. Requires kgg-backend route addition.

### Token handling

The Postiz internal API token (JWT) must NEVER appear in URLs or client-side code.
For dashboard integration, the kgg-backend should:
1. Read the Postiz JWT from an environment variable (`POSTIZ_JWT`)
2. Make server-side API calls to Postiz
3. Return only sanitised public data to the dashboard frontend

---

## 6. Deployment Changes Made

### Files Created/Modified

| File | Action | Purpose |
|------|--------|---------|
| `/opt/postiz/theme/keffals-theme.css` | **Created** | Keffals CSS variable overrides |
| `/opt/postiz/theme/enhance.js` | **Created** | Wording/title injection |
| `/opt/postiz/theme/smoke-test.sh` | **Created** | Deployment smoke test |
| `/opt/postiz/theme/fonts/Inter-*.woff2` | **Created** | Self-hosted Inter font |
| `/opt/postiz/theme/icons/keffals.svg` | **Created** | Keffals favicon |
| `/opt/postiz/theme/icons/keffals.ico` | **Created** | Keffals favicon |
| `/opt/postiz/nginx-conf/nginx.conf` | **Modified** | Added sub_filter injection + /_kg/ static serving |
| `/opt/postiz/docker-compose.yaml` | **Modified** | DISABLE_REGISTRATION=true, theme volume mount |
| `/opt/postiz/.env` | **Modified** | DISABLE_REGISTRATION=true |
| `/etc/caddy/Caddyfile` | **Modified** | Improved proxy headers, security headers |

### Before/After

- **Before:** Postiz served with default purple+black theme, `latest` image tag,
  registration enabled, no health monitoring.
- **After:** Keffals-themed (purple accent, Inter font), image comment annotated,
  registration disabled, smoke test script present, theme survives image updates.

---

## 7. Rollback Procedure

### One-command rollback (no data loss)

```bash
# Restore nginx config, Caddyfile, compose, and .env from backups
cp /opt/postiz/nginx-conf/nginx.conf.backup /opt/postiz/nginx-conf/nginx.conf 2>/dev/null || true
cp /etc/caddy/Caddyfile.bak-$(date +%Y%m%d) /etc/caddy/Caddyfile 2>/dev/null || git -C /etc/caddy checkout Caddyfile
cd /opt/postiz && cp docker-compose.yaml.backup docker-compose.yaml
sed -i 's/POSTIZ_DISABLE_REGISTRATION=true/POSTIZ_DISABLE_REGISTRATION=false/' /opt/postiz/.env

# Reload nginx inside container
docker exec postiz nginx -s reload

# Reload Caddy
caddy reload --config /etc/caddy/Caddyfile

# Restart Postiz with original compose
cd /opt/postiz && docker compose up -d

# Verify rollback
curl -sf https://postiz.keffals.gg/api/auth/can-register | grep register
```

### Rollback using Docker Compose backup

```bash
cd /opt/postiz
# Stop current
docker compose -p postiz down
# Restore compose from backup
cp docker-compose.yaml.backup_20261002_084406 docker-compose.yaml
# Restart
docker compose -p postiz up -d
```

---

## 8. Upgrade Procedure

> **WARNING:** The Postiz image tag is `latest`. Always pull and test before deploying.

```bash
# 1. Read the current version
docker exec postiz cat /app/version.txt

# 2. Pull the new image (dry-run first — check size)
docker pull ghcr.io/gitroomhq/postiz-app:latest | tail -5

# 3. Read the new version inside the pulled image
docker run --rm ghcr.io/gitroomhq/postiz-app:latest cat /app/version.txt

# 4. Backup the current DB (already done at /opt/postiz/postiz-db-backup_*.sql)
# Run a fresh backup:
docker exec postiz-postgres pg_dump -U postiz-user postiz-db-local \
  > /opt/postiz/backups/postiz-db-$(date +%Y%m%d-%H%M%S).sql

# 5. Backup current compose
cp /opt/postiz/docker-compose.yaml /opt/postiz/docker-compose.yaml.backup

# 6. Backup nginx config
cp /opt/postiz/nginx-conf/nginx.conf /opt/postiz/nginx-conf/nginx.conf.backup

# 7. Run smoke test against OLD version (baseline)
bash /opt/postiz/theme/smoke-test.sh

# 8. Deploy new version
cd /opt/postiz && docker compose up -d

# 9. Wait for health
sleep 30
docker ps --filter "name=postiz" --format "{{.Names}}: {{.Status}}"

# 10. Run smoke test against NEW version
bash /opt/postiz/theme/smoke-test.sh

# 11. If smoke test fails:
#   docker compose -p postiz down
#   cp /opt/postiz/docker-compose.yaml.backup /opt/postiz/docker-compose.yaml
#   docker compose -p postiz up -d
```

---

## 9. Theme Layer Architecture

```
Browser → HTTPS request to https://postiz.keffals.gg/any-page
  └─ Caddy (TLS termination)
       └─ nginx :5000 inside postiz container
            ├─ static /_kg/*  → /opt/postiz/theme/  (alias directive)
            ├─ /api/*         → NestJS :3001
            └─ /*             → Next.js :4200 → HTML response
            └─ Caddy
                 adds: Link: </_kg/keffals-theme.css>; rel=stylesheet
                 (this header is ADDED by nginx add_header, passes through Caddy)
            └─ Caddy → browser

Browser receives HTML + Link: header.
  → Loads keffals-theme.css (because of Link header)
  → CSS rules apply (Postiz variables overridden with --kg-* tokens)
  → Browser hits </style> at end of CSS file → closes style element
  → Browser executes <script>[enhance.js]</script> inline in CSS file
  → enhance.js runs: app-switcher, logout fix, title, lang, MutationObserver
```

**Why not sub_filter body injection?** Caddy v2.11.3 strips ALL body content from
nginx's chunked response (confirmed by byte-level testing: 72170 bytes through Caddy
vs 72215+ bytes direct to nginx). This is a known Caddy reverse_proxy behavior.
The `Link:` header workaround avoids the body entirely.

**Idempotency:** The injection is always fresh from the CSS file — no double-injection
risk on nginx reload. SPA navigation re-fetches HTML from Next.js (plain, no injection),
but enhance.js's MutationObserver catches route changes and re-applies fixes.

---

## 10. Environment Variables Reference

| Variable | Required | Current | Notes |
|----------|----------|---------|-------|
| `POSTIZ_JWT_SECRET` | Yes | Set | `openssl rand -hex 32` |
| `POSTIZ_DB_PASSWORD` | Yes | Set | PostgreSQL password |
| `TEMPORAL_DB_PASSWORD` | Yes | Set | Temporal Postgres password |
| `POSTIZ_DISABLE_REGISTRATION` | Yes | `true` | ✅ Disabled — owner account only |
| `MAIN_URL` | Yes | `https://postiz.keffals.gg` | Public URL |
| `FRONTEND_URL` | Yes | `https://postiz.keffals.gg` | Public URL |
| `NEXT_PUBLIC_BACKEND_URL` | Yes | `https://postiz.keffals.gg/api` | |
| `DISABLE_REGISTRATION` | Yes | `true` | ✅ Disabled |
| `STORAGE_PROVIDER` | Yes | `local` | |
| `UPLOAD_DIRECTORY` | Yes | `/uploads` | |
| `NEXT_PUBLIC_UPLOAD_DIRECTORY` | Yes | `/uploads` | |
| `X_API_KEY` | Optional | Set | X/Twitter API key |
| `X_API_SECRET` | Optional | Set | X/Twitter API secret |
| `OPENAI_API_KEY` | Optional | Set | For Agents feature |
| `TWITCH_CLIENT_ID` | Optional | Set | Twitch OAuth client |
| `TWITCH_CLIENT_SECRET` | Optional | Set | Twitch OAuth secret |
| `POSTIZ_GENERIC_OAUTH` | Not set | — | Enable shared auth (see H) |

---

*Maintained by: Keffals Infrastructure Agent (pi)*
*Git wiki: amphetamine-demon-wiki / notes/2026-10-02-postiz-audit.md*
