#!/usr/bin/env bash
#
# install.sh — build and install Quantum ESPRESSO on NCHC Forerunner 1 (創進一號).
#
#   git clone <this repo>
#   ./<repo>/install.sh
#
# Runs from any directory, as any user, without root, containers or Spack.
# Everything it needs is pinned: the source commit, the submodule revisions and
# the exact toolchain module. See README.md for the design notes.

set -o errexit -o nounset -o pipefail -o errtrace
shopt -s inherit_errexit 2>/dev/null || true

# Checked here rather than in preflight because the logger itself uses
# printf's %(fmt)T, which needs bash >= 4.2.
if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 2) )); then
  printf 'ERROR: this installer needs bash >= 4.2, found %s\n' "$BASH_VERSION" >&2
  exit 1
fi

# --------------------------------------------------------------------------
# Locate the repository, no matter where we were invoked from or how many
# symlinks point at this script.
# --------------------------------------------------------------------------
_self=${BASH_SOURCE[0]}
while [[ -L $_self ]]; do
  _dir=$(cd -P "$(dirname "$_self")" && pwd)
  _self=$(readlink "$_self")
  [[ $_self != /* ]] && _self=$_dir/$_self
done
QE_REPO_DIR=$(cd -P "$(dirname "$_self")" && pwd)
readonly QE_REPO_DIR
unset _self _dir

# shellcheck source=lib/common.sh
source "$QE_REPO_DIR/lib/common.sh"
trap on_error ERR

# --------------------------------------------------------------------------
# Defaults (every one of these is overridable on the command line)
# --------------------------------------------------------------------------
QE_VERSION="7.6"
QE_COMPILER="ifort"
QE_PREFIX=""
QE_BUILD_ROOT="${HOME}/.cache/qe-installer"
QE_MODULEFILE_DIR="${HOME}/opt/modulefiles"
QE_JOBS=""
QE_ARCH_FLAGS=""
QE_TEST_MODE="smoke"
QE_KEEP_BUILD=0
QE_FORCE=0
QE_VERBOSE=0
QE_DRY_RUN=0
QE_USE_SLURM=0
QE_SLURM_ACCOUNT=""
QE_SLURM_PARTITION=""
QE_SLURM_TIME=""
QE_SLURM_CPUS=""
QE_INVOCATION="$0 $*"
QE_BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
QE_SUBMODULE_STATUS=""
QE_STAGING_DIR=""
QE_PREVIOUS_DIR=""
QE_MODULEFILE=""

usage() {
  cat <<EOF
Quantum ESPRESSO installer for NCHC Forerunner 1 (創進一號)

Usage: ${0##*/} [options]

Options:
  --prefix DIR          Install prefix
                        (default: \$HOME/opt/quantum-espresso/<version>-<toolchain>)
  --version VER         Quantum ESPRESSO version to install (default: ${QE_VERSION})
                        Available: $(cd "$QE_REPO_DIR/config/versions" && ls *.sh | sed 's/\.sh$//' | tr '\n' ' ')
  --compiler ifort|ifx  Fortran compiler (default: ${QE_COMPILER}; see README
                        for why ifx is not the default)
  --jobs N              Parallel compile jobs (default: 16 on a login node,
                        all allocated cores inside a Slurm job)
  --arch-flags FLAGS    Override the CPU optimisation flags
  --build-root DIR      Where sources are cloned and compiled
                        (default: ${QE_BUILD_ROOT})
  --modulefile-dir DIR  Where the generated Lmod modulefile is written
                        (default: ${QE_MODULEFILE_DIR})
  --test MODE           none | smoke | full   (default: ${QE_TEST_MODE})
  --slurm               Build inside a Slurm job instead of on the login node
  --slurm-account ACC   Slurm account for --slurm (default: auto-detected)
  --slurm-partition P   Slurm partition for --slurm (default: development)
  --keep-build          Do not delete the build tree afterwards
  --force               Rebuild and reinstall even if already up to date
  --verbose             Stream compiler output instead of logging it
  --dry-run             Print what would be done and exit
  -h, --help            This message

Examples:
  ./install.sh
  ./install.sh --version 7.5 --prefix /work1/\$USER/qe-7.5
  ./install.sh --slurm --jobs 56 --test full
EOF
}

