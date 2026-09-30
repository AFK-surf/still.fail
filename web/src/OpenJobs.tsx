// At the sidebar's foot: the services and background jobs left up a long while, across the chats of the scope's
// stations, so none is forgotten running: web services and background jobs, each under its heading. Only those up for more than LONG; nothing at all while there are none. Each
// leads to its chat (a service opens there, beside it) and stops from here. The core keeps the lists (the `jobs` topic
// of each station, current with its events).
import { useState } from "react";
import { NavLink } from "react-router";
import type { Job } from "./core/shapes.ts";
import { useCall, useTopics } from "./core/react.ts";
import { useToast } from "./toast.tsx";
import { stationBase } from "./station.tsx";
import { isService, JobDot, span, toneOf, useNow } from "./Jobs.tsx";
import { Stop } from "./icons.tsx";
import { Tip } from "./ui.tsx";
import * as css from "./OpenJobs.css.ts";

/** Up this long, a service or job is worth a reminder. */
const LONG = 3600_000;
/** How often the ages are worked out again. */
const EVERY = 60_000;
/** Rows shown before the rest folds under「还有 N 个」. */
export const SHOWN = 3;

/** A job still up, as a station's `jobs` topic has it: with the chat it is in, when the viewer sees one. */
type OpenJob = Job & { chat?: { id: string; title: string; archived: boolean } };
export type Held = OpenJob & { station: string; stationName?: string };

/** Those of `stations` (addresses, with names when there are several to tell apart), as the core keeps them. */
function useOpenJobs(stations: { address: string; name?: string }[]): Held[] {
  const states = useTopics<OpenJob[]>(stations.map((s) => ({ topic: "jobs", station: s.address })));
  // A station that does not answer, or too old to know the list, has none to show.
  return stations.flatMap((s, i) => (Array.isArray(states[i]?.value) ? states[i]!.value! : [])
    .map((j) => ({ ...j, station: s.address, ...(s.name ? { stationName: s.name } : {}) })));
}

/**
 * What both screens show (the phone's at the top of its list, ./mobile/OpenJobs.tsx): those up longer than LONG, the
 * oldest first, in two groups (none while empty), with the time now to age them by, and stopping one (what went wrong
 * said in `toast`).
 */
export function useLongJobs(stations: { address: string; name?: string }[], toast: (text: string) => void) {
  const now = useNow(EVERY);
  const jobs = useOpenJobs(stations);
  const call = useCall();
  const long = jobs.filter((j) => now - j.startedAt >= LONG).sort((a, b) => a.startedAt - b.startedAt);
  const groups = [
    { key: "services", head: "开了很久的网页服务", list: long.filter(isService) },
    { key: "jobs", head: "一直在跑的后台任务", list: long.filter((j) => !isService(j)) },
  ].filter((g) => g.list.length > 0);
  // The core puts the job in place as it is now: gone from here, stopped in its chat.
  const stop = (job: Held) => void (call("job.stop", { station: job.station, id: job.id }) as Promise<unknown>)
    .catch((e: Error) => toast(`没能停下「${job.name}」：${e.message}`));
  return { now, groups, stop };
}

/** Where a job is: its station (when there are several), its chat, whether that is archived. */
export const whereOf = (job: Held) => [job.stationName, job.chat?.title || (job.chat ? "对话" : "不在任何对话里"), job.chat?.archived && "已归档"].filter(Boolean).join(" · ");
/** Its chat's address, when it is in one. */
export const chatPath = (job: Held) => job.chat ? `${stationBase(job.station)}/chats/${encodeURIComponent(job.chat.id)}` : null;

export function OpenJobs({ stations }: { stations: { address: string; name?: string }[] }) {
  const toast = useToast();
  const { now, groups, stop } = useLongJobs(stations, toast);
  const [all, setAll] = useState<Record<string, boolean>>({});
  if (groups.length === 0) return null;
  const row = (job: Held) => {
    const path = chatPath(job);
    const chat = path && `${path}${isService(job) ? `?service=${encodeURIComponent(job.id)}` : ""}`;
    const where = whereOf(job);
    const body = (
      <>
        <span className={css.openJobMark}><JobDot tone={toneOf(job)} /></span>
        <span className={css.openJobText}>
          <span className={css.openJobName}>{job.name}</span>
          <span className={css.openJobWhere}>{where}</span>
        </span>
        <span className={css.openJobAge}>{span(now - job.startedAt)}</span>
      </>
    );
    return (
      <div key={`${job.station}/${job.id}`} className={css.openJob}>
        {chat ? <NavLink className={css.openJobRow} to={chat}>{body}</NavLink> : <div className={css.openJobRow}>{body}</div>}
        <Tip label="停止" side="top">
          <button type="button" className={css.openJobStop} aria-label={`停止「${job.name}」`} onClick={() => stop(job)}><Stop size={14} /></button>
        </Tip>
      </div>
    );
  };
  const group = (key: string, head: string, list: Held[]) => {
    if (list.length === 0) return null;
    const shown = all[key] || list.length <= SHOWN + 1 ? list : list.slice(0, SHOWN);
    return (
      <div key={key} className={css.openJobsGroup}>
        <div className={css.openJobsHead}>{head} · {list.length}</div>
        {shown.map(row)}
        {shown.length < list.length && <button type="button" className={css.openJobsMore} onClick={() => setAll({ ...all, [key]: true })}>还有 {list.length - shown.length} 个</button>}
      </div>
    );
  };
  return (
    <section className={css.openJobs} aria-label="开了很久的服务和任务">
      {groups.map((g) => group(g.key, g.head, g.list))}
    </section>
  );
}
