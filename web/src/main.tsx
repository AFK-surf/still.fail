import "./renamed.ts";
import "./styles/index.ts";
import "./viewer/whole.ts";
import { followAppearance } from "./theme.ts";
import { followFonts } from "./fonts.ts";
import { startScrollbars } from "./scrollbars.ts";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { I18nRoot } from "./i18n.ts";
import "@fontsource-variable/inter";
import { CloudApp } from "./cloud/CloudApp.tsx";
import { nameTitle } from "./cloud/beta.tsx";
import { startTelemetry } from "./telemetry.ts";
import { followPageLoads } from "./reloads.ts";

import { webUpdates } from "./core/webUpdates.ts";

if (import.meta.env.PROD) webUpdates.start();
// In development, what is off (a corner, a small panel's padding) outlined in red as it shows (dev/offs.ts).
if (import.meta.env.DEV) void import("./dev/offs.ts").then((m) => m.watchOffs());
followAppearance();
followFonts();
startScrollbars();

// still.fail cloud's web app (sign-in, workspaces; stations over iroh). The data comes from the client core (core/); a
// station serves no page of its own.
startTelemetry("cloud");
followPageLoads();
nameTitle();
createRoot(document.getElementById("app")!).render(<StrictMode><I18nRoot><CloudApp /></I18nRoot></StrictMode>);
