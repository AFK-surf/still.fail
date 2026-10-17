// The official site in the browser: the page built to HTML (prerender.tsx) is taken over, and the demo mounted in it.
import "../styles/index.ts";
import "./site.css.ts";
import { StrictMode } from "react";
import { hydrateRoot } from "react-dom/client";
import { mountDemo } from "../demo/mount.tsx";
import { Site } from "./Site.tsx";
import { followMotion } from "@stillfail/ui/motion.ts";

// The demo in it moves as the system asks (the site's own motion goes by its media query: site.css.ts).
followMotion();
hydrateRoot(document.getElementById("site")!, <StrictMode><Site mountDemo={mountDemo} /></StrictMode>);