# --------------------------------------------------------------------------
# Argument parsing
# --------------------------------------------------------------------------
parse_args() {
  while (( $# > 0 )); do
    case $1 in
      --prefix)           QE_PREFIX=$2; shift 2 ;;
      --version)          QE_VERSION=$2; shift 2 ;;
      --compiler)         QE_COMPILER=$2; shift 2 ;;
      --jobs|-j)          QE_JOBS=$2; shift 2 ;;
      --arch-flags)       QE_ARCH_FLAGS=$2; shift 2 ;;
      --build-root)       QE_BUILD_ROOT=$2; shift 2 ;;
      --modulefile-dir)   QE_MODULEFILE_DIR=$2; shift 2 ;;
      --test)             QE_TEST_MODE=$2; shift 2 ;;
      --slurm)            QE_USE_SLURM=1; shift ;;
      --slurm-account)    QE_SLURM_ACCOUNT=$2; shift 2 ;;
      --slurm-partition)  QE_SLURM_PARTITION=$2; shift 2 ;;
      --keep-build)       QE_KEEP_BUILD=1; shift ;;
      --force)            QE_FORCE=1; shift ;;
      --verbose)          QE_VERBOSE=1; shift ;;
      --dry-run)          QE_DRY_RUN=1; shift ;;
      -h|--help)          usage; exit 0 ;;
      *)                  usage >&2; die "unknown option: $1" ;;
    esac
  done
}

# --------------------------------------------------------------------------
# Configuration: merge defaults, site profile, version pins and CLI options.
# --------------------------------------------------------------------------
load_configuration() {
  # shellcheck source=config/platform.sh
  source "$QE_REPO_DIR/config/platform.sh"

  local version_file=$QE_REPO_DIR/config/versions/${QE_VERSION}.sh
  [[ -r $version_file ]] || die \
    "unknown version '${QE_VERSION}'; available: $(cd "$QE_REPO_DIR/config/versions" && ls ./*.sh | sed 's|.*/||; s|\.sh$||' | tr '\n' ' ')"
  # shellcheck source=config/versions/7.6.sh
  source "$version_file"

  QE_FC_WRAPPER=$(qe_fortran_wrapper "$QE_COMPILER") ||
    die "unsupported --compiler '${QE_COMPILER}' (expected ifort or ifx)"

  [[ -n $QE_ARCH_FLAGS ]] || QE_ARCH_FLAGS=$QE_ARCH_FLAGS_DEFAULT
  [[ -n $QE_PREFIX ]] ||
    QE_PREFIX="${HOME}/opt/quantum-espresso/${QE_VERSION}-${QE_TOOLCHAIN_ID}"
  # Normalise user-supplied paths so that relative arguments behave, without
  # creating anything yet (--dry-run must stay side-effect free).
  QE_PREFIX=$(abspath "$QE_PREFIX")
  QE_BUILD_ROOT=$(abspath "$QE_BUILD_ROOT")
  QE_MODULEFILE_DIR=$(abspath "$QE_MODULEFILE_DIR")

  if [[ -z $QE_JOBS ]]; then
    if [[ -n ${SLURM_CPUS_PER_TASK:-} ]]; then
      QE_JOBS=$SLURM_CPUS_PER_TASK
    elif [[ -n ${SLURM_CPUS_ON_NODE:-} ]]; then
      QE_JOBS=$SLURM_CPUS_ON_NODE
    else
      # A polite default for a shared login node.
      local cores; cores=$(nproc)
      QE_JOBS=$(( cores < 16 ? cores : 16 ))
    fi
  fi
  [[ $QE_JOBS =~ ^[1-9][0-9]*$ ]] || die "--jobs must be a positive integer, got '${QE_JOBS}'"
  [[ $QE_TEST_MODE =~ ^(none|smoke|full)$ ]] ||
    die "--test must be none, smoke or full, got '${QE_TEST_MODE}'"

  QE_SRC_DIR="${QE_BUILD_ROOT}/src/q-e-${QE_VERSION}"
  QE_BUILD_DIR="${QE_BUILD_ROOT}/build/${QE_VERSION}-${QE_TOOLCHAIN_ID}-${QE_COMPILER}"
  QE_LOG_DIR="${QE_BUILD_ROOT}/logs/${QE_VERSION}-${QE_TOOLCHAIN_ID}-${QE_COMPILER}"
  [[ -n $QE_SLURM_PARTITION ]] || QE_SLURM_PARTITION=$QE_SLURM_PARTITION_DEFAULT
  [[ -n $QE_SLURM_TIME ]]      || QE_SLURM_TIME=$QE_SLURM_TIME_DEFAULT
  [[ -n $QE_SLURM_CPUS ]]      || QE_SLURM_CPUS=$QE_SLURM_CPUS_DEFAULT

  # Exported for the manifest writer (which is a python3 one-liner).
  QE_TOOLCHAIN_MODULES_STR="${QE_TOOLCHAIN_MODULES[*]}"
  export QE_VERSION QE_PREFIX QE_GIT_URL QE_GIT_TAG QE_GIT_COMMIT \
         QE_PLATFORM_ID QE_TOOLCHAIN_ID QE_TOOLCHAIN_MODULES_STR \
         QE_COMPILER QE_FC_WRAPPER QE_MPICC_WRAPPER QE_ARCH_FLAGS \
         QE_JOBS QE_BUILD_DATE QE_INVOCATION
}

