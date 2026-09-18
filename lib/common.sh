#!/usr/bin/env bash
# lib/common.sh — logging, error handling and small shell utilities.
#
# Sourced by install.sh; never executed directly.

# --------------------------------------------------------------------------
# Logging
# --------------------------------------------------------------------------

if [[ -t 2 ]]; then
  readonly _C_RESET=$'\033[0m' _C_RED=$'\033[31m' _C_YELLOW=$'\033[33m'
  readonly _C_BLUE=$'\033[34m' _C_GREEN=$'\033[32m' _C_DIM=$'\033[2m'
else
  readonly _C_RESET='' _C_RED='' _C_YELLOW='' _C_BLUE='' _C_GREEN='' _C_DIM=''
fi

# Every message goes to stderr so that stdout stays usable for real output.
_log() {
  local color=$1 level=$2; shift 2
  printf '%s[%(%H:%M:%S)T] %-5s %s%s\n' "$color" -1 "$level" "$*" "$_C_RESET" >&2
}

log_info()  { _log "$_C_BLUE"   "INFO"  "$@"; }
log_warn()  { _log "$_C_YELLOW" "WARN"  "$@"; }
log_error() { _log "$_C_RED"    "ERROR" "$@"; }
log_ok()    { _log "$_C_GREEN"  "OK"    "$@"; }
log_debug() { [[ ${QE_VERBOSE:-0} == 1 ]] && _log "$_C_DIM" "DEBUG" "$@"; return 0; }

# A visible separator for the major phases of the install.
log_phase() {
  printf '\n%s=== %s ===%s\n' "$_C_GREEN" "$*" "$_C_RESET" >&2
}

die() { log_error "$@"; exit 1; }

# --------------------------------------------------------------------------
# Error trap
# --------------------------------------------------------------------------

# Installed by install.sh via `trap on_error ERR`. Reports where we died and,
# when a command log exists, where to look for the real error message.
on_error() {
  local rc=$? cmd=$BASH_COMMAND
  log_error "command failed (exit ${rc}): ${cmd}"
  local i
  for ((i = 1; i < ${#BASH_SOURCE[@]}; i++)); do
    log_error "  at ${BASH_SOURCE[i]}:${BASH_LINENO[i-1]} in ${FUNCNAME[i]}()"
  done
  [[ -n ${QE_LAST_LOG:-} && -f ${QE_LAST_LOG:-} ]] &&
    log_error "last 20 lines of ${QE_LAST_LOG}:" &&
    tail -n 20 "$QE_LAST_LOG" >&2
  exit "$rc"
}

# --------------------------------------------------------------------------
# Command helpers
# --------------------------------------------------------------------------

# run <cmd...> — echo the command when verbose, then run it.
run() {
  log_debug "+ $*"
  "$@"
}

# run_logged <logfile> <cmd...> — run a long/noisy command, sending its output
# to a log file. Keeps the console readable while preserving the full record.
run_logged() {
  local logfile=$1; shift
  mkdir -p "$(dirname "$logfile")"
  QE_LAST_LOG=$logfile
  log_debug "+ $* (log: ${logfile})"
  if [[ ${QE_VERBOSE:-0} == 1 ]]; then
    "$@" 2>&1 | tee -a "$logfile"
    return "${PIPESTATUS[0]}"
  fi
  "$@" >>"$logfile" 2>&1
}

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "required command not found in PATH: ${c}"
  done
}

# retry <attempts> <sleep_seconds> <cmd...> — for network operations only.
retry() {
  local attempts=$1 delay=$2; shift 2
  local n=1
  until "$@"; do
    if (( n >= attempts )); then
      log_error "still failing after ${attempts} attempts: $*"
      return 1
    fi
    log_warn "attempt ${n}/${attempts} failed, retrying in ${delay}s: $*"
    sleep "$delay"
    n=$(( n + 1 ))
  done
}

# --------------------------------------------------------------------------
# Integrity helpers
# --------------------------------------------------------------------------

# verify_sha256 <file> <expected> — fail loudly on any mismatch.
verify_sha256() {
  local file=$1 expected=$2 actual
  [[ -f $file ]] || die "cannot checksum missing file: ${file}"
  actual=$(sha256sum "$file" | awk '{print $1}')
  if [[ $actual != "$expected" ]]; then
    log_error "checksum mismatch for ${file}"
    log_error "  expected: ${expected}"
    log_error "  actual:   ${actual}"
    die "refusing to continue with unverified input"
  fi
  log_debug "sha256 ok: ${file}"
}

# --------------------------------------------------------------------------
# Filesystem helpers
# --------------------------------------------------------------------------

# free_mib <dir> — free space in MiB on the filesystem holding <dir>
# (walks up to the nearest existing ancestor).
free_mib() {
  local dir=$1
  while [[ ! -d $dir && $dir != / ]]; do dir=$(dirname "$dir"); done
  df -Pm "$dir" | awk 'NR==2 {print $4}'
}

require_free_space() {
  local dir=$1 need_mib=$2 have
  have=$(free_mib "$dir")
  (( have >= need_mib )) || die \
    "not enough free space for ${dir}: need ~${need_mib} MiB, have ${have} MiB"
  log_debug "free space ok for ${dir}: ${have} MiB"
}

# Serialise concurrent installs that target the same prefix.
acquire_lock() {
  local lockfile=$1
  mkdir -p "$(dirname "$lockfile")"
  exec {QE_LOCK_FD}>"$lockfile"
  if ! flock -n "$QE_LOCK_FD"; then
    log_warn "another install is holding ${lockfile}; waiting..."
    flock "$QE_LOCK_FD"
  fi
  log_debug "lock acquired: ${lockfile}"
}

# JSON string escaping for the provenance manifest (no jq on the login nodes).
json_escape() {
  printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

# abspath <path> — normalise to an absolute path without touching the
# filesystem (so it is safe during --dry-run and for paths that do not exist).
abspath() {
  local p=$1
  [[ $p == /* ]] || p=$PWD/$p
  local -a out=()
  local part
  local IFS=/
  for part in $p; do
    case $part in
      '' | .) ;;
      ..) (( ${#out[@]} > 0 )) && unset 'out[-1]' ;;
      *)  out+=("$part") ;;
    esac
  done
  (( ${#out[@]} == 0 )) && { printf '/'; return 0; }
  printf '/%s' "${out[@]}"
}
