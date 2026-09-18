#!/usr/bin/env bash
# lib/toolchain.sh — bring up Lmod and the pinned Intel oneAPI toolchain.

# Lmod defines `module` as a shell function, which a non-interactive shell does
# not inherit. Source its initialisation script ourselves so the installer does
# not depend on the user's dotfiles.
lmod_bootstrap() {
  if declare -F module >/dev/null 2>&1; then
    log_debug "module function already present"
    return 0
  fi
  local init
  for init in "${QE_LMOD_INIT_CANDIDATES[@]}"; do
    if [[ -r $init ]]; then
      # Lmod's init script is not written for `set -u`/`set -e`.
      set +u +e
      # shellcheck disable=SC1090
      source "$init"
      set -u -e
      log_debug "sourced Lmod init: ${init}"
      break
    fi
  done
  declare -F module >/dev/null 2>&1 ||
    die "Lmod not found; this installer targets ${QE_PLATFORM_DESC}"
}

# module_quiet <args...> — Lmod writes its chatter to stderr and its exit code
# is not always meaningful, so verification is done by the caller.
module_quiet() {
  set +e
  module "$@" >/dev/null 2>&1
  set -e
}

load_toolchain() {
  lmod_bootstrap

  # Start from a clean module environment: what the user happened to have
  # loaded must not leak into the build.
  module_quiet --force purge

  local m
  for m in "${QE_TOOLCHAIN_MODULES[@]}"; do
    log_info "loading module ${m}"
    module_quiet load "$m"
  done

  # Trust nothing: verify by looking for the tools we are about to use rather
  # than by trusting Lmod's exit status.
  local missing=()
  local tool
  for tool in "$QE_MPICC_WRAPPER" "$QE_FC_WRAPPER" icx; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done
  if (( ${#missing[@]} > 0 )); then
    log_error "toolchain did not provide: ${missing[*]}"
    die "check that module(s) '${QE_TOOLCHAIN_MODULES[*]}' exist on this system"
  fi

  # Guard against a same-named module from a different install tree.
  local cc_path
  cc_path=$(command -v "$QE_MPICC_WRAPPER")
  [[ $cc_path == "$QE_PLATFORM_FINGERPRINT"* ]] ||
    log_warn "${QE_MPICC_WRAPPER} resolves to ${cc_path}, outside ${QE_PLATFORM_FINGERPRINT}"

  [[ -n ${MKLROOT:-} ]] || die "MKLROOT is unset; the Intel module did not provide MKL"
  [[ -n ${I_MPI_ROOT:-} ]] || die "I_MPI_ROOT is unset; the Intel module did not provide Intel MPI"

  log_ok "toolchain ready (MKLROOT=${MKLROOT}, I_MPI_ROOT=${I_MPI_ROOT})"
}

# First line of a compiler's --version, minus Intel's deprecation remarks.
tool_version() {
  local tool=$1
  command -v "$tool" >/dev/null 2>&1 || { printf 'not found'; return 0; }
  "$tool" --version 2>&1 | grep -v 'remark #' | head -n 1
}
