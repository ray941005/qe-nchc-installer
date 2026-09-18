#!/usr/bin/env bash
# lib/source.sh — obtain exactly the sources we pinned, and prove it.
#
# Why git and not the release tarball: GitLab's generated source archives do
# not contain the git submodules under external/ (devxlib, fox, mbd, lapack,
# wannier90, ...), and their checksums are not guaranteed stable over time.
# A tag plus a commit hash is content-addressed and verifiable forever, and
# the submodule pointers recorded in the tree pin the dependencies too.

fetch_source() {
  log_phase "Fetch source"

  local src=$QE_SRC_DIR

  if [[ -d $src/.git ]]; then
    local head
    head=$(git -C "$src" rev-parse HEAD 2>/dev/null || printf 'unknown')
    if [[ $head == "$QE_GIT_COMMIT" ]]; then
      log_info "reusing existing source tree at ${src} (${head:0:12})"
    else
      log_warn "source tree at ${src} is at ${head:0:12}, expected ${QE_GIT_COMMIT:0:12}"
      log_warn "discarding it and re-cloning"
      rm -rf "$src"
    fi
  elif [[ -e $src ]]; then
    log_warn "${src} exists but is not a git checkout; discarding it"
    rm -rf "$src"
  fi

  if [[ ! -d $src/.git ]]; then
    mkdir -p "$(dirname "$src")"
    log_info "cloning ${QE_GIT_URL} at tag ${QE_GIT_TAG}"
    retry 3 10 git -c advice.detachedHead=false clone \
      --quiet --depth 1 --branch "$QE_GIT_TAG" "$QE_GIT_URL" "$src" ||
      die "failed to clone ${QE_GIT_URL}"
  fi

  # The tag could be moved upstream; the commit hash cannot lie.
  local actual
  actual=$(git -C "$src" rev-parse HEAD)
  if [[ $actual != "$QE_GIT_COMMIT" ]]; then
    log_error "source commit mismatch for tag ${QE_GIT_TAG}"
    log_error "  pinned:  ${QE_GIT_COMMIT}"
    log_error "  fetched: ${actual}"
    die "refusing to build unverified sources"
  fi
  log_ok "source verified at ${QE_GIT_COMMIT}"

  # Submodule revisions come from the verified tree itself, so initialising
  # them adds no new trust assumption. Shallow fetches keep this to ~20 s.
  log_info "initialising external/ submodules (pinned by the QE tree)"
  retry 3 10 git -C "$src" submodule update --init --recursive --depth 1 --quiet ||
    die "failed to initialise QE submodules"

  # '+' means "checked out at a revision other than the recorded one".
  local dirty
  dirty=$(git -C "$src" submodule status --recursive | grep -c '^+' || true)
  (( dirty == 0 )) || die "${dirty} submodule(s) are not at their recorded revision"

  QE_SUBMODULE_STATUS=$(git -C "$src" submodule status | awk '{printf "%s %s\n", $2, $1}')
  log_ok "submodules pinned:"
  printf '%s\n' "$QE_SUBMODULE_STATUS" | sed 's/^/        /' >&2
}
