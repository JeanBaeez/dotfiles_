#!/usr/bin/env bats
# Tests for the Claude Code skills step of bootstrap.sh. Offline: the upstream UI
# skills repo is a local fixture, and TARGET_HOME is a temporary folder.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  source "$REPO_ROOT/bootstrap.sh"
  DOTFILES_DIR="$REPO_ROOT"
  TARGET_USER="$(id -un)"
  TARGET_GROUP="$(id -gn)"
  TARGET_HOME="$(mktemp -d)"
  TIMESTAMP="test1"

  # A stand-in for the upstream UI skills repository.
  FIXTURE="$(mktemp -d)"
  for skill in ui-ux-pro-max ui-styling; do
    mkdir -p "$FIXTURE/.claude/skills/$skill"
    printf -- '---\nname: %s\ndescription: fixture\n---\n' "$skill" > "$FIXTURE/.claude/skills/$skill/SKILL.md"
  done
  git -C "$FIXTURE" init -q && git -C "$FIXTURE" add -A && git -C "$FIXTURE" -c user.email=t@t -c user.name=t commit -qm fixture
  UI_SKILLS_REPO="$FIXTURE"
}

teardown() {
  rm -rf "$TARGET_HOME" "$FIXTURE"
}

@test "every skill in claude/skills has a SKILL.md named after its folder, with a description" {
  for dir in "$REPO_ROOT"/claude/skills/*/; do
    name="$(basename "$dir")"
    [ -f "$dir/SKILL.md" ]
    grep -q "^name: $name\$" "$dir/SKILL.md"
    grep -q "^description: ." "$dir/SKILL.md"
  done
}

@test "the skills reference their scripts from their own folder, not a fixed path" {
  ! grep -rq '~/.claude/skills/' "$REPO_ROOT/claude/skills"
}

@test "babysit's Codex helper is executable and valid bash" {
  [ -x "$REPO_ROOT/claude/skills/babysit/codex.sh" ]
  run bash -n "$REPO_ROOT/claude/skills/babysit/codex.sh"
  [ "$status" -eq 0 ]
}

@test "install_claude_skills installs the repo's skills and the upstream UI skills" {
  run install_claude_skills
  [ "$status" -eq 0 ]
  for skill in feature-flow babysit ui-ux-pro-max ui-styling; do
    [ -f "$TARGET_HOME/.claude/skills/$skill/SKILL.md" ]
  done
  [ -x "$TARGET_HOME/.claude/skills/babysit/codex.sh" ]
}

@test "re-running replaces each skill and keeps earlier copies outside ~/.claude/skills" {
  install_claude_skills
  TIMESTAMP="test2"
  install_claude_skills
  # One folder per skill, nothing that Claude Code would load twice.
  [ "$(ls "$TARGET_HOME/.claude/skills" | wc -l | tr -d ' ')" -eq 4 ]
  ! ls "$TARGET_HOME/.claude/skills" | grep -q '\.bak\|test1'
  [ -d "$TARGET_HOME/.claude/skills-backup/feature-flow.test2" ]
}

@test "an unreachable upstream still installs the repo's own skills" {
  UI_SKILLS_REPO="$TARGET_HOME/does-not-exist"
  run install_claude_skills
  [ "$status" -eq 0 ]
  [[ "$output" == *"Could not fetch the UI skills"* ]]
  [ -f "$TARGET_HOME/.claude/skills/feature-flow/SKILL.md" ]
  [ ! -e "$TARGET_HOME/.claude/skills/ui-styling" ]
}

@test "install_codex leaves an existing Codex alone" {
  stub="$(mktemp -d)"
  printf '#!/bin/sh\necho "codex-cli 9.9.9"\n' > "$stub/codex" && chmod +x "$stub/codex"
  PATH="$stub:$PATH" run install_codex
  [ "$status" -eq 0 ]
  [[ "$output" == *"Codex already installed: codex-cli 9.9.9"* ]]
  rm -rf "$stub"
}

@test "install_codex without npm warns and carries on" {
  empty="$(mktemp -d)"
  PATH="$empty:/usr/bin:/bin" run install_codex
  [ "$status" -eq 0 ]
  if ! command -v codex >/dev/null 2>&1 && ! PATH="$empty:/usr/bin:/bin" command -v npm >/dev/null 2>&1; then
    [[ "$output" == *"npm not found"* ]]
  fi
  rm -rf "$empty"
}
