#!/usr/bin/env bash
# lib/selftest.sh — prove the installed binaries actually work.
#
# "It compiled" is not the same as "it runs". The smoke test runs a real SCF
# calculation under MPI and checks the total energy against a known value, so
# a build that links but produces garbage (wrong BLAS, broken MPI, bad
# optimisation flags) is caught here rather than by a user three weeks later.

# Run in the staging tree so that a failed test never gets promoted to $PREFIX.
selftest_smoke() {
  log_phase "Smoke test"

  # shellcheck source=/dev/null
  source "$QE_REPO_DIR/tests/smoke/expected.sh"

  local workdir=$QE_BUILD_ROOT/selftest.$$
  rm -rf "$workdir"; mkdir -p "$workdir"

  cp "$QE_REPO_DIR/tests/smoke/si.scf.in" "$workdir/"
  cp "$QE_REPO_DIR/tests/smoke/Si.pz-vbc.UPF" "$workdir/"
  verify_sha256 "$workdir/Si.pz-vbc.UPF" "$QE_SMOKE_PSEUDO_SHA256"

  local pw=$QE_STAGING_DIR/bin/pw.x
  [[ -x $pw ]] || die "smoke test cannot find ${pw}"

  # One thread per rank keeps the result bit-comparable across machines with
  # different core counts; production runs should of course use more.
  local -a launcher
  if [[ -n ${SLURM_JOB_ID:-} ]]; then
    launcher=(srun --ntasks=2 --cpus-per-task=1)
  else
    launcher=(mpirun -np 2)
  fi

  log_info "running: ${launcher[*]} pw.x -in si.scf.in"
  local rc=0
  (
    cd "$workdir"
    OMP_NUM_THREADS=1 "${launcher[@]}" "$pw" -in si.scf.in
  ) >"$workdir/si.scf.out" 2>&1 || rc=$?

  if (( rc != 0 )); then
    log_error "pw.x exited with status ${rc}"
    tail -n 25 "$workdir/si.scf.out" >&2
    die "smoke test failed; full output kept at ${workdir}/si.scf.out"
  fi

  grep -q 'JOB DONE' "$workdir/si.scf.out" ||
    { tail -n 25 "$workdir/si.scf.out" >&2
      die "pw.x did not reach 'JOB DONE'; output kept at ${workdir}/si.scf.out"; }

  local energy
  energy=$(awk '/^!.*total energy/ {print $5}' "$workdir/si.scf.out" | tail -n 1)
  [[ -n $energy ]] ||
    die "could not read the total energy from ${workdir}/si.scf.out"

  # bc is not guaranteed on a minimal RHEL image; awk is.
  local verdict
  verdict=$(awk -v got="$energy" -v want="$QE_SMOKE_ENERGY_RY" -v tol="$QE_SMOKE_ENERGY_TOL_RY" \
    'BEGIN { d = got - want; if (d < 0) d = -d; printf "%s %.3e", (d <= tol ? "PASS" : "FAIL"), d }')

  local status=${verdict%% *} delta=${verdict##* }
  if [[ $status != PASS ]]; then
    log_error "total energy ${energy} Ry differs from reference ${QE_SMOKE_ENERGY_RY} Ry by ${delta} Ry"
    log_error "(tolerance ${QE_SMOKE_ENERGY_TOL_RY} Ry) — output kept at ${workdir}/si.scf.out"
    die "smoke test failed: numerically wrong result"
  fi

  log_ok "SCF total energy ${energy} Ry (reference ${QE_SMOKE_ENERGY_RY} Ry, Δ=${delta} Ry)"
  rm -rf "$workdir"
}

# The upstream regression suite. Much slower, and it needs the build tree, so
# it is opt-in via --test full.
selftest_full() {
  log_phase "Upstream test-suite (ctest)"
  [[ -d $QE_BUILD_DIR ]] ||
    die "--test full needs the build tree; re-run with --keep-build"
  log_info "running ctest -L pw (this takes a while)"
  run_logged "$QE_LOG_DIR/ctest.log" \
    ctest --test-dir "$QE_BUILD_DIR" -L pw --output-on-failure -j 4 ||
    die "ctest reported failures; see ${QE_LOG_DIR}/ctest.log"
  log_ok "upstream pw test-suite passed"
}

run_selftest() {
  case $QE_TEST_MODE in
    none)  log_info "skipping self-test (--test none)" ;;
    smoke) selftest_smoke ;;
    full)  selftest_smoke; selftest_full ;;
    *)     die "unknown test mode: ${QE_TEST_MODE}" ;;
  esac
}
