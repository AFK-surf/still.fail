// The services and background jobs left up a long while, at the top of the list on a narrow screen (what a phone sees
// first), as the Android app has them (apps/android/…/screens/OpenJobs.kt): the wide screen's (../OpenJobs.tsx
// useLongJobs, at its sidebar's foot), each row leading to its chat (a service opens over it) and stopped from its end,
// always shown (no hover here). Nothing at all while there are none.
import { useState } from "react";
import type { Job } from "../core/shapes.ts";
import { chatPath, SHOWN, useLongJobs } from "../OpenJobs.tsx";
import { JobDot } from "../Jobs.tsx";
import { Stop } from "../icons.tsx";
import { doingMatches, failed, useDoingList } from "../doing.ts";
import { useApp } from "./app.tsx";
import { FailedMark, failedIn, Spinner } from "./parts.tsx";
import * as css from "./OpenJobs.css.ts";
import { t } from "../i18n.ts";

export function OpenJobs({ scope }: { scope: string }) {
  const app = useApp();
  const { groups, stop } = useLongJobs(scope, app.toast);
  const [all, setAll] = useState<Record<string, boolean>>({});
  const doing = useDoingList();
  // Stopping: its spinner in the button's place until the station answers (the toast says if it could not), and the
  // failure mark before the button a few seconds after it could not.
  const stopping = (job: Job) => doing.some((d) => !failed(d) && doingMatches(d, "job.stop", { station: job.station, id: job.id }));
  const stopFailed = (job: Job) => failedIn(doing, "job.stop", { station: job.station, id: job.id });
  if (groups.length === 0) return null;
  const open = (job: Job) => {
    const path = chatPath(job);
    if (!path) return;
    app.push(path);
    if (job.service) app.push(`${path}/services/${encodeURIComponent(job.id)}`);
  };
  return (
    <section className={css.mOpenJobs} aria-label={t("web-mobile.openJobs.label")}>
      {groups.map(({ key, head, jobs: list }) => {
        const shown = all[key] || list.length <= SHOWN + 1 ? list : list.slice(0, SHOWN);
        return (
          <div key={key} className={css.mOpenGroup}>
            <div className={css.mOpenHead}>{head}</div>
            {shown.map((job) => (
              <div key={`${job.station}/${job.id}`} className={css.mOpenRow} data-link={job.chat ? true : undefined} onClick={() => open(job)}>
                <span className={css.mOpenMark}><JobDot tone={job.tone} /></span>
                <span className={css.mOpenText}>
                  <span className={css.mOpenName}>{job.name}</span>
                  <span className={css.mOpenWhere}>{job.whereText} · {job.age}</span>
                </span>
                {!stopping(job) && stopFailed(job) !== undefined && <FailedMark error={stopFailed(job)!} />}
                <button type="button" className={css.mOpenStop} aria-label={t("web-mobile.openJobs.stop", { name: job.name })} disabled={stopping(job)} aria-busy={stopping(job) || undefined}
                  onClick={(e) => { e.stopPropagation(); stop(job); }}>
                  {stopping(job) ? <Spinner size={15} /> : <Stop size={15} />}
                </button>
              </div>
            ))}
            {shown.length < list.length && <button type="button" className={css.mOpenMore} onClick={() => setAll({ ...all, [key]: true })}>{t("web-mobile.openJobs.more", { n: list.length - shown.length })}</button>}
          </div>
        );
      })}
    </section>
  );
}
