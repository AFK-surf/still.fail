// The phone beside the computer on the site's page (OneComputer.tsx), in a frame as wide as a phone: the demo's app,
// laid out as on a phone (the phone's rules go by the screen's width, which here is the phone's), on its stations.
import "../styles/index.ts";
import { mountDemo } from "../demo/mount.tsx";
import { followMotion } from "@stillfail/ui/motion.ts";

followMotion();
const root = document.getElementById("demo")!;
// In a phone's shell: its status bar's room under the camera island (demo/demo.css.ts).
root.dataset.phone = "";
mountDemo(root, { start: "stations" });
