// A chat's web services and background jobs, as its pages show them. Jobs are mostly long-running watchers (a CI run
// followed, a deploy kept an eye on): what matters is whether each is still alive and what it last said
// (`ember-job notify`), not how long it took. Status is a small dot before the name and a word on the line under it;
// the title bar's popover shows what matters now, the 任务 tab beside the chat shows everything.
import { useEffect, useRef, useState, type ReactNode } from "react";
import type { ChatJobsView, Job, JobLogView } from "./core/shapes.ts";
import { stationApi, useStationCall } from "./api.ts";
import { useTopic } from "./core/react.ts";
import { ArrowRight, ChevronDown, ChevronRight, PanelOpen, Stop } from "./icons.tsx";
import { Empty, Segmented, Tip } from "./ui.tsx";
import { useToast } from "./toast.tsx";
import * as css from "./Jobs.css.ts";
import * as pagesCss from "./styles/pages.css.ts";

// What a job's dot says, its word, the line under its name and every time in words are the core's (client/core/src/
// jobs.rs): `tone` (up, live, restart, fail, off), `meta`, `detail`, a notice's `ago` and `clock`; a chat's all
// together, what matters first, is its `chatJobs` view.

/** A chat's jobs before the core has said (or from a core that does not know them): none. */
export const NO_JOBS: ChatJobsView = { jobs: [], servicesNote: "", jobsNote: "", current: 0, ended: 0, clear: [], allText: "", clearText: "", hiddenText: "" };

/** The line under a job's name: what it is up to, in a few words (its state's word coloured as its dot). */
export function metaOf(job: Job): ReactNode {
  return (job.meta ?? []).map((part, i) => part.kind === "word"
    ? <em key={i} className={css.jobWord} data-tone={job.tone}>{part.text}</em>
    : part.kind === "notice" ? <span key={i} className={css.jobSaid}>{part.text}</span> : part.text);
}

/** A job's status: a small dot, on its name's line. */
export function JobDot({ tone }: { tone: string | undefined }) {
  return <span className={css.jobDot} data-tone={tone} aria-hidden="true" />;
}

/** A job's row: its dot, its name, what it is up to; what is at its end (a service's arrow, a job's chevron). */
export function JobRow({ job, onClick, end, selected, expanded }:
  { job: Job; onClick?: (() => void) | undefined; end?: ReactNode; selected?: boolean; expanded?: boolean }) {
  const tone = job.tone;
  return (
    <button type="button" className={css.jobRow} onClick={onClick} data-static={!onClick || undefined} data-off={tone === "off" || undefined} data-selected={selected || undefined}
      aria-expanded={expanded} aria-current={selected || undefined}>
      <JobDot tone={tone} />
      <span className={css.jobText}>
        <span className={css.jobName}>{job.name}</span>
        <span className={css.jobMeta}>{metaOf(job)}</span>
      </span>
      {end && <span className={css.jobEnd}>{end}</span>}
    </button>
  );
}

/** A job's output (its last `lines`), as the core keeps it, current as it grows; `id` null reads nothing. */
export function useJobLog(station: string, id: string | null, lines: number): JobLogView | null {
  return useTopic<JobLogView>(id ? { topic: "jobLog", station, job: id, lines } : null).value ?? null;
}

/** Stops a job from the page (its agent is told who did). */
export function useStopJob(station: string): (job: Job) => void {
  const call = useStationCall(station);
  const toast = useToast();
  return (job) => void stationApi(call).stopJob(job.id)
    .catch((e: Error) => toast(`没能停下「${job.name}」：${e.message}`));
}

/** Clears a chat's jobs that are over from the page (each session's, as the station keeps them: `clear`). */
export function useClearEnded(station: string): (sessions: string[]) => void {
  const call = useStationCall(station);
  const toast = useToast();
  return (sessions) => {
    void Promise.all(sessions.map((s) => stationApi(call).clearEndedJobs(s)))
      .catch((e: Error) => toast(`没能清掉已结束的任务：${e.message}`));
  };
}

