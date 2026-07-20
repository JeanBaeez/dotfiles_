#!/usr/bin/env bats
# Content tests for the shipped dotfiles: they guard the two regressions this
# change fixes — lsd icon aliases being shadowed by Kali's coreutils ls aliases,
# and the README documenting the client-side Nerd Font requirement.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  ZSHRC="$REPO_ROOT/.zshrc"
  README="$REPO_ROOT/README.md"
}

@test ".zshrc is valid zsh syntax" {
  if ! command -v zsh >/dev/null 2>&1; then skip "zsh not installed"; fi
  run zsh -n "$ZSHRC"
  [ "$status" -eq 0 ]
}

@test ".zshrc: lla is an lsd alias with icons" {
  run grep -E "alias lla='lsd .*--icon always'" "$ZSHRC"
  [ "$status" -eq 0 ]
}

@test ".zshrc: lsd aliases win over coreutils ls aliases (defined later)" {
  # The coreutils `ll` (ls -l) must appear BEFORE the lsd `lla`, so lsd wins.
  local coreutils_line lsd_line
  coreutils_line="$(grep -n "^alias ll='ls -l'" "$ZSHRC" | head -1 | cut -d: -f1)"
  lsd_line="$(grep -n "alias lla='lsd" "$ZSHRC" | head -1 | cut -d: -f1)"
  [ -n "$coreutils_line" ]
  [ -n "$lsd_line" ]
  [ "$lsd_line" -gt "$coreutils_line" ]
}

@test ".zshrc: lsd aliases are guarded by a lsd availability check" {
  run grep -E "command -v lsd >/dev/null 2>&1" "$ZSHRC"
  [ "$status" -eq 0 ]
}

@test ".zshrc: no invalid --group-dirs=aliasesfirst value remains" {
  run grep -F "group-dirs=aliasesfirst" "$ZSHRC"
  [ "$status" -ne 0 ]
}

@test "README documents the FiraCode Nerd Font and the local-terminal step" {
  run grep -qi "FiraCode Nerd Font" "$README"
  [ "$status" -eq 0 ]
  run grep -qiE "local terminal|terminal font" "$README"
  [ "$status" -eq 0 ]
}
