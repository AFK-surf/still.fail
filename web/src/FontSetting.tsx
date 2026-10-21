// 字体 (pages/Appearance.tsx; the phone's in mobile/Fonts.tsx, the Android app's screens/Fonts.kt): one place at a time
// (界面, 正文, 代码), its faces as tiles each drawn in itself, and under them a chat as it would look. On the wide screen
// a tile pointed at is tried in the preview before it is chosen; a face installed here is picked from a list of its
// own (where the browser lets the page ask for them, fonts.ts).
import { useEffect, useMemo, useState, type CSSProperties, type ReactNode } from "react";
import { Popover } from "radix-ui";
import { Check, Search } from "@stillfail/ui/icons.tsx";
import type { FontFace } from "./core/shapes.ts";
import { canListLocal, familyOf, listLocal, loadFace, useLocalFonts } from "./fonts.ts";
import { t } from "./i18n.ts";
import { setPrefs, usePrefs } from "./prefs.ts";
import { Prose } from "./Prose.tsx";
import { Segmented } from "./ui.tsx";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import * as conversationCss from "./styles/conversation.css.ts";
import * as css from "./FontSetting.css.ts";

export type Place = "ui" | "text" | "code";
export const PLACES: Place[] = ["ui", "text", "code"];
const LOCAL = "local:";
/** The page's own variable for each place (fonts.ts). */
const VARS: Record<Place, string> = { ui: "--font-body", text: "--font-text", code: "--font-mono" };

export const placeLabel = (place: Place) => t(`web-pages.appearance.fonts.${place}`);
/** What none chosen reads as: the app's own; text, as the interface. */
export const noneLabel = (place: Place) => t(place === "text" ? "web-pages.appearance.fonts.followUi" : "web-pages.appearance.fonts.default");

/** The faces still.fail keeps that suit a place: code's are all one width, the others' not. */
export function facesFor(place: Place, list: FontFace[]): FontFace[] {
  return list.filter((f) => f.mono === (place === "code"));
}

/** Each place's own face as the stylesheet has it (styles/global.css.ts), for its tile and to try it; text's is ui's. */
const OWN: Record<Place, string> = {
  ui: "\"Inter Variable\", -apple-system, BlinkMacSystemFont, \"PingFang SC\", \"Hiragino Sans GB\", sans-serif",
  text: "var(--font-body)",
  code: "ui-monospace, SFMono-Regular, Menlo, monospace",
};

const quoted = (family: string) => `"${family.replace(/["\\]/g, "")}"`;

/** How a face (or an installed family) is set in a style; null: the app's own. */
function familyFor(place: Place, id: string, list: FontFace[]): string | null {
  if (id.startsWith(LOCAL)) return quoted(id.slice(LOCAL.length));
  const face = list.find((f) => f.id === id);
  if (!face) return null;
  loadFace(face);
  return familyOf(face, place === "code");
}

/** Words in a face (its stylesheet fetched for those characters); none: the place's own (text's: the interface's). */
export function InFace({ face, place, children }: { face: FontFace | null; place: Place; children: ReactNode }) {
  useEffect(() => { if (face) loadFace(face); }, [face]);
  return <span style={{ fontFamily: face ? familyOf(face, place === "code") ?? OWN[place] : OWN[place] }}>{children}</span>;
}

export function FontSetting() {
  const chosen = usePrefs((p) => p.fonts);
  const list = usePrefs((p) => p.faces?.list) ?? [];
  const [place, setPlace] = useState<Place>("ui");
  /** A tile pointed at: tried in the preview, not chosen. */
  const [trying, setTrying] = useState<string | null>(null);
  const value = chosen[place] ?? "";
  const choose = (id: string) => setPrefs({ fonts: { [place]: id === "" ? null : id } });
  const tried = trying === null ? undefined : familyFor(place, trying, list);
  // Tried in the preview: its place's variable there (ui's, text's too while text follows it).
  const style = tried === undefined ? undefined : ({
    [VARS[place]]: tried ?? OWN[place],
    ...(place === "ui" && !chosen.text ? { [VARS.text]: tried ?? OWN.ui } : {}),
  } as CSSProperties);
  const glyph = t("web-pages.appearance.fonts.glyph");
  const tile = (id: string, face: FontFace | null, name: ReactNode) => (
    <button key={id} type="button" className={css.tile} aria-pressed={value === id} onClick={() => choose(id)}
      onPointerEnter={() => setTrying(id)} onPointerLeave={() => setTrying(null)} onFocus={() => setTrying(id)} onBlur={() => setTrying(null)}>
      <span className={css.tileGlyph}><InFace face={face} place={place}>{glyph}</InFace></span>
      <span className={css.tileName}>{name}</span>
      <Check size={14} className={css.tileCheck} />
    </button>
  );
  return (
    <div className={css.setting}>
      <Segmented label={t("web-pages.appearance.fonts.title")} value={place} onChange={(p) => { setPlace(p); setTrying(null); }}
        options={PLACES.map((p) => ({ value: p, label: placeLabel(p) }))} />
      <div className={css.tiles} role="group" aria-label={placeLabel(place)}>
        {tile("", null, noneLabel(place))}
        {facesFor(place, list).map((f) => tile(f.id, f, <InFace face={f} place={place}>{f.name}</InFace>))}
        {canListLocal && <LocalTile place={place} value={value} glyph={glyph} onChoose={choose} onTry={setTrying} />}
      </div>
      <FontPreview style={style} />
    </div>
  );
}

