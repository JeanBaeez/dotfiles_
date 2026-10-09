export const meta = {
  name: 'babysit-review',
  description: 'Review a branch across every SDLC dimension, verify each finding adversarially, get Codex\'s second opinion, and re-check earlier findings until resolved',
  whenToUse: 'Called by the babysit skill; pass mode "ultra" for the deepest pass',
  phases: [
    { title: 'Recheck', detail: 'the reviewer of each open finding checks whether it is resolved' },
    { title: 'Review', detail: 'one reviewer per SDLC dimension (two lenses each in ultra)' },
    { title: 'Codex', detail: 'Codex reviews the branch on its own' },
    { title: 'Verify', detail: 'every finding is challenged by skeptics and by Codex' },
  ],
}

const A = args || {}
const ULTRA = A.mode === 'ultra'
const CODEX = `${A.skillDir}/codex.sh`

const DIMENSIONS = [
  { key: 'requirements', focus: 'Does the change do exactly what the spec and acceptance criteria say? Anything missing, extra, or contradicting the spec?' },
  { key: 'design', focus: 'Architecture and design: fits the codebase, right boundaries, no needless complexity, maintainable, matches existing conventions.' },
  { key: 'correctness', focus: 'Logic errors, edge cases, races and concurrency, state that can go wrong, error handling, off-by-one, wrong assumptions about APIs.' },
  { key: 'security', focus: 'Privilege, trust boundaries, caller authentication, input validation, injection, secrets, TOCTOU, unsafe defaults, supply chain.' },
  { key: 'privacy', focus: 'What data is read, kept, shown or sent; least data; consent and permission prompts; nothing leaves the machine unexpectedly.' },
  { key: 'tests', focus: 'Are the acceptance criteria tested? Do the tests test the right thing, run in CI, and fail when the feature breaks? Missing edge-case tests.' },
  { key: 'resilience', focus: 'Crash, quit, reboot, timeout, partial failure, resource exhaustion, unsafe physical conditions: is a safe state always restored? Recovery on next launch? Observability?' },
  { key: 'performance', focus: 'Work on the main thread, polling, allocations in hot paths, wasted energy and battery, startup cost.' },
  { key: 'ux', focus: 'User-facing behaviour and copy: clear, honest, accessible (VoiceOver, keyboard, contrast, Reduce Motion), consistent with the approved UI material.' },
  { key: 'release', focus: 'Build, CI, signing, entitlements, packaging, migrations, docs and README, versioning: will this ship and keep shipping?' },
]
const LENSES = ULTRA ? ['a careful reader of every changed line', 'an adversary trying to break it in production'] : ['a careful reader of every changed line']
const VOTES = ULTRA ? 3 : 1

const CONTEXT = [
  `Repository: ${A.repo}. Review branch ${A.head} against ${A.base}: git diff ${A.base}...${A.head}.`,
  A.spec ? `Spec and acceptance criteria: ${A.spec}.` : '',
  A.build ? `Build: ${A.build}` : '',
  A.test ? `Test: ${A.test}` : '',
  'Read-only: do not edit files, commit, push, or change the machine. You may build and run the tests.',
].filter(Boolean).join('\n')

const FINDINGS = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          severity: { type: 'string', enum: ['critical', 'high', 'medium', 'low'] },
          file: { type: 'string' },
          line: { type: 'integer' },
          title: { type: 'string' },
          detail: { type: 'string', description: 'what is wrong, the concrete failure scenario, and the fix' },
        },
        required: ['severity', 'file', 'title', 'detail'],
      },
    },
  },
  required: ['findings'],
}
const VERDICT = {
  type: 'object',
  properties: { real: { type: 'boolean' }, reason: { type: 'string' } },
  required: ['real', 'reason'],
}
const RECHECK = {
  type: 'object',
  properties: { resolved: { type: 'boolean' }, evidence: { type: 'string' } },
  required: ['resolved', 'evidence'],
}
const CODEX_VOTES = {
  type: 'object',
  properties: {
    available: { type: 'boolean', description: 'false if codex.sh exited 3 (not installed or not signed in)' },
    votes: { type: 'array', items: { type: 'object', properties: { n: { type: 'integer' }, agree: { type: 'boolean' }, evidence: { type: 'string' } }, required: ['n', 'agree'] } },
  },
  required: ['available', 'votes'],
}

const key = f => `${f.file}:${f.line || 0}:${(f.title || '').toLowerCase().slice(0, 60)}`

// 1. Every open finding from the last pass goes back to a reviewer, who checks whether it is fixed.
phase('Recheck')
const previous = A.previous || []
const rechecked = await parallel(previous.map((f, i) => () => agent(
  `${CONTEXT}\n\nYou raised this finding in the last review. Check the current code: is it resolved? Be strict: resolved means the failure scenario can no longer happen.\n\n${JSON.stringify(f)}`,
  { label: `recheck:${i + 1}`, phase: 'Recheck', schema: RECHECK }).then(v => ({ f, v }))))
const stillOpen = rechecked.filter(Boolean).filter(r => !r.v || !r.v.resolved).map(r => ({ ...r.f, source: r.f.source || 'previous' }))

