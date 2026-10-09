#!/bin/bash
# Codex as a second opinion for the babysit skill. Read-only: Codex reviews and judges, never edits.
#
#   codex.sh review    <repo> <base> [focus]       Codex's own review of <base>...HEAD
#   codex.sh challenge <repo> <findings-file>      Codex judges each finding: AGREE or DISAGREE, with evidence
#
# Exits 3 when Codex is not installed or not signed in, so callers can say "no second opinion"
# instead of failing the review.
set -uo pipefail

command -v codex >/dev/null 2>&1 || { echo "codex: not installed" >&2; exit 3; }
mode="${1:?usage: codex.sh review|challenge <repo> ...}"
repo="${2:?repo}"
cd "$repo" || exit 2

case "$mode" in
  review)
    base="${3:?base branch}"
    focus="${4:-correctness, security, resilience, tests and anything that would block shipping}"
    codex exec review --base "$base" "Review these changes as a strict senior reviewer. Focus: ${focus}. For every finding give one line: SEVERITY (critical|high|medium|low) | file:line | the problem | why it matters. Say NO FINDINGS if there are none." 2>&1
    ;;
  challenge)
    findings="${3:?findings file}"
    codex exec --sandbox read-only "You are an independent second reviewer. For each numbered finding below, read the code it cites in this repository and answer on one line: <number> AGREE|DISAGREE - <evidence from the code>. Disagree when the code does not have the problem, the problem cannot happen, or the severity is wrong (say which).

$(cat "$findings")" 2>&1
    ;;
  *)
    echo "unknown mode: $mode" >&2; exit 2 ;;
esac
status=$?
# A missing login shows up as an auth error; report it as "no second opinion".
if [[ $status -ne 0 ]]; then exit 3; fi
