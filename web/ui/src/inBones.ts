// Whether what is drawn is a page's bones (waiting.tsx Bones): on its own, without the drawing, for what reads it far from
// any (web/src/core/react.ts, which tests load in node).
import { createContext } from "react";

/**
 * Whether what is drawn now is a page's bones (`Bones`): drawn of made-up data, it reads nothing of the core (no topic
 * subscribed, no call made: web/src/core/react.ts) and nothing in it is pressed, focused or read out.
 */
export const InBones = createContext(false);
