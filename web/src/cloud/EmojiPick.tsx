// A station's icon (the settings' stations): a square before its name; pressed, our icons to pick from and a way to have
// none. What is kept is the emoji each stands for (older clients show it). Those who may not change it see only the one it has.
import { useState } from "react";
import { Popover } from "radix-ui";
import { Close, Plus, STATION_ICONS } from "../icons.tsx";
import { StationMark } from "../StationMark.tsx";
import { t } from "../i18n.ts";
import * as controlsCss from "../styles/controls.css.ts";
import * as css from "./EmojiPick.css.ts";

const bare = (emoji: string) => emoji.replace(/️/g, "");

export function EmojiPick({ emoji, name, editable, busy, onPick }: { emoji: string | null | undefined; name: string; editable: boolean; busy?: boolean; onPick(emoji: string): void }) {
  const [open, setOpen] = useState(false);
  if (!editable) return emoji ? <span className={css.shown} aria-hidden="true"><StationMark emoji={emoji} size={16} /></span> : null;
  const choose = (e: string) => { setOpen(false); if (e !== (emoji ?? "")) onPick(e); };
  return (
    <Popover.Root open={open} onOpenChange={setOpen}>
      <Popover.Trigger asChild>
        <button type="button" className={css.slot} data-set={emoji ? "" : undefined} disabled={busy} aria-label={t("web-pages.stations.emoji.label", { name })}>
          {emoji ? <StationMark emoji={emoji} size={16} /> : <Plus size={14} />}
        </button>
      </Popover.Trigger>
      <Popover.Portal>
        <Popover.Content className={`${controlsCss.popover} ${css.pick}`} align="start" sideOffset={6} collisionPadding={8}>
          <StationIconGrid emoji={emoji} size={18} onPick={choose} />
          {emoji && <button type="button" className={`${controlsCss.menuItem} ${css.clear}`} onClick={() => choose("")}><Close size={16} />{t("web-pages.stations.emoji.clear")}</button>}
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  );
}

/** Our icons to pick from, the one it has marked (the phone's sheet has the same, larger: `className`). */
export function StationIconGrid({ emoji, size, className, onPick }: { emoji: string | null | undefined; size: number; className?: string; onPick(emoji: string): void }) {
  const kept = emoji ? bare(emoji) : null;
  return (
    <div className={`${css.grid}${className ? ` ${className}` : ""}`} role="group">
      {STATION_ICONS.map(({ emoji: e, name, Icon }) => (
        <button key={name} type="button" className={css.choice} aria-label={e} aria-pressed={bare(e) === kept} onClick={() => onPick(e)}><Icon size={size} /></button>
      ))}
    </div>
  );
}
