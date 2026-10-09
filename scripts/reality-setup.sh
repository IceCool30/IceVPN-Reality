#!/usr/bin/env bash
#
# reality-setup.sh - Generate the keys and print the exact VLESS+REALITY settings.
#
# REALITY needs three random values you cannot just make up:
#   - a private key (x25519) and its public key
#   - a shortId (a short hex tag per client, optional but recommended)
#   - a UUID per client
#
# You also pick a "target" (dest): a real, foreign website that supports TLS 1.3
# and HTTP/2 and does NOT redirect. REALITY borrows that site's TLS handshake as
# camouflage. Good picks: www.samsung.com, swcdn.apple.com, www.microsoft.com,
# cdn.jsdelivr.net, www.nvidia.com. Pick one that is NOT blocked in the country
# your server is in, and NOT hosted by the same company as your VPS.
#
# This script prints everything you paste into the 3x-ui panel when you create the
# VLESS inbound. It does NOT touch the panel. Run it, copy the output into the UI.
#
# USAGE
#   bash reality-setup.sh
#   TARGET=www.samsung.com bash reality-setup.sh

set -euo pipefail

TARGET="${TARGET:-www.samsung.com}"
SNI="${SNI:-$TARGET}"

log()  { printf '\033[1;36m%s\033[0m\n' "$*"; }
need() { command -v "$1" >/dev/null || true; }

# Prefer xray's own keygen if present, else openssl, else python.
gen_x25519() {
  if command -v xray >/dev/null 2>&1; then
    xray x25519
  elif command -v openssl >/dev/null 2>&1; then
    # openssl genpkey X25519 gives a private key; extract raw base64url-ish.
    openssl genpkey -algorithm X25519 2>/dev/null | openssl pkey -text -noout 2>/dev/null || true
    printf '\n(openssl path may not print raw keys; use xray x25519 for the real pair)\n' >&2
  else
    printf '\nInstall xray-core and run: xray x25519\n' >&2
  fi
}

gen_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then uuidgen | tr 'A-Z' 'a-z'
  elif [ -r /proc/sys/kernel/random/uuid ]; then cat /proc/sys/kernel/random/uuid
  else python3 -c 'import uuid;print(uuid.uuid4())'; fi
}

gen_shortid() {
  # 8 hex chars, even length, per REALITY rules (max 16).
  if [ -r /dev/urandom ]; then head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n'
  else python3 -c 'import os;print(os.urandom(4).hex())'; fi
}

cat <<EOF

$(printf '\033[1;32m')
============================================================
 VLESS + REALITY inbound settings
============================================================$(printf '\033[0m')

Target (dest) to borrow TLS from: ${TARGET}
SNI / serverNames:               ${SNI}

Step 1. Generate the key pair. Run this on the SERVER (after 3x-ui is installed)
        so xray is available:

            xray x25519

        It prints a Private key and a Password (public key). Copy BOTH.

        If xray is not on PATH, it is at /usr/local/x-ui/bin/xray
        (run: /usr/local/x-ui/bin/xray x25519)

$(printf '\033[1;33m')
--- paste these into the 3x-ui "Add Inbound" form ---$(printf '\033[0m')

  Protocol:        vless
  Port:            443
  Transport:       tcp
  Security:        reality

  reality settings:
    dest / target: ${TARGET}:443
    serverNames:   ${SNI}
    Private key:   <from: xray x25519>
    Password:      <the PUBLIC key from xray x25519>
    shortIds:      $(gen_shortid)
    spiderX:       /
    Fingerprint:   chrome
    Flow:          xtls-rprx-vision
    xver:          0

Step 2. Create the inbound, note its id (usually 1).

Step 3. Add users. Either in the panel, or with tier-manager.sh:
    export ICEVPN_PANEL='http://IP:PANELPORT/PATH'
    export ICEVPN_TOKEN='your-token'
    export ICEVPN_INBOUND=1
    ./tier-manager.sh free alice
    ./tier-manager.sh paid bob

EOF

# Also print one ready client UUID + shortId for reference.
log "A ready client UUID (for manual entry): $(gen_uuid)"
log "A ready shortId (for manual entry):      $(gen_shortid)"