// A web service on a station's machine, full screen on a narrow screen: the desktop's preview (../Preview.tsx) under a
// bar that goes back to the chat.
import { useParams } from "react-router";
import { StationPreview } from "../Preview.tsx";
import { useStation } from "../station.tsx";
import { useApp } from "./app.tsx";
import { NavBar } from "./parts.tsx";

export function PreviewScreen() {
  const app = useApp();
  const station = useStation();
  const port = Number(useParams().port);
  return (
    <div className="m-screen m-preview">
      <NavBar back="对话" onBack={app.pop} title={`localhost:${port}`} sub={<span className="m-navbar-note">{station.name}</span>} />
      <StationPreview station={station.address} port={port} />
    </div>
  );
}