/** The last line a job wrote, and when (the job's own word for it until its output is read). */
function LastOutput({ station, job }: { station: string; job: Job }) {
  const log = useJobLog(station, job.id, 1);
  const said = log ? log.said : job.outputSaid;
  if (!said) return null;
  return (
    <div className={css.jobLast}>
      <span>{said}</span>
      {log?.last && <code>{log.last}</code>}
    </div>
  );
}

/** What a job said, newest first, each with when. */
function Notices({ job, limit, clockTimes = false }: { job: Job; limit?: number; clockTimes?: boolean }) {
  const notices = (job.notices ?? []).slice(0, limit);
  if (notices.length === 0) return <p className={css.jobNoticesNone}>还没有通知。它用 <code>stillfail-job notify</code> 说的话会列在这里。</p>;
  return (
    <ol className={css.jobNotices} data-clock={clockTimes || undefined}>
      {notices.map((n, i) => <li key={`${n.at}-${i}`}><time dateTime={new Date(n.at).toISOString()}>{clockTimes ? n.clock : n.ago}</time><span>{n.text}</span></li>)}
    </ol>
  );
}

/**
 * The title bar popover's body: what matters now (services up or restarting, jobs alive, what died lately); a job opens
 * in place to its last few notices and last output; everything else is a click away in the 任务 tab.
 */
export function JobsPopover({ station, view, onService, onTab }:
  { station: string; view: ChatJobsView; onService: (id: string) => void; onTab: (id?: string) => void }) {
  const stop = useStopJob(station);
  const clear = useClearEnded(station);
  const [open, setOpen] = useState<string | null>(null);
  const { jobs } = view;
  if (jobs.length === 0) {
    return <div className={css.jobsEmpty}><b>还没有服务或后台任务</b><span>agent 开网页、或挂上长期盯着的任务时，会列在这里。</span></div>;
  }
  const shown = jobs.filter((j) => j.current);
  const services = shown.filter((j) => j.service);
  const plain = shown.filter((j) => !j.service);
  return (
    <>
      {services.length > 0 && (
        <section className={css.jobsGroup}>
          <div className={css.jobsHead}>服务{view.servicesNote && <span>{view.servicesNote}</span>}</div>
          {services.map((j) => (
            <JobRow key={j.id} job={j} onClick={j.tone === "fail" ? () => onTab(j.id) : () => onService(j.id)}
              end={j.tone === "fail" ? <ChevronRight size={16} /> : <ArrowRight size={16} />} />
          ))}
        </section>
      )}
      {plain.length > 0 && (
        <section className={css.jobsGroup}>
          <div className={css.jobsHead}>后台任务{view.jobsNote && <span>{view.jobsNote}</span>}</div>
          {plain.map((j) => (
            <div key={j.id} className={css.jobFold} data-open={open === j.id || undefined}>
              <JobRow job={j} expanded={open === j.id} onClick={() => setOpen(open === j.id ? null : j.id)}
                end={open === j.id ? <ChevronDown size={16} /> : <ChevronRight size={16} />} />
              {open === j.id && (
                <div className={css.jobFoldBody}>
                  <Notices job={j} limit={3} />
                  <LastOutput station={station} job={j} />
                  <div className={css.jobActions}>
                    {j.state === "running" && <button type="button" className={css.jobAction} onClick={() => stop(j)}><Stop size={14} />停止</button>}
                    <button type="button" className={css.jobAction} onClick={() => onTab(j.id)}><PanelOpen size={14} />在侧栏看</button>
                  </div>
                </div>
              )}
            </div>
          ))}
        </section>
      )}
      {shown.length === 0 && <p className={css.jobsQuiet}>眼下没有在跑的服务或任务。</p>}
      <div className={css.jobsFoot}>
        <button type="button" className={css.jobsAll} onClick={() => onTab()}>
          {view.allText} · 在侧栏看
        </button>
        {/* What the popover leaves out is all over: the button to clear them says how many. */}
        {view.ended > 0 && <button type="button" className={css.jobsClear} onClick={() => clear(view.clear)}>{view.clearText}</button>}
      </div>
    </>
  );
}

