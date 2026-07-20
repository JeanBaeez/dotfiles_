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

@test "set_packages: distro-specific names (fd/fd-find, tldr/tealdeer)" {
  set_packages apt;    printf '%s\n' "${PACKAGES[@]}" | grep -qx fd-find
  set_packages pacman; printf '%s\n' "${PACKAGES[@]}" | grep -qx fd
  set_packages dnf;    printf '%s\n' "${PACKAGES[@]}" | grep -qx tealdeer
}

@test "set_packages: unknown manager fails" {
  run set_packages brew
  [ "$status" -ne 0 ]
}

# --- detect_pm --------------------------------------------------------------

@test "detect_pm: returns a supported manager or fails cleanly" {
  if run detect_pm && [ "$status" -eq 0 ]; then
    [[ "$output" =~ ^(apt|dnf|pacman)$ ]]
  else
    skip "no supported package manager on this host"
  fi
}
