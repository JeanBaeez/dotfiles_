#!/usr/bin/env bats
# Unit tests for bootstrap.sh — exercises the pure, extracted functions by
# sourcing the script (the source-guard keeps main() from running, so no
# packages are installed and no files are touched).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  BOOTSTRAP="$REPO_ROOT/bootstrap.sh"
  # Source for function access. main() must NOT run (guarded on BASH_SOURCE==$0).
  source "$BOOTSTRAP"
}

# --- structural -------------------------------------------------------------

@test "bootstrap.sh is syntactically valid" {
  run bash -n "$BOOTSTRAP"
  [ "$status" -eq 0 ]
}

@test "sourcing does not execute main (no target resolution side effects)" {
  # resolve_target (called only from main) sets TARGET_USER; it must be unset here.
  [ -z "${TARGET_USER:-}" ]
  # ...but the functions are defined and callable.
  run type -t progress_bar_string
  [ "$output" = "function" ]
}

# --- progress_bar_string ----------------------------------------------------

@test "progress_bar_string: empty bar at 0%" {
  run progress_bar_string 0 4 20
  [ "$status" -eq 0 ]
  [[ "$output" == *"  0% (0/4)"* ]]
  local hashes="${output//[^#]/}"
  [ "${#hashes}" -eq 0 ]
}

@test "progress_bar_string: half-full bar at 50%" {
  run progress_bar_string 2 4 20
  [ "$status" -eq 0 ]
  [[ "$output" == *" 50% (2/4)"* ]]
  local hashes="${output//[^#]/}"
  [ "${#hashes}" -eq 10 ]
}

@test "progress_bar_string: full bar at 100%" {
  run progress_bar_string 4 4 20
  [ "$status" -eq 0 ]
  [[ "$output" == *"100% (4/4)"* ]]
  local hashes="${output//[^#]/}"
  [ "${#hashes}" -eq 20 ]
}

@test "progress_bar_string: clamps current above total" {
  run progress_bar_string 9 4 10
  [ "$status" -eq 0 ]
  [[ "$output" == *"100% (4/4)"* ]]
  # clamped to total => bar fully filled (width 10)
  local hashes="${output//[^#]/}"
  [ "${#hashes}" -eq 10 ]
}

@test "progress_bar_string: clamps negative current to zero" {
  run progress_bar_string -3 4 20
  [ "$status" -eq 0 ]
  [[ "$output" == *"  0% (0/4)"* ]]
  local hashes="${output//[^#]/}"
  [ "${#hashes}" -eq 0 ]
}

@test "progress_bar_string: survives zero total without dividing by zero" {
  run progress_bar_string 0 0 10
  [ "$status" -eq 0 ]
  [[ "$output" == *"(0/1)"* ]]
}

@test "progress_bar_string: default width is 28" {
  run progress_bar_string 4 4
  [ "$status" -eq 0 ]
  local hashes="${output//[^#]/}"
  [ "${#hashes}" -eq 28 ]
}

# --- install_with_progress --------------------------------------------------
# pm_install is stubbed per-test (bats runs each test in its own process and
# re-sources bootstrap.sh via setup, so the override is isolated). `run` makes
# stdout a pipe, so the non-TTY `[n/total] pkg` fallback branch is exercised.

@test "install_with_progress: reports per-package progress, no failure warning" {
  pm_install() { return 0; }
  run install_with_progress ok1 ok2
  [ "$status" -eq 0 ]
  [[ "$output" == *"[1/2] ok1"* ]]
  [[ "$output" == *"[2/2] ok2"* ]]
  [[ "$output" != *"could not be installed"* ]]
  [[ "$output" != *"Install log kept at:"* ]]
}

@test "install_with_progress: removes the temp install-log on a clean run" {
  pm_install() { return 0; }
  # Pin the mktemp log to a known path so we can assert it is cleaned up. The
  # -d form (used elsewhere) still goes to the real mktemp; the no-arg log form
  # returns our fixed path. The function writes to it via >>, then rm -f's it on
  # success — a leaked temp file on every clean run would leave it behind.
  local dir logf
  dir="$(command mktemp -d)"
  logf="$dir/install.log"
  mktemp() { [[ "$1" == -d ]] && { builtin command mktemp "$@"; return; }; printf '%s\n' "$logf"; }
  run install_with_progress ok1 ok2
  [ "$status" -eq 0 ]
  [ ! -e "$logf" ]
  rm -rf "$dir"
}

