#!/usr/bin/env bash
#
# zkapi-tor-cli.sh — stateful chat client for the Tor-routed zkapi daemon.
#
#   zkapi-tor-cli.sh make_single_request "What is the capital of France?"
#   zkapi-tor-cli.sh start_conversation "Hi, remember the word persimmon."
#   zkapi-tor-cli.sh ask "What word did I ask you to remember?"
#   zkapi-tor-cli.sh list_models
#   zkapi-tor-cli.sh set_model anthropic/claude-haiku-4.5
#
# State (server pid, active model, conversation history) lives under
# /tmp/zkapi-tor-cli.<uid>/ — the script itself is stateless between calls.
#
# Semantics:
#   * make_single_request and start_conversation always run against a FRESH
#     server: kill any running one, relaunch zkapi-serve-tor.sh (new throwaway
#     Tor client => new network identity), wait for the API, then ask.
#   * ask adds to the current conversation and does NOT restart anything.
#   * default model: openai/gpt-6-astra-pro (change with set_model).
set -uo pipefail

here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# Repo-local .config/zkapi-clientd wins if present (portable wallet backup);
# otherwise the standard user config directory is used, matching the daemon.
if [ -f "$here/.config/zkapi-clientd/config.json" ]; then export XDG_CONFIG_HOME="$here/.config"; fi
SERVE="$here/zkapi-serve-tor.sh"
API="http://127.0.0.1:8787/v1"
STATE_DIR="/tmp/zkapi-tor-cli.$(id -u)"
PID_FILE="$STATE_DIR/server.pid"
MODEL_FILE="$STATE_DIR/model"
CONV_FILE="$STATE_DIR/conv.json"
DEFAULT_MODEL="openai/gpt-6-astra-pro"
READY_TIMEOUT="${ZKAPI_TORCLI_READY_TIMEOUT:-240}"
# Give the launcher's bootstrap a strictly smaller budget than our own wait,
# so a slow bootstrap either completes inside our window or the launcher dies
# first and we report its log — never a simultaneous give-up.
export TOR_ISOLATE_TIMEOUT="${TOR_ISOLATE_TIMEOUT:-$((READY_TIMEOUT - 30))}"
SETTLE_TIMEOUT="${ZKAPI_TORCLI_SETTLE_TIMEOUT:-180}"
CONFIG_DIR="${ZKAPI_CLIENTD_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/zkapi-clientd}"
COMPANION="http://127.0.0.1:8790"

mkdir -p "$STATE_DIR" || exit 1

die() { echo "zkapi-tor-cli: $*" >&2; exit 1; }

api_up() { curl -sf -m 25 "$API/models" -o /dev/null 2>/dev/null; }

