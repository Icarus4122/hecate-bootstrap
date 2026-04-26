#!/usr/bin/env bash
# tests/test_release_evidence.sh
#
# Verifies scripts/dev/release-evidence.sh:
#
#   1. Emits Git, Docker, Empusa contract, and Binary checksum sections.
#   2. Warns (does not fail) when docker is not on PATH.
#   3. Reports mutable :latest Dockerfile FROM as [WARN].
#   4. Includes Empusa source version when path is supplied.
#   5. --strict + dirty worktree → nonzero exit ([FAIL]).
#   6. --out FILE writes the full report to FILE.
#   7. --strict + not-in-git → nonzero exit ([FAIL]); default → [WARN].
#   8. --strict + missing release-sanity.sh → nonzero exit ([FAIL]); default → [WARN].
#   9. --strict + Empusa version mismatch → nonzero exit ([FAIL]); default → [WARN].
#
# No Docker, no network required.  Uses an isolated PATH so docker is
# guaranteed missing and a fresh git repo so dirty/clean is controllable.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/helpers.sh
source "$TESTS_DIR/helpers.sh"
begin_tests "release-evidence collector"

REPO_DIR="$(dirname "$TESTS_DIR")"
SCRIPT="$REPO_DIR/scripts/dev/release-evidence.sh"
assert_file_exists "$SCRIPT" "release-evidence.sh present"

EXPECTED=$(grep -E '^EXPECTED_EMPUSA_VERSION=' "$REPO_DIR/scripts/dev/release-sanity.sh" \
    | head -1 | sed -E 's/.*"([^"]+)".*/\1/')

make_sandbox

