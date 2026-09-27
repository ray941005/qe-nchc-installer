#!/usr/bin/env bash
# lib/build.sh — configure, compile and install Quantum ESPRESSO.

# Kept in an array so the manifest can record it verbatim.
declare -a QE_CMAKE_ARGS=()

configure_build() {
  log_phase "Configure"

  QE_CMAKE_ARGS=(
    -S "$QE_SRC_DIR"
    -B "$QE_BUILD_DIR"
    -DCMAKE_BUILD_TYPE=Release
    # Configure against the final location so any path CMake bakes in is
    # correct; the staging directory below is only for the atomic swap.
    -DCMAKE_INSTALL_PREFIX="$QE_PREFIX"
    -DCMAKE_C_COMPILER="$QE_MPICC_WRAPPER"
    -DCMAKE_Fortran_COMPILER="$QE_FC_WRAPPER"
    -DCMAKE_C_FLAGS="$QE_ARCH_FLAGS"
    -DCMAKE_Fortran_FLAGS="$QE_ARCH_FLAGS"
    -DQE_ENABLE_MPI=ON
    -DQE_ENABLE_OPENMP=ON
    -DQE_ENABLE_SCALAPACK=ON
    # Intel10_64lp = MKL, LP64, threaded. Covers BLAS, LAPACK,
    # ScaLAPACK/BLACS and the FFTW3 interface in one go.
    -DBLA_VENDOR=Intel10_64lp
  )

  # A stale CMake cache would silently keep the previous settings.
  if [[ -f $QE_BUILD_DIR/CMakeCache.txt ]] && [[ $QE_FORCE == 1 ]]; then
    log_info "--force given: removing stale build directory"
    rm -rf "$QE_BUILD_DIR"
  fi
  mkdir -p "$QE_BUILD_DIR"

  log_info "cmake ${QE_CMAKE_ARGS[*]}"
  run_logged "$QE_LOG_DIR/configure.log" cmake "${QE_CMAKE_ARGS[@]}" ||
    die "CMake configuration failed; see ${QE_LOG_DIR}/configure.log"

  log_ok "configured (${QE_FC_WRAPPER} -> $(tool_version "$QE_COMPILER"))"
}

compile() {
  log_phase "Compile"
  warn_if_heavy_on_login_node

  log_info "building with ${QE_JOBS} parallel jobs (this takes 5-15 minutes)"
  local start=$SECONDS
  run_logged "$QE_LOG_DIR/build.log" cmake --build "$QE_BUILD_DIR" -j "$QE_JOBS" ||
    die "build failed; see ${QE_LOG_DIR}/build.log"
  log_ok "compiled in $(( (SECONDS - start) / 60 ))m $(( (SECONDS - start) % 60 ))s"
}

# Install into a staging directory next to the final prefix, then swap it in
# with a rename, so an interrupted install leaves no half-written tree.
install_tree() {
  log_phase "Install"

  local staging=${QE_PREFIX}.stage.$$
  local previous=${QE_PREFIX}.previous.$$
  rm -rf "$staging"

  run_logged "$QE_LOG_DIR/install.log" \
    cmake --install "$QE_BUILD_DIR" --prefix "$staging" ||
    die "install step failed; see ${QE_LOG_DIR}/install.log"

  [[ -x $staging/bin/pw.x ]] ||
    die "install produced no ${staging}/bin/pw.x — aborting before touching ${QE_PREFIX}"

  QE_STAGING_DIR=$staging
  QE_PREVIOUS_DIR=$previous
  log_ok "staged $(find "$staging/bin" -maxdepth 1 -type f | wc -l) executables in ${staging}"
}

# Runs after postinstall has filled the staging tree, so what appears at
# $QE_PREFIX is complete.
commit_install() {
  if [[ -d $QE_PREFIX ]]; then
    log_info "replacing existing installation at ${QE_PREFIX}"
    mv "$QE_PREFIX" "$QE_PREVIOUS_DIR"
  fi
  mv "$QE_STAGING_DIR" "$QE_PREFIX"
  rm -rf "$QE_PREVIOUS_DIR"
  log_ok "installed to ${QE_PREFIX}"
}

cleanup_build() {
  if [[ $QE_KEEP_BUILD == 1 ]]; then
    log_info "keeping build tree at ${QE_BUILD_DIR} (--keep-build)"
    return 0
  fi
  log_info "removing build tree ${QE_BUILD_DIR}"
  rm -rf "$QE_BUILD_DIR"
}
