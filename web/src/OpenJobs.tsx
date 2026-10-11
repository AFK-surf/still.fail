// At the sidebar's foot: the services and background jobs left up a long while (an hour), across the chats of the
// scope's stations, so none is forgotten running: web services and background jobs, each under its heading; nothing at
// all while there are none. Each leads to its chat (a service opens there, beside it) and stops from here. The core
// puts them together (its `longJobs` view, from each station's `jobs`, current with its events).
import { useState } from "react";
import { Popover } from "radix-ui";
import { NavLink } from "react-router";
import type { Job, LongJobsView } from "./core/shapes.ts";
import { useCall, useTopic } from "./core/react.ts";
import { failure, useToast } from "./toast.tsx";
import { stationBase } from "./station.tsx";
import { JobDot, JobStop } from "./Jobs.tsx";
import { Tip } from "./ui.tsx";
import * as css from "./OpenJobs.css.ts";
import * as controlsCss from "./styles/controls.css.ts";
import { t } from "./i18n.ts";

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
    .catch((e: unknown) => toast(t("web-main.jobs.stopFailed", { name: job.name, error: failure(e) })));
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
        <Tip label={t("web-main.jobs.stop")} side="top">
          <JobStop station={job.station ?? ""} job={job} stop={stop} className={css.openJobStop} label={t("web-main.jobs.stopNamed", { name: job.name })} />
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
        {shown.length < list.length && <button type="button" className={css.openJobsMore} onClick={() => setAll({ ...all, [key]: true })}>{t("web-main.jobs.more", { n: list.length - shown.length })}</button>}
      </div>
    );
  };
  return (
    <section className={css.openJobs} aria-label={t("web-main.jobs.long")}>
      {groups.map((g) => group(g.key, g.head, g.jobs))}
    </section>
  );
}

/**
 * The sidebar's foot keeps them small: how many, beside the stations' line, and pressed, the list (OpenJobs) above it.
 * Nothing while there are none.
 */
export function OpenJobsChip({ scope }: { scope: string }) {
  const toast = useToast();
  const { groups } = useLongJobs(scope, toast);
  const n = groups.reduce((sum, g) => sum + g.jobs.length, 0);
  if (n === 0) return null;
  return (
    <Popover.Root>
      <Popover.Trigger asChild>
        <button type="button" className={css.openJobsChip} aria-label={t("web-main.jobs.long")}><span className={css.openJobsChipDot} />{t("web-main.jobs.chip", { n })}</button>
      </Popover.Trigger>
      <Popover.Portal>
        <Popover.Content className={`${controlsCss.popover} ${css.openJobsPop}`} side="top" align="end" sideOffset={6} collisionPadding={8}>
          <OpenJobs scope={scope} />
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  );
}