// 2. Reviewers by dimension and lens, and Codex on its own, all at once.
phase('Review')
const reviewers = DIMENSIONS.flatMap(d => LENSES.map(lens => ({ d, lens })))
const [byDimension, codexOwn] = await Promise.all([
  parallel(reviewers.map(({ d, lens }) => () => agent(
    `${CONTEXT}\n\nReview dimension: ${d.key.toUpperCase()}. ${d.focus}\nRead as ${lens}. Report only real problems in the changed code or caused by it, each with a concrete failure scenario. Nothing is fine; say nothing rather than pad.`,
    { label: `review:${d.key}${ULTRA ? `:${lens.split(' ')[1]}` : ''}`, phase: 'Review', schema: FINDINGS }))),
  agent(
    `Run: bash "${CODEX}" review "${A.repo}" "${A.base}"\nIt prints Codex's own review of ${A.base}...HEAD on branch ${A.head} (check out ${A.head} first if HEAD is elsewhere; read-only otherwise). If it exits 3, Codex is unavailable: return no findings. Otherwise convert each line Codex reports into a finding.`,
    { label: 'codex:review', phase: 'Codex', schema: FINDINGS }),
])

const seen = new Set(stillOpen.map(key))
const fresh = []
for (const f of [...byDimension.filter(Boolean).flatMap(r => r.findings).map(f => ({ ...f, source: 'claude' })),
                 ...((codexOwn && codexOwn.findings) || []).map(f => ({ ...f, source: 'codex' }))]) {
  if (!seen.has(key(f))) { seen.add(key(f)); fresh.push(f) }
}
log(`${stillOpen.length} earlier finding(s) still open; ${fresh.length} new finding(s) to verify`)

// 3. Every new finding is challenged: skeptics who default to "not real", then Codex judges the survivors.
phase('Verify')
const judged = await parallel(fresh.map((f, i) => () => parallel(Array.from({ length: VOTES }, (_, v) => () => agent(
  `${CONTEXT}\n\nTry to REFUTE this finding by reading the code it cites. It is real only if the failure scenario can actually happen. Default to real=false when unsure.\n\n${JSON.stringify(f)}`,
  { label: `verify:${i + 1}${VOTES > 1 ? `.${v + 1}` : ''}`, phase: 'Verify', schema: VERDICT })))
  .then(votes => ({ f, real: votes.filter(Boolean).filter(x => x.real).length * 2 > VOTES, votes: votes.filter(Boolean) }))))
const survivors = judged.filter(Boolean).filter(j => j.real).map(j => j.f)

let codex = { available: false, votes: [] }
if (survivors.length) {
  const list = survivors.map((f, i) => `${i + 1}. [${f.severity}] ${f.file}:${f.line || '?'} ${f.title} — ${f.detail}`).join('\n')
  codex = (await agent(
    `Write these findings to a temporary file, then run: bash "${CODEX}" challenge "${A.repo}" <that file>\nCodex answers one line per finding: <n> AGREE|DISAGREE - evidence. If it exits 3, return available=false. Return Codex's vote for each finding.\n\nFINDINGS:\n${list}`,
    { label: 'codex:challenge', phase: 'Verify', schema: CODEX_VOTES })) || codex
}

// Codex disagreeing does not silently drop a finding: a tie-break reviewer weighs both sides.
const confirmed = []
const disputed = []
await parallel(survivors.map((f, i) => async () => {
  const vote = codex.available ? codex.votes.find(v => v.n === i + 1) : null
  if (!vote || vote.agree) { confirmed.push({ ...f, codex: vote ? 'agrees' : 'no opinion' }); return }
  const tie = await agent(
    `${CONTEXT}\n\nTwo reviewers disagree. Claude's skeptics confirmed this finding; Codex disagrees: "${vote.evidence || ''}". Read the code and decide. real=true only if the failure scenario can happen.\n\n${JSON.stringify(f)}`,
    { label: `tie-break:${i + 1}`, phase: 'Verify', schema: VERDICT })
  if (tie && tie.real) confirmed.push({ ...f, codex: `disagrees: ${vote.evidence || ''}` })
  else disputed.push({ ...f, codex: `disagrees: ${vote.evidence || ''}`, tieBreak: tie ? tie.reason : 'no verdict' })
}))

const open = [...stillOpen, ...confirmed]
const order = { critical: 0, high: 1, medium: 2, low: 3 }
open.sort((a, b) => (order[a.severity] ?? 9) - (order[b.severity] ?? 9))
const resolved = rechecked.filter(Boolean).filter(r => r.v && r.v.resolved).map(r => ({ ...r.f, evidence: r.v.evidence }))
return {
  verdict: open.some(f => f.severity === 'critical' || f.severity === 'high') ? 'changes-needed' : open.length ? 'minor-changes' : 'clean',
  mode: ULTRA ? 'ultra' : 'standard',
  codexAvailable: codex.available || (codexOwn && codexOwn.findings && codexOwn.findings.length > 0),
  open, resolved, disputed,
}
