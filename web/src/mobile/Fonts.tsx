// 外观 › 字体 on a phone (the wide screen's is FontSetting.tsx, the Android app's screens/Fonts.kt): the three places
// one at a time, a chat as their faces set it, and the faces of the place in view, each drawn in itself.
import { useState, type ReactNode } from "react";
import { Check } from "@stillfail/ui/icons.tsx";
import { facesFor, FontPreview, InFace, noneLabel, PLACES, placeLabel, type Place } from "../FontSetting.tsx";
import { t } from "../i18n.ts";
import { setPrefs, usePrefs } from "../prefs.ts";
import { useApp } from "./app.tsx";
import { LargeTitle, ListCard, ListRow, Seg, TopBack } from "./parts.tsx";
import { GoRow } from "./Settings.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import * as css from "./Settings.css.ts";

/** 外观's row: the three faces at a glance, opening the page. */
export function FontRow() {
  const app = useApp();
  const faces = usePrefs((p) => p.faces);
  const chosen = usePrefs((p) => p.fonts);
  const names = PLACES.filter((p) => chosen[p]).map((p) => faces?.[p].name ?? "");
  return <GoRow title={t("web-pages.appearance.fonts.title")} value={names.length ? names.join(" · ") : t("web-pages.appearance.fonts.default")}
    onClick={() => app.push(app.at("/settings/appearance/fonts"))} />;
}

export function FontScreen() {
  const app = useApp();
  const [at, setAt] = useState(0);
  const place: Place = PLACES[at]!;
  const value = usePrefs((p) => p.fonts[place]) ?? "";
  const list = usePrefs((p) => p.faces?.list) ?? [];
  const choose = (id: string) => setPrefs({ fonts: { [place]: id === "" ? null : id } });
  const row = (id: string, name: ReactNode, sample: ReactNode) => (
    <ListRow key={id} onClick={() => choose(id)}>
      <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
        <span className={listsCss.mRowTitle}>{name}</span>
        <span className={css.mFontSample}>{sample}</span>
      </span>
      {value === id && <Check size={14} className={partsCss.mAccent} />}
    </ListRow>
  );
  const sample = t("web-pages.appearance.fonts.sampleRow");
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <TopBack label={t("web-mobile.settings.appearance.title")} onBack={app.pop} />
      <LargeTitle small="" big={t("web-pages.appearance.fonts.title")} />
      <div className={css.mFontPlaces}>
        <Seg options={PLACES.map(placeLabel)} selected={at} onSelect={setAt} height={34} fill />
      </div>
      <FontPreview className={`${listsCss.mCard} ${css.mFontPreview}`} />
      <ListCard>
        {row("", <InFace face={null} place={place}>{noneLabel(place)}</InFace>, <InFace face={null} place={place}>{sample}</InFace>)}
        {facesFor(place, list).map((f) => row(f.id, <InFace face={f} place={place}>{f.name}</InFace>, <InFace face={f} place={place}>{sample}</InFace>))}
        {/* One installed here, chosen where the browser lists them (FontSetting.tsx). */}
        {value.startsWith("local:") && row(value, value.slice("local:".length), null)}
      </ListCard>
      <div className={css.mSegNote}>{t("web-pages.appearance.fonts.description")}</div>
      <div style={{ height: 30 }} />
    </div>
  );
}
