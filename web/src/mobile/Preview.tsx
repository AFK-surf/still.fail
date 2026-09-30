// A web service an agent started (or a visualization it posted), full screen on a narrow screen: the desktop's preview (../Preview.tsx) under a bar
// that goes back to the chat. Found by its job; people know it by its name. The core keeps the job as it changes (a
// restart is said over the page, and it loads again once the service is back).
import { useParams } from "react-router";
import { useJob } from "../api.ts";
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
  // Kept current by the core (its events, or read again from a station too old to send them).
  const found = useJob(station.address, file ? null : service);
  const job = found.value ?? null;
  const error = found.error?.message ?? null;
  const up = job?.open && job.port != null;
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

