#!/usr/bin/env bash
# lib/preflight.sh — fail early, with an actionable message, before anything
# expensive or destructive happens.

# version_ge <a> <b> — true when version a >= version b (dotted numeric).
version_ge() {
  [[ $1 == "$2" ]] && return 0
  local newest
  newest=$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)
  [[ $newest == "$1" ]]
}

preflight() {
  log_phase "Preflight"

  [[ $(id -u) -ne 0 ]] ||
    die "refusing to run as root: this installer is designed for unprivileged, per-user installs"

  [[ -d $QE_PLATFORM_FINGERPRINT ]] ||
    die "this installer targets ${QE_PLATFORM_DESC}; '${QE_PLATFORM_FINGERPRINT}' is missing, so this is a different machine"

  require_cmd git cmake sha256sum awk sed tar flock python3 df

  local cmake_version
  cmake_version=$(cmake --version | head -n 1 | awk '{print $3}')
  version_ge "$cmake_version" "$QE_CMAKE_MIN" ||
    die "Quantum ESPRESSO ${QE_VERSION} needs CMake >= ${QE_CMAKE_MIN}, found ${cmake_version}"
  log_debug "cmake ${cmake_version} >= ${QE_CMAKE_MIN}"

  # The prefix itself may not exist yet; its nearest existing ancestor must be
  # writable so the atomic swap at the end can work.
  local parent=$QE_PREFIX
  while [[ ! -d $parent && $parent != / ]]; do parent=$(dirname "$parent"); done
  [[ -w $parent ]] || die "install prefix is not writable: ${parent}"

  mkdir -p "$QE_BUILD_ROOT"
  [[ -w $QE_BUILD_ROOT ]] || die "build directory is not writable: ${QE_BUILD_ROOT}"

  # A full out-of-source build of QE takes roughly 6 GiB; the installed tree is
  # about 1.5 GiB. Ask for a little headroom on top.
  require_free_space "$QE_BUILD_ROOT" 8192
  require_free_space "$parent" 3072

  # Only require network access if we actually have to fetch something: a
  # re-run against an already-cloned, already-verified source tree works
  # offline.
  local have_source=0
  if [[ -d $QE_SRC_DIR/.git ]] &&
     [[ $(git -C "$QE_SRC_DIR" rev-parse HEAD 2>/dev/null) == "$QE_GIT_COMMIT" ]]; then
    have_source=1
  fi
  if (( have_source == 0 )); then
    log_info "checking that ${QE_GIT_URL} is reachable"
    timeout 30 git ls-remote --tags "$QE_GIT_URL" "$QE_GIT_TAG" >/dev/null 2>&1 ||
      die "cannot reach ${QE_GIT_URL}; this installer needs outbound HTTPS from the login node"
  fi

  log_ok "preflight passed"
}

# Warn (but do not refuse) when the user is about to saturate a shared login
# node. Compute nodes and --slurm builds are exempt.
warn_if_heavy_on_login_node() {
  [[ -n ${SLURM_JOB_ID:-} ]] && return 0
  local cores
  cores=$(nproc)
  if (( QE_JOBS > cores / 4 )); then
    log_warn "building with -j${QE_JOBS} on a shared login node (${cores} cores)"
    log_warn "consider '--slurm' or a smaller '--jobs' if others are working here"
  fi
}