@test "install_with_progress: renders the progress bar and package name on a TTY" {
  command -v python3 >/dev/null 2>&1 || skip "python3 needed to allocate a pty"
  # Under bats `run`, stdout is a pipe so `[[ -t 1 ]]` is false and only the
  # non-TTY fallback runs. Drive the function through a pseudo-tty so the
  # single-line redraw path (which embeds progress_bar_string) is exercised.
  local script
  script='source "'"$BOOTSTRAP"'"; pm_install() { return 0; }; install_with_progress alpha beta'
  run python3 -c 'import pty,sys; pty.spawn(["bash","-c",sys.argv[1]])' "$script"
  [ "$status" -eq 0 ]
  # The redraw shows "installing <pkg>" and the bar with the (current/total)
  # counter from progress_bar_string. The first draw is (0/2); the final is
  # (2/2) — a swapped current/total in that call would not produce "(0/2)".
  [[ "$output" == *"installing alpha"* ]]
  [[ "$output" == *"(0/2)"* ]]
  [[ "$output" == *"(2/2)"* ]]
  [[ "$output" == *"["* ]]           # progress bar brackets are drawn
  [[ "$output" != *"[1/2] alpha"* ]] # not the non-TTY "[n/total] pkg" fallback
}

@test "install_with_progress: warns and keeps log when a package fails" {
  pm_install() { [[ "$1" == boom ]] && return 1 || return 0; }
  run install_with_progress ok boom
  [ "$status" -eq 0 ]
  [[ "$output" == *"Some packages could not be installed: boom"* ]]
  [[ "$output" == *"Install log kept at:"* ]]
  # the diagnostic log must actually survive on failure; verify then clean up.
  local logf
  logf="$(printf '%s\n' "$output" | sed -n 's/.*Install log kept at: //p')"
  [ -n "$logf" ]
  [ -f "$logf" ]
  rm -f "$logf"
}

@test "install_with_progress: no packages is a silent no-op" {
  pm_install() { return 1; }  # must never be invoked
  run install_with_progress
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- backup_then_copy -------------------------------------------------------
# The safety-critical backup-before-overwrite logic. Pure filesystem behavior,
# exercised in a throwaway temp dir. TIMESTAMP is set at source time.

@test "backup_then_copy: backs up an existing regular file, then copies src over it" {
  local tmp
  tmp="$(mktemp -d)"
  printf 'SRC\n' >"$tmp/src"
  printf 'OLD\n' >"$tmp/dst"
  run backup_then_copy "$tmp/src" "$tmp/dst"
  [ "$status" -eq 0 ]
  # original preserved under the timestamped backup name...
  [ -f "$tmp/dst.bak.$TIMESTAMP" ]
  [ "$(cat "$tmp/dst.bak.$TIMESTAMP")" = "OLD" ]
  # ...and src is now in place
  [ "$(cat "$tmp/dst")" = "SRC" ]
  rm -rf "$tmp"
}

@test "backup_then_copy: removes an existing symlink instead of backing it up" {
  local tmp
  tmp="$(mktemp -d)"
  printf 'SRC\n'  >"$tmp/src"
  printf 'REAL\n' >"$tmp/real"
  ln -s "$tmp/real" "$tmp/dst"
  run backup_then_copy "$tmp/src" "$tmp/dst"
  [ "$status" -eq 0 ]
  [ ! -e "$tmp/dst.bak.$TIMESTAMP" ]   # symlinks are not backed up
  [ ! -L "$tmp/dst" ]                  # link replaced by a real copy
  [ "$(cat "$tmp/dst")"  = "SRC" ]
  [ "$(cat "$tmp/real")" = "REAL" ]    # the link's old target is untouched
  rm -rf "$tmp"
}

@test "backup_then_copy: copies a directory source recursively" {
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/src/sub"
  printf 'A\n' >"$tmp/src/a.txt"
  printf 'B\n' >"$tmp/src/sub/b.txt"
  run backup_then_copy "$tmp/src" "$tmp/dst"
  [ "$status" -eq 0 ]
  [ -d "$tmp/dst" ]
  [ "$(cat "$tmp/dst/a.txt")"     = "A" ]
  [ "$(cat "$tmp/dst/sub/b.txt")" = "B" ]
  rm -rf "$tmp"
}

# --- resolve_target ---------------------------------------------------------

@test "resolve_target: aborts when the target user has no resolvable home" {
  # A user that cannot exist => getent yields nothing (or is absent) => the
  # home-resolution guard must exit non-zero with a diagnostic.
  TARGET_USER=__no_such_user_zzzq__
  run resolve_target
  [ "$status" -ne 0 ]
  [[ "$output" == *"Could not resolve home directory"* ]]
}

# --- map_arch ---------------------------------------------------------------

@test "map_arch: x86_64 and amd64 map to x86_64" {
  run map_arch x86_64
  [ "$status" -eq 0 ] && [ "$output" = "x86_64" ]
  run map_arch amd64
  [ "$status" -eq 0 ] && [ "$output" = "x86_64" ]
}

@test "map_arch: aarch64 and arm64 map to arm64" {
  run map_arch aarch64
  [ "$status" -eq 0 ] && [ "$output" = "arm64" ]
  run map_arch arm64
  [ "$status" -eq 0 ] && [ "$output" = "arm64" ]
}

@test "map_arch: unknown arch fails" {
  run map_arch riscv128
  [ "$status" -ne 0 ]
}

# --- nerd_font_url ----------------------------------------------------------

@test "nerd_font_url: defaults to FiraCode" {
  run nerd_font_url
  [ "$status" -eq 0 ]
  [ "$output" = "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip" ]
}

@test "nerd_font_url: honors an explicit font name" {
  run nerd_font_url JetBrainsMono
  [[ "$output" == *"/JetBrainsMono.zip" ]]
}

# --- set_packages -----------------------------------------------------------

@test "set_packages: fontconfig present for every package manager" {
  for pm in apt dnf pacman; do
    set_packages "$pm"
    printf '%s\n' "${PACKAGES[@]}" | grep -qx fontconfig \
      || { echo "fontconfig missing for $pm"; return 1; }
  done
}

@test "set_packages: core toolchain present for apt" {
  set_packages apt
  local expected=(zsh lsd tmux git nodejs npm python3 unzip curl)
  for pkg in "${expected[@]}"; do
    printf '%s\n' "${PACKAGES[@]}" | grep -qx "$pkg" \
      || { echo "missing $pkg for apt"; return 1; }
  done
}

@test "set_packages: language/compiler runtimes present for every package manager" {
  # CLAUDE.md invariant: nodejs, npm, a C compiler, python3/pip, and go must
  # appear in EVERY PM arm or a fresh nvim install errors on launch. Package
  # names differ per distro, so assert the exact per-PM names. (No associative
  # arrays — keep this runnable under bash 3.2, like the rest of the suite.)
  local pm expected pkg
  for pm in apt dnf pacman; do
    case "$pm" in
      apt)    expected="nodejs npm build-essential python3 python3-pip golang-go" ;;
      dnf)    expected="nodejs npm gcc make python3 python3-pip golang" ;;
      pacman) expected="nodejs npm base-devel python python-pip go" ;;
    esac
    set_packages "$pm"
    for pkg in $expected; do
      printf '%s\n' "${PACKAGES[@]}" | grep -qx "$pkg" \
        || { echo "missing $pkg for $pm"; return 1; }
    done
  done
}

