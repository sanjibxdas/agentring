# agentring on a boxd VM

The relay, LiveKit and the daemon all running on one boxd VM, reachable from
the internet through the boxd proxy. No VPS with open UDP is needed.

The three pieces and where they live:

| Piece | Where | What it does |
|---|---|---|
| relay | `relay.good-cliff.boxd.sh` (a named boxd proxy → Caddy → `relay:8080`) | pairing, messages, call state, push |
| LiveKit | `wss://relay.good-cliff.boxd.sh/rtc` (Caddy → `livekit:7880`) | the call audio |
| daemon | systemd unit `agentring.service` | the `agentring` CLI, the MCP server and the voice AI |

The daemon is what your agent talks to. It only makes outbound connections, so
NAT is not a problem for it.

## Why the ports look odd

A boxd VM is NAT'd: its own public IP refuses every inbound port, and the boxd
edge forwards a handful of ports to random public port numbers. LiveKit
advertises `node_ip:tcp_port` in its ICE candidates, and that port has to be the
one the edge really listens on — so the chain is:

```
phone ──▶ edge 152.236.3.40:52465   (the public port boxd assigned)
      ──▶ VM host:7881               (socat: agentring-livekit-forward.service)
      ──▶ VM host:52465              (docker publishes it)
      ──▶ livekit container:52465    (rtc.tcp_port in livekit.boxd.yaml)
```

UDP is not reachable through boxd, so calls use the ICE-TCP candidate: they
connect more slowly than over UDP but they work. On an ordinary VPS with
`UDP 50000-50100` and `TCP 7881` open, use the upstream `deploy/docker-compose.yml`
instead — it is simpler and faster.

## Setup

```bash
cd deploy
cp .env.boxd.example .env.boxd      # set AGENTRING_DOMAIN and LIVEKIT_NODE_IP
$EDITOR .env.boxd

# the named proxy: a named proxy is never challenged by boxd's bot protection,
# which an agent's own HTTP calls would otherwise trip
boxd machine proxy new relay --port=8000

# LiveKit's TCP port, and the public port boxd assigns it
boxd machine expose 7881 --tcp
#   -> good-cliff.boxd.sh:52465 -> 7881
# put that public port in livekit.boxd.yaml as rtc.tcp_port and node_ip

# the Firebase files, so a locked phone rings (docs/firebase.md)
cp google-services.json secrets/
cp agentring-*-firebase-adminsdk-*.json secrets/firebase-service-account.json
chmod 600 secrets/*.json
# then uncomment the two FCM_ lines in .env.boxd

./setup.sh up
```

`setup.sh check` shows what is running and what is still missing.

## The daemon

```bash
uv tool install './daemon[voice]'
agentring init --relay https://relay.good-cliff.boxd.sh --api-key ak_...
```

The API key is printed by the relay on first start, or read it back with:

```bash
docker compose -f docker-compose.boxd.yml --env-file .env.boxd exec -T relay cat /data/api_key
```

The daemon runs as a systemd unit (`agentring.service`, `agentring serve --ai`),
so the agent stays online and the phone can call it back.

## The voice provider

`~/.agentring/.env` (mode 600):

```
DEEPGRAM_API_KEY=your-deepgram-key
AGENTRING_VOICE_PROVIDER=deepgram
```

`DEEPGRAM_THINK_MODEL` and `DEEPGRAM_THINK_PROVIDER` override the LLM stage.
The default is `gpt-5.4-mini` on Deepgram's managed OpenAI: `gpt-4o-mini` is
the one model that does not call the tools reliably — it answers from the tool's
description instead of calling it.

See `deploy/daemon.env.example`.

## Pairing the phone

```bash
./pair.sh          # a paste code
./pair.sh --qr     # and the QR code
```

Pairing tokens are single use and expire after 10 minutes. The app learns the
Firebase settings when it pairs, so pair it *after* the Firebase files are in
place.

## Ring window

The relay's default ring window is 30 s, which is too short for a phone that
takes ~25 s to wake up. `AGENTRING_RING_TIMEOUT_S` (default 180 in
`docker-compose.boxd.yml`) sets it.

## Notes

* The Firebase service-account JSON can send pushes to your devices: treat it
  as a password.
* Push payloads are signed, not encrypted, so Google can read the message text.
* Call audio is not end to end encrypted: the LiveKit server you run can access
  it.
* With the voice AI, everything said on an AI call goes to the voice provider.
  On Deepgram's free tier, Deepgram may use that data to improve its products.
