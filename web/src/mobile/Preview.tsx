// A web service an agent started (or a visualization it posted), full screen on a narrow screen: the desktop's preview (../Preview.tsx) under a bar
// that goes back to the chat. Found by its job; people know it by its name. The job is its chat's, kept as the chat
// changes (a restart is said over the page, and it loads again once the service is back); read once by itself until the
// chat has it.
import { useEffect, useState } from "react";
import { useParams } from "react-router";
import { useChat } from "../api.ts";
import { useCall } from "../core/react.ts";
import type { Job } from "../core/shapes.ts";
import { fileSourceOf, StationPreview } from "../Preview.tsx";
import { useStation } from "../station.tsx";
import { useApp } from "./app.tsx";
import { draftKeyOf } from "./ChatHost.tsx";
import { NavBar } from "./parts.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as css from "./Preview.css.ts";
import * as barsCss from "./styles/bars.css.ts";
import * as homeCss from "./styles/home.css.ts";

export function PreviewScreen() {
  const app = useApp();
  const station = useStation();
  const { chat = "", service = "" } = useParams();
  // A visualization an agent posted opens here too, as a service does (../Preview.tsx's fileService).
  const file = fileSourceOf(service);
  const call = useCall();
  const view = useChat(station.address, { session: chat }).value;
  const live = view?.agents.flatMap((a) => a.jobs ?? []).find((j) => j.id === service);
  const [read, setRead] = useState<Job | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    if (file) return;
    call("station.request", { station: station.address, method: "GET", path: `/jobs/${encodeURIComponent(service)}` })
      .then((j) => setRead(j as Job), (e: Error) => setError(e.message));
  }, [call, station.address, service]);
  const job = live ?? read;
  const up = job && job.port != null && (job.state === "running" || job.state === "exited");
  if (file) {
    return (
      <div className={`${pagesCss.mScreen} ${css.mPreview}`}>
        <NavBar back="对话" onBack={app.pop} title={file.name} sub={<span className={barsCss.mNavbarNote}>{station.name}</span>} />
        <StationPreview station={station.address} file={file} name={file.name} service={service} alone restarting={null} draftKey={draftKeyOf(station.address, chat)} />
      </div>
    );
  }
  return (
    <div className={`${pagesCss.mScreen} ${css.mPreview}`}>
      <NavBar back="对话" onBack={app.pop} title={job?.name ?? "服务"} sub={<span className={barsCss.mNavbarNote}>{station.name}</span>} />
      {error && !job && <p className={homeCss.mNote}>找不到这个服务：{error}</p>}
      {job && !up && <p className={homeCss.mNote}>「{job.name}」已经停了。</p>}
      {job && up && (
        <StationPreview station={station.address} port={job.port!} name={job.name} service={service} alone
          restarting={job.state === "exited" ? { restarts: job.restarts ?? 0 } : null} draftKey={draftKeyOf(station.address, chat)} />
      )}
    </div>
  );
}