/**
 * The 任务 tab beside the chat: every service and job (those over faded, last); a job picked shows what it said, or
 * its output as it grows, under its name, state and command.
 */
export function JobsTab({ station, view, picked, onPick, onService }:
  { station: string; view: ChatJobsView; picked: string | null; onPick: (id: string) => void; onService: (id: string) => void }) {
  const stop = useStopJob(station);
  const clear = useClearEnded(station);
  const [tab, setTab] = useState<"notices" | "output">("notices");
  const all = view.jobs;
  const services = all.filter((j) => j.service);
  const plain = all.filter((j) => !j.service);
  const job = plain.find((j) => j.id === picked) ?? plain[0] ?? null;
  if (all.length === 0) return <Empty><p>这个对话里还没有服务或后台任务。</p></Empty>;
  return (
    <div className={css.jobsTab}>
      <div className={css.jobsTabList}>
        {services.length > 0 && (
          <section className={css.jobsGroup}>
            <div className={css.jobsHead}>服务</div>
            {services.map((j) => (
              <JobRow key={j.id} job={j} onClick={j.tone === "up" || j.tone === "restart" ? () => onService(j.id) : undefined}
                end={j.tone === "up" || j.tone === "restart" ? <ArrowRight size={16} /> : undefined} />
            ))}
          </section>
        )}
        {plain.length > 0 && (
          <section className={css.jobsGroup}>
            <div className={css.jobsHead}>后台任务</div>
            {plain.map((j) => <JobRow key={j.id} job={j} selected={j.id === job?.id} onClick={() => onPick(j.id)} />)}
          </section>
        )}
        {view.ended > 0 && <button type="button" className={css.jobsClear} onClick={() => clear(view.clear)}>{view.clearText}</button>}
      </div>
      {job && (
        <div className={css.jobDetail}>
          <div className={css.jobDetailHead}>
            <JobDot tone={job.tone} />
            <b>{job.name}</b>
            <span className={css.jobDetailState}>{job.detail}</span>
            <span className={css.jobDetailGrow} />
            <Segmented<"notices" | "output"> label="看什么" value={tab} onChange={setTab} options={[{ value: "notices", label: "通知" }, { value: "output", label: "输出" }]} />
            {job.state === "running" && <Tip label="停止"><button type="button" className={`${pagesCss.iconBtn} ${css.jobDetailStop}`} aria-label="停止" onClick={() => stop(job)}><Stop size={16} /></button></Tip>}
          </div>
          {job.command && <Tip label={job.command} cut><div className={css.jobDetailCommand}>{job.command}</div></Tip>}
          {tab === "notices"
            ? <><div className={css.jobDetailNotices}><Notices job={job} clockTimes /></div><LastOutput station={station} job={job} /></>
            : <Output station={station} job={job} />}
        </div>
      )}
    </div>
  );
}

/** A job's output, following its end while it is scrolled there. */
function Output({ station, job }: { station: string; job: Job }) {
  const log = useJobLog(station, job.id, 400);
  const box = useRef<HTMLPreElement>(null);
  const atEnd = useRef(true);
  useEffect(() => {
    const el = box.current;
    if (el && atEnd.current) el.scrollTop = el.scrollHeight;
  }, [log?.text]);
  return (
    <pre ref={box} className={css.jobOutput} onScroll={(e) => { const el = e.currentTarget; atEnd.current = el.scrollHeight - el.scrollTop - el.clientHeight < 24; }}>
      {log === null ? "正在读取…" : log.text || "（还没有输出）"}
    </pre>
  );
}
