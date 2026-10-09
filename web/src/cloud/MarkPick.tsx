// A station's mark (the settings' stations): a square before its name; pressed, a panel to pick one of still.fail's icons
// or an emoji (any, pasted or typed, besides those offered), to put up a picture (or paste one), or to have none. Those
// who may not change it see only the one it has. What is sent is ../stationPick.ts's.
import { useRef, useState } from "react";
import { Popover } from "radix-ui";
import { Close, ImageUpload, Plus, STATION_ICONS } from "../icons.tsx";
import { Glyph, isPicture, StationMark, stationGlyph } from "../StationMark.tsx";
import { EMOJI, emojiMark, firstEmoji, glyphMark, kindOf, NO_MARK, pastedPicture, pictureMark, pictureOf, type Kind, type Mark } from "../stationPick.ts";
import { Segmented } from "../ui.tsx";
import { t } from "../i18n.ts";
import * as controlsCss from "../styles/controls.css.ts";
import * as css from "./MarkPick.css.ts";

const bare = (emoji: string) => emoji.replace(/️/g, "");

export function MarkPick({ emoji, icon, name, editable, busy, onPick }: {
  emoji: string | null | undefined; icon: string | null | undefined; name: string; editable: boolean; busy?: boolean; onPick(mark: Mark): void;
}) {
  const [open, setOpen] = useState(false);
  const set = !!emoji || !!icon;
  if (!editable) return set ? <span className={css.shown} aria-hidden="true"><StationMark emoji={emoji} icon={icon} size={16} /></span> : null;
  return (
    <Popover.Root open={open} onOpenChange={setOpen}>
      <Popover.Trigger asChild>
        <button type="button" className={css.slot} data-set={set ? "" : undefined} data-picture={isPicture(icon) || undefined} disabled={busy} aria-label={t("web-pages.stations.emoji.label", { name })}>
          {set ? <StationMark emoji={emoji} icon={icon} size={isPicture(icon) ? 28 : 16} /> : <Plus size={14} />}
        </button>
      </Popover.Trigger>
      <Popover.Portal>
        <Popover.Content className={`${controlsCss.popover} ${css.pick}`} align="start" sideOffset={6} collisionPadding={8}>
          <MarkPanel emoji={emoji} icon={icon} onPick={(m) => { setOpen(false); onPick(m); }} />
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  );
}

/** The panel itself: which grid, the grid, and putting up a picture or having none. */
function MarkPanel({ emoji, icon, onPick }: { emoji: string | null | undefined; icon: string | null | undefined; onPick(mark: Mark): void }) {
  const [kind, setKind] = useState<Kind>(() => kindOf(emoji, icon));
  const [typed, setTyped] = useState("");
  const [failed, setFailed] = useState<string | null>(null);
  const file = useRef<HTMLInputElement>(null);
  const upload = (f: Blob) => {
    setFailed(null);
    pictureOf(f).then((url) => onPick(pictureMark(url)), (e: unknown) => setFailed(t((e as Error).message === "too_big" ? "web-pages.stations.mark.tooBig" : "web-pages.stations.mark.unreadable")));
  };
  const picture = isPicture(icon) ? icon : null;
  return (
    <div className={css.panel} onPaste={(e) => { const f = pastedPicture(e.clipboardData); if (f) { e.preventDefault(); upload(f); } }}>
      <Segmented<Kind> className={css.kinds} label={t("web-pages.stations.mark.kind")} value={kind} onChange={setKind}
        options={[{ value: "glyph", label: t("web-pages.stations.mark.glyphs") }, { value: "emoji", label: "Emoji" }]} />
      {kind === "emoji" && (
        <form onSubmit={(ev) => { ev.preventDefault(); const one = firstEmoji(typed); if (one) onPick(emojiMark(one)); }}>
          <input className={`${controlsCss.input} ${css.field}`} value={typed} autoFocus placeholder={t("web-pages.stations.emoji.paste")} aria-label={t("web-pages.stations.emoji.paste")}
            onChange={(ev) => { setTyped(ev.target.value); const one = firstEmoji(ev.target.value); if (one) onPick(emojiMark(one)); }} />
        </form>
      )}
      {kind === "glyph" ? <GlyphGrid icon={icon} size={18} onPick={onPick} /> : <EmojiGrid emoji={stationGlyph(icon) || picture ? null : emoji} onPick={onPick} />}
      <div className={css.foot}>
        <button type="button" className={`${controlsCss.menuItem} ${css.footButton}`} aria-pressed={!!picture} onClick={() => file.current?.click()}>
          {picture ? <img src={picture} alt="" className={css.footPicture} /> : <ImageUpload size={16} />}
          {t(picture ? "web-pages.stations.mark.another" : "web-pages.stations.mark.upload")}
        </button>
        {(emoji || icon) && <button type="button" className={`${controlsCss.menuItem} ${css.footButton}`} onClick={() => onPick(NO_MARK)}><Close size={16} />{t("web-pages.stations.emoji.clear")}</button>}
        <input ref={file} type="file" accept="image/png,image/jpeg,image/webp,image/gif" hidden onChange={(e) => { const f = e.target.files?.[0]; e.target.value = ""; if (f) upload(f); }} />
      </div>
      {failed && <p className={`${controlsCss.fieldError} ${css.failed}`} role="alert">{failed}</p>}
    </div>
  );
}

/** Still.fail's icons, the one it has marked (the phone's sheet has them larger: `className`, `size`). */
export function GlyphGrid({ icon, size, className, onPick }: { icon: string | null | undefined; size: number; className?: string; onPick(mark: Mark): void }) {
  const kept = stationGlyph(icon)?.name;
  return (
    <div className={`${css.grid}${className ? ` ${className}` : ""}`} role="group">
      {STATION_ICONS.map((g) => (
        <button key={g.name} type="button" className={css.choice} aria-label={g.name} aria-pressed={g.name === kept} onClick={() => onPick(glyphMark(g))}><g.Icon size={size} /></button>
      ))}
    </div>
  );
}

/** The emoji offered, the one it has marked; one it has that is not among them comes first. */
export function EmojiGrid({ emoji, className, onPick }: { emoji: string | null | undefined; className?: string; onPick(mark: Mark): void }) {
  const kept = emoji ? bare(emoji) : null;
  const offered = emoji && !EMOJI.some((e) => bare(e) === kept) ? [emoji, ...EMOJI.slice(0, -1)] : EMOJI;
  return (
    <div className={`${css.grid} ${css.emojiGrid}${className ? ` ${className}` : ""}`} role="group">
      {offered.map((e) => (
        <button key={e} type="button" className={css.choice} aria-label={e} aria-pressed={bare(e) === kept} onClick={() => onPick(emojiMark(e))}><Glyph emoji={e} /></button>
      ))}
    </div>
  );
}
