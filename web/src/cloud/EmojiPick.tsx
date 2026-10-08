// A station's emoji (the settings' stations): a square before its name; pressed, a few to pick from, a field taking any
// one pasted or typed, and a way to have none. Those who may not change it see only the one it has.
import { useState } from "react";
import { Popover } from "radix-ui";
import { Close, Plus } from "../icons.tsx";
import { Tip } from "../ui.tsx";
import { t } from "../i18n.ts";
import * as controlsCss from "../styles/controls.css.ts";
import * as css from "./EmojiPick.css.ts";

const CHOICES = ["🖥️", "💻", "🍎", "🐧", "🪟", "☁️", "🏠", "🏢", "🚀", "⚡", "🔥", "🧪", "🛠️", "🐳", "🦀", "🐙", "🌲", "🌊", "🌙", "☀️", "🍊", "🍋", "🍇", "🐱"];

/** The first emoji of what was typed, as a person sees one (a flag, a family are one); null for none. */
function first(text: string): string | null {
  const one = [...new Intl.Segmenter().segment(text.trim())][0]?.segment;
  return one && /\p{Extended_Pictographic}|\p{Regional_Indicator}/u.test(one) ? one : null;
}

export function EmojiPick({ emoji, name, editable, busy, onPick }: { emoji: string | null | undefined; name: string; editable: boolean; busy?: boolean; onPick(emoji: string): void }) {
  const [open, setOpen] = useState(false);
  const [typed, setTyped] = useState("");
  if (!editable) return emoji ? <span className={css.shown} aria-hidden="true">{emoji}</span> : null;
  const choose = (e: string) => { setOpen(false); setTyped(""); if (e !== (emoji ?? "")) onPick(e); };
  return (
    <Popover.Root open={open} onOpenChange={setOpen}>
      <Popover.Trigger asChild>
        <button type="button" className={css.slot} data-set={emoji ? "" : undefined} disabled={busy} aria-label={t("web-pages.stations.emoji.label", { name })}>
          {emoji || <Plus size={14} />}
        </button>
      </Popover.Trigger>
      <Popover.Portal>
        <Popover.Content className={`${controlsCss.popover} ${controlsCss.popoverSolid} ${css.pick}`} align="start" sideOffset={6} collisionPadding={8}>
          {/* One grid, the field and its clearing in its last row: the field spans the columns the button leaves. */}
          <form className={css.grid} onSubmit={(ev) => { ev.preventDefault(); const one = first(typed); if (one) choose(one); }}>
            {CHOICES.map((e) => <button key={e} type="button" className={css.choice} aria-pressed={e === emoji} onClick={() => choose(e)}>{e}</button>)}
            <input className={`${controlsCss.input} ${css.field}`} data-alone={emoji ? undefined : ""} value={typed} placeholder={t("web-pages.stations.emoji.paste")} aria-label={t("web-pages.stations.emoji.paste")}
              onChange={(ev) => { setTyped(ev.target.value); const one = first(ev.target.value); if (one) choose(one); }} />
            {emoji && <Tip label={t("web-pages.stations.emoji.clear")}><button type="button" className={`${css.choice} ${css.clear}`} aria-label={t("web-pages.stations.emoji.clear")} onClick={() => choose("")}><Close size={16} /></button></Tip>}
          </form>
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  );
}
