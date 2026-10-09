#!/usr/bin/env bash
#
# tier-manager.sh - Drive the 3x-ui API to run a free + paid tier.
#
# VERIFIED AGAINST 3x-ui v3 source (internal/web/controller/client.go, api.go,
# middleware/security.go, database/model/model.go):
#   - Base path:        /panel/api
#   - Auth:             Authorization: Bearer <API_TOKEN>  (this bypasses CSRF,
#                       which only guards browser sessions, not token callers)
#   - Add client:       POST /panel/api/clients/add
#                         body: {"client": {...}, "inboundIds": [<id>]}
#   - List inbounds:    GET  /panel/api/inbounds/list
#   - List clients:     GET  /panel/api/clients/list
#   - Delete client:    POST /panel/api/clients/del/:email
#   - Update client:    POST /panel/api/clients/update/:email
#
# CLIENT FIELDS (from model.Client, json tags confirmed in source):
#   id         string  UUID, the VLESS client id (uuidgen)
#   email      string  unique per user, the handle you manage by
#   flow       string  "xtls-rprx-vision" (must match the inbound)
#   enable     bool
#   totalGB    int64   TRAFFIC LIMIT IN GB (not bytes). 0 = unlimited.
#   expiryTime int64   ms since epoch. 0 = never.
#   reset      int     RESET PERIOD IN DAYS. 0 = no reset. 30 = monthly refill.
#   limitIp    int     max concurrent IPs. 0 = unlimited.
#
# USAGE
#   export ICEVPN_PANEL='http://YOUR_IP:PANELPORT/RANDOMPATH'
#   export ICEVPN_TOKEN='your-api-token'
#   export ICEVPN_INBOUND=1            # the VLESS inbound id (see list-inbounds)
#
#   ./tier-manager.sh list-inbounds
#   ./tier-manager.sh list-clients
#   ./tier-manager.sh free   <email>          # FREE_TIER_GB cap, monthly reset
#   ./tier-manager.sh paid   <email>          # unlimited, expires each cycle
#   ./tier-manager.sh renew  <email>          # extend expiry / clear used traffic
#   ./tier-manager.sh delete <email>          # revoke
#
# The API token bypasses CSRF, so we do NOT log in or handle cookies.
# TLS: the panel is plain HTTP by default. Behind HTTPS, --insecure keeps it
# working with a self-signed cert.

set -euo pipefail

PANEL="${ICEVPN_PANEL:-}"
TOKEN="${ICEVPN_TOKEN:-}"
INBOUND="${ICEVPN_INBOUND:-1}"
FREE_TIER_GB="${FREE_TIER_GB:-5}"
PAID_EXPIRY_DAYS="${PAID_EXPIRY_DAYS:-30}"   # paid tier billing cycle length

log()  { printf '\033[1;36m==> %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[error] %s\033[0m\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "Missing dependency: $1"; }

main() {
  local action="${1:-}"
  [ -n "$action" ] || { grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
  need curl
  need jq
  [ -n "$PANEL" ] || die "Set ICEVPN_PANEL (e.g. http://IP:PORT/PATH)"
  [ -n "$TOKEN" ] || die "Set ICEVPN_TOKEN (mint one in the panel)"
  case "$action" in
    list-inbounds) cmd_list_inbounds ;;
    list-clients)  cmd_list_clients ;;
    free)          cmd_free "${2:-}" ;;
    paid)          cmd_paid "${2:-}" ;;
    renew)         cmd_renew "${2:-}" ;;
    delete)        cmd_delete "${2:-}" ;;
    *) die "Unknown action: $action (list-inbounds, list-clients, free, paid, renew, delete)" ;;
  esac
}

# api <METHOD> <path> [json-body]  -> prints response body
api() {
  local method="$1" path="$2" body="${3:-}"
  if [ -n "$body" ]; then
    curl -sS --insecure -X "$method" \
      -H "Authorization: Bearer ${TOKEN}" \
      -H 'Content-Type: application/json' \
      -d "$body" "${PANEL}/panel/api${path}"
  else
    curl -sS --insecure -X "$method" \
      -H "Authorization: Bearer ${TOKEN}" \
      "${PANEL}/panel/api${path}"
  fi
}

gen_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then uuidgen | tr 'A-Z' 'a-z'
  elif [ -r /proc/sys/kernel/random/uuid ]; then cat /proc/sys/kernel/random/uuid
  else python3 -c 'import uuid;print(uuid.uuid4())'; fi
}

