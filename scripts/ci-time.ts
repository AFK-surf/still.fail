// How long a run of the pipeline (.github/workflows/pipeline.yml) took, against what it should: the time from its
// first job starting to its last ending, the jobs on the way, and the longest steps. A run over its budget says so,
// and what to look at first (docs/development.md, "CI time").
//   node scripts/ci-time.ts <run id> [attempt]   the run's times as text; exit 3 when over budget
//   node scripts/ci-time.ts <run id> --json      the same, as JSON
// Reads the run through `gh api` (GH_TOKEN in CI). The pipeline's last job (timing) runs it on itself, into the run's
// summary; a station's watch runs it on each run that ends and wakes an agent for one over budget.
import { execFileSync } from "node:child_process";

/** Seconds a run may take, from its first job starting to its last ending. */
export const BUDGET = {
  /** A branch: the check, and what main would deploy built beside it (2026-10-04: ~100 s with caches warm). */
  branch: 180,
  /** main, releasing nothing (docs, the site): the check (~40 s) and the tag. */
  main: 180,
  /** A branch or main that checked the Android app (check-android): its Gradle run alone is ~2 min (2026-10-07: the app
   * one module of ~31k lines, compiled then linted, one after the other). */
  android: 240,
  /** A branch that built the Windows app and tried it on Windows (windows-smoke): its build, its upload and then the
   * smoke, one after another, ~280 s (2026-10-09). */
  windows: 330,
  /** main, releasing apps or the station: the check, the API, then the releases side by side (Android's the longest). */
  release: 480,
} as const;

const REPO = process.env.GITHUB_REPOSITORY ?? "AFK-surf/still.fail";
const RELEASES = new Set(["station", "android", "desktop", "static"]);

type Step = { name: string; started_at: string | null; completed_at: string | null };
type Job = { name: string; conclusion: string | null; started_at: string | null; completed_at: string | null; steps?: Step[] };
type Run = { head_branch: string; head_sha: string; run_attempt: number; html_url: string; run_started_at: string };

const api = <T>(path: string): T => JSON.parse(execFileSync("gh", ["api", path], { encoding: "utf8", maxBuffer: 64 << 20 }));
const secs = (a: string, b: string) => Math.round((Date.parse(b) - Date.parse(a)) / 1000);

export function timing(id: string, attempt?: number) {
  const n = attempt ?? api<Run>(`repos/${REPO}/actions/runs/${id}`).run_attempt;
  const run = api<Run>(`repos/${REPO}/actions/runs/${id}/attempts/${n}`);
  const jobs = api<{ jobs: Job[] }>(`repos/${REPO}/actions/runs/${id}/attempts/${n}/jobs?per_page=100`).jobs.filter(
    // Ran (not skipped), and not the job measuring it; in an attempt after the first, ran in it: the jobs a re-run of the
    // failed ones keeps from before carry their old times, and the hours between the attempts were counted as the run's
    // (windows-station's second attempt, 576 s of which 180 s waiting for it to be asked, 2026-10-10).
    (j) => j.started_at && j.completed_at && j.conclusion !== "skipped" && j.name !== "timing" && (n === 1 || j.started_at >= run.run_started_at),
  ) as (Job & { started_at: string; completed_at: string })[];
  if (jobs.length === 0) return undefined;
  const start = jobs.map((j) => j.started_at).sort()[0]!;
  const end = jobs.map((j) => j.completed_at).sort().at(-1)!;
  const branchKind = run.head_branch !== "main" ? "branch" : jobs.some((j) => RELEASES.has(j.name)) ? "release" : "main";
  const kind =
    branchKind === "release" ? branchKind
    : jobs.some((j) => j.name === "windows-smoke") ? "windows"
    : jobs.some((j) => j.name === "check-android") ? "android"
    : branchKind;
  const steps = jobs
    .flatMap((j) => (j.steps ?? []).filter((s) => s.started_at && s.completed_at).map((s) => ({ job: j.name, step: s.name, seconds: secs(s.started_at!, s.completed_at!) })))
    .sort((a, b) => b.seconds - a.seconds)
    .slice(0, 8);
  return {
    id,
    attempt: n,
    url: run.html_url,
    branch: run.head_branch,
    commit: run.head_sha.slice(0, 8),
    kind,
    seconds: secs(start, end),
    budget: BUDGET[kind],
    /** Waiting for a runner before the first job: not counted, said when it is long. */
    queued: secs(run.run_started_at, start),
    jobs: jobs
      .map((j) => ({ name: j.name, conclusion: j.conclusion, from: secs(start, j.started_at), seconds: secs(j.started_at, j.completed_at) }))
      .sort((a, b) => a.from - b.from),
    steps,
  };
}

export function text(t: NonNullable<ReturnType<typeof timing>>) {
  const over = t.seconds > t.budget;
  const lines = [
    `${over ? "OVER BUDGET" : "ok"}: run ${t.id} (attempt ${t.attempt}, ${t.kind}, ${t.branch} ${t.commit}) took ${t.seconds} s of ${t.budget} s` +
      (t.queued > 60 ? `, after ${t.queued} s waiting for a runner` : ""),
    t.url,
    "",
    "jobs (start → seconds):",
    ...t.jobs.map((j) => `  +${String(j.from).padStart(4)} s  ${String(j.seconds).padStart(4)} s  ${j.name}${j.conclusion === "success" ? "" : ` (${j.conclusion})`}`),
    "",
    "longest steps:",
    ...t.steps.map((s) => `  ${String(s.seconds).padStart(4)} s  ${s.job} › ${s.step}`),
  ];
  return lines.join("\n");
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const [id, second] = process.argv.slice(2);
  if (!id) {
    console.error("usage: node scripts/ci-time.ts <run id> [attempt | --json]");
    process.exit(2);
  }
  const t = timing(id, second && second !== "--json" ? Number(second) : undefined);
  if (!t) {
    console.log(`run ${id}: no job ran`);
    process.exit(0);
  }
  console.log(second === "--json" ? JSON.stringify(t) : text(t));
  if (t.seconds > t.budget) process.exit(3);
}
