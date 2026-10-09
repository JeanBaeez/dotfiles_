---
name: feature-flow
description: Use whenever a new feature is requested in any project, before any code is written. Runs the whole lifecycle — branch from dev, prove the feature is feasible, produce UI material with the ui-ux-pro-max and ui-styling skills, get the user's approval, then build it with development, security, QA and resilience agents that must agree on each other's work, and hand it to the babysit skill for review and PR babysitting until done.
---

# Feature flow

One feature, end to end, the same way every time. Each step has a gate; do not skip ahead.

The user has opted into multi-agent orchestration for this flow: steps 4 and 5 run the bundled
workflows with the Workflow tool.

## 0. Branches

- `dev` is the integration branch. If it does not exist, create it from the default branch.
- Create `feature/<slug>` from `dev` (`<slug>`: short, kebab-case). Never commit to `main` or `dev`.
- If the remote refuses a branch push, say so and keep working locally; PRs target `dev`.

## 1. Feasibility — is it possible, and at what cost?

Before designing anything, establish whether the feature can be built as asked:

- Platform and API constraints (read the docs and probe the machine read-only: what APIs exist,
  what they need — permissions, privileges, entitlements, OS versions, hardware).
- Prior art: how existing tools do it, and what went wrong for them.
- Risks: safety, privacy, security, data loss, cost, legal (licences, trademarks, store rules).
- Effort and the shape of the solution.

For anything non-trivial run a small research fan-out (one agent per angle above) with the
Workflow tool, then write `docs/features/<slug>/feasibility.md`: a verdict (**feasible**,
**feasible with conditions**, or **not feasible**), the evidence for it (links, probe output),
the conditions, and the alternatives. If not feasible, stop here and report.

## 2. Investigate and produce UI material (when the feature has UI)

- Invoke the `ui-ux-pro-max` skill (run its searches for the relevant UX guidelines, controls,
  accessibility and platform conventions) and the `ui-styling` skill (tokens, states, theming).
  Translate web-centric advice to the project's platform; the platform's own conventions win.
- Produce real material, not prose: mockups in the project's own idiom (native renders for a
  native app, HTML/SVG otherwise), every state that matters (default, on, off, disabled, error,
  loading, light and dark), exact copy, and how it fits the existing screens.
- Save it in `docs/features/<slug>/` with a short `spec.md`: the behaviour, the acceptance
  criteria, and what is explicitly out of scope.

## 3. Approval — the hard gate

Show the user the feasibility verdict, the UI material and the spec, and ask with
AskUserQuestion: approve, approve with changes, or stop. No production code before approval.
Fold any requested changes back into the spec and material, and ask again if they were material.

## 4. Build — four agents that must agree

Run the bundled workflow with the Workflow tool:

```
Workflow({ scriptPath: "<this skill's base directory>/build.workflow.js", args: {
  feature: "<one paragraph>", slug: "<slug>", repo: "<absolute repo path>",
  base: "dev", branch: "feature/<slug>", spec: "docs/features/<slug>/spec.md",
  build: "<build command>", test: "<test command>", maxRounds: 3 } })
```

(The base directory is the one shown as "Base directory for this skill" when this skill loads; use it as an absolute path, wherever the skill is installed.) The workflow:

1. **Plan** — development, security, QA and resilience each write their part (implementation
   tasks; threat model and required controls; test plan and acceptance tests; failure modes and
   fail-safes). One merged plan.
2. **Agree on the plan** — every role must approve; objections revise the plan, up to `maxRounds`.
3. **Build** — development implements; then QA adds tests, security hardens, resilience adds
   fail-safes, each committing its own work on the feature branch.
4. **Agree on the work** — every role reviews the whole diff, including the others' work, builds
   and runs the tests; issues go back for fixing until all four approve, up to `maxRounds`.

If it returns without consensus, show the user the open disagreements; do not paper over them.

## 5. Review and babysitting

Invoke the `babysit` skill (pass `ultra` for risky features: privileged code, payments, data
migrations, security boundaries). It reviews every SDLC dimension with a Codex second opinion,
routes fixes back to the owning roles, opens the PR into `dev`, and watches it until it is merged
or closed.

## 6. Finish

Install or deploy the way the project does (for a local app: built, installed and running), and
report: what shipped, what was verified and how, what was not, and the PR link.
