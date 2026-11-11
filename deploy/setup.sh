#!/usr/bin/env bash
# agentring on this boxd VM — bring the whole stack up (or check it).
#
#   ./setup.sh up      start relay + LiveKit + Caddy, the daemon service and the port forward
#   ./setup.sh check   show what is running and what is still missing
#   ./setup.sh down    stop the containers (the daemon service stays)
#
# What is where:
#   relay      https://relay.good-cliff.boxd.sh   (named boxd proxy -> Caddy -> relay:8080)
#   LiveKit    wss://relay.good-cliff.boxd.sh/rtc (Caddy -> livekit:7880)
#   media      edge 152.236.3.40:52465 -> VM:7881 -> socat -> VM:52465 -> livekit
#   daemon     systemd unit agentring.service (the `agentring` CLI + the MCP server)
#
# Still needed for the phone to ring while locked: a Firebase project (see below).
set -euo pipefail

REPO=/home/boxd/agentring
DEPLOY=$REPO/deploy
COMPOSE="docker compose -f $DEPLOY/docker-compose.boxd.yml --env-file $DEPLOY/.env.boxd"
PROXY=relay.good-cliff.boxd.sh
EDGE_IP=152.236.3.40

case "${1:-check}" in
up)
  cd "$DEPLOY"
  $COMPOSE up -d --build
  sudo systemctl restart agentring-livekit-forward agentring
  echo "agentring is up: https://$PROXY"
  ;;

check)
  echo "== containers =="
  $COMPOSE ps --format '  {{.Service}}\t{{.Status}}\t{{.Ports}}'
  echo
  echo "== services =="
  for s in agentring agentring-livekit-forward; do
    printf '  %-28s %s\n' "$s" "$(systemctl is-active $s)"
  done
  echo
  echo "== public endpoints =="
  printf '  relay healthz : %s\n' "$(curl -s -m 15 https://$PROXY/healthz || echo FAIL)"
  printf '  relay status  : %s\n' "$(curl -s -m 15 -o /dev/null -w '%{http_code}' https://$PROXY/v1/status) (401 = alive, needs the API key)"
  echo
  echo "== boxd port forward =="
  boxd machine expose --list | sed 's/^/  /'
  echo
  echo "== agent =="
  agentring status 2>&1 | sed 's/^/  /'
  ;;

down)
  cd "$DEPLOY"
  $COMPOSE down
  ;;

*)
  echo "usage: $0 {up|check|down}" >&2
  exit 1
  ;;
esac
