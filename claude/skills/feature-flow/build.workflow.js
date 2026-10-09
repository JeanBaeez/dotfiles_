export const meta = {
  name: 'feature-build',
  description: 'Build an approved feature with development, security, QA and resilience agents that must agree on the plan and on each other\'s work',
  whenToUse: 'Step 4 of the feature-flow skill, after the user approved the spec',
  phases: [
    { title: 'Plan', detail: 'each role writes its part; one merged plan' },
    { title: 'Agree on plan', detail: 'every role signs off on the plan' },
    { title: 'Build', detail: 'development implements; QA, security and resilience add their work' },
    { title: 'Agree on work', detail: 'every role reviews all the work until all four agree' },
  ],
}

const A = args || {}
const MAX = A.maxRounds || 3

const ROLES = [
  { key: 'development', brief: 'You are the DEVELOPMENT lead. You own the implementation: correct, idiomatic for this codebase, matching its conventions, comments and naming, and no larger than the spec needs.' },
  { key: 'security', brief: 'You are the SECURITY engineer. You own the threat model: privileges and least privilege, trust boundaries, authentication of callers, input validation, secrets, injection, TOCTOU, privacy, supply chain, and safe defaults.' },
  { key: 'qa', brief: 'You are QA. You own correctness evidence: acceptance criteria from the spec, a test plan, automated tests in the project\'s own test harness, edge cases and regressions, and proof that the tests actually ran.' },
  { key: 'resilience', brief: 'You are the RESILIENCE engineer. You own failure: every way this can fail or be left in a bad state (crash, quit, reboot, timeout, partial failure, resource exhaustion, unsafe physical conditions), fail-safes that restore a safe state, recovery on next launch, and observability.' },
]

const CONTEXT = [
  `Feature: ${A.feature}`,
  `Repository: ${A.repo}. Work only on branch ${A.branch} (based on ${A.base}); check it out if needed and never touch other branches.`,
  `Approved spec: ${A.spec} (read it first). UI material sits next to it.`,
  `Build: ${A.build}`,
  `Test: ${A.test}`,
  'Rules: do not push; do not run commands that change the user\'s machine beyond the repository (no sudo, no installs, no system settings) unless the spec says a test needs it and it is reversed at once; commit only your own changes with a clear message ending "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>".',
].join('\n')

const PLAN = {
  type: 'object',
  properties: {
    tasks: { type: 'array', items: { type: 'string' }, description: 'concrete tasks this role owns' },
    requirements: { type: 'array', items: { type: 'string' }, description: 'what this role requires of the others' },
    risks: { type: 'array', items: { type: 'string' } },
  },
  required: ['tasks', 'requirements', 'risks'],
}
const VERDICT = {
  type: 'object',
  properties: {
    approve: { type: 'boolean' },
    issues: { type: 'array', items: { type: 'string' }, description: 'blocking issues, each with file:line or plan item and the fix wanted; empty when approving' },
    notes: { type: 'string' },
  },
  required: ['approve', 'issues'],
}
const WORK = {
  type: 'object',
  properties: {
    summary: { type: 'string' },
    files: { type: 'array', items: { type: 'string' } },
    commits: { type: 'array', items: { type: 'string' } },
    verification: { type: 'string', description: 'commands run and their results' },
  },
  required: ['summary', 'files', 'verification'],
}

phase('Plan')
const parts = await parallel(ROLES.map(r => () => agent(
  `${CONTEXT}\n\n${r.brief}\n\nRead the spec and the code it touches. Write your role's part of the implementation plan. Do not edit files.`,
  { label: `plan:${r.key}`, phase: 'Plan', schema: PLAN })))
let plan = await agent(
  `${CONTEXT}\n\nMerge these four role plans into one implementation plan: numbered tasks, each with an owner (development, security, qa or resilience), the files it touches, and how it is verified. Keep every security, QA and resilience requirement. Return the plan as markdown.\n\n${JSON.stringify(ROLES.map((r, i) => ({ role: r.key, part: parts[i] })), null, 1)}`,
  { label: 'plan:merge', phase: 'Plan' })

