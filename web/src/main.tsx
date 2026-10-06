import "./renamed.ts";
import "./styles/index.ts";
import { followAppearance } from "./theme.ts";
import { startScrollbars } from "./scrollbars.ts";
import { StrictMode, useEffect } from "react";
import { createRoot } from "react-dom/client";
import { I18nRoot, useLang } from "./i18n.ts";
import "@fontsource-variable/inter";
import { CloudApp } from "./cloud/CloudApp.tsx";
import { nameTitle } from "./cloud/beta.tsx";
import { startTelemetry } from "./telemetry.ts";
import { wholeImage } from "./wholeImages.ts";

import { webUpdates } from "./core/webUpdates.ts";

if (import.meta.env.PROD) webUpdates.start();
followAppearance();
startScrollbars();
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

createRoot(document.getElementById("app")!).render(<StrictMode><SayLanguage /><I18nRoot><CloudApp /></I18nRoot></StrictMode>);
