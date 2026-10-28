// The phone beside the computer on the site's page (OneComputer.tsx), in a frame as wide as a phone: the demo's app,
// laid out as on a phone (the phone's rules go by the screen's width, which here is the phone's), on its stations.
import "../styles/index.ts";
import { mountDemo } from "../demo/mount.tsx";
import { followMotion } from "@stillfail/ui/motion.ts";

followMotion();
// In the page's language, as it was built (site/phone.html, site/en/phone.html).
const page = new URLSearchParams(location.search).get("at");
mountDemo(document.getElementById("demo")!, { start: page === "chat" ? "chat" : "stations", ...(page && page !== "chat" ? { at: page } : {}), lang: document.documentElement.lang === "en" ? "en" : "zh" });
