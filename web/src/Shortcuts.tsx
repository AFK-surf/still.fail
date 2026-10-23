// The keyboard shortcuts shown: all of them at a glance (⌘/), and the page in settings where each one's keys are changed
// (kept on this device by the core, keymap.ts).
import { useEffect, useState } from "react";
import { Link } from "react-router";
import { CHANGEABLE, actions, bindingOf, groups, setKeys, useKeymap, workspaceKeyLabel, type Action } from "./keymap.ts";
import { useToast } from "@stillfail/ui/toast.tsx";
import { Dialog, MobileBack, Section } from "./ui.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import * as css from "./Shortcuts.css.ts";
import { t } from "./i18n.ts";

/** Keys that belong to one place, not changed here: said in the list so that it is all of them. */
const fixed = (): { group: string; rows: [string, string][] }[] => [
  { group: t("web-main.shortcuts.group.workspace"), rows: [[t("web-main.shortcuts.switchWorkspace"), `${workspaceKeyLabel(0)} … ${workspaceKeyLabel(8)}`]] },
  { group: t("web-main.shortcuts.group.composer"), rows: [[t("web-main.shortcuts.send"), "↩"], [t("web-main.shortcuts.newline"), "⇧↩"], [t("web-main.shortcuts.prevNextChat"), "↑ / ↓"]] },
  { group: t("web-main.shortcuts.group.preview"), rows: [[t("web-main.shortcuts.prevNextImage"), "← / →"], [t("web-main.shortcuts.zoom"), "+ / -"], [t("web-main.shortcuts.fitActual"), "0 / 1"], [t("common.close"), "Esc"]] },
];

/** A group's actions here: those only the desktop app has are not shown elsewhere. */
const actionsOf = (group: string) => actions().filter((a) => a.group === group && a.listed);

/** Every shortcut, by where it works; the way to change them at its foot. */
export function ShortcutsDialog({ open, onClose, settings }: { open: boolean; onClose(): void; settings: string }) {
  useKeymap();
  return (
    <Dialog open={open} onClose={onClose} title={t("web-main.shortcuts.title")}
      footer={CHANGEABLE ? <Link className={`${controlsCss.btn} ${controlsCss.btnGhost}`} to={settings} onClick={onClose}>{t("web-main.shortcuts.change")}</Link> : undefined}>
      <div className={css.sheet}>
        {groups().map(({ group, name }) => (
          <section key={group} className={css.group}>
            <h3 className={css.groupTitle}>{name}</h3>
            {actionsOf(group).map((a) => (
              <div key={a.action} className={css.line}><span>{a.name}</span><span className={css.keys}>{a.text}</span></div>
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
        void setKeys(recording, []);
        return setRecording(null);
      }
      const binding = bindingOf(e);
      if (!binding) return;
      // Keys another action had are moved here, said so.
      void setKeys(recording, [binding]).then((said) => { if (said) toast(said); });
      setRecording(null);
    };
    window.addEventListener("keydown", onKey, true);
    return () => window.removeEventListener("keydown", onKey, true);
  }, [recording, toast]);
  const any = actions().some((a) => a.changed);
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={back} label={t("web-main.nav.settings")} />
      <header className={pagesCss.pageHead}><div><h1>{t("web-main.shortcuts.title")}</h1></div></header>
      {groups().map(({ group, name }, i) => (
        <Section key={group} title={name}
          description={i === 0 ? <>{t("web-main.shortcuts.hint")}</> : undefined}
          actions={i === 0 && any ? <button type="button" className={controlsCss.textToggle} onClick={() => void setKeys(null, null)}>{t("web-main.shortcuts.resetAll")}</button> : undefined}>
          <div className={css.rows}>
            {actionsOf(group).map(({ action: a, name: label, keys, text, changed }) => (
              <div key={a} className={css.row}>
                <span className={css.rowLabel}>{label}</span>
                {changed && <button type="button" className={controlsCss.textToggle} onClick={() => void setKeys(a, null)}>{t("web-main.shortcuts.reset")}</button>}
                <button type="button" className={css.record} data-recording={recording === a || undefined} data-none={keys.length === 0 || undefined}
                  onClick={() => setRecording(recording === a ? null : a)}>
                  {recording === a ? t("web-main.shortcuts.recording") : text}
                </button>
              </div>
            ))}
          </div>
        </Section>
      ))}
    </div>
  );
}
