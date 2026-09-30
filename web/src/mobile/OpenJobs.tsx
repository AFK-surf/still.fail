// The services and background jobs left up a long while, at the top of the list on a narrow screen (what a phone sees
// first), as the Android app has them (apps/android/…/screens/OpenJobs.kt): the wide screen's (../OpenJobs.tsx
// useLongJobs, at its sidebar's foot), each row leading to its chat (a service opens over it) and stopped from its end,
// always shown (no hover here). Nothing at all while there are none.
import { useMemo, useState } from "react";
import type { StationState } from "../core/shapes.ts";
import { chatPath, SHOWN, useLongJobs, whereOf, type Held } from "../OpenJobs.tsx";
import { isService, JobDot, span, toneOf } from "../Jobs.tsx";
import { Stop } from "../icons.tsx";
import { useApp } from "./app.tsx";
import * as css from "./OpenJobs.css.ts";

export function OpenJobs({ stations }: { stations: StationState[] }) {
  const app = useApp();
  const several = stations.length > 1;
  const online = useMemo(() => stations.filter((s) => s.state === "online").map((s) => ({ address: s.station, ...(several ? { name: s.name } : {}) })),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [stations.map((s) => `${s.station}\t${s.name}\t${s.state}`).join("\n")]);
  const { now, groups, stop } = useLongJobs(online, app.toast);
  const [all, setAll] = useState<Record<string, boolean>>({});
  if (groups.length === 0) return null;
  const open = (job: Held) => {
    const path = chatPath(job);
    if (!path) return;
    app.push(path);
    if (isService(job)) app.push(`${path}/services/${encodeURIComponent(job.id)}`);
  };
  return (
    <section className={css.mOpenJobs} aria-label="开了很久的服务和任务">
      {groups.map(({ key, head, list }) => {
        const shown = all[key] || list.length <= SHOWN + 1 ? list : list.slice(0, SHOWN);
        return (
          <div key={key} className={css.mOpenGroup}>
            <div className={css.mOpenHead}>{head} · {list.length}</div>
            {shown.map((job) => (
              <div key={`${job.station}/${job.id}`} className={css.mOpenRow} data-link={job.chat ? true : undefined} onClick={() => open(job)}>
                <span className={css.mOpenMark}><JobDot tone={toneOf(job)} /></span>
                <span className={css.mOpenText}>
                  <span className={css.mOpenName}>{job.name}</span>
                  <span className={css.mOpenWhere}>{whereOf(job)} · {span(now - job.startedAt)}</span>
                </span>
                <button type="button" className={css.mOpenStop} aria-label={`停止「${job.name}」`} onClick={(e) => { e.stopPropagation(); stop(job); }}><Stop size={15} /></button>
              </div>
            ))}
            {shown.length < list.length && <button type="button" className={css.mOpenMore} onClick={() => setAll({ ...all, [key]: true })}>还有 {list.length - shown.length} 个</button>}
          </div>
        );
      })}
    </section>
  );
}
