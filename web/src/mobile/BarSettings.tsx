// Settings · 下方栏 (the bottom bar, Bar.tsx): the device's bars, each a card of up to four places. A place's − takes it
// out, the empty slot adds one (a sheet of the places), a place held and moved sideways takes another slot; a bar is
// made the one in view, deleted (with more than one), or a new one made. Said to the core whole each time (`bars`).
import { useFrameDraw } from "./gesture.ts";
import { useRef, type PointerEvent as ReactPointerEvent } from "react";
import { railLabel } from "../Rail.tsx";
import { Archive, Chart, Chats, Folder, Im, Minus, Plus, Quota, type IconProps } from "@stillfail/ui/icons.tsx";
import { StationGlyph } from "../StationGlyph.tsx";
import type { ComponentType } from "react";
import { useApp, SheetGrab, SheetHead } from "./app.tsx";
import { BAR_PLACES, setBars, useBars, type BarPlace } from "./Bar.tsx";
import { LargeTitle, ListCard, ListRow, PickRow, TopBack } from "./parts.tsx";
import * as listsCss from "./styles/lists.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as sheetsCss from "./styles/sheets.css.ts";
import * as css from "./BarSettings.css.ts";
import { t } from "../i18n.ts";

const SIZE = 4;
const ICONS: Partial<Record<BarPlace, ComponentType<IconProps>>> = { chats: Chats, files: Folder, profiles: Quota, connects: Im, usage: Chart, archive: Archive };
const STILL = { online: 1, dim: 0, failing: 0, working: 0, asleep: false };
function PlaceIcon({ place, size = 28 }: { place: BarPlace; size?: number }) {
  if (place === "stations") return <StationGlyph counts={STILL} size={size} />;
  const I = ICONS[place]!;
  return <I size={size} />;
}

export function BarSettingsScreen() {
  const app = useApp();
  const bars = useBars();
  const sets = bars.sets as BarPlace[][];
  const save = (next: BarPlace[][], current = bars.current) => setBars(next, current);
  // Without bar i: the one in view stays the one it was (one place on if it was after i; the one before, or the
  // first, if it was i).
  const without = (next: BarPlace[][], i: number) => {
    const left = next.filter((_, j) => j !== i);
    save(left, bars.current > i ? bars.current - 1 : bars.current === i ? Math.max(0, Math.min(i, left.length - 1)) : bars.current);
  };
  const pick = (i: number) => app.sheet({
    height: Math.min(0.9, (96 + BAR_PLACES.length * 52 + 24) / window.innerHeight),
    content: () => <PickSheet bar={i} />,
  });
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <TopBack label={t("web-mobile.settings.title")} onBack={app.pop} />
      <LargeTitle small={t("web-mobile.settings.device")} big={t("web-mobile.bar.title")} />
      <p className={css.mNote}>{t("web-mobile.bar.note")}</p>
      {sets.map((set, i) => (
        <section key={i}>
          <div className={css.mHead}>
            <b>{t("web-mobile.bar.nth", { n: i + 1 })}</b>
            {i === bars.current && <span className={css.mNow}>{t("web-mobile.bar.current")}</span>}
            <span className={partsCss.mGrow} />
            {i !== bars.current && <button type="button" className={css.mAct} onClick={() => save(sets, i)}>{t("web-mobile.bar.use")}</button>}
            {sets.length > 1 && (
              <button type="button" className={css.mAct} data-danger onClick={() => without(sets, i)}>
                {t("common.delete")}
              </button>
            )}
          </div>
          <Slots set={set} last={sets.length === 1 && set.length === 1} onMove={(from, to) => { const next = sets.map((s) => [...s]); const [k] = next[i]!.splice(from, 1); next[i]!.splice(to, 0, k!); save(next); }}
            // Its last place taken out (with other bars): the bar goes with it (the core keeps no empty bar).
            onRemove={(j) => { const next = sets.map((s) => [...s]); next[i]!.splice(j, 1); if (next[i]!.length) save(next); else if (sets.length > 1) without(next, i); }}
            onAdd={() => pick(i)} />
        </section>
      ))}
      <ListCard>
        <ListRow onClick={() => pick(sets.length)}>
          <span className={css.mNewIcon}><Plus size={20} /></span>
          <span className={`${partsCss.mGrow} ${listsCss.mRowTitle} ${css.mNewText}`}>{t("web-mobile.bar.new")}</span>
        </ListRow>
      </ListCard>
      <p className={css.mNote}>{sets.length > 1 ? t("web-mobile.bar.oneLeft") : t("web-mobile.bar.onlyOne")}</p>
      <div style={{ height: 30 }} />
    </div>
  );
}