@test "set_packages: distro-specific names (fd/fd-find, tldr/tealdeer)" {
  set_packages apt;    printf '%s\n' "${PACKAGES[@]}" | grep -qx fd-find
  set_packages pacman; printf '%s\n' "${PACKAGES[@]}" | grep -qx fd
  set_packages dnf;    printf '%s\n' "${PACKAGES[@]}" | grep -qx tealdeer
}

@test "set_packages: unknown manager fails with a diagnostic and leaves PACKAGES intact" {
  set_packages apt
  local before="${PACKAGES[*]}"
  run set_packages brew
  [ "$status" -ne 0 ]
  # the `*)` arm's user-facing diagnostic is the whole point of the branch
  [[ "$output" == *"unknown package manager 'brew'"* ]]
  # a direct (non-subshell) call confirms the error path does not partially
  # repopulate PACKAGES with a previous manager's list
  set_packages brew 2>/dev/null || true
  [ "${PACKAGES[*]}" = "$before" ]
}

# --- detect_pm --------------------------------------------------------------
# detect_pm probes the host with `command -v apt-get|dnf|pacman` and returns the
# first match in that fixed precedence order (bootstrap.sh). Stub `command -v` so
# the manager set is simulated rather than read from the runner's real OS — this
# lets us assert the deterministic apt>dnf>pacman winner and the no-manager case
# on any host (incl. the macOS dev box, which has none of the three).

# Make `command -v <bin>` succeed only for the binaries passed here; everything
# else (and every non `-v` invocation) falls through to the real builtin.
stub_command_for() {
  _available_bins=" $* "
  command() {
    if [[ "$1" == "-v" ]]; then
      case "$_available_bins" in
        *" $2 "*) printf '/usr/bin/%s\n' "$2"; return 0 ;;
        *) return 1 ;;
      esac
    fi
    builtin command "$@"
  }
}

@test "detect_pm: apt-only host selects apt" {
  stub_command_for apt-get
  run detect_pm
  [ "$status" -eq 0 ]
  [ "$output" = "apt" ]
}

@test "detect_pm: dnf-only host selects dnf" {
  stub_command_for dnf
  run detect_pm
  [ "$status" -eq 0 ]
  [ "$output" = "dnf" ]
}

@test "detect_pm: pacman-only host selects pacman" {
  stub_command_for pacman
  run detect_pm
  [ "$status" -eq 0 ]
  [ "$output" = "pacman" ]
}

@test "detect_pm: apt wins when apt and dnf are both present" {
  stub_command_for apt-get dnf
  run detect_pm
  [ "$status" -eq 0 ]
  [ "$output" = "apt" ]
}

@test "detect_pm: dnf wins over pacman when both are present" {
  stub_command_for dnf pacman
  run detect_pm
  [ "$status" -eq 0 ]
  [ "$output" = "dnf" ]
}

@test "detect_pm: no supported manager returns non-zero and emits nothing" {
  stub_command_for  # simulate a host with none of apt/dnf/pacman
  run detect_pm
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}