phase('Agree on plan')
let planAgreed = false
let planVerdicts = []
for (let round = 1; round <= MAX && !planAgreed; round++) {
  planVerdicts = await parallel(ROLES.map(r => () => agent(
    `${CONTEXT}\n\n${r.brief}\n\nReview this plan from your role. Approve only if everything your role requires is in it and nothing in it is unsafe or wrong. Do not edit files.\n\nPLAN:\n${plan}`,
    { label: `plan-review:${r.key}:${round}`, phase: 'Agree on plan', schema: VERDICT })))
  const issues = planVerdicts.map((v, i) => v && !v.approve ? v.issues.map(x => `[${ROLES[i].key}] ${x}`) : []).flat()
  planAgreed = planVerdicts.every(v => v && v.approve)
  log(`Plan round ${round}: ${planAgreed ? 'all four approve' : `${issues.length} objection(s)`}`)
  if (!planAgreed && round < MAX) {
    plan = await agent(`${CONTEXT}\n\nRevise the plan to resolve every objection. Return the full revised plan as markdown.\n\nPLAN:\n${plan}\n\nOBJECTIONS:\n${issues.join('\n')}`,
      { label: `plan-revise:${round}`, phase: 'Agree on plan' })
  }
}
if (!planAgreed) {
  return { status: 'no-consensus-on-plan', plan, verdicts: planVerdicts }
}

phase('Build')
const work = []
work.push(await agent(
  `${CONTEXT}\n\n${ROLES[0].brief}\n\nImplement the development tasks of this plan. Build with the build command until it succeeds with no new warnings. Commit.\n\nPLAN:\n${plan}`,
  { label: 'build:development', phase: 'Build', schema: WORK }))
// One working tree: the specialists take turns, each building on the last.
for (const r of ROLES.slice(1)) {
  work.push(await agent(
    `${CONTEXT}\n\n${r.brief}\n\nDevelopment has implemented the plan (see git log ${A.base}..${A.branch}). Now do your role's tasks from the plan: write the code or tests your role owns, run the build and the tests, and commit. If development's code needs a change for your role, make it and say so.\n\nPLAN:\n${plan}`,
    { label: `build:${r.key}`, phase: 'Build', schema: WORK }))
}

phase('Agree on work')
let agreed = false
let verdicts = []
let rounds = 0
for (let round = 1; round <= MAX && !agreed; round++) {
  rounds = round
  verdicts = await parallel(ROLES.map(r => () => agent(
    `${CONTEXT}\n\n${r.brief}\n\nReview ALL the work on this branch, not just your own: git diff ${A.base}...${A.branch}, the commits of every role, the build and the tests (run them). Approve only if the work meets the plan for your role and you agree with what the other roles did. List every blocking issue with file:line.\n\nPLAN:\n${plan}`,
    { label: `work-review:${r.key}:${round}`, phase: 'Agree on work', schema: VERDICT })))
  const issues = verdicts.map((v, i) => v && !v.approve ? v.issues.map(x => `[${ROLES[i].key}] ${x}`) : []).flat()
  agreed = verdicts.every(v => v && v.approve)
  log(`Work round ${round}: ${agreed ? 'all four agree' : `${issues.length} issue(s)`}`)
  if (!agreed && round < MAX) {
    work.push(await agent(
      `${CONTEXT}\n\nFix every issue below. Each names the role that raised it; keep that role's intent. Build, run the tests, and commit.\n\nISSUES:\n${issues.join('\n')}`,
      { label: `fix:${round}`, phase: 'Agree on work', schema: WORK }))
  }
}

return { status: agreed ? 'agreed' : 'no-consensus-on-work', rounds, plan, work, verdicts }
