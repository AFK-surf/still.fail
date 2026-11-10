// The app's own parts beside @stillfail/ui's (its parts.tsx, all of which this gives too): what made an agent's model,
// a connect's kind, a time, a page's way back, the splash, page changes. The tips' keys are the app's keymap's.
import { shortcutOf, useKeymap } from "./keymap.ts";
import { setPrefs, usePrefs } from "./prefs.ts";
import type { RuntimeKind, Stamp } from "./api.ts";
import { FeishuLogo, RuntimeLogo as RuntimeMark, SlackLogo } from "@stillfail/ui/brands.tsx";
export { FeishuLogo, SlackLogo };
import { ChevronLeft } from "@stillfail/ui/icons.tsx";
import { setShortcuts } from "@stillfail/ui/shortcuts.ts";
import { ICON, Tip } from "@stillfail/ui/parts.tsx";
import { Link } from "wouter-preact";
import * as css from "./ui.css.ts";

export * from "@stillfail/ui/parts.tsx";
export * from "@stillfail/ui/waiting.tsx";

setShortcuts({ keys: shortcutOf, use: useKeymap });

/** A back link that only phones show, where an opened page hides the sidebar. */
export function MobileBack({ to, label }: { to: string; label: string }) {
  return <Link className={css.mobileBack} to={to}><ChevronLeft {...ICON} />{label}</Link>;
}

/** A runtime's mark (brands.tsx), as the app's rows and headings place it (cloud/settings.css.ts finds it by its class). */
export function RuntimeLogo({ runtime, size = 16 }: { runtime: RuntimeKind; size?: number }) {
  return <RuntimeMark runtime={runtime} size={size} className={css.runtimeLogo} />;
}

/** Every relative time on the page follows one switch, kept on this device (prefs.ts): a click on any of them flips all between "3 分钟前" and the date. */
function useAbsoluteTime(): [boolean, () => void] {
  const absolute = usePrefs((p) => p.absoluteTime);
  return [absolute, () => setPrefs({ absoluteTime: !absolute })];
}

/** A time as the core says it (fresh each minute): relative by default; clicking flips every time on the page to absolute and back. `fixed`: always relative, not a switch (the sidebar's), the date on hover. */
export function Time({ stamp, className, fixed = false }: { stamp: Stamp | undefined; className?: string; fixed?: boolean }) {
  const [switched, flip] = useAbsoluteTime();
  if (!stamp) return null;
  const absolute = switched && !fixed;
  return (
    <Tip label={absolute ? stamp.ago : stamp.full}><time className={`${fixed ? "" : css.timeToggle}${className ? ` ${className}` : ""}`.trim()} dateTime={new Date(stamp.at).toISOString()}
      data-full={stamp.full} onClick={fixed ? undefined : (e) => { e.preventDefault(); e.stopPropagation(); flip(); }}>
      {absolute ? stamp.full : stamp.ago}
    </time></Tip>
  );
}
