#!/usr/bin/env bash
# Print a fresh pairing code for the agentring Android app.
#
#   ./pair.sh          -> the code to paste in the app (Pair -> Paste code)
#   ./pair.sh --qr     -> also print the QR code to scan
#
# Pairing tokens are single use and expire after 10 minutes: run this again if it expired.
set -euo pipefail

cd /home/boxd/agentring/deploy
API=$(docker compose -f docker-compose.boxd.yml --env-file .env.boxd exec -T relay cat /data/api_key)

resp=$(curl -s -m 20 -X POST https://relay.good-cliff.boxd.sh/v1/pairing-tokens \
       -H "Authorization: Bearer $API" -H 'Content-Type: application/json' -d '{}')

code=$(printf '%s' "$resp" | jq -r .pairing_token)
relay=$(printf '%s' "$resp" | jq -r .qr_payload | jq -r .relay_url)

cat <<EOF

  agentring pairing code (valid 10 minutes, single use)

  $code

  On the phone:  agentring app -> Pair -> Paste code
  Relay:         $relay

EOF

if [ "${1:-}" = "--qr" ]; then
  agentring pair
fi
