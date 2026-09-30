// At the sidebar's foot: the services and background jobs left up a long while (an hour), across the chats of the
// scope's stations, so none is forgotten running: web services and background jobs, each under its heading; nothing at
// all while there are none. Each leads to its chat (a service opens there, beside it) and stops from here. The core
// puts them together (its `longJobs` view, from each station's `jobs`, current with its events).
import { useState } from "react";
import { NavLink } from "react-router";
import type { Job, LongJobsView } from "./core/shapes.ts";
import { useCall, useTopic } from "./core/react.ts";
import { useToast } from "./toast.tsx";
import { stationBase } from "./station.tsx";
import { JobDot } from "./Jobs.tsx";
import { Stop } from "./icons.tsx";
import { Tip } from "./ui.tsx";
import * as css from "./OpenJobs.css.ts";

/** Rows shown before the rest folds under「还有 N 个」. */
export const SHOWN = 3;

/**
 * What both screens show (the phone's at the top of its list, ./mobile/OpenJobs.tsx): the scope's `longJobs` as the
 * core has them (those up longer than an hour on its stations that are up, oldest first, in two groups; none while
 * empty), and stopping one (what went wrong said in `toast`).
 */
export function useLongJobs(scope: string, toast: (text: string) => void) {
  // A core from before it knows none: nothing to show.
  const groups = useTopic<LongJobsView>({ topic: "longJobs", scope }).value?.groups ?? [];
  const call = useCall();
  // The core puts the job in place as it is now: gone from here, stopped in its chat.
  const stop = (job: Job) => void (call("job.stop", { station: job.station, id: job.id }) as Promise<unknown>)
    .catch((e: Error) => toast(`没能停下「${job.name}」：${e.message}`));
  return { groups, stop };
}

/** Its chat's address, when it is in one. */
export const chatPath = (job: Job) => job.chat && job.station ? `${stationBase(job.station)}/chats/${encodeURIComponent(job.chat.id)}` : null;

export function OpenJobs({ scope }: { scope: string }) {
  const toast = useToast();
  const { groups, stop } = useLongJobs(scope, toast);
  const [all, setAll] = useState<Record<string, boolean>>({});
  if (groups.length === 0) return null;
  const row = (job: Job) => {
    const path = chatPath(job);
    const chat = path && `${path}${job.service ? `?service=${encodeURIComponent(job.id)}` : ""}`;
    const body = (
      <>
        <span className={css.openJobMark}><JobDot tone={job.tone} /></span>
        <span className={css.openJobText}>
          <span className={css.openJobName}>{job.name}</span>
          <span className={css.openJobWhere}>{job.whereText}</span>
        </span>
        <span className={css.openJobAge}>{job.age}</span>
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
  const group = (key: string, head: string, list: Job[]) => {
    if (list.length === 0) return null;
    const shown = all[key] || list.length <= SHOWN + 1 ? list : list.slice(0, SHOWN);
    return (
      <div key={key} className={css.openJobsGroup}>
        <div className={css.openJobsHead}>{head}</div>
        {shown.map(row)}
        {shown.length < list.length && <button type="button" className={css.openJobsMore} onClick={() => setAll({ ...all, [key]: true })}>还有 {list.length - shown.length} 个</button>}
      </div>
    );
  };
  return (
    <section className={css.openJobs} aria-label="开了很久的服务和任务">
      {groups.map((g) => group(g.key, g.head, g.jobs))}
    </section>
  );
}
