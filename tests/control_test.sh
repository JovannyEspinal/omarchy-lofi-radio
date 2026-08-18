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
[[ $(player_pgid) == "$player_pgid" ]] || fail 'player_pgid returned more than the process group id'
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

# Simulate a live orphan after its controller state disappeared. The production
# discovery is exercised separately on real Chromium; this checks the stop path.
write_identity "$player_start_time"
rm -f "$pid_path" "$pgid_path" "$start_time_path" "$exe_path"
orphan_player_identity() {
  printf '%s %s %s %s\n' "$player_pid" "$player_pgid" "$player_start_time" "$player_executable"
}
stop_player
kill -0 "$player_pid" 2>/dev/null && fail 'orphaned player was not stopped'
printf 'ok - stops a verified orphan when identity files are missing\n'
