// Whether the app is drawn as a picture: built to HTML that no script takes over (the site's phones showing what it is
// for, web/src/site/prerender.tsx), so nothing measures it and none of its effects run.
import { createContext } from "react";

/**
 * Drawn as a picture: what the app draws only once it has measured or its effects have run is drawn as it renders —
 * its lists whole, from their start (virtual/list.tsx), a chat's composer as its chat says (mobile/ChatHost.tsx).
 */
export const Picture = createContext(false);
