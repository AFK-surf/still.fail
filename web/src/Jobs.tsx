// A chat's web services and background jobs, as its pages show them. Jobs are mostly long-running watchers (a CI run
// followed, a deploy kept an eye on): what matters is whether each is still alive and what it last said
// (`ember-job notify`), not how long it took. Status is a small dot before the name and a word on the line under it;
// the title bar's popover shows what matters now, the 任务 tab beside the chat shows everything.
import { useEffect, useRef, useState, type ReactNode } from "react";
import type { Job } from "./core/shapes.ts";
import { useStationCall } from "./api.ts";
import { ArrowRight, ChevronDown, ChevronRight, PanelOpen, Stop } from "./icons.tsx";
import { Empty, Segmented } from "./ui.tsx";
import { useToast } from "./toast.tsx";

/** What a job's dot says: a service up, a job alive, a service restarting, one that died, one that is over. */
export type Tone = "up" | "live" | "restart" | "fail" | "off";

/** A job that ended by itself or failed this long ago is no longer news: it stays in the tab, out of the popover. */
const NEWS = 24 * 3600_000;

export const isService = (job: Job) => job.port !== undefined;

export function toneOf(job: Job): Tone {
  if (job.state === "failed") return "fail";
  if (job.state === "stopped") return "off";
  if (isService(job)) return job.state === "running" ? "up" : "restart";
  if (job.state === "running") return "live";
  return job.exitCode === 0 ? "off" : "fail";
}

/** Whether it belongs in the popover: up, alive, restarting, or died lately. */
export function isCurrent(job: Job, now: number): boolean {
  const tone = toneOf(job);
  return tone !== "off" && (tone !== "fail" || now - (job.endedAt ?? job.startedAt) < NEWS);
}

/** What the title bar's button says of them: red when one died lately, amber while a service restarts. */
export function alarmOf(jobs: Job[], now: number): "fail" | "restart" | undefined {
  const current = jobs.filter((j) => isCurrent(j, now));
  if (current.some((j) => toneOf(j) === "fail")) return "fail";
  if (current.some((j) => toneOf(j) === "restart")) return "restart";
  return undefined;
}

const RANK: Record<Tone, number> = { fail: 0, restart: 1, up: 2, live: 2, off: 3 };

/** Died first, then restarting, then up and alive, then what is over; newest first within each. */
export function sorted(jobs: Job[]): Job[] {
  return [...jobs].sort((a, b) => RANK[toneOf(a)] - RANK[toneOf(b)] || b.startedAt - a.startedAt);
}

/** A time span in words: 12 秒, 4 分钟, 3 小时, 2 天. */
export function span(ms: number): string {
  const s = Math.max(0, Math.round(ms / 1000));
  if (s < 60) return `${s} 秒`;
  if (s < 3600) return `${Math.floor(s / 60)} 分钟`;
  if (s < 86400) return `${Math.floor(s / 3600)} 小时`;
  return `${Math.floor(s / 86400)} 天`;
}

/** How long ago: 刚刚, 12 秒前, 4 分钟前, 3 小时前, 昨天, 2 天前. */
export function ago(at: number, now: number): string {
  const s = Math.round((now - at) / 1000);
  if (s < 5) return "刚刚";
  if (s >= 86400 && s < 2 * 86400) return "昨天";
  return `${span(now - at)}前`;
}

