#!/usr/bin/env bash

set -u

readonly plugin_name='Lofi Radio'
readonly lofi_url='https://www.youtube.com/@LofiGirl/live'
readonly synthwave_url='https://www.youtube.com/watch?v=4xDzrJKXOOY'
readonly runtime_base="${XDG_RUNTIME_DIR:-/tmp}"
readonly runtime_dir="$runtime_base/espi-lofi-radio-${UID}"
readonly state_base="${XDG_STATE_HOME:-$HOME/.local/state}"
readonly state_dir="$state_base/espi-lofi-radio"
readonly profile_dir="$state_dir/chromium-profile"
readonly pid_path="$runtime_dir/chromium.pid"
readonly pgid_path="$runtime_dir/chromium.pgid"
readonly start_time_path="$runtime_dir/chromium.start-time"
readonly exe_path="$runtime_dir/chromium.exe"
readonly paused_path="$runtime_dir/paused"
readonly station_path="$runtime_dir/station"
readonly lock_path="$runtime_dir/control.lock"
readonly log_path="$runtime_dir/chromium.log"

notify_error() {
  local message=$1
  command -v notify-send >/dev/null 2>&1 && notify-send "$plugin_name" "$message"
  printf '%s: %s\n' "$plugin_name" "$message" >&2
}

prepare_runtime() {
  install -d -m 700 "$runtime_dir" "$state_dir" "$profile_dir" || {
    notify_error "Could not create the private runtime or profile directory."
    return 1
  }
}

current_station() {
  local station=1
  if [[ -r $station_path ]]; then
    read -r station <"$station_path" || station=1
  fi
  [[ $station == 1 || $station == 2 ]] || station=1
  printf '%s\n' "$station"
}

station_url() {
  [[ $(current_station) == 2 ]] && printf '%s\n' "$synthwave_url" || printf '%s\n' "$lofi_url"
}

station_name() {
  [[ $(current_station) == 2 ]] && printf '%s\n' 'Synthwave' || printf '%s\n' 'Lofi Hip Hop'
}

process_start_time() {
  local pid=$1 stat
  local -a stat_fields
  [[ -r /proc/$pid/stat ]] || return 1
  read -r stat <"/proc/$pid/stat" || return 1
  stat=${stat##*) }
  read -r -a stat_fields <<<"$stat"
  [[ ${stat_fields[19]:-} =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "${stat_fields[19]}"
}

player_identity() {
  local pid pgid start_time executable actual_pgid actual_start_time actual_executable
  [[ -r $pid_path && -r $pgid_path && -r $start_time_path && -r $exe_path ]] || return 1
  read -r pid <"$pid_path" || return 1
  read -r pgid <"$pgid_path" || return 1
  read -r start_time <"$start_time_path" || return 1
  read -r executable <"$exe_path" || return 1
  [[ $pid =~ ^[1-9][0-9]*$ && $pgid =~ ^[1-9][0-9]*$ && $start_time =~ ^[0-9]+$ ]] || return 1
  [[ $pid == "$pgid" ]] || return 1
  [[ $executable == /* ]] || return 1

  actual_pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ') || return 1
  [[ $actual_pgid == "$pgid" ]] || return 1
  actual_start_time=$(process_start_time "$pid") || return 1
  [[ $actual_start_time == "$start_time" ]] || return 1
  actual_executable=$(readlink -f "/proc/$pid/exe" 2>/dev/null) || return 1
  [[ $actual_executable == "$executable" ]] || return 1
  [[ ${actual_executable##*/} == chromium ]] || return 1

  printf '%s %s\n' "$pid" "$pgid"
}

player_pid() {
  local pid pgid
  read -r pid pgid < <(player_identity) || return 1
  printf '%s\n' "$pid"
}

player_pgid() {
  local pid pgid
  read -r pid pgid < <(player_identity) || return 1
  printf '%s\n' "$pgid"
}

is_running() {
  player_pid >/dev/null
}

start_player() {
  local url=${1:-$(station_url)}
  local pid pgid start_time executable

  command -v chromium >/dev/null 2>&1 || {
    notify_error "Missing dependency: chromium"
    return 1
  }
  is_running && return 0

  rm -f -- "$pid_path" "$pgid_path" "$start_time_path" "$exe_path" "$paused_path"
  : >"$log_path"

  nohup setsid chromium \
    --headless=new \
    --disable-gpu \
    --no-first-run \
    --no-default-browser-check \
    --autoplay-policy=no-user-gesture-required \
    --user-data-dir="$profile_dir" \
    "$url" 9>&- >"$log_path" 2>&1 &
  pid=$!
  printf '%s\n' "$pid" >"$pid_path"

  for _ in {1..30}; do
    if kill -0 "$pid" 2>/dev/null; then
      pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')
      start_time=$(process_start_time "$pid") || start_time=
      executable=$(readlink -f "/proc/$pid/exe" 2>/dev/null) || executable=
      if [[ $pgid == "$pid" && $start_time =~ ^[0-9]+$ && ${executable##*/} == chromium ]]; then
        printf '%s\n' "$pgid" >"$pgid_path"
        printf '%s\n' "$start_time" >"$start_time_path"
        printf '%s\n' "$executable" >"$exe_path"
        return 0
      fi
    fi
    sleep 0.1
  done

  notify_error "The headless YouTube player did not start. See $log_path"
  return 1
}

open_login() {
  command -v chromium >/dev/null 2>&1 || {
    notify_error "Missing dependency: chromium"
    return 1
  }

  stop_player
  setsid -f chromium \
    --user-data-dir="$profile_dir" \
    --no-first-run \
    --no-default-browser-check \
    --disable-background-mode \
    'https://www.youtube.com/' >/dev/null 2>&1
}

stop_player() {
  local pgid
  if pgid=$(player_pgid); then
    if pgid=$(player_pgid); then kill -CONT -- "-$pgid" 2>/dev/null || true; fi
    if pgid=$(player_pgid); then kill -TERM -- "-$pgid" 2>/dev/null || true; fi
    for _ in {1..30}; do
      is_running || break
      sleep 0.1
    done
    if pgid=$(player_pgid); then kill -KILL -- "-$pgid" 2>/dev/null || true; fi
  fi
  rm -f -- "$pid_path" "$pgid_path" "$start_time_path" "$exe_path" "$paused_path"
}

toggle_player() {
  local pgid
  if ! is_running; then
    start_player
    return
  fi
  pgid=$(player_pgid) || return 1

  if [[ -e $paused_path ]]; then
    kill -CONT -- "-$pgid"
    rm -f -- "$paused_path"
  else
    kill -STOP -- "-$pgid"
    : >"$paused_path"
  fi
}

main() {
  local action=${1:-status}

  prepare_runtime || return 1
  exec 9>"$lock_path"
  flock -w 5 9 || {
    notify_error "Another control operation is still running."
    return 1
  }

  case $action in
    status)
      station_name
      if ! is_running; then return 4; fi
      [[ -e $paused_path ]] && return 3
      return 0
      ;;
    toggle)
      toggle_player
      ;;
    restart|recover)
      stop_player
      start_player
      ;;
    switch)
      if [[ $(current_station) == 1 ]]; then printf '2\n' >"$station_path"; else printf '1\n' >"$station_path"; fi
      stop_player
      start_player
      command -v notify-send >/dev/null 2>&1 && notify-send "$plugin_name" "Now playing: $(station_name)"
      ;;
    stop)
      stop_player
      ;;
    login)
      open_login
      ;;
    *)
      printf 'Usage: %s {status|toggle|restart|switch|stop|login}\n' "$0" >&2
      return 2
      ;;
  esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