print_plan() {
  log_phase "Plan"
  cat >&2 <<EOF
  platform        : ${QE_PLATFORM_DESC}
  package         : Quantum ESPRESSO ${QE_VERSION}
  source          : ${QE_GIT_URL} @ ${QE_GIT_TAG}
                    commit ${QE_GIT_COMMIT}
  toolchain       : ${QE_TOOLCHAIN_MODULES[*]} (${QE_COMPILER} / ${QE_FC_WRAPPER}, ${QE_MPICC_WRAPPER})
  features        : MPI + OpenMP + ScaLAPACK (MKL), ${QE_ARCH_FLAGS}
  install prefix  : ${QE_PREFIX}
  modulefile      : ${QE_MODULEFILE_DIR}/quantum-espresso/${QE_VERSION}-${QE_TOOLCHAIN_ID}.lua
  build root      : ${QE_BUILD_ROOT}
  parallel jobs   : ${QE_JOBS}
  self-test       : ${QE_TEST_MODE}
EOF
}

# --------------------------------------------------------------------------
# Skip work that has already been done, unless --force.
# --------------------------------------------------------------------------
already_installed() {
  local manifest=$QE_PREFIX/share/quantum-espresso/manifest.json
  [[ -x $QE_PREFIX/bin/pw.x && -r $manifest ]] || return 1
  QE_M=$manifest python3 - <<'PY'
import json, os, sys
try:
    m = json.load(open(os.environ["QE_M"]))
except Exception:
    sys.exit(1)
want = (
    os.environ["QE_GIT_COMMIT"],
    os.environ["QE_TOOLCHAIN_ID"],
    os.environ["QE_COMPILER"],
    os.environ["QE_ARCH_FLAGS"],
)
got = (
    m.get("package", {}).get("git_commit"),
    m.get("toolchain", {}).get("id"),
    m.get("toolchain", {}).get("fortran_compiler"),
    m.get("toolchain", {}).get("arch_flags"),
)
sys.exit(0 if want == got else 1)
PY
}

