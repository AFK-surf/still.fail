// A web service an agent started, full screen on a narrow screen: the desktop's preview (../Preview.tsx) under a bar
// that goes back to the chat. Found by its job; people know it by its name.
import { useEffect, useState } from "react";
import { useParams } from "react-router";
import { useCall } from "../core/react.ts";
import { StationPreview } from "../Preview.tsx";
import { useStation } from "../station.tsx";
import { useApp } from "./app.tsx";
import { NavBar } from "./parts.tsx";

export function PreviewScreen() {
  const app = useApp();
  const station = useStation();
  const service = useParams().service ?? "";
  const call = useCall();
  const [job, setJob] = useState<{ name: string; port: number | null; state: string } | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    call("station.request", { station: station.address, method: "GET", path: `/jobs/${encodeURIComponent(service)}` })
      .then((j) => setJob(j as { name: string; port: number | null; state: string }), (e: Error) => setError(e.message));
  }, [call, station.address, service]);
  const up = job && job.port !== null && (job.state === "running" || job.state === "exited");
  return (
    <div className="m-screen m-preview">
      <NavBar back="对话" onBack={app.pop} title={job?.name ?? "服务"} sub={<span className="m-navbar-note">{station.name}</span>} />
      {error && <p className="m-note">找不到这个服务：{error}</p>}
      {job && !up && <p className="m-note">「{job.name}」已经停了。</p>}
      {job && up && <StationPreview station={station.address} port={job.port!} name={job.name} service={service} alone />}
    </div>
  );
}
