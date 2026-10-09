#!/usr/bin/env bash
#
# test-connection.sh - Verify the server is reachable and check for leaks.
# Runs on Linux/macOS. On Windows use Git Bash or WSL.
#
# It checks: your current public IP, that the VLESS/REALITY port answers, and
# that the borrowed target site actually supports TLS 1.3 + H2 (REALITY needs it).

set -uo pipefail

VLESS_PORT="${VLESS_PORT:-443}"
TARGET="${TARGET:-www.samsung.com}"
SERVER_IP="${1:-}"

log()  { printf '\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[warn] %s\033[0m\n' "$*"; }

log "Your current public IP (changes once the VPN is on):"
curl -sS https://ipinfo.io/json 2>/dev/null | jq -r '"\(.ip)  \(.city), \(.country)  (\(.org))"' 2>/dev/null \
  || warn "Could not reach ipinfo.io"

if [ -n "$SERVER_IP" ]; then
  log "Is the VLESS/REALITY port ${VLESS_PORT} open on ${SERVER_IP}?"
  if timeout 5 bash -c "echo > /dev/tcp/${SERVER_IP}/${VLESS_PORT}" 2>/dev/null; then
    echo "  OK, port ${VLESS_PORT} is reachable."
  else
    warn "Port ${VLESS_PORT} not reachable. Check the cloud firewall (Layer 2) and that Xray is running."
  fi

  log "Does the borrowed target ${TARGET} speak TLS 1.3 + H2? (REALITY requires it)"
  if command -v openssl >/dev/null 2>&1; then
    echo | timeout 8 openssl s_client -connect "${TARGET}:443" -tls1_3 -alpn h2 2>/dev/null \
      | grep -qE 'ALPN protocol: h2' \
      && echo "  OK, ${TARGET} supports TLS 1.3 and h2. Good REALITY target." \
      || warn "${TARGET} may NOT support TLS1.3+h2. Pick a different target (see reality-setup.sh)."
  else
    echo "  (openssl not available, skipping target check)"
  fi
fi

cat <<EOF

Manual checks after a client connects:
  1. Reload https://ipinfo.io  -> IP must be your VPS IP.
  2. https://dnsleaktest.com -> Extended test -> your ISP name should be gone.
  3. https://browserleaks.com/webrtc -> your real IP must not show.
  4. https://www.cloudflare.com/cdn-cgi/trace -> check the 'loc' field changed.

Remember the honest ceiling: REALITY defeats protocol/DPI detection (a censor
cannot easily tell it is a proxy). It does NOT change the fact that your exit IP
is a datacenter IP, so IP-reputation blocks (Netflix, some banks) can still flag
it. See docs/what-this-beats.md.

EOF