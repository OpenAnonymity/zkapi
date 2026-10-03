#!/usr/bin/env bash
#
# zkapi-serve-tor.sh — zkapi-native Tor for the zkAPI daemon.
#
#   * fresh throwaway Tor client (new DataDirectory => new guards, new exits)
#     on every daemon start
#   * while the daemon stays up, Tor's own 10-minute circuit rotation
#     (MaxCircuitDirtiness default) refreshes the exit path
#   * the daemon reaches Tor through its built-in SOCKS5 transport
#     (config --relay-url socks5://...) — no torify, no LD_PRELOAD
#   * on exit, direct mode is restored and the throwaway client is deleted
set -uo pipefail

here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# Portable config home: if a repo-local .config/zkapi-clientd exists (e.g. a
# wallet backed up into the working tree), prefer it so the stack travels with
# the checkout; otherwise fall back to the standard user config directory.
if [ -f "$here/.config/zkapi-clientd/config.json" ]; then export XDG_CONFIG_HOME="$here/.config"; fi
BIN="$here/zkapi-clientd/bin/zkapi-clientd"
[ -x "$BIN" ] || { echo "zkapi-serve-tor: daemon not found at $BIN" >&2; exit 1; }
command -v tor >/dev/null 2>&1 || { echo "zkapi-serve-tor: tor not in PATH" >&2; exit 127; }

datadir="$(mktemp -d)" || exit 1
chmod 700 "$datadir"
log="$datadir/tor.log"

socks_port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')" || exit 1

tor --ClientOnly 1 --PublishServerDescriptor 0 \
    --DataDirectory "$datadir" --SocksPort "127.0.0.1:${socks_port}" \
    --SafeLogging 1 --__OwningControllerProcess "$$" \
    ${TOR_ISOLATE_EXTRA_OPTS:+$TOR_ISOLATE_EXTRA_OPTS} \
    > "$log" 2>&1 &
torpid=$!
echo "zkapi-serve-tor: throwaway client on 127.0.0.1:${socks_port} (datadir ${datadir})" >&2

child=""
cleanup() {
  if [ -n "$child" ] && kill -0 "$child" 2>/dev/null; then kill "$child" 2>/dev/null; fi
  if kill -0 "$torpid" 2>/dev/null; then
    kill "$torpid" 2>/dev/null
    for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$torpid" 2>/dev/null || break; sleep 0.2; done
    kill -9 "$torpid" 2>/dev/null
  fi
  rm -rf "$datadir"
  # Restore direct mode so later non-Tor runs don't fail closed on a dead port.
  "$BIN" config --relay-url "" >/dev/null 2>&1 || true
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

elapsed=0
shown=0
while ! grep -q "Bootstrapped 100" "$log" 2>/dev/null; do
  if ! kill -0 "$torpid" 2>/dev/null; then echo "tor exited early:" >&2; tail -5 "$log" >&2; exit 1; fi
  if [ "$elapsed" -ge "${TOR_ISOLATE_TIMEOUT:-120}" ]; then echo "bootstrap timed out:" >&2; tail -5 "$log" >&2; exit 1; fi
  # surface tor's actual progress lines (Bootstrapped X% (stage)) as they appear
  n=$(grep -c "Bootstrapped" "$log" 2>/dev/null); [ -z "$n" ] && n=0
  if [ "$n" -gt "$shown" ]; then grep "Bootstrapped" "$log" | tail -n $((n - shown)) >&2; shown=$n; fi
  if [ $((elapsed % 10)) -eq 0 ] && [ "$elapsed" -gt 0 ]; then echo "still bootstrapping (${elapsed}s)..." >&2; fi
  sleep 1; elapsed=$((elapsed + 1))
done

"$BIN" config --relay-url "socks5://127.0.0.1:${socks_port}" >/dev/null || { echo "failed to save relay URL" >&2; exit 1; }
echo "zkapi-serve-tor: route saved as socks5://127.0.0.1:${socks_port}; serving (plain, no torify)" >&2
"$BIN" serve &
child=$!
rc=0
wait "$child" || rc=$?
exit "$rc"
