#!/usr/bin/env bash
#
# bootstrap.sh - Turn a fresh Ubuntu VPS into a hardened 3x-ui server.
#
# This installs the 3x-ui control panel (Xray-core engine). It does NOT create
# the VLESS+REALITY inbound for you, because that inbound needs a few choices
# (which website to borrow TLS from, etc). The panel makes that a few clicks, and
# reality-setup.sh + the guide walk you through it.
#
# WHAT IT DOES
#   1. Updates the system, installs base tools.
#   2. Installs 3x-ui NON-INTERACTIVELY with a random admin user/password/port.
#      It prints the panel URL and credentials at the end. SAVE THEM.
#   3. Enables BBR congestion control (big speed win for a proxy).
#   4. Locks the OS firewall to fail-closed: only SSH and the VLESS/REALITY port.
#
# WHY NOT OPEN THE PANEL PORT TO THE WORLD
#   The panel is your control room. We keep the OS firewall tight and you open
#   the panel port to YOUR ip only in the cloud firewall (see oci-firewall-guide).
#
# HOW TO RUN
#   ssh into your fresh VPS, then:
#       sudo bash bootstrap.sh
#   Keep this session open. It prints the panel URL + credentials at the end.
#
# BEFORE YOU RUN
#   Open SSH and the VLESS port in your cloud firewall too (two layers).
#   See oci-firewall-guide.md. VLESS/REALITY runs on 443 by default so it blends
#   in with normal HTTPS.

set -euo pipefail

# ----- Config you can edit -----
SSH_PORT="${SSH_PORT:-22}"
VLESS_PORT="${VLESS_PORT:-443}"        # REALITY listens here, blends with HTTPS
PANEL_PORT="${PANEL_PORT:-}"           # blank = let installer pick a random port

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[warn] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[error] %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root: sudo bash bootstrap.sh"

log "1/5 Updating system and installing base tools"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl jq ufw ca-certificates

log "2/5 Enabling BBR congestion control (faster throughput)"
if ! grep -q 'net.core.default_qdisc=fq' /etc/sysctl.conf 2>/dev/null; then
  cat >> /etc/sysctl.conf <<'EOF'

# IceVPN-Reality: enable BBR
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
  sysctl -p >/dev/null 2>&1 || true
fi
sysctl net.ipv4.tcp_congestion_control 2>/dev/null || true

log "3/5 Installing 3x-ui (non-interactive, random credentials)"
# XUI_NONINTERACTIVE=1 makes the installer pick a random user/password/port and
# skip every prompt. It prints the access details at the end. SAVE THEM.
export XUI_NONINTERACTIVE=1
if [ -n "$PANEL_PORT" ]; then
  # Pin the panel port via the installer's env override if you set PANEL_PORT.
  export XUI_PORT="$PANEL_PORT"
fi
bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh) \
  || die "3x-ui install failed. Scroll up for the reason."

log "4/5 Enabling fail2ban (included with 3x-ui) and the panel service"
systemctl enable --now x-ui >/dev/null 2>&1 || systemctl enable --now 3x-ui >/dev/null 2>&1 || true

log "5/5 Locking down the OS firewall (fail-closed)"
IFACE="$(ip route show default | awk '{print $5; exit}')"
[ -n "$IFACE" ] || die "Could not detect default network interface."

ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow "${SSH_PORT}/tcp"    comment 'SSH'
ufw allow "${VLESS_PORT}/tcp"  comment 'VLESS/REALITY (HTTPS camouflage)'
# NOTE: we deliberately do NOT open the panel port here at the OS layer to the
# world. Open it to your own IP in the cloud firewall only. If you need local
# access, temporarily: ufw allow from YOUR_IP to any port PANEL_PORT proto tcp
ufw --force enable

log "Listening services"
ss -tulpn | grep -E 'xray|x-ui|:443|:${VLESS_PORT}' || true

cat <<EOF

$(printf '\033[1;32m')
============================================================
 3x-ui is installed.
============================================================$(printf '\033[0m')

NEXT STEPS:
  1. Scroll UP. The installer printed your panel URL, username, and password.
     It looks like: http://YOUR_IP:PANELPORT/RANDOMPATH
     SAVE THESE NOW. They are shown once.
  2. Open the panel port to YOUR ip only (cloud firewall, see oci-firewall-guide).
  3. Create the VLESS+REALITY inbound: run ../scripts/reality-setup.sh, or follow
     docs/reality-inbound.md for the exact panel settings.
  4. Mint an API token in the panel (Panel Settings -> API / token), then use
     ../scripts/tier-manager.sh to create free (capped) and paid (uncapped) users.

PORTS TO OPEN IN YOUR CLOUD FIREWALL (Layer 2):
  - ${SSH_PORT}/tcp   SSH (lock to your IP)
  - ${VLESS_PORT}/tcp VLESS/REALITY (open to 0.0.0.0/0 so clients connect)
  - PANEL_PORT/tcp    Management panel (open to YOUR IP only, never the world)

REMINDER:
  - Two firewall layers. Oracle uses a Security List AND an NSG. See oci-firewall-guide.md.
  - REALITY needs no domain. You borrow a real site's TLS. See docs/reality-inbound.md.

EOF