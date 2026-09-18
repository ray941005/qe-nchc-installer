#!/usr/bin/env bash
# lib/postinstall.sh — make the installed tree usable and self-describing.
#
# Everything here writes into the *staging* directory, so the finished tree
# that gets swapped into place already contains its own environment script,
# modulefile and provenance manifest.

# render_template <template> <destination> — substitute @TOKEN@ placeholders.
render_template() {
  local tmpl=$1 dest=$2
  [[ -r $tmpl ]] || die "missing template: ${tmpl}"
  mkdir -p "$(dirname "$dest")"
  sed \
    -e "s|@QE_VERSION@|${QE_VERSION}|g" \
    -e "s|@PREFIX@|${QE_PREFIX}|g" \
    -e "s|@TOOLCHAIN_ID@|${QE_TOOLCHAIN_ID}|g" \
    -e "s|@TOOLCHAIN_MODULES@|${QE_TOOLCHAIN_MODULES[*]}|g" \
    -e "s|@QE_GIT_COMMIT@|${QE_GIT_COMMIT}|g" \
    -e "s|@BUILD_DATE@|${QE_BUILD_DATE}|g" \
    "$tmpl" > "$dest"
}

write_manifest() {
  local dest=$1
  local installer_commit="unknown" installer_dirty="unknown"
  if git -C "$QE_REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    installer_commit=$(git -C "$QE_REPO_DIR" rev-parse HEAD)
    if [[ -n $(git -C "$QE_REPO_DIR" status --porcelain) ]]; then
      installer_dirty="true"
    else
      installer_dirty="false"
    fi
  fi

  mkdir -p "$(dirname "$dest")"
  QE_M_INSTALLER_COMMIT=$installer_commit \
  QE_M_INSTALLER_DIRTY=$installer_dirty \
  QE_M_SUBMODULES=$QE_SUBMODULE_STATUS \
  QE_M_CMAKE_ARGS=$(printf '%s\n' "${QE_CMAKE_ARGS[@]}") \
  QE_M_FC_VERSION=$(tool_version "$QE_COMPILER") \
  QE_M_CC_VERSION=$(tool_version icx) \
  QE_M_MPI_VERSION=$(mpirun --version 2>&1 | head -n 1) \
  QE_M_CMAKE_VERSION=$(cmake --version | head -n 1) \
  QE_M_HOST=$(hostname) \
  QE_M_CPU=$(awk -F: '/model name/ {gsub(/^ +/,"",$2); print $2; exit}' /proc/cpuinfo) \
  QE_M_OS=$(sed -n 's/^PRETTY_NAME="\(.*\)"/\1/p' /etc/os-release) \
  QE_M_PWX_SHA=$(sha256sum "${QE_STAGING_DIR}/bin/pw.x" | awk '{print $1}') \
  QE_M_NBIN=$(find "${QE_STAGING_DIR}/bin" -maxdepth 1 -type f | wc -l) \
  python3 -c '
import json, os

def env(name, default=""):
    return os.environ.get(name, default)

submodules = {}
for line in env("QE_M_SUBMODULES").splitlines():
    if line.strip():
        path, sha = line.split()
        submodules[path] = sha

manifest = {
    "schema_version": 1,
    "generated_at": env("QE_BUILD_DATE"),
    "installer": {
        "name": "qe-nchc-installer",
        "commit": env("QE_M_INSTALLER_COMMIT"),
        "working_tree_dirty": env("QE_M_INSTALLER_DIRTY"),
        "invocation": env("QE_INVOCATION"),
    },
    "package": {
        "name": "quantum-espresso",
        "version": env("QE_VERSION"),
        "git_url": env("QE_GIT_URL"),
        "git_tag": env("QE_GIT_TAG"),
        "git_commit": env("QE_GIT_COMMIT"),
        "submodules": submodules,
    },
    "platform": {
        "id": env("QE_PLATFORM_ID"),
        "host": env("QE_M_HOST"),
        "os": env("QE_M_OS"),
        "cpu": env("QE_M_CPU"),
    },
    "toolchain": {
        "id": env("QE_TOOLCHAIN_ID"),
        "modules": env("QE_TOOLCHAIN_MODULES_STR").split(),
        "fortran_compiler": env("QE_COMPILER"),
        "fortran_wrapper": env("QE_FC_WRAPPER"),
        "fortran_version": env("QE_M_FC_VERSION"),
        "c_wrapper": env("QE_MPICC_WRAPPER"),
        "c_version": env("QE_M_CC_VERSION"),
        "mpi": env("QE_M_MPI_VERSION"),
        "mkl_root": env("MKLROOT"),
        "arch_flags": env("QE_ARCH_FLAGS"),
    },
    "build": {
        "cmake": env("QE_M_CMAKE_VERSION"),
        "cmake_args": [a for a in env("QE_M_CMAKE_ARGS").splitlines() if a],
        "parallel_jobs": int(env("QE_JOBS", "0")),
    },
    "install": {
        "prefix": env("QE_PREFIX"),
        "executables": int(env("QE_M_NBIN", "0")),
        "pw_x_sha256": env("QE_M_PWX_SHA"),
    },
}
print(json.dumps(manifest, indent=2, ensure_ascii=False))
' > "$dest" || die "failed to write manifest"

  log_debug "manifest written to ${dest}"
}

postinstall() {
  log_phase "Post-install"

  local share_dir=$QE_STAGING_DIR/share/quantum-espresso

  render_template "$QE_REPO_DIR/share/qe-env.sh.tmpl" "$QE_STAGING_DIR/etc/qe-env.sh"
  chmod 0644 "$QE_STAGING_DIR/etc/qe-env.sh"
  log_info "environment script: ${QE_PREFIX}/etc/qe-env.sh"

  render_template "$QE_REPO_DIR/share/modulefile.lua.tmpl" \
    "$share_dir/modulefile/${QE_VERSION}-${QE_TOOLCHAIN_ID}.lua"

  write_manifest "$share_dir/manifest.json"

  log_ok "post-install complete"
}

# Copy the generated modulefile to a stable, prefix-independent location so
# that `module use` only ever needs one directory.
#
# Deliberately called only after the install has been committed: publishing it
# earlier would leave a modulefile pointing at a prefix that does not exist if
# the self-test then fails.
publish_modulefile() {
  local src=$QE_PREFIX/share/quantum-espresso/modulefile/${QE_VERSION}-${QE_TOOLCHAIN_ID}.lua
  QE_MODULEFILE=$QE_MODULEFILE_DIR/quantum-espresso/${QE_VERSION}-${QE_TOOLCHAIN_ID}.lua
  mkdir -p "$(dirname "$QE_MODULEFILE")"
  cp "$src" "$QE_MODULEFILE"
  log_ok "modulefile published: ${QE_MODULEFILE}"
}