# --------------------------------------------------------------------------
# Optional: do the build inside a Slurm job instead of on the login node.
# --------------------------------------------------------------------------
submit_slurm_build() {
  log_phase "Submitting build job"
  require_cmd sbatch

  if [[ -z $QE_SLURM_ACCOUNT ]]; then
    QE_SLURM_ACCOUNT=$(sacctmgr -nP show assoc user="$USER" format=Account 2>/dev/null | head -n 1 || true)
  fi
  [[ -n $QE_SLURM_ACCOUNT ]] ||
    die "could not determine a Slurm account; pass --slurm-account"

  mkdir -p "$QE_LOG_DIR"
  local job_script=$QE_LOG_DIR/build-job.sbatch
  local job_log=$QE_LOG_DIR/build-job.%j.out

  # Forward the original request, minus --slurm, and pin --jobs to the
  # allocation so the job never oversubscribes its cpuset.
  local -a forwarded=(
    --version "$QE_VERSION" --compiler "$QE_COMPILER"
    --prefix "$QE_PREFIX" --build-root "$QE_BUILD_ROOT"
    --modulefile-dir "$QE_MODULEFILE_DIR" --arch-flags "$QE_ARCH_FLAGS"
    --test "$QE_TEST_MODE" --jobs "$QE_SLURM_CPUS"
  )
  (( QE_FORCE == 1 ))      && forwarded+=(--force)
  (( QE_KEEP_BUILD == 1 )) && forwarded+=(--keep-build)
  (( QE_VERBOSE == 1 ))    && forwarded+=(--verbose)

  sed \
    -e "s|@PARTITION@|${QE_SLURM_PARTITION}|g" \
    -e "s|@ACCOUNT@|${QE_SLURM_ACCOUNT}|g" \
    -e "s|@TIME@|${QE_SLURM_TIME}|g" \
    -e "s|@CPUS@|${QE_SLURM_CPUS}|g" \
    -e "s|@LOGFILE@|${job_log}|g" \
    -e "s|@INSTALLER@|$(printf '%q' "$QE_REPO_DIR/install.sh")|g" \
    -e "s|@ARGS@|$(printf '%q ' "${forwarded[@]}")|g" \
    "$QE_REPO_DIR/share/build-job.sbatch.tmpl" > "$job_script"

  log_info "partition=${QE_SLURM_PARTITION} account=${QE_SLURM_ACCOUNT} cpus=${QE_SLURM_CPUS} time=${QE_SLURM_TIME}"
  log_info "job script: ${job_script}"
  log_info "waiting for the job to finish (Ctrl-C leaves it running; use scancel to stop it)"

  # --wait makes this still feel like one synchronous command and propagates
  # the job's exit status.
  sbatch --wait "$job_script"
}

# --------------------------------------------------------------------------
# Final report
# --------------------------------------------------------------------------
print_summary() {
  log_phase "Done"
  cat >&2 <<EOF
Quantum ESPRESSO ${QE_VERSION} is installed in
    ${QE_PREFIX}

Use it in either of these ways:

  1) Lmod (recommended):
       module use ${QE_MODULEFILE_DIR}
       module load quantum-espresso/${QE_VERSION}-${QE_TOOLCHAIN_ID}

  2) Plain shell:
       source ${QE_PREFIX}/etc/qe-env.sh

Then:
       mpirun -np 8 pw.x -in your.scf.in

Build provenance (exact commits, compiler versions and CMake flags):
       ${QE_PREFIX}/share/quantum-espresso/manifest.json
An example Slurm job script is in ${QE_REPO_DIR}/examples/.
EOF
}

# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------
main() {
  parse_args "$@"
  load_configuration

  # shellcheck source=lib/toolchain.sh
  source "$QE_REPO_DIR/lib/toolchain.sh"
  # shellcheck source=lib/preflight.sh
  source "$QE_REPO_DIR/lib/preflight.sh"
  # shellcheck source=lib/source.sh
  source "$QE_REPO_DIR/lib/source.sh"
  # shellcheck source=lib/build.sh
  source "$QE_REPO_DIR/lib/build.sh"
  # shellcheck source=lib/postinstall.sh
  source "$QE_REPO_DIR/lib/postinstall.sh"
  # shellcheck source=lib/selftest.sh
  source "$QE_REPO_DIR/lib/selftest.sh"

  print_plan

  if (( QE_DRY_RUN == 1 )); then
    log_info "--dry-run: stopping here"
    exit 0
  fi

  if (( QE_USE_SLURM == 1 )); then
    submit_slurm_build
    exit $?
  fi

  mkdir -p "$QE_BUILD_ROOT"
  acquire_lock "${QE_BUILD_ROOT}/locks/$(printf '%s' "$QE_PREFIX" | sha256sum | cut -c1-16).lock"

  if (( QE_FORCE == 0 )) && already_installed; then
    log_ok "already installed and up to date: ${QE_PREFIX}"
    log_info "pass --force to rebuild from scratch"
    # Still (re)publish the modulefile: it lives outside the prefix, so it can
    # have been removed or repointed by another install since. Re-running the
    # installer should leave the environment consistent, not merely skip.
    publish_modulefile
    print_summary
    exit 0
  fi

  preflight
  load_toolchain
  fetch_source
  configure_build
  compile
  install_tree
  postinstall
  run_selftest      # against the staging tree: a broken build is never promoted
  commit_install
  publish_modulefile
  cleanup_build
  print_summary
}

main "$@"