server_running() {
  [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null && api_up
}

stop_server() {
  [ -f "$PID_FILE" ] || return 0
  local pid elapsed=0
  pid="$(cat "$PID_FILE")"
  kill -TERM "$pid" 2>/dev/null || true
  while kill -0 "$pid" 2>/dev/null && [ "$elapsed" -lt 15 ]; do sleep 0.5; elapsed=$((elapsed + 1)); done
  kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null
  rm -f "$PID_FILE"
}

start_server() {
  [ -x "$SERVE" ] || die "launcher not found at $SERVE"
  stop_server   # clear any orphan holding the loopback port before launching
  : > "$STATE_DIR/server.log"
  nohup "$SERVE" > "$STATE_DIR/server.log" 2>&1 &
  echo $! > "$PID_FILE"
  local elapsed=0 offset=0 size
  until api_up; do
    # propagate the launcher's bootstrap progress (tor's Bootstrapped %, the
    # serve script's "still bootstrapping" beeps) to the terminal, like the
    # policy/settlement waits do; full log stays in server.log
    size="$(stat -c %s "$STATE_DIR/server.log" 2>/dev/null || echo 0)"
    if [ "$size" -gt "$offset" ]; then
      tail -c "+$((offset + 1))" "$STATE_DIR/server.log" | grep -iE "bootstrap" >&2
      offset="$size"
    fi
    kill -0 "$(cat "$PID_FILE")" 2>/dev/null || { sed -n '1,20p' "$STATE_DIR/server.log" >&2; die "server exited during startup (log: $STATE_DIR/server.log)"; }
    [ "$elapsed" -ge "$READY_TIMEOUT" ] && die "API not ready after ${READY_TIMEOUT}s (log: $STATE_DIR/server.log)"
    sleep 1; elapsed=$((elapsed + 1))
  done
}

active_model() {
  if [ -s "$MODEL_FILE" ]; then cat "$MODEL_FILE"; return; fi
  # No explicit set_model yet: adopt the cheapest live model once and persist
  # it, so the default can never rot into a retired model ID.
  local pick
  pick="$(curl -sf -m 40 "$API/models" 2>/dev/null | python3 -c '
import json,sys
try: ids=[m["id"] for m in json.load(sys.stdin)["data"]]
except Exception: ids=[]
print(ids[0] if ids else "")' 2>/dev/null)"
  if [ -n "$pick" ]; then
    printf '%s\n' "$pick" > "$MODEL_FILE"
    echo "no model chosen yet; defaulting to the cheapest live model: $pick (change with set_model)" >&2
    printf '%s\n' "$pick"
  else
    printf '%s\n' "$DEFAULT_MODEL"   # offline fallback only
  fi
}

# wallet_state — prints "pending", "ready", or "unreachable" by asking the
# wallet companion directly (0-spend check, same bridge token the daemon uses).
wallet_state() {
  local token json
  token="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["zkapi"]["bridge_token"])' "$CONFIG_DIR/config.json" 2>/dev/null)" || { echo unreachable; return; }
  json="$(curl -sf -m 5 -H "Authorization: Bearer $token" "$COMPANION/wallet/status" 2>/dev/null)" || { echo unreachable; return; }
  printf '%s' "$json" | python3 -c 'import json,sys; print("pending" if json.load(sys.stdin).get("pending_request") else "ready")' 2>/dev/null || echo unreachable
}

# ensure_ready — if a previous lease is mid-settlement (the 60-90s window),
# sleep-and-ping until the wallet accepts new leases. After a few idle rounds,
# nudge retirement once via /wallet/settle, then keep polling.
ensure_ready() {
  local token elapsed=0 nudged=0 state
  while :; do
    state="$(wallet_state)"
    [ "$state" = ready ] && return 0
    if [ "$elapsed" -ge "$SETTLE_TIMEOUT" ]; then
      die "wallet not ready (${state}) after ${SETTLE_TIMEOUT}s; check server log and zkapi-diag.sh output"
    fi
    if [ "$state" = pending ] && [ "$nudged" -eq 0 ] && [ "$elapsed" -ge 30 ]; then
      token="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["zkapi"]["bridge_token"])' "$CONFIG_DIR/config.json" 2>/dev/null)"
      curl -sf -m 30 -X POST -H "Authorization: Bearer $token" "$COMPANION/wallet/settle" -o /dev/null 2>/dev/null && nudged=1
    fi
    echo "waiting for previous request to settle (${elapsed}s, state: $state)..." >&2
    sleep 5; elapsed=$((elapsed + 5))
  done
}

# py_chat <fresh|append> <text> — posts to the local API, keeps history in
# CONV_FILE, prints the assistant reply. Exit 2 = no stored conversation.
py_chat() {
  local mode="$1" text="$2"
  CONV_FILE="$CONV_FILE" python3 - "$mode" "$(active_model)" "$text" <<'PY'
import json, os, sys, urllib.error, urllib.request
mode, model, text = sys.argv[1:4]
conv = os.environ["CONV_FILE"]
if mode == "fresh":
    msgs = []
else:
    try:
        msgs = json.load(open(conv))
    except Exception:
        sys.exit(2)
msgs.append({"role": "user", "content": text})
req = urllib.request.Request(
    "http://127.0.0.1:8787/v1/chat/completions",
    data=json.dumps({"model": model, "messages": msgs}).encode(),
    headers={"content-type": "application/json"},
)
try:
    with urllib.request.urlopen(req, timeout=300) as resp:
        body = json.load(resp)
except urllib.error.HTTPError as err:
    sys.stderr.write(err.read().decode("utf-8", "replace").strip() + "\n")
    sys.exit(3)
except Exception as err:
    sys.stderr.write("request failed: %s\n" % err)
    sys.exit(4)
try:
    content = body["choices"][0]["message"]["content"]
except Exception:
    sys.stderr.write(json.dumps(body)[:400] + "\n")
    sys.exit(5)
msgs.append({"role": "assistant", "content": content})
json.dump(msgs, open(conv, "w"))
print(content)
PY
}

# warm_policy — block until the daemon can serve a non-empty model list.
# The reviewed-policy fetch lives in the DAEMON (issuer /chat/model-tickets +
# /chat/pinned-models over the anonymous transport), and GET /v1/models both
# reports it and triggers a fresh fetch on every call — so polling it IS the
# retry. The companion's /oa/v1/status is static deployment metadata and never
# carries the policy.
warm_policy() {
  local n elapsed=0
  while :; do
    n="$(curl -sf -m 40 "$API/models" 2>/dev/null | python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("data") or []))' 2>/dev/null)"
    [ "${n:-0}" -gt 0 ] 2>/dev/null && return 0
    [ "$elapsed" -ge "${ZKAPI_TORCLI_WARM_TIMEOUT:-180}" ] && return 1
    echo "waiting for the reviewed-model policy to load (${elapsed}s)..." >&2
    sleep 5; elapsed=$((elapsed + 5))
  done
}

# run_chat <fresh|append> <text> — py_chat plus one automatic recovery from
# the cold-policy race: warm the policy cache and retry the identical request.
# History is only persisted on success, so the retry never double-appends.
run_chat() {
  local mode="$1" text="$2" errf out rc
  errf="$(mktemp)"
  if out="$(py_chat "$mode" "$text" 2>"$errf")"; then
    printf '%s\n' "$out"; rm -f "$errf"; return 0
  fi
  rc=$?
  if [ "$rc" -eq 2 ]; then
    rm -f "$errf"; die "no active conversation (or its history was lost); use start_conversation"
  fi
  if [ "$rc" -eq 3 ] && grep -q model_budget_unavailable "$errf"; then
    echo "model policy was cold; warming and retrying once..." >&2
    if warm_policy; then
      if out="$(py_chat "$mode" "$text" 2>"$errf")"; then
        printf '%s\n' "$out"; rm -f "$errf"; return 0
      fi
      rc=$?
    fi
  fi
  cat "$errf" >&2
  if grep -q model_budget_unavailable "$errf"; then
    echo "available models:" >&2
    curl -sf -m 40 "$API/models" 2>/dev/null | python3 -c 'import json,sys
try:
  for m in json.load(sys.stdin)["data"]: print("  " + m["id"])
except Exception: pass' >&2
    echo "(choose one with: $0 set_model <id>)" >&2
  fi
  rm -f "$errf"; return "$rc"
}

usage() {
  sed -n '3,20p' "${BASH_SOURCE[0]}" | grep '^#' | cut -c3-
}

case "${1:-}" in
  make_single_request)
    [ $# -ge 2 ] || die "usage: $0 make_single_request \"question\""
    stop_server; start_server; ensure_ready; warm_policy || true
    run_chat fresh "$2"
    ;;
  start_conversation)
    [ $# -ge 2 ] || die "usage: $0 start_conversation \"first message\""
    stop_server; start_server; ensure_ready; warm_policy || true
    run_chat fresh "$2"
    ;;
  ask)
    [ $# -ge 2 ] || die "usage: $0 ask \"follow-up\""
    server_running || die "no conversation server is running; use start_conversation"
    ensure_ready; warm_policy || true
    run_chat append "$2"
    ;;
  list_models)
    server_running || start_server
    curl -sf -m 15 "$API/models" | python3 -c 'import json,sys
for m in json.load(sys.stdin)["data"]: print(m["id"])'
    ;;
  set_model)
    [ $# -ge 2 ] || { echo "current model: $(active_model)"; exit 0; }
    printf '%s\n' "$2" > "$MODEL_FILE"
    echo "model set: $2"
    ;;
  *)
    usage; exit 2
    ;;
esac
