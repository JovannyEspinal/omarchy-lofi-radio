#!/usr/bin/env bash

set -u

readonly project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
player_pid=

cleanup() {
  [[ -z $player_pid ]] || kill "$player_pid" 2>/dev/null || true
  rm -rf -- "$test_dir"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

mkdir -p "$test_dir/bin" "$test_dir/runtime" "$test_dir/state"
cp "$(command -v sleep)" "$test_dir/bin/chromium"
export PATH="$test_dir/bin:$PATH"
export XDG_RUNTIME_DIR="$test_dir/runtime"
export XDG_STATE_HOME="$test_dir/state"

# shellcheck source=../control.sh
source "$project_dir/control.sh"
prepare_runtime || fail 'prepare runtime'

setsid chromium 60 &
player_pid=$!
for _ in {1..30}; do
  [[ -r /proc/$player_pid/stat ]] && break
  sleep 0.01
done

player_pgid=$(ps -o pgid= -p "$player_pid" | tr -d ' ')
player_start_time=$(process_start_time "$player_pid")
player_executable=$(readlink -f "/proc/$player_pid/exe")

write_identity() {
  printf '%s\n' "$player_pid" >"$pid_path"
  printf '%s\n' "$player_pgid" >"$pgid_path"
  printf '%s\n' "$1" >"$start_time_path"
  printf '%s\n' "$player_executable" >"$exe_path"
}

write_identity "$player_start_time"
player_identity >/dev/null || fail 'valid identity was rejected'
printf 'ok - accepts the process instance started by the controller\n'

write_identity "$((player_start_time + 1))"
player_identity >/dev/null 2>&1 && fail 'stale start time was accepted'
printf 'ok - rejects a reused PID with a different start time\n'

write_identity "$player_start_time"
printf '%s\n' "$((player_pgid + 1))" >"$pgid_path"
player_identity >/dev/null 2>&1 && fail 'wrong process group was accepted'
printf 'ok - rejects a PID that is no longer in the stored process group\n'

write_identity "$player_start_time"
printf '%s\n' "$(command -v tail)" >"$exe_path"
player_identity >/dev/null 2>&1 && fail 'wrong executable was accepted'
printf 'ok - rejects a process that is not the expected Chromium executable\n'

write_identity "$((player_start_time + 1))"
stop_player
kill -0 "$player_pid" 2>/dev/null || fail 'stale state killed an unrelated process'
printf 'ok - stale state cannot signal an unrelated process group\n'

stop_calls=0
start_calls=0
is_running() { return 0; }
player_pgid() { printf '999999\n'; }
stop_player() { stop_calls=$((stop_calls + 1)); rm -f -- "$paused_path"; }
start_player() { start_calls=$((start_calls + 1)); }
: >"$paused_path"
toggle_player || fail 'resume toggle failed'
[[ $stop_calls == 1 ]] || fail 'resume toggle did not stop the paused player'
[[ $start_calls == 1 ]] || fail 'resume toggle did not start a fresh player'
[[ ! -e $paused_path ]] || fail 'resume toggle left the paused marker'
printf 'ok - resume restarts the player instead of sending SIGCONT\n'

stop_calls=0
start_calls=0
stop_player() { stop_calls=$((stop_calls + 1)); rm -f -- "$paused_path"; return 1; }
start_player() { start_calls=$((start_calls + 1)); return 0; }
: >"$paused_path"
toggle_player >/dev/null 2>&1 && fail 'resume toggle hid a stop failure'
[[ $stop_calls == 1 ]] || fail 'resume toggle did not call stop after failure'
[[ $start_calls == 0 ]] || fail 'resume toggle started after stop failure'
printf 'ok - resume propagates a stop failure\n'
