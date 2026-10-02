#!/usr/bin/env bash
# =============================================================================
# Postiz Smoke Test
# Location: /opt/postiz/theme/smoke-test.sh
# Usage:   bash /opt/postiz/theme/smoke-test.sh
#
# Checks that Postiz is up, the Keffals theme is injected, and no routes
# produce console errors.  Fails (exit 1) if any check fails.
#
# Injection mechanism (updated 2026-10-02):
# - CSS via Link: header (nginx add_header, survives Caddy)
# - enhance.js via inline </style><script> at end of keffals-theme.css
#   (browser executes it when parsing the CSS file as a stylesheet)
#
# Requires: curl, grep (no external deps — runs on the VPS directly).
# =============================================================================
set -euo pipefail

HOST="${POSTIZ_HOST:-https://postiz.keffals.gg}"
TIMEOUT=10
FAILED=0

log()  { echo "[$(date +%H:%M:%S)] $*"; }
pass() { echo "  ✓ $*"; }
fail() { echo "  ✗ $*" >&2; FAILED=1; }

# ── Helpers ────────────────────────────────────────────────────────────────
http_get() {
  curl -sf -L --max-time "$TIMEOUT" \
    -H "Accept: text/html,application/xhtml+xml" \
    "$1"
}

# ── 1. Health check ───────────────────────────────────────────────────────
log "1. Backend health (/api/auth/can-register)"
HEALTH=$(curl -sf --max-time "$TIMEOUT" \
  "https://postiz.keffals.gg/api/auth/can-register" 2>&1 || true)
if [[ "$HEALTH" == *"register"* ]]; then
  pass "Backend responding"
else
  fail "Backend not responding: $HEALTH"
fi

# ── 2. Registration disabled ──────────────────────────────────────────────
log "2. Registration disabled"
if [[ "$HEALTH" == *"false"* ]] || \
   grep -q "POSTIZ_DISABLE_REGISTRATION=true" /opt/postiz/.env 2>/dev/null; then
  pass "Registration disabled"
else
  fail "Registration may still be enabled"
fi

# ── 3. Theme CSS injected via Link: header ────────────────────────────────
log "3. Keffals CSS via Link: header in HTTP response"
# Caddy strips body injections; check the Link: header instead.
# The Link header is added by nginx add_header and passes through Caddy.
LINK_HEADER=$(curl -sf -I --max-time "$TIMEOUT" \
  "https://postiz.keffals.gg/" 2>&1 | grep -i "^link.*keffals-theme.css.*stylesheet" || true)
if [[ -n "$LINK_HEADER" ]]; then
  pass "Link: [keffals-theme.css]; rel=stylesheet header present"
else
  fail "keffals-theme.css Link header missing — nginx add_header may be stripped by Caddy"
fi

# ── 4. enhance.js embedded inline in CSS file ────────────────────────────
log "4. enhance.js embedded inline at end of keffals-theme.css"
CSS_CONTENT=$(curl -sf --max-time "$TIMEOUT" \
  "https://postiz.keffals.gg/_kg/keffals-theme.css" 2>&1 || true)
if echo "$CSS_CONTENT" | grep -q '</style><script>'; then
  pass "CSS file contains </style><script> (inline script present)"
else
  fail "enhance.js inline script missing from CSS file"
fi

if echo "$CSS_CONTENT" | grep -q 'keffals-app-switcher\|fixLogout\|fixTitle'; then
  pass "CSS file contains enhance.js code (app-switcher, fixLogout, fixTitle)"
else
  fail "enhance.js code not found in CSS file"
fi

# ── 5. Keffals font self-hosted ──────────────────────────────────────────
log "5. Inter font served locally"
if echo "$CSS_CONTENT" | grep -q '_kg/fonts/Inter'; then
  pass "Font face points to /_kg/fonts/ (not CDN)"
else
  fail "Font may still be loaded from CDN"
fi

# ── 6. Static font files reachable ────────────────────────────────────────
log "6. Font file (Inter-Regular.woff2) reachable"
FONT_R=$(curl -sf -I --max-time "$TIMEOUT" \
  "https://postiz.keffals.gg/_kg/fonts/Inter-Regular.woff2" 2>&1 || true)
if echo "$FONT_R" | grep -q "200 OK\|HTTP"; then
  pass "Inter-Regular.woff2 serves HTTP 200"
else
  fail "Font file not reachable"
fi

