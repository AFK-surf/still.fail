// The keyboard shortcuts shown: all of them at a glance (⌘/), and the page in settings where each one's keys are changed
// (kept on this device, keymap.ts).
import { useEffect, useState } from "react";
import { Link } from "react-router";
import { ACTIONS, CHANGEABLE, bindingOf, boundTo, changed, keyLabel, keysOf, setKeys, useKeymap, type Action } from "./keymap.ts";
import { useToast } from "./toast.tsx";
import { Dialog, MobileBack, Section } from "./ui.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as controlsCss from "./styles/controls.css.ts";
import * as css from "./Shortcuts.css.ts";

const GROUPS = ["全局", "对话"] as const;

/** Keys that belong to one place, not changed here: said in the list so that it is all of them. */
const FIXED: { group: string; rows: [string, string][] }[] = [
  { group: "输入框", rows: [["发送", "↩"], ["换行", "⇧↩"], ["上一个/下一个对话（输入框为空时）", "↑ / ↓"]] },
  { group: "文件预览", rows: [["上一张/下一张", "← / →"], ["放大/缩小", "+ / -"], ["适应窗口/原始大小", "0 / 1"], ["关闭", "Esc"]] },
];

/** A group's actions here: those only the desktop app has are not shown elsewhere. */
const actionsOf = (group: string) => (Object.keys(ACTIONS) as Action[])
  .filter((a) => ACTIONS[a].group === group && (window.stillfailDesktop || ACTIONS[a].keys.length > 0));

/** What an action's keys are here, in words. */
function keysText(action: Action): string {
  const keys = keysOf(action);
  return keys.length ? keys.map(keyLabel).join(" / ") : "未设置";
}

/** Every shortcut, by where it works; the way to change them at its foot. */
export function ShortcutsDialog({ open, onClose, settings }: { open: boolean; onClose(): void; settings: string }) {
  useKeymap();
  return (
    <Dialog open={open} onClose={onClose} title="快捷键"
      footer={CHANGEABLE ? <Link className={`${controlsCss.btn} ${controlsCss.btnGhost}`} to={settings} onClick={onClose}>修改快捷键</Link> : undefined}>
      <div className={css.sheet}>
        {GROUPS.map((group) => (
          <section key={group} className={css.group}>
            <h3 className={css.groupTitle}>{group}</h3>
            {actionsOf(group).map((a) => (
              <div key={a} className={css.line}><span>{ACTIONS[a].label}</span><span className={css.keys}>{keysText(a)}</span></div>
            ))}
          </section>
        ))}
        {FIXED.map(({ group, rows }) => (
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
        toast(`${keyLabel(binding)} 已从「${ACTIONS[other].label}」移到这里`);
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
      <MobileBack to={back} label="设置" />
      <header className={pagesCss.pageHead}><div><h1>快捷键</h1></div></header>
      {GROUPS.map((group, i) => (
        <Section key={group} title={group}
          description={i === 0 ? <>点一个快捷键，再按下新的组合；Esc 取消，⌫ 清除。只对这个设备生效。</> : undefined}
          actions={i === 0 && any ? <button type="button" className={controlsCss.textToggle} onClick={() => { for (const a of Object.keys(ACTIONS) as Action[]) setKeys(a, null); }}>全部恢复默认</button> : undefined}>
          <div className={css.rows}>
            {actionsOf(group).map((a) => (
              <div key={a} className={css.row}>
                <span className={css.rowLabel}>{ACTIONS[a].label}</span>
                {changed(a) && <button type="button" className={controlsCss.textToggle} onClick={() => setKeys(a, null)}>恢复默认</button>}
                <button type="button" className={css.record} data-recording={recording === a || undefined} data-none={keysOf(a).length === 0 || undefined}
                  onClick={() => setRecording(recording === a ? null : a)}>
                  {recording === a ? "按下新的快捷键…" : keysText(a)}
                </button>
              </div>
            ))}
          </div>
        </Section>
      ))}
    </div>
  );
}
