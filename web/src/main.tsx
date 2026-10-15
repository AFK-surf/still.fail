import "./renamed.ts";
import "./styles/index.ts";
import { followAppearance } from "./theme.ts";
import { startScrollbars } from "./scrollbars.ts";
import { followWindowColors } from "./titleBar.ts";
import { StrictMode, useEffect } from "react";
import { createRoot } from "react-dom/client";
import { I18nRoot, useLang } from "./i18n.ts";
import "@fontsource-variable/inter";
import { CloudApp } from "./cloud/CloudApp.tsx";
import { nameTitle } from "./cloud/beta.tsx";
import { startTelemetry } from "./telemetry.ts";
import { wholeImage } from "./wholeImages.ts";
import { WindowControls } from "./WindowControls.tsx";

import { webUpdates } from "./core/webUpdates.ts";

if (import.meta.env.PROD) webUpdates.start();
// In development, what is off (a corner, a small panel's padding) outlined in red as it shows (dev/offs.ts).
if (import.meta.env.DEV) void import("./dev/offs.ts").then((m) => m.watchOffs());
followAppearance();
startScrollbars();
followWindowColors();
// The desktop app's 「复制图片」 on a chat's thumbnail copies the image it stands in for.
window.stillfailDesktop?.onImageWanted?.(wholeImage);

// still.fail cloud's web app (sign-in, workspaces; stations over iroh). The data comes from the client core (core/); a
// station serves no page of its own.
startTelemetry("cloud");
nameTitle();
/** The desktop app's menus and dialogs speak the page's language (apps/desktop/src/main.ts). */
function SayLanguage() {
  const lang = useLang();
  useEffect(() => { window.stillfailDesktop?.language?.(lang); }, [lang]);
  return null;
}

createRoot(document.getElementById("app")!).render(<StrictMode><SayLanguage /><I18nRoot><CloudApp /><WindowControls /></I18nRoot></StrictMode>);
