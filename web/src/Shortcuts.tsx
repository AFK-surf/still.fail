// The keyboard shortcuts shown: all of them at a glance (⌘/), and the page in settings where each one's keys are changed
// (kept on this device, keymap.ts).
import { useEffect, useState } from "react";
import { Link } from "react-router";
import { ACTIONS, CHANGEABLE, bindingOf, boundTo, changed, groupLabel, keyLabel, keysOf, labelOf, setKeys, useKeymap, type Action } from "./keymap.ts";
import { useToast } from "./toast.tsx";
import { Dialog, MobileBack, Section } from "./ui.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as controlsCss from "./styles/controls.css.ts";
import * as css from "./Shortcuts.css.ts";
import { t } from "./i18n.ts";

const GROUPS = ["global", "chat"] as const;

/** Keys that belong to one place, not changed here: said in the list so that it is all of them. */
const fixed = (): { group: string; rows: [string, string][] }[] => [
  { group: t("web-main.shortcuts.group.composer"), rows: [[t("web-main.shortcuts.send"), "↩"], [t("web-main.shortcuts.newline"), "⇧↩"], [t("web-main.shortcuts.prevNextChat"), "↑ / ↓"]] },
  { group: t("web-main.shortcuts.group.preview"), rows: [[t("web-main.shortcuts.prevNextImage"), "← / →"], [t("web-main.shortcuts.zoom"), "+ / -"], [t("web-main.shortcuts.fitActual"), "0 / 1"], [t("common.close"), "Esc"]] },
];

/** A group's actions here: those only the desktop app has are not shown elsewhere. */
const actionsOf = (group: (typeof GROUPS)[number]) => (Object.keys(ACTIONS) as Action[])
  .filter((a) => ACTIONS[a].group === group && (window.stillfailDesktop || ACTIONS[a].keys.length > 0));

/** What an action's keys are here, in words. */
function keysText(action: Action): string {
  const keys = keysOf(action);
  return keys.length ? keys.map(keyLabel).join(" / ") : t("web-main.shortcuts.unset");
}

/** Every shortcut, by where it works; the way to change them at its foot. */
export function ShortcutsDialog({ open, onClose, settings }: { open: boolean; onClose(): void; settings: string }) {
  useKeymap();
  return (
    <Dialog open={open} onClose={onClose} title={t("web-main.shortcuts.title")}
      footer={CHANGEABLE ? <Link className={`${controlsCss.btn} ${controlsCss.btnGhost}`} to={settings} onClick={onClose}>{t("web-main.shortcuts.change")}</Link> : undefined}>
      <div className={css.sheet}>
        {GROUPS.map((group) => (
          <section key={group} className={css.group}>
            <h3 className={css.groupTitle}>{groupLabel(group)}</h3>
            {actionsOf(group).map((a) => (
              <div key={a} className={css.line}><span>{labelOf(a)}</span><span className={css.keys}>{keysText(a)}</span></div>
            ))}
          </section>
        ))}
        {fixed().map(({ group, rows }) => (
          <section key={group} className={css.group}>
            <h3 className={css.groupTitle}>{group}</h3>
            {rows.map(([label, keys]) => <div key={label} className={css.line}><span>{label}</span><span className={css.keys}>{keys}</span></div>)}
          </section>
        ))}
      </div>
    </Dialog>
  );
}

/** Settings → 快捷键 (the desktop app's only): each action's keys, changed by pressing new ones; kept on this device. */
export function ShortcutsPage({ back }: { back: string }) {
  useKeymap();
  const toast = useToast();
  const [recording, setRecording] = useState<Action | null>(null);
  // While one is recorded, the next key press is its new keys: no shortcut of the page's does anything meanwhile.
  useEffect(() => {
    if (!recording) return;
    const onKey = (e: KeyboardEvent) => {
      e.preventDefault();
      e.stopPropagation();
      if (e.key === "Escape" && !e.metaKey && !e.ctrlKey && !e.altKey && !e.shiftKey) return setRecording(null);
      if ((e.key === "Backspace" || e.key === "Delete") && !e.metaKey && !e.ctrlKey && !e.altKey && !e.shiftKey) {
        setKeys(recording, []);
        return setRecording(null);
      }
      const binding = bindingOf(e);
      if (!binding) return;
      const other = boundTo(binding, recording);
      if (other) {
        setKeys(other, keysOf(other).filter((k) => k !== binding));
        toast(t("web-main.shortcuts.moved", { keys: keyLabel(binding), action: labelOf(other) }));
      }
      setKeys(recording, [binding]);
      setRecording(null);
    };
    window.addEventListener("keydown", onKey, true);
    return () => window.removeEventListener("keydown", onKey, true);
  }, [recording, toast]);
  const any = (Object.keys(ACTIONS) as Action[]).some(changed);
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={back} label={t("web-main.nav.settings")} />
      <header className={pagesCss.pageHead}><div><h1>{t("web-main.shortcuts.title")}</h1></div></header>
      {GROUPS.map((group, i) => (
        <Section key={group} title={groupLabel(group)}
          description={i === 0 ? <>{t("web-main.shortcuts.hint")}</> : undefined}
          actions={i === 0 && any ? <button type="button" className={controlsCss.textToggle} onClick={() => { for (const a of Object.keys(ACTIONS) as Action[]) setKeys(a, null); }}>{t("web-main.shortcuts.resetAll")}</button> : undefined}>
          <div className={css.rows}>
            {actionsOf(group).map((a) => (
              <div key={a} className={css.row}>
                <span className={css.rowLabel}>{labelOf(a)}</span>
                {changed(a) && <button type="button" className={controlsCss.textToggle} onClick={() => setKeys(a, null)}>{t("web-main.shortcuts.reset")}</button>}
                <button type="button" className={css.record} data-recording={recording === a || undefined} data-none={keysOf(a).length === 0 || undefined}
                  onClick={() => setRecording(recording === a ? null : a)}>
                  {recording === a ? t("web-main.shortcuts.recording") : keysText(a)}
                </button>
              </div>
            ))}
          </div>
        </Section>
      ))}
    </div>
  );
}