/** The tile of the families installed here: one chosen is drawn in itself; it opens them all, searchable, each in itself. */
function LocalTile({ place, value, glyph, onChoose, onTry }: { place: Place; value: string; glyph: string; onChoose: (id: string) => void; onTry: (id: string | null) => void }) {
  const local = useLocalFonts();
  const [open, setOpen] = useState(false);
  const [filter, setFilter] = useState("");
  const [failed, setFailed] = useState<string | null>(null);
  const chosen = value.startsWith(LOCAL) ? value.slice(LOCAL.length) : null;
  const shown = useMemo(() => (local ?? []).filter((f) => f.toLowerCase().includes(filter.trim().toLowerCase())).slice(0, 400), [local, filter]);
  const opened = (next: boolean) => {
    setOpen(next);
    if (!next) { onTry(null); setFilter(""); return; }
    // Asked the first time it is opened: the browser asks its person then.
    if (local === null) { setFailed(null); listLocal().catch((e: unknown) => setFailed(e instanceof Error ? e.message : String(e))); }
  };
  const inChosen = chosen ? { fontFamily: quoted(chosen) } : undefined;
  return (
    <Popover.Root open={open} onOpenChange={opened}>
      <Popover.Trigger asChild>
        <button type="button" className={css.tile} aria-pressed={chosen !== null}>
          <span className={css.tileGlyph} style={inChosen}>{chosen ? glyph : "…"}</span>
          <span className={css.tileName} style={inChosen}>{chosen ?? t("web-pages.appearance.fonts.local")}</span>
          <Check size={14} className={css.tileCheck} />
        </button>
      </Popover.Trigger>
      <Popover.Portal>
        <Popover.Content className={`${controlsCss.popover} ${css.localPanel}`} side="bottom" align="start" sideOffset={6} collisionPadding={8}>
          <label className={css.localSearch}>
            <Search size={14} />
            <input placeholder={t("web-pages.appearance.fonts.searchLocal")} value={filter} onChange={(e) => setFilter(e.target.value)} autoFocus />
          </label>
          <div className={css.localList} onPointerLeave={() => onTry(null)}>
            {failed && <p className={css.localNote}>{t("web-pages.appearance.fonts.localFailed", { error: failed })}</p>}
            {!failed && local !== null && shown.length === 0 && <p className={css.localNote}>{t("web-pages.appearance.fonts.noMatch")}</p>}
            {shown.map((family) => (
              <button key={family} type="button" className={`${controlsCss.menuItem} ${css.localRow}`} aria-pressed={family === chosen}
                onPointerEnter={() => onTry(LOCAL + family)} onFocus={() => onTry(LOCAL + family)}
                onClick={() => { onChoose(LOCAL + family); opened(false); }}>
                <span className={css.localName} style={{ fontFamily: `${quoted(family)}${place === "code" ? ", var(--font-mono)" : ""}` }}>{family}</span>
                <Check size={14} className={css.tileCheck} />
              </button>
            ))}
          </div>
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  );
}

const CODE_SAMPLE = "```ts\nform.onsubmit = (e) => {\n  e.preventDefault(); // 0O 1lI\n};\n```";

/**
 * A chat as the faces set it now (`style`: a face tried in its place, over the page's): a message of theirs in its
 * bubble, an agent's under its name, with inline code and a block of it. `className`: its card (the phone's).
 */
export function FontPreview({ style, className }: { style?: CSSProperties | undefined; className?: string }) {
  return (
    <div className={className ?? css.preview} style={style} aria-label={t("web-pages.appearance.fonts.preview")}>
      <div className={css.previewMine}><div className={conversationCss.msgBubble}><span className={css.previewWords}>{t("web-pages.appearance.fonts.sampleMine")}</span></div></div>
      <div className={conversationCss.msg}>
        <div className={conversationCss.msgHead}>
          <span className={css.previewName}>Claude</span>
          <span className={conversationCss.msgTime}>{t("web-pages.appearance.fonts.sampleTime")}</span>
        </div>
        <div className={conversationCss.markdown}><Prose>{`${t("web-pages.appearance.fonts.sampleText")}\n\n${CODE_SAMPLE}\n\n${t("web-pages.appearance.fonts.sampleAfter")}`}</Prose></div>
      </div>
    </div>
  );
}
