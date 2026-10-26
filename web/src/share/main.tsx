// The share page (share.still.fail, cloud/src/share.ts): a published chat, read straight from its station (Share.tsx).
// The app's styles, in their order, then the page's own; its light or dark, and its motion, as the system has them.
import "../styles/index.ts";
import "./share.css.ts";
import "@fontsource-variable/inter";
import { Tooltip } from "radix-ui";
import { createRoot } from "react-dom/client";
import { I18nRoot } from "../i18n.ts";
import { ToastProvider } from "@stillfail/ui/toast.tsx";
import { Share } from "./Share.tsx";
import { followMotion } from "@stillfail/ui/motion.ts";

followMotion();
createRoot(document.getElementById("app")!).render(<I18nRoot><Tooltip.Provider delayDuration={400}><ToastProvider><Share /></ToastProvider></Tooltip.Provider></I18nRoot>);
