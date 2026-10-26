// The official site in the browser: the page built to HTML (prerender.tsx) is taken over at once, and the demo mounted
// in it once its script is here. That script (the app, most of what the page loads) comes after the page's own, so the
// page and its scene do not wait for it: the demo's box shows the frame it was built with till then.
import "../styles/index.ts";
import "./site.css.ts";
import { StrictMode, useEffect, useState } from "react";
import { hydrateRoot } from "react-dom/client";
import { Site, type DemoProps } from "./Site.tsx";

// The page's language, as it was built (site/index.html, site/en/index.html).
const lang = document.documentElement.lang === "en" ? "en" : "zh";
const demo = Promise.all([import("../demo/mount.tsx"), import("@stillfail/ui/motion.ts")]).then(([{ mountDemo }, { followMotion }]) => {
  // The demo in it moves as the system asks (the site's own motion goes by its media query: site.css.ts).
  followMotion();
  return mountDemo;
});

function Page() {
  const [mount, setMount] = useState<DemoProps["mountDemo"]>();
  useEffect(() => { void demo.then((m) => setMount(() => m)); }, []);
  return <Site {...(mount ? { mountDemo: mount } : {})} lang={lang} />;
}

hydrateRoot(document.getElementById("site")!, <StrictMode><Page /></StrictMode>);
