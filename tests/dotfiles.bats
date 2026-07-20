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

@test ".zshrc: each lsd alias carries its exact expected flags" {
  # Test 25 only pins `lla`, and the ordering/guard tests never check flags, so a
  # typo (a dropped `--icon always`, a broken `--group-dirs` value, or a mangled
  # `lt` tree flag) would go unnoticed. Assert every lsd alias' full definition.
  # Note `ls`/`l` intentionally omit `--icon always` while ll/la/lla/lt include
  # it — this asymmetry is deliberate and must be preserved.
  local def
  for def in \
    "alias ls='lsd --group-dirs first'" \
    "alias l='lsd --group-dirs first'" \
    "alias ll='lsd -lh --group-dirs first --icon always'" \
    "alias la='lsd -A --group-dirs first --icon always'" \
    "alias lla='lsd -lhA --group-dirs first --icon always'" \
    "alias lt='lsd --tree --depth 2 --icon always'"; do
    run grep -F "$def" "$ZSHRC"
    [ "$status" -eq 0 ]
  done
}

@test ".zshrc: lsd aliases win over coreutils ls aliases (defined later)" {
  # For each same-named alias (ll/la/l), the lsd redefinition must appear AFTER
  # its coreutils counterpart so lsd wins. Comparing the same name is what
  # actually guards against the shadowing regression.
  local name coreutils_pat lsd_pat coreutils_line lsd_line
  for name in ls ll la l; do
    case "$name" in
      ls) coreutils_pat="^    alias ls='ls --color=auto'" ;;
      ll) coreutils_pat="^alias ll='ls -l'" ;;
      la) coreutils_pat="^alias la='ls -A'" ;;
      l)  coreutils_pat="^alias l='ls -CF'" ;;
    esac
    lsd_pat="^  alias ${name}='lsd"
    coreutils_line="$(grep -nE "$coreutils_pat" "$ZSHRC" | head -1 | cut -d: -f1)"
    lsd_line="$(grep -nE "$lsd_pat" "$ZSHRC" | head -1 | cut -d: -f1)"
    [ -n "$coreutils_line" ]
    [ -n "$lsd_line" ]
    [ "$lsd_line" -gt "$coreutils_line" ]
  done
}

@test ".zshrc: lsd aliases are guarded by a lsd availability check" {
  # The lsd `alias ...='lsd ...'` definitions must sit INSIDE the
  # `if command -v lsd; ...; fi` guard, not merely coexist with the guard
  # string somewhere in the file. Otherwise `ls`/`ll` would alias to lsd on a
  # host without lsd, breaking `ls` entirely.
  local guard_line first_lsd_line last_lsd_line fi_line
  guard_line="$(grep -nE "^if command -v lsd >/dev/null 2>&1; then" "$ZSHRC" | head -1 | cut -d: -f1)"
  first_lsd_line="$(grep -nE "^  alias [a-z]+='lsd" "$ZSHRC" | head -1 | cut -d: -f1)"
  last_lsd_line="$(grep -nE "^  alias [a-z]+='lsd" "$ZSHRC" | tail -1 | cut -d: -f1)"
  # First `fi` at column 0 after the guard closes the block.
  fi_line="$(awk -v g="$guard_line" 'NR>g && /^fi$/ {print NR; exit}' "$ZSHRC")"
  [ -n "$guard_line" ]
  [ -n "$first_lsd_line" ]
  [ -n "$last_lsd_line" ]
  [ -n "$fi_line" ]
  # Guard opens before the aliases, which all precede the closing `fi`.
  [ "$guard_line" -lt "$first_lsd_line" ]
  [ "$last_lsd_line" -lt "$fi_line" ]
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

@test ".zshrc: cat/catn/catnp derive from a single detected bat binary (batcat or bat)" {
  # The bat alias block is the cross-distro sibling of the lsd fix: batcat on
  # apt, bat on dnf/pacman. All three aliases must use the one detected binary,
  # and no stale unconditional 'alias cat=batcat' (broken on dnf/pacman) may remain.
  run grep -E "command -v batcat" "$ZSHRC";          [ "$status" -eq 0 ]
  run grep -E "command -v bat >/dev/null" "$ZSHRC";  [ "$status" -eq 0 ]
  run grep -F 'alias cat="$_bat_bin"' "$ZSHRC";                        [ "$status" -eq 0 ]
  run grep -F 'alias catn="$_bat_bin --style=plain"' "$ZSHRC";         [ "$status" -eq 0 ]
  run grep -F 'alias catnp="$_bat_bin --style=plain --paging=never"' "$ZSHRC"; [ "$status" -eq 0 ]
  # no stale hardcoded aliases
  run grep -E "^alias cat='batcat'" "$ZSHRC";  [ "$status" -ne 0 ]
  run grep -E "^alias catn='bat " "$ZSHRC";    [ "$status" -ne 0 ]
}