now_ms() { echo $(( $(date +%s) * 1000 )); }

cmd_list_inbounds() {
  log "Inbounds (find your VLESS inbound id here)"
  api GET /inbounds/list | jq -r '.obj[] | "\(.id)\t\(.protocol)\t\(.remark // "-")\tport=\(.port)"' \
    || die "Could not list inbounds. Check ICEVPN_PANEL, ICEVPN_TOKEN, ICEVPN_INBOUND."
}

cmd_list_clients() {
  log "Clients"
  api GET /clients/list | jq -r '.[] | "\(.email)\ttotalGB=\(.totalGB)\texpiry=\(.expiryTime)\tenable=\(.enable)"' \
    || die "Could not list clients."
}

# create_client <email> <totalGB> <reset_days> <expiry_days>
# totalGB 0 = unlimited. expiry_days 0 = never expires.
create_client() {
  local email="$1" total_gb="$2" reset_days="$3" expiry_days="$4"
  local uuid expiry_ms body resp
  uuid="$(gen_uuid)"
  expiry_ms=0
  [ "$expiry_days" != "0" ] && expiry_ms=$(( $(now_ms) + $(days_to_ms "$expiry_days") ))

  body="$(jq -nc \
    --arg id "$uuid" \
    --arg email "$email" \
    --arg flow "xtls-rprx-vision" \
    --argjson totalGB "$total_gb" \
    --argjson reset "$reset_days" \
    --argjson expiryTime "$expiry_ms" \
    --argjson inbound "$INBOUND" \
    '{client:{id:$id, email:$email, flow:$flow, enable:true, totalGB:$totalGB, reset:$reset, expiryTime:$expiryTime, limitIp:0}, inboundIds:[$inbound]}')"

  log "Creating $email (cap ${total_gb}GB, reset ${reset_days}d, expiry ${expiry_days}d)"
  resp="$(api POST /clients/add "$body")"
  if echo "$resp" | jq -e '.success' >/dev/null 2>&1; then
    cat <<EOF

  Created client: ${email}
  VLESS UUID:     ${uuid}

  The user gets their connection link from the panel (Clients -> ${email}), or via
  GET /panel/api/clients/links/${email}. Import it into their client app
  (v2rayNG on Android, streisand on iOS, v2rayN on Windows, V2Box/FoXray on Mac).

EOF
  else
    die "Create failed: $resp"
  fi
}

cmd_free() {
  local email="${1:-}"; [ -n "$email" ] || die "free needs an email/handle"
  # Free tier: capped, resets every 30 days, no hard expiry.
  create_client "$email" "$FREE_TIER_GB" 30 0
}

cmd_paid() {
  local email="${1:-}"; [ -n "$email" ] || die "paid needs an email/handle"
  # Paid tier: unlimited traffic, expires after the billing cycle (renew on payment).
  create_client "$email" 0 0 "$PAID_EXPIRY_DAYS"
}

# renew <email> - clear used traffic and push expiry out another cycle
cmd_renew() {
  local email="${1:-}"; [ -n "$email" ] || die "renew needs an email/handle"
  log "Renewing $email (resetting traffic, extending expiry ${PAID_EXPIRY_DAYS}d)"
  local expiry_ms body resp
  expiry_ms=$(( $(now_ms) + $(days_to_ms "$PAID_EXPIRY_DAYS") ))
  body="$(api GET /clients/list | jq -c --arg e "$email" --argjson exp "$expiry_ms" \
    'map(select(.email==$e)) | .[0] | .up=0 | .down=0 | .expiryTime=$exp | .enable=true')"
  [ -n "$body" ] && [ "$body" != "null" ] || die "Client $email not found"
  resp="$(api POST "/clients/update/${email}" "$body")"
  echo "$resp" | jq -e '.success' >/dev/null 2>&1 && echo "  OK, renewed" || die "Renew failed: $resp"
}

cmd_delete() {
  local email="${1:-}"; [ -n "$email" ] || die "delete needs an email/handle"
  log "Revoking $email"
  local resp; resp="$(api POST "/clients/del/${email}")"
  echo "$resp" | jq -e '.success' >/dev/null 2>&1 && echo "  OK, revoked" || die "Delete failed: $resp"
}

# Only run main when executed directly, so tests can source the functions.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
days_to_ms() { echo $(( $1 * 86400000 )); }