/** A clock time for a notice: 13:04 today, 9/27 13:04 before. */
export function clock(at: number, now: number): string {
  const d = new Date(at);
  const hm = `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
  return new Date(now).toDateString() === d.toDateString() ? hm : `${d.getMonth() + 1}/${d.getDate()} ${hm}`;
}

/** Now, again every `every` ms: for the times in words. */
export function useNow(every = 1000): number {
  const [now, setNow] = useState(Date.now);
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), every);
    return () => clearInterval(timer);
  }, [every]);
  return now;
}

/** A job's state in a word, coloured as its dot. */
function word(job: Job): { text: string; tone: Tone } {
  const tone = toneOf(job);
  if (isService(job)) {
    if (tone === "up") return { text: "在线", tone };
    if (tone === "restart") return { text: "正在重启", tone };
    if (tone === "fail") return { text: "没能启动", tone };
    return { text: "已停止", tone };
  }
  if (tone === "live") return { text: "在盯着", tone };
  if (tone === "fail") return { text: job.state === "failed" ? "没能启动" : "意外退出", tone };
  return { text: job.state === "stopped" ? "已停止" : "已结束", tone };
}

/** The line under a job's name: what it is up to, in a few words. */
export function metaOf(job: Job, now: number): ReactNode {
  const w = word(job);
  const said = <em className="job-word" data-tone={w.tone}>{w.text}</em>;
  const ended = job.endedAt ? ago(job.endedAt, now) : null;
  if (isService(job)) {
    if (w.tone === "up") return <>{said} · {span(now - job.startedAt)}</>;
    if (w.tone === "restart") return <>{said}{job.restarts ? ` · 第 ${job.restarts} 次` : ""}</>;
    return <>{said}{ended ? ` · ${ended}` : ""}</>;
  }
  if (w.tone === "live") {
    const last = job.notices?.[0];
    if (last) return <><span className="job-said">{last.text}</span> · {ago(last.at, now)}</>;
    if (job.outputAt) return <>还没通知过 · 最后输出 {ago(job.outputAt, now)}</>;
    return <>{said} · {span(now - job.startedAt)}</>;
  }
  if (w.tone === "fail" && job.state !== "failed") {
    return <>{said} · {job.exitCode !== undefined ? `退出码 ${job.exitCode}` : "被信号结束"}{ended ? ` · ${ended}` : ""}</>;
  }
  return <>{said}{ended ? ` · ${ended}` : ""}</>;
}

/** A job's status: a small dot, on its name's line. */
export function JobDot({ tone }: { tone: Tone }) {
  return <span className="job-dot" data-tone={tone} aria-hidden="true" />;
}

/** A job's row: its dot, its name, what it is up to; what is at its end (a service's arrow, a job's chevron). */
export function JobRow({ job, now, onClick, end, selected, expanded }:
  { job: Job; now: number; onClick?: (() => void) | undefined; end?: ReactNode; selected?: boolean; expanded?: boolean }) {
  const tone = toneOf(job);
  return (
    <button type="button" className="job-row" onClick={onClick} data-static={!onClick || undefined} data-off={tone === "off" || undefined} data-selected={selected || undefined}
      aria-expanded={expanded} aria-current={selected || undefined}>
      <JobDot tone={tone} />
      <span className="job-text">
        <span className="job-name">{job.name}</span>
        <span className="job-meta">{metaOf(job, now)}</span>
      </span>
      {end && <span className="job-end">{end}</span>}
    </button>
  );
}

/** A job's output (its last `lines`), read again every `every` ms while shown. */
export function useJobLog(station: string, id: string | null, lines: number, every = 2000): { text: string; outputAt?: number } | null {
  const call = useStationCall(station);
  const [log, setLog] = useState<{ id: string; text: string; outputAt?: number } | null>(null);
  useEffect(() => {
    if (!id) return;
    let live = true;
    const read = () => void call.request<{ text: string; outputAt?: number }>("GET", `/jobs/${encodeURIComponent(id)}/log?lines=${lines}`)
      .then((r) => { if (live) setLog({ id, text: r.text, ...(r.outputAt ? { outputAt: r.outputAt } : {}) }); }, () => {});
    read();
    const timer = setInterval(read, every);
    return () => { live = false; clearInterval(timer); };
  }, [call, id, lines, every]);
  return log && log.id === id ? log : null;
}

/** Stops a job from the page (its agent is told who did). */
export function useStopJob(station: string): (job: Job) => void {
  const call = useStationCall(station);
  const toast = useToast();
  return (job) => void call.request("POST", `/jobs/${encodeURIComponent(job.id)}/stop`)
    .catch((e: Error) => toast(`没能停下「${job.name}」：${e.message}`));
}

/** The last line a job wrote, and when. */
function LastOutput({ station, job, now }: { station: string; job: Job; now: number }) {
  const log = useJobLog(station, job.id, 1, job.state === "running" ? 3000 : 600_000);
  const at = log?.outputAt ?? job.outputAt;
  const line = log?.text.trim();
  if (!at && !line) return null;
  return (
    <div className="job-last">
      <span>最后输出{at ? ` · ${ago(at, now)}` : ""}</span>
      {line && <code>{line}</code>}
    </div>
  );
}

/** What a job said, newest first, each with when. */
function Notices({ job, now, limit, clockTimes = false }: { job: Job; now: number; limit?: number; clockTimes?: boolean }) {
  const notices = (job.notices ?? []).slice(0, limit);
  if (notices.length === 0) return <p className="job-notices-none">还没有通知。它用 <code>ember-job notify</code> 说的话会列在这里。</p>;
  return (
    <ol className="job-notices" data-clock={clockTimes || undefined}>
      {notices.map((n, i) => <li key={`${n.at}-${i}`}><time dateTime={new Date(n.at).toISOString()}>{clockTimes ? clock(n.at, now) : ago(n.at, now)}</time><span>{n.text}</span></li>)}
    </ol>
  );
}

/**
 * The title bar popover's body: what matters now (services up or restarting, jobs alive, what died lately); a job opens
 * in place to its last few notices and last output; everything else is a click away in the 任务 tab.
 */
export function JobsPopover({ station, jobs, onService, onTab }:
  { station: string; jobs: Job[]; onService: (id: string) => void; onTab: (id?: string) => void }) {
  const now = useNow();
  const stop = useStopJob(station);
  const [open, setOpen] = useState<string | null>(null);
  if (jobs.length === 0) {
    return <div className="jobs-empty"><b>还没有服务或后台任务</b><span>agent 开网页、或挂上长期盯着的任务时，会列在这里。</span></div>;
  }
  const shown = sorted(jobs.filter((j) => isCurrent(j, now)));
  const services = shown.filter(isService);
  const plain = shown.filter((j) => !isService(j));
  const hidden = jobs.length - shown.length;
  const count = (list: Job[], tone: Tone) => list.filter((j) => toneOf(j) === tone).length;
  const serviceNote = [count(services, "up") && `${count(services, "up")} 个在线`, count(services, "restart") && `${count(services, "restart")} 个在重启`].filter(Boolean).join("，");
  const plainNote = count(plain, "live") ? `${count(plain, "live")} 个在盯着` : "";
  return (
    <>
      {services.length > 0 && (
        <section>
          <div className="jobs-head">服务{serviceNote && <span>{serviceNote}</span>}</div>
          {services.map((j) => (
            <JobRow key={j.id} job={j} now={now} onClick={toneOf(j) === "fail" ? () => onTab(j.id) : () => onService(j.id)}
              end={toneOf(j) === "fail" ? <ChevronRight size={16} /> : <ArrowRight size={16} />} />
          ))}
        </section>
      )}
      {plain.length > 0 && (
        <section>
          <div className="jobs-head">后台任务{plainNote && <span>{plainNote}</span>}</div>
          {plain.map((j) => (
            <div key={j.id} className="job-fold" data-open={open === j.id || undefined}>
              <JobRow job={j} now={now} expanded={open === j.id} onClick={() => setOpen(open === j.id ? null : j.id)}
                end={open === j.id ? <ChevronDown size={16} /> : <ChevronRight size={16} />} />
              {open === j.id && (
                <div className="job-fold-body">
                  <Notices job={j} now={now} limit={3} />
                  <LastOutput station={station} job={j} now={now} />
                  <div className="job-actions">
                    {j.state === "running" && <button type="button" className="job-action" onClick={() => stop(j)}><Stop size={14} />停止</button>}
                    <button type="button" className="job-action" onClick={() => onTab(j.id)}><PanelOpen size={14} />在侧栏看</button>
                  </div>
                </div>
              )}
            </div>
          ))}
        </section>
      )}
      {shown.length === 0 && <p className="jobs-quiet">眼下没有在跑的服务或任务。</p>}
      <button type="button" className="jobs-all" onClick={() => onTab()}>
        全部 {jobs.length} 个 · 在侧栏看{hidden > 0 && <span>另有 {hidden} 个已停止或结束</span>}
      </button>
    </>
  );
}

/**
 * The 任务 tab beside the chat: every service and job (those over faded, last); a job picked shows what it said, or
 * its output as it grows, under its name, state and command.
 */
export function JobsTab({ station, jobs, picked, onPick, onService }:
  { station: string; jobs: Job[]; picked: string | null; onPick: (id: string) => void; onService: (id: string) => void }) {
  const now = useNow();
  const stop = useStopJob(station);
  const [view, setView] = useState<"notices" | "output">("notices");
  const all = sorted(jobs);
  const services = all.filter(isService);
  const plain = all.filter((j) => !isService(j));
  const job = plain.find((j) => j.id === picked) ?? plain[0] ?? null;
  if (jobs.length === 0) return <Empty><p>这个对话里还没有服务或后台任务。</p></Empty>;
  return (
    <div className="jobs-tab">
      <div className="jobs-tab-list">
        {services.length > 0 && (
          <section>
            <div className="jobs-head">服务</div>
            {services.map((j) => (
              <JobRow key={j.id} job={j} now={now} onClick={toneOf(j) === "up" || toneOf(j) === "restart" ? () => onService(j.id) : undefined}
                end={toneOf(j) === "up" || toneOf(j) === "restart" ? <ArrowRight size={16} /> : undefined} />
            ))}
          </section>
        )}
        {plain.length > 0 && (
          <section>
            <div className="jobs-head">后台任务</div>
            {plain.map((j) => <JobRow key={j.id} job={j} now={now} selected={j.id === job?.id} onClick={() => onPick(j.id)} />)}
          </section>
        )}
      </div>
      {job && (
        <div className="job-detail">
          <div className="job-detail-head">
            <JobDot tone={toneOf(job)} />
            <b>{job.name}</b>
            <span className="job-detail-state">{word(job).text} · {job.state === "running" ? span(now - job.startedAt) : job.endedAt ? ago(job.endedAt, now) : ""}{job.notices?.length ? ` · ${job.notices.length} 条通知` : ""}</span>
            <span className="job-detail-grow" />
            <Segmented<"notices" | "output"> label="看什么" value={view} onChange={setView} options={[{ value: "notices", label: "通知" }, { value: "output", label: "输出" }]} />
            {job.state === "running" && <button type="button" className="icon-btn job-detail-stop" aria-label="停止" title="停止" onClick={() => stop(job)}><Stop size={16} /></button>}
          </div>
          {job.command && <div className="job-detail-command" title={job.command}>{job.command}</div>}
          {view === "notices"
            ? <><div className="job-detail-notices"><Notices job={job} now={now} clockTimes /></div><LastOutput station={station} job={job} now={now} /></>
            : <Output station={station} job={job} />}
        </div>
      )}
    </div>
  );
}

/** A job's output, following its end while it is scrolled there. */
function Output({ station, job }: { station: string; job: Job }) {
  const log = useJobLog(station, job.id, 400, job.state === "running" ? 2000 : 60_000);
  const box = useRef<HTMLPreElement>(null);
  const atEnd = useRef(true);
  useEffect(() => {
    const el = box.current;
    if (el && atEnd.current) el.scrollTop = el.scrollHeight;
  }, [log?.text]);
  return (
    <pre ref={box} className="job-output" onScroll={(e) => { const el = e.currentTarget; atEnd.current = el.scrollHeight - el.scrollTop - el.clientHeight < 24; }}>
      {log === null ? "正在读取…" : log.text || "（还没有输出）"}
    </pre>
  );
}
