// The official site in the browser: the page built to HTML (prerender.tsx) is taken over, and the demo mounted in it.
import "../styles/index.ts";
import "./site.css.ts";
import { StrictMode } from "react";
import { hydrateRoot } from "react-dom/client";
import { mountDemo } from "../demo/mount.tsx";
import { Site } from "./Site.tsx";

hydrateRoot(document.getElementById("site")!, <StrictMode><Site mountDemo={mountDemo} /></StrictMode>);
