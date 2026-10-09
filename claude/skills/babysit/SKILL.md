---
name: babysit
description: Code review across every SDLC dimension with a Codex second opinion, then babysitting every agent's fixes and every PR until it is merged or closed. Use after a feature is built (feature-flow step 5), or whenever asked to review a branch or PR thoroughly. Pass "ultra" for the deepest pass (two lenses per dimension, three-vote adversarial verification).
argument-hint: "[ultra] [branch-or-PR]"
---

# Babysit

Review, get a second opinion, get it fixed, and stay with it until it is done. A finding is only
closed when the reviewer who raised it has checked the fix.

The user has opted into multi-agent orchestration for this skill: it runs the bundled review
workflow with the Workflow tool.

## Arguments

- `ultra`: two reviewers per dimension with different lenses, three skeptics per finding.
  Without it: one reviewer per dimension, one skeptic per finding.
- A branch or PR to review. Default: the current branch against `dev` (or the default branch if
  there is no `dev`).

## 1. Review

Run the bundled workflow, from this skill's base directory (shown as "Base directory for this skill" when it loads; an absolute path, wherever the skill is installed):

```
Workflow({ scriptPath: "<this skill's base directory>/review.workflow.js", args: {
  repo: "<absolute repo path>", base: "dev", head: "<branch>", mode: "ultra" | "standard",
  spec: "docs/features/<slug>/spec.md", build: "<build command>", test: "<test command>",
  skillDir: "<absolute path of this skill's folder>", previous: [] } })
```

It reviews ten dimensions of the SDLC — requirements, design, correctness, security, privacy,
tests, resilience, performance, UX and accessibility, release (build, CI, signing, packaging,
docs) — while Codex reviews the branch on its own (`codex.sh review`, read-only). Every finding is
then challenged by skeptics who default to "not real", and the survivors go to Codex
(`codex.sh challenge`). Where Codex disagrees, a tie-break reviewer reads the code and decides; a
dispute never disappears silently, it is returned under `disputed`.

If Codex is not installed or not signed in, the review goes on and says "no second opinion".

## 2. Fix, then re-review until clean

- Route each open finding to the role that owns it (development, security, QA, resilience) — in a
  feature-flow build, the same agents — and have it fixed on the feature branch.
- Re-run the workflow with `previous` set to the open findings. Each is rechecked by a reviewer
  that must see the failure scenario gone; new findings from the fixes are reviewed the same way.
- Repeat until the verdict is `clean` (or only `low` findings the user accepts). Show the user
  anything `disputed`.

## 3. The pull request

- Commit, push the branch and open a PR into `dev` with a summary of the feature, the review
  rounds, and what was verified. If the remote refuses a branch push, use the forge's
  pull-request-by-push mechanism if it has one (Forgejo/Gitea AGit:
  `git push origin HEAD:refs/for/dev/<topic> -o title=... -o description=...`), otherwise say so.
- Link the PR to the thread when the T3 `link_pull_request` tool exists.

## 4. Babysit until completion

Stay on every PR you opened, and on every agent still fixing something, until each is merged,
closed, or explicitly handed back to the user:

- **CI**: watch the checks (on GitHub use the T3 `watch_pull_request` tool when available, else
  `gh pr checks`; on Forgejo/Gitea read the commit status through the API). A failure is
  diagnosed and fixed, never re-run blindly.
- **Review comments**: answer or fix each one; a reviewer's request is resolved only when its
  author's concern is addressed.
- **Conflicts**: rebase or merge from the base, re-run the build and tests, re-review the result.
- **New commits** on the PR: review them with `previous` set to the open findings.
- Report briefly at each change of state; when everything is merged or closed, say what shipped.
  Before handing back, call `unwatch_pull_request` when you used `watch_pull_request`.

## Rules

- Read-only reviewers; only the owning role edits code.
- Every finding cites file:line and a concrete failure scenario; no style nits as blockers.
- Never claim "clean" without having run the build and tests in that round.