/** A bar's four slots: its places (a − each), then (with room) one to add. A place held and moved sideways takes the
 *  slot it is let go over. */
function Slots({ set, last, onMove, onRemove, onAdd }: { set: BarPlace[]; last: boolean; onMove: (from: number, to: number) => void; onRemove: (j: number) => void; onAdd: () => void }) {
  const card = useRef<HTMLDivElement>(null);
  const hold = useRef<{ j: number; x: number; el: HTMLElement; moved: boolean } | null>(null);
  const fingers = useFrameDraw<number>(dx => {
    const h = hold.current;
    if (h?.moved) { h.el.dataset.lifted = ""; h.el.style.transform = `translate3d(${dx}px, 0, 0) scale(1.08)`; }
  });
  const down = (j: number) => (e: ReactPointerEvent<HTMLDivElement>) => {
    if ((e.target as HTMLElement).closest("button")) return;
    fingers.cancel();
    hold.current = { j, x: e.clientX, el: e.currentTarget, moved: false };
    e.currentTarget.setPointerCapture(e.pointerId);
  };
  const move = (e: ReactPointerEvent<HTMLDivElement>) => {
    const h = hold.current;
    if (!h) return;
    const dx = e.clientX - h.x;
    if (Math.abs(dx) > 6) h.moved = true;
    if (h.moved) fingers.set(dx);
  };
  const up = (e: ReactPointerEvent<HTMLDivElement>) => {
    fingers.flush();
    const h = hold.current;
    hold.current = null;
    if (!h) return;
    delete h.el.dataset.lifted;
    h.el.style.transform = "";
    if (e.type === "pointercancel" || !h.moved || !card.current) return;
    const slot = card.current.offsetWidth / SIZE;
    const to = Math.max(0, Math.min(set.length - 1, h.j + Math.round((e.clientX - h.x) / slot)));
    if (to !== h.j) onMove(h.j, to);
  };
  return (
    <div ref={card} className={css.mCard}>
      {set.map((place, j) => (
        <div key={place} className={css.mSlot} onPointerDown={down(j)} onPointerMove={move} onPointerUp={up} onPointerCancel={up}>
          <span className={css.mIcon}><PlaceIcon place={place} /></span>
          <small>{railLabel(place)}</small>
          {/* The one place left of the one bar stays: a bar of nothing is no bar. */}
          {!last && <button type="button" className={css.mMinus} aria-label={t("web-mobile.bar.remove", { place: railLabel(place) })} onClick={() => onRemove(j)}><Minus size={12} strokeWidth={2.6} /></button>}
        </div>
      ))}
      {set.length < SIZE && (
        <button type="button" className={css.mSlot} data-empty onClick={onAdd}>
          <span className={css.mAdd}><Plus size={22} /></span>
          <small>{t("web-mobile.bar.add")}</small>
        </button>
      )}
    </div>
  );
}

/** The places to add to bar `bar` (a new one, past the last): those there already, or a full bar, can't. */
function PickSheet({ bar }: { bar: number }) {
  const app = useApp();
  const bars = useBars();
  const sets = bars.sets as BarPlace[][];
  const set = sets[bar] ?? [];
  const full = set.length >= SIZE;
  return (
    <>
      <SheetGrab />
      <SheetHead title={bar < sets.length ? t("web-mobile.bar.addTo", { n: bar + 1 }) : t("web-mobile.bar.new")} />
      <div className={sheetsCss.mSheetScroll}>
        {BAR_PLACES.map((place) => (
          <PickRow key={place} label={railLabel(place)} leading={<span className={css.mPickIcon}><PlaceIcon place={place} size={22} /></span>}
            sub={set.includes(place) ? t("web-mobile.bar.already") : undefined} enabled={!full && !set.includes(place)}
            onClick={() => {
              const next = sets.map((s) => [...s]);
              if (bar < next.length) next[bar]!.push(place); else next.push([place]);
              setBars(next, bars.current);
              app.sheet(null);
            }} />
        ))}
      </div>
    </>
  );
}
