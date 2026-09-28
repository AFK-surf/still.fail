// A web service an agent started, full screen on a narrow screen: the desktop's preview (../Preview.tsx) under a bar
// that goes back to the chat. Found by its job; people know it by its name. The job is its chat's, kept as the chat
// changes (a restart is said over the page, and it loads again once the service is back); read once by itself until the
// chat has it.
import { useEffect, useState } from "react";
import { useParams } from "react-router";
import { useChat } from "../api.ts";
import { useCall } from "../core/react.ts";
import type { Job } from "../core/shapes.ts";
import { StationPreview } from "../Preview.tsx";
import { useStation } from "../station.tsx";
import { useApp } from "./app.tsx";
import { NavBar } from "./parts.tsx";

export function PreviewScreen() {
  const app = useApp();
  const station = useStation();
  const { chat = "", service = "" } = useParams();
  const call = useCall();
  const view = useChat(station.address, { session: chat }).value;
  const live = view?.agents.flatMap((a) => a.jobs ?? []).find((j) => j.id === service);
  const [read, setRead] = useState<Job | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    call("station.request", { station: station.address, method: "GET", path: `/jobs/${encodeURIComponent(service)}` })
      .then((j) => setRead(j as Job), (e: Error) => setError(e.message));
  }, [call, station.address, service]);
  const job = live ?? read;
  const up = job && job.port != null && (job.state === "running" || job.state === "exited");
  return (
    <div className="m-screen m-preview">
      <NavBar back="对话" onBack={app.pop} title={job?.name ?? "服务"} sub={<span className="m-navbar-note">{station.name}</span>} />
      {error && !job && <p className="m-note">找不到这个服务：{error}</p>}
      {job && !up && <p className="m-note">「{job.name}」已经停了。</p>}
      {job && up && (
        <StationPreview station={station.address} port={job.port!} name={job.name} service={service} alone
          restarting={job.state === "exited" ? { restarts: job.restarts ?? 0 } : null} />
      )}
    </div>
  );
}
