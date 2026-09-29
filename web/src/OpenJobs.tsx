// At the sidebar's foot: the services and background jobs left up a long while, across the chats of the scope's
// stations, so none is forgotten running: web services and background jobs, each under its heading. Only those up for more than LONG; nothing at all while there are none. Each
// leads to its chat (a service opens there, beside it) and stops from here.
import { useEffect, useState } from "react";
import { NavLink } from "react-router";
import type { Job } from "./core/shapes.ts";
import { useCall } from "./core/react.ts";
import { useToast } from "./toast.tsx";
import { stationBase } from "./station.tsx";
import { isService, JobDot, span, toneOf, useNow } from "./Jobs.tsx";
import { Stop } from "./icons.tsx";
import { Tip } from "./ui.tsx";
import * as css from "./OpenJobs.css.ts";

/** Up this long, a service or job is worth a reminder. */
const LONG = 3600_000;
/** How often the stations are asked again. */
const EVERY = 60_000;
/** Rows shown before the rest folds under「还有 N 个」. */
const SHOWN = 3;

/** A job still up, as a station's `GET /jobs` has it: with the chat it is in, when the viewer sees one. */
type OpenJob = Job & { chat?: { id: string; title: string; archived: boolean } };
type Held = OpenJob & { station: string; stationName?: string };

/** Those of `stations` (addresses, with names when there are several to tell apart), read again every minute and on coming back to the page. */
function useOpenJobs(stations: { address: string; name?: string }[]): { jobs: Held[]; reload: () => void } {
  const call = useCall();
  const [jobs, setJobs] = useState<Held[]>([]);
  const [tick, setTick] = useState(0);
  const key = stations.map((s) => s.address).join("\n");
  useEffect(() => {
    let live = true;
    const read = () => void Promise.all(stations.map((s) =>
      (call("station.request", { station: s.address, method: "GET", path: "/jobs" }) as Promise<OpenJob[]>)
        // A station that does not answer, or too old to know the list, has none to show.
        .then((list) => (Array.isArray(list) ? list : []).map((j) => ({ ...j, station: s.address, ...(s.name ? { stationName: s.name } : {}) })), () => [] as Held[]),
    )).then((all) => { if (live) setJobs(all.flat()); });
    read();
    const timer = setInterval(read, EVERY);
    const onVisible = () => { if (document.visibilityState === "visible") read(); };
    document.addEventListener("visibilitychange", onVisible);
    return () => { live = false; clearInterval(timer); document.removeEventListener("visibilitychange", onVisible); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [call, key, tick]);
  return { jobs, reload: () => setTick((t) => t + 1) };
}

export function OpenJobs({ stations }: { stations: { address: string; name?: string }[] }) {
  const now = useNow(EVERY);
  const { jobs, reload } = useOpenJobs(stations);
  const [all, setAll] = useState<Record<string, boolean>>({});
  const call = useCall();
  const toast = useToast();
  const long = jobs.filter((j) => now - j.startedAt >= LONG).sort((a, b) => a.startedAt - b.startedAt);
  if (long.length === 0) return null;
  const stop = (job: Held) => void (call("station.request", { station: job.station, method: "POST", path: `/jobs/${encodeURIComponent(job.id)}/stop` }) as Promise<unknown>)
    .then(reload, (e: Error) => toast(`没能停下「${job.name}」：${e.message}`));
  const row = (job: Held) => {
    const chat = job.chat ? `${stationBase(job.station)}/chats/${encodeURIComponent(job.chat.id)}${isService(job) ? `?service=${encodeURIComponent(job.id)}` : ""}` : null;
    const where = [job.stationName, job.chat?.title ?? "不在任何对话里", job.chat?.archived && "已归档"].filter(Boolean).join(" · ");
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
      {group("services", "开了很久的网页服务", long.filter(isService))}
      {group("jobs", "一直在跑的后台任务", long.filter((j) => !isService(j)))}
    </section>
  );
}