# Build a stub Hecate repo: scripts/dev/release-{evidence,sanity}.sh,
# manifests/binaries.tsv, docker/*/Dockerfile, plus a fresh git history
# so worktree state is deterministic.
build_stub_hecate() {
    local hroot="$1" mutable_latest="$2" manifest_body="$3"
    mkdir -p "$hroot/scripts/dev" "$hroot/manifests" \
             "$hroot/docker/kali-main" "$hroot/docker/builder"
    cp "$SCRIPT" "$hroot/scripts/dev/release-evidence.sh"
    cp "$REPO_DIR/scripts/dev/release-sanity.sh" "$hroot/scripts/dev/release-sanity.sh"
    chmod +x "$hroot/scripts/dev"/*.sh

    if [[ "$mutable_latest" == "yes" ]]; then
        cat > "$hroot/docker/kali-main/Dockerfile" <<'EOF'
FROM kalilinux/kali-rolling:latest
RUN echo hi
EOF
    else
        cat > "$hroot/docker/kali-main/Dockerfile" <<'EOF'
FROM kalilinux/kali-rolling@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
RUN echo hi
EOF
    fi
    cat > "$hroot/docker/builder/Dockerfile" <<'EOF'
FROM ubuntu:24.04
RUN echo hi
EOF
    printf '%s' "$manifest_body" > "$hroot/manifests/binaries.tsv"

    # Initialise a clean git repo so worktree state is deterministic.
    (
        cd "$hroot"
        git init -q
        git config user.email t@t
        git config user.name t
        git add -A
        git commit -q -m init
    )
}

# Run with docker scrubbed from PATH so the script's docker-missing
# branch is exercised.  We keep everything else (git, sed, awk, grep)
# because release-evidence depends on them.
make_no_docker_path() {
    local out="" entry
    local IFS=':'
    for entry in $PATH; do
        [[ -z "$entry" ]] && continue
        if [[ -x "$entry/docker" || -x "$entry/docker.exe" ]]; then
            continue
        fi
        out+="$entry:"
    done
    printf '%s' "${out%:}"
}
NO_DOCKER_PATH="$(make_no_docker_path)"

run_evidence() {
    local hroot="$1"
    shift
    set +e
    OUT=$(PATH="$NO_DOCKER_PATH" \
          bash "$hroot/scripts/dev/release-evidence.sh" "$@" 2>&1)
    RC=$?
    set -e
}

TAB=$'\t'
HEADER="name${TAB}type${TAB}repo${TAB}tag${TAB}mode${TAB}dest${TAB}flags${TAB}sha256"
GOOD_HEX="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
MIXED_TSV="$HEADER"$'\n'"toolP${TAB}github-release${TAB}o/r${TAB}v1${TAB}toolP_linux${TAB}toolP${TAB}executable${TAB}${GOOD_HEX}"$'\n'"toolT${TAB}github-release${TAB}o/r${TAB}v1${TAB}all-assets${TAB}toolT/v1${TAB}-${TAB}TODO_SHA256"$'\n'

# ── 1. Section emission, mutable :latest WARN, docker-missing WARN ─
H1="$SANDBOX/h1"
build_stub_hecate "$H1" "yes" "$MIXED_TSV"
run_evidence "$H1"
assert_exit_code "0" "$RC" "default run: exit 0 even without docker"
assert_contains "$OUT" "── Git ──" "section: Git"
assert_contains "$OUT" "── Docker ──" "section: Docker"
assert_contains "$OUT" "── Docker base image evidence ──" "section: Docker base image evidence"
assert_contains "$OUT" "── Empusa contract ──" "section: Empusa contract"
assert_contains "$OUT" "── Binary checksums ──" "section: Binary checksums"
assert_contains "$OUT" "[WARN] docker not installed" "docker-missing: WARN line"
assert_contains "$OUT" "uses mutable tag :latest" "mutable :latest: WARN"
assert_contains "$OUT" "[PASS] toolP: sha256 pinned" "checksums: pinned PASS"
assert_contains "$OUT" "[WARN] toolT: TODO_SHA256 (mode=all-assets" \
    "checksums: all-assets TODO WARN"
assert_contains "$OUT" "[INFO] expected Empusa contract version: ${EXPECTED}" \
    "Empusa: expected version printed"

# ── 2. Empusa supplied → source version line ───────────────────────
H2="$SANDBOX/h2"; E2="$SANDBOX/e2"
build_stub_hecate "$H2" "no" "$MIXED_TSV"
mkdir -p "$E2"
cat > "$E2/pyproject.toml" <<EOF
[project]
name = "empusa"
version = "${EXPECTED}"
EOF
run_evidence "$H2" "$E2"
assert_contains "$OUT" "Empusa source version (pyproject.toml): ${EXPECTED}" \
    "Empusa-supplied: version line"
assert_contains "$OUT" "[PASS] Empusa source matches expected contract version" \
    "Empusa-supplied: PASS line"

# ── 3. Digest-pinned Dockerfile → no mutable WARN ──────────────────
assert_not_contains "$OUT" "uses mutable tag :latest" \
    "digest-pinned: no mutable WARN for kali-main"

# ── 4. --strict + dirty worktree → FAIL ────────────────────────────
H4="$SANDBOX/h4"
build_stub_hecate "$H4" "no" "$MIXED_TSV"
echo "dirty" > "$H4/dirty.txt"   # untracked file → dirty
run_evidence "$H4" --strict
assert_neq "0" "$RC" "strict+dirty: nonzero exit"
assert_contains "$OUT" "[FAIL] worktree dirty (strict mode)" \
    "strict+dirty: FAIL line"

# ── 5. --strict + clean → exit 0 ──────────────────────────────────
H5="$SANDBOX/h5"
build_stub_hecate "$H5" "no" "$MIXED_TSV"
run_evidence "$H5" --strict
assert_exit_code "0" "$RC" "strict+clean: exit 0"
assert_contains "$OUT" "[PASS] worktree clean" "strict+clean: PASS line"

# ── 6. --out FILE writes report ────────────────────────────────────
H6="$SANDBOX/h6"
build_stub_hecate "$H6" "yes" "$MIXED_TSV"
OUT_FILE="$SANDBOX/out6.txt"
run_evidence "$H6" --out "$OUT_FILE"
assert_file_exists "$OUT_FILE" "out flag: file written"
file_body="$(cat "$OUT_FILE")"
assert_contains "$file_body" "── Git ──" "out file: contains Git section"
assert_contains "$file_body" "── Binary checksums ──" \
    "out file: contains Binary checksums section"

# ── 7. docker unavailable → digest evidence skipped WARN ───────────
assert_contains "$OUT" "[WARN] docker unavailable; digest evidence skipped" \
    "no-docker: digest evidence skipped WARN"

# ── 8. Mocked docker: RepoDigests present → [INFO] local RepoDigest ─
H8="$SANDBOX/h8"
build_stub_hecate "$H8" "yes" "$MIXED_TSV"
MOCK_BIN="$SANDBOX/mockbin8"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/docker" <<'EOF'
#!/usr/bin/env bash
# Mock docker: returns a fake digest for kalilinux/kali-rolling:latest only.
case "$*" in
    "--version") echo "Docker version 99.0.0-mock, build mock" ;;
    "compose version") echo "Docker Compose version v2.0.0-mock" ;;
    "image inspect --format "*"kalilinux/kali-rolling:latest")
        echo "kalilinux/kali-rolling@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$MOCK_BIN/docker"
set +e
OUT=$(PATH="$MOCK_BIN:$NO_DOCKER_PATH" \
      bash "$H8/scripts/dev/release-evidence.sh" 2>&1)
RC=$?
set -e
assert_exit_code "0" "$RC" "mock-docker: exit 0"
assert_contains "$OUT" "[INFO]   local RepoDigest: kalilinux/kali-rolling@sha256:aaaa" \
    "mock-docker: RepoDigest line printed"
assert_not_contains "$OUT" "[WARN] docker unavailable; digest evidence skipped" \
    "mock-docker: no docker-unavailable WARN"
# ubuntu:24.04 isn't known to the mock → should report digest unavailable locally
assert_contains "$OUT" "[WARN]   digest unavailable locally" \
    "mock-docker: missing image → digest-unavailable WARN"

# ── 9. Digest-pinned FROM emits [PASS] digest pinned ──────────────
H9="$SANDBOX/h9"
build_stub_hecate "$H9" "no" "$MIXED_TSV"
run_evidence "$H9"
assert_contains "$OUT" "[PASS]   digest pinned" \
    "digest-pinned FROM: PASS digest pinned line"

# ── 10. Multiple Dockerfiles handled ───────────────────────────────
assert_contains "$OUT" "docker/kali-main/Dockerfile -> FROM" \
    "multiple Dockerfiles: kali-main listed"
assert_contains "$OUT" "docker/builder/Dockerfile -> FROM" \
    "multiple Dockerfiles: builder listed"

# ── 11. Not in git repo: default WARN, --strict FAIL ──────────────
H11="$SANDBOX/h11"
build_stub_hecate "$H11" "no" "$MIXED_TSV"
rm -rf "$H11/.git"
run_evidence "$H11"
assert_exit_code "0" "$RC" "no-git default: exit 0"
assert_contains "$OUT" "[WARN] not a git repository" \
    "no-git default: WARN line"
run_evidence "$H11" --strict
assert_neq "0" "$RC" "no-git strict: nonzero exit"
assert_contains "$OUT" "[FAIL] not a git repository (strict mode)" \
    "no-git strict: FAIL line"

# ── 12. Missing release-sanity.sh: default WARN, --strict FAIL ────
H12="$SANDBOX/h12"
build_stub_hecate "$H12" "no" "$MIXED_TSV"
rm -f "$H12/scripts/dev/release-sanity.sh"
# re-stage so worktree stays clean for the strict-mode run
(cd "$H12" && git add -A && git commit -q -m "drop sanity")
run_evidence "$H12"
assert_exit_code "0" "$RC" "no-sanity default: exit 0"
assert_contains "$OUT" "[WARN] release-sanity.sh not found" \
    "no-sanity default: WARN line"
run_evidence "$H12" --strict
assert_neq "0" "$RC" "no-sanity strict: nonzero exit"
assert_contains "$OUT" "[FAIL] release-sanity.sh not found" \
    "no-sanity strict: FAIL line"

# ── 13. Empusa version mismatch: default WARN, --strict FAIL ──────
H13="$SANDBOX/h13"; E13="$SANDBOX/e13"
build_stub_hecate "$H13" "no" "$MIXED_TSV"
mkdir -p "$E13"
cat > "$E13/pyproject.toml" <<EOF
[project]
name = "empusa"
version = "0.0.0-mismatch"
EOF
run_evidence "$H13" "$E13"
assert_exit_code "0" "$RC" "empusa-mismatch default: exit 0"
assert_contains "$OUT" "[WARN] Empusa source version 0.0.0-mismatch != expected ${EXPECTED}" \
    "empusa-mismatch default: WARN line"
run_evidence "$H13" --strict "$E13"
assert_neq "0" "$RC" "empusa-mismatch strict: nonzero exit"
assert_contains "$OUT" "[FAIL] Empusa source version 0.0.0-mismatch != expected ${EXPECTED} (strict mode)" \
    "empusa-mismatch strict: FAIL line"

end_tests
