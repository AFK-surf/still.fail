import "./renamed.ts";
import "./styles/index.ts";
import { applyAppearance } from "./theme.ts";
import { startScrollbars } from "./scrollbars.ts";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter } from "react-router";
import "@fontsource-variable/inter";
import { App } from "./App.tsx";
import { PageViews, startTelemetry } from "./telemetry.ts";

applyAppearance();
startScrollbars();
const root = createRoot(document.getElementById("app")!);

// Built twice: served by a station at /admin (talks to it directly), and as
// ember cloud's web app at / (sign-in, workspaces; stations over iroh). Either way the
// data comes from the client core (core/)..
startTelemetry(import.meta.env.MODE === "cloud" ? "cloud" : "station");
if (import.meta.env.MODE === "cloud") {
  const { CloudApp } = await import("./cloud/CloudApp.tsx");
  root.render(<StrictMode><CloudApp /></StrictMode>);
} else {
  root.render(
    <StrictMode>
      <BrowserRouter basename="/admin">
        <PageViews />
        <App />
      </BrowserRouter>
    </StrictMode>,
  );
}