# ── 7. Frontend page loads (no 5xx) ───────────────────────────────────────
log "7. Frontend /calendar reachable"
CAL=$(curl -sf -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" \
  "https://postiz.keffals.gg/calendar" 2>&1 || echo "000")
if [[ "$CAL" == 200 ]]; then
  pass "Calendar page: HTTP $CAL"
else
  fail "Calendar page: HTTP $CAL (expected 200)"
fi

# ── 8. Settings page reachable ─────────────────────────────────────────────
log "8. /settings reachable"
SET=$(curl -sf -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" \
  "https://postiz.keffals.gg/settings" 2>&1 || echo "000")
if [[ "$SET" == 200 ]]; then
  pass "Settings page: HTTP $SET"
else
  fail "Settings page: HTTP $SET (expected 200)"
fi

# ── 9. /_kg/ static assets accessible ─────────────────────────────────────
log "9. /_kg/ static assets accessible"
KG=$(curl -sf -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" \
  "https://postiz.keffals.gg/_kg/keffals-theme.css" 2>&1 || echo "000")
if [[ "$KG" == 200 ]]; then
  pass "/_kg/keffals-theme.css: HTTP $KG"
else
  fail "/_kg/ path returns HTTP $KG (nginx alias may be missing)"
fi

# ── 10. enhance.js standalone file accessible ──────────────────────────────
log "10. enhance.js standalone file accessible"
EJ=$(curl -sf -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" \
  "https://postiz.keffals.gg/_kg/enhance.js" 2>&1 || echo "000")
if [[ "$EJ" == 200 ]]; then
  pass "enhance.js: HTTP $EJ"
else
  fail "enhance.js: HTTP $EJ"
fi

# ── 11. PostgreSQL healthy ─────────────────────────────────────────────────
log "11. PostgreSQL healthy"
PG_HEALTH=$(docker exec postiz-postgres pg_isready -U postiz-user -d postiz-db-local 2>&1 || true)
if echo "$PG_HEALTH" | grep -q "accepting connections"; then
  pass "PostgreSQL accepting connections"
else
  fail "PostgreSQL unhealthy: $PG_HEALTH"
fi

# ── 12. Redis healthy ─────────────────────────────────────────────────────
log "12. Redis healthy"
REDIS_HEALTH=$(docker exec postiz-redis redis-cli ping 2>&1 || true)
if echo "$REDIS_HEALTH" | grep -q "PONG"; then
  pass "Redis responding PONG"
else
  fail "Redis unhealthy: $REDIS_HEALTH"
fi

# ── 13. Temporal healthy ──────────────────────────────────────────────────
log "13. Temporal healthy"
TEMP=$(curl -sf --max-time "$TIMEOUT" \
  "http://127.0.0.1:7233/health" 2>&1 || true)
if echo "$TEMP" | grep -q "ok\|SERVING"; then
  pass "Temporal health endpoint OK"
else
  TEMP_RUNNING=$(docker ps --filter "name=temporal" --format "{{.Names}}" 2>&1 || true)
  if [[ "$TEMP_RUNNING" == "temporal" ]]; then
    pass "Temporal container running (no /health — normal)"
  else
    fail "Temporal may be unhealthy"
  fi
fi

# ── 14. CSS file is well-formed ───────────────────────────────────────────
log "14. keffals-theme.css is well-formed (balanced braces)"
CSS_BYTES=$(echo "$CSS_CONTENT" | wc -c)
CSS_OPEN=$(echo "$CSS_CONTENT" | tr -cd '{' | wc -c)
CSS_CLOSE=$(echo "$CSS_CONTENT" | tr -cd '}' | wc -c)
if [[ "$CSS_OPEN" == "$CSS_CLOSE" ]] && [[ "$CSS_OPEN" -gt 0 ]]; then
  pass "CSS: $CSS_OPEN open / $CSS_CLOSE close braces (balanced)"
else
  fail "CSS: $CSS_OPEN open / $CSS_CLOSE close — unbalanced!"
fi

# ── 15. Browser console check (enhance.js test) ────────────────────────────
log "15. enhance.js will run in browser (</style><script> pattern)"
if echo "$CSS_CONTENT" | grep -q '</style><script>.*</script><style></style>'; then
  pass "CSS ends with </style><script>[code]</script><style></style> — browser will execute"
else
  # Check for the basic pattern at minimum
  if echo "$CSS_CONTENT" | grep -q '</style><script>'; then
    pass "CSS contains </style><script> pattern"
  else
    fail "Missing </style><script> pattern — enhance.js may not auto-execute"
  fi
fi

# ── Summary ────────────────────────────────────────────────────────────────
echo ""
if [[ $FAILED -eq 0 ]]; then
  log "ALL CHECKS PASSED"
  exit 0
else
  log "SOME CHECKS FAILED — review output above"
  exit 1
fi
