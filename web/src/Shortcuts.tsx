// The keyboard shortcuts shown: all of them at a glance (⌘/), as the core says them (keymap.ts).
import { actions, groups, useKeymap, workspaceKeyLabel } from "./keymap.ts";
import { Dialog } from "./ui.tsx";
import * as css from "./Shortcuts.css.ts";
import { t } from "./i18n.ts";

/** Keys that belong to one place, not changed here: said in the list so that it is all of them. */
const fixed = (): { group: string; rows: [string, string][] }[] => [
  { group: t("web-main.shortcuts.group.workspace"), rows: [[t("web-main.shortcuts.switchWorkspace"), `${workspaceKeyLabel(0)} … ${workspaceKeyLabel(8)}`]] },
  { group: t("web-main.shortcuts.group.composer"), rows: [[t("web-main.shortcuts.send"), "↩"], [t("web-main.shortcuts.newline"), "⇧↩"], [t("web-main.shortcuts.prevNextChat"), "↑ / ↓"]] },
  { group: t("web-main.shortcuts.group.preview"), rows: [[t("web-main.shortcuts.prevNextImage"), "← / →"], [t("web-main.shortcuts.zoom"), "+ / -"], [t("web-main.shortcuts.fitActual"), "0 / 1"], [t("common.close"), "Esc"]] },
];

/** A group's actions here: those the core lists. */
const actionsOf = (group: string) => actions().filter((a) => a.group === group && a.listed);

/** Every shortcut, by where it works. */
export function ShortcutsDialog({ open, onClose }: { open: boolean; onClose(): void }) {
  useKeymap();
  return (
    <Dialog open={open} onClose={onClose} title={t("web-main.shortcuts.title")}>
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
