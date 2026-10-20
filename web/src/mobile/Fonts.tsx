// 外观 › 字体 on a phone (the wide screen's is FontSetting.tsx, the Android app's FontsScreen): one place's face, picked
// from the app's own and those still.fail keeps, each named in itself, with the preview of the three above them.
import type { ReactNode } from "react";
import { useParams } from "react-router";
import { Check } from "@stillfail/ui/icons.tsx";
import { facesFor, FaceName, FontPreview, noneLabel, PLACES, placeLabel, type Place } from "../FontSetting.tsx";
import { t } from "../i18n.ts";
import { setPrefs, usePrefs } from "../prefs.ts";
import { useApp } from "./app.tsx";
import { LargeTitle, ListCard, ListRow, SectionHeader, TopBack } from "./parts.tsx";
import { GoRow } from "./Settings.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import * as css from "./Settings.css.ts";

/** The 外观 page's rows: each place and its face, opening its page. */
export function FontRows() {
  const app = useApp();
  const faces = usePrefs((p) => p.faces);
  const chosen = usePrefs((p) => p.fonts);
  return (
    <>
      <SectionHeader title={t("web-pages.appearance.fonts.title")} start={24} />
      <ListCard>
        {PLACES.map((place) => (
          <GoRow key={place} title={placeLabel(place)} value={chosen[place] ? faces?.[place].name : noneLabel(place)}
            onClick={() => app.push(app.at(`/settings/appearance/fonts/${place}`))} />
        ))}
      </ListCard>
    </>
  );
}

export function FontScreen() {
  const app = useApp();
  const { place: at = "ui" } = useParams();
  const place: Place = PLACES.includes(at as Place) ? (at as Place) : "ui";
  const value = usePrefs((p) => p.fonts[place]) ?? "";
  const list = usePrefs((p) => p.faces?.list) ?? [];
  const choose = (id: string) => setPrefs({ fonts: { [place]: id === "" ? null : id } });
  const row = (id: string, label: ReactNode) => (
    <ListRow key={id} onClick={() => choose(id)}>
      <span className={`${partsCss.mGrow} ${listsCss.mRowTitle}`}>{label}</span>
      {value === id && <Check size={14} className={partsCss.mAccent} />}
    </ListRow>
  );
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <TopBack label={t("web-mobile.settings.appearance.title")} onBack={app.pop} />
      <LargeTitle small="" big={placeLabel(place)} />
      <FontPreview card={listsCss.mCard} />
      <ListCard>
        {row("", noneLabel(place))}
        {facesFor(place, list).map((f) => row(f.id, <FaceName face={f} place={place} />))}
        {/* One installed here, chosen where the browser lists them (FontSetting.tsx). */}
        {value.startsWith("local:") && row(value, value.slice("local:".length))}
      </ListCard>
      <div className={css.mSegNote}>{t("web-pages.appearance.fonts.description")}</div>
      <div style={{ height: 30 }} />
    </div>
  );
}
