import "./renamed.ts";
import "./styles/index.ts";
import { followAppearance } from "./theme.ts";
import { startScrollbars } from "./scrollbars.ts";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "@fontsource-variable/inter";
import { CloudApp } from "./cloud/CloudApp.tsx";
import { nameTitle } from "./cloud/beta.tsx";
import { startTelemetry } from "./telemetry.ts";

import { webUpdates } from "./core/webUpdates.ts";

if (import.meta.env.PROD) webUpdates.start();
followAppearance();
startScrollbars();

// still.fail cloud's web app (sign-in, workspaces; stations over iroh). The data comes from the client core (core/); a
// station serves no page of its own.
startTelemetry("cloud");
nameTitle();
createRoot(document.getElementById("app")!).render(<StrictMode><CloudApp /></StrictMode>);
