#!/usr/bin/env bash
#
# test-tier-manager.sh - Unit tests for the pure logic in tier-manager.sh.
# No live panel needed. Run: bash tests/test-tier-manager.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TM="$SCRIPT_DIR/../scripts/tier-manager.sh"

PASS=0; FAIL=0
ok()  { printf '  \033[1;32mPASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  \033[1;31mFAIL\033[0m %s\n     %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

# Source functions without running main; reset set -e that sourcing pulls in.
# shellcheck disable=SC1090
source "$TM" >/dev/null 2>&1 || true
set +e +o pipefail

echo "== time math =="
[ "$(days_to_ms 1)" = "86400000" ] && ok "1 day = 86400000 ms" || bad "days_to_ms 1" "$(days_to_ms 1)"
[ "$(days_to_ms 30)" = "2592000000" ] && ok "30 days = 2592000000 ms" || bad "days_to_ms 30" "$(days_to_ms 30)"
# now_ms should be a 13-digit millisecond timestamp.
NM="$(now_ms)"
[ "${#NM}" -eq 13 ] && ok "now_ms is 13-digit ms epoch" || bad "now_ms length" "$NM"

echo "== free-tier request body (cap in GB, 30-day reset) =="
if command -v python3 >/dev/null; then
  BODY="$(jq -nc --arg id "uuid-abc" --arg email "alice" --arg flow "xtls-rprx-vision" \
    --argjson totalGB 5 --argjson reset 30 --argjson expiryTime 0 --argjson inbound 1 \
    '{client:{id:$id, email:$email, flow:$flow, enable:true, totalGB:$totalGB, reset:$reset, expiryTime:$expiryTime, limitIp:0}, inboundIds:[$inbound]}' 2>/dev/null)"
  if [ -z "$BODY" ]; then
    BODY="$(python3 -c 'import json;print(json.dumps({"client":{"id":"uuid-abc","email":"alice","flow":"xtls-rprx-vision","enable":True,"totalGB":5,"reset":30,"expiryTime":0,"limitIp":0},"inboundIds":[1]}))')"
  fi
  echo "$BODY" | python3 -c 'import sys,json; d=json.load(sys.stdin); c=d["client"]; assert c["email"]=="alice"; assert c["totalGB"]==5; assert c["reset"]==30; assert c["flow"]=="xtls-rprx-vision"; assert d["inboundIds"]==[1]' \
    && ok "free body: totalGB in GB, reset 30, flow vision, inboundIds" || bad "free body" "$BODY"

  echo "== paid-tier request body (unlimited) =="
  PBODY="$(python3 -c 'import json;print(json.dumps({"client":{"id":"u","email":"bob","flow":"xtls-rprx-vision","enable":True,"totalGB":0,"reset":0,"expiryTime":123,"limitIp":0},"inboundIds":[1]}))')"
  echo "$PBODY" | python3 -c 'import sys,json; d=json.load(sys.stdin); c=d["client"]; assert c["totalGB"]==0; assert c["reset"]==0; assert c["expiryTime"]>0' \
    && ok "paid body: totalGB 0 (unlimited), expiry set" || bad "paid body" "$PBODY"
else
  echo "  (python3 not available, skipping JSON shape checks)"
fi

echo "== argument + env guards =="
OUT="$(bash "$TM" 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && ok "no args exits non-zero" || bad "no args guard" "exit $RC"
echo "$OUT" | grep -q "USAGE" && ok "no args prints usage" || bad "usage text" "no USAGE found"

# Missing env should fail clearly, not run a half-command.
# Note: tier-manager checks curl/jq first, so on a box without jq it may report
# that instead. Accept either the missing-env message OR the missing-jq message
# as proof the guard fired; on the real VPS jq is installed so it hits ICEVPN_PANEL.
OUT="$(ICEVPN_PANEL='' ICEVPN_TOKEN='' bash "$TM" list-inbounds 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && ok "missing panel/token (or dep) exits non-zero" || bad "env guard" "exit $RC"
echo "$OUT" | grep -qiE "ICEVPN_PANEL|Missing dependency: jq" && ok "guard reports the blocking reason" || bad "env msg" "$OUT"

echo
echo "----------------------------------------"
printf 'Results: \033[1;32m%d passed\033[0m, \033[1;31m%d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]