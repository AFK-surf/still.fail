// 字体 (pages/Appearance.tsx; the phone's in mobile/Settings.tsx): each place's face, chosen from the app's own, those
// still.fail keeps and, where the browser lets it list them, those installed here; each named in itself, and a preview
// of the three as chosen (the page is set in them at once, fonts.ts).
import { useEffect, useState, type ReactNode } from "react";
import type { FontFace } from "./core/shapes.ts";
import { canListLocal, familyOf, listLocal, loadFace, useLocalFonts } from "./fonts.ts";
import { t } from "./i18n.ts";
import { setPrefs, usePrefs } from "./prefs.ts";
import { Button, Select } from "./ui.tsx";
import * as css from "./FontSetting.css.ts";
import * as pagesCss from "./styles/pages.css.ts";

export type Place = "ui" | "text" | "code";
export const PLACES: Place[] = ["ui", "text", "code"];
const LOCAL = "local:";

export const placeLabel = (place: Place) => t(`web-pages.appearance.fonts.${place}`);
/** What none chosen reads as: the app's own; text, as the interface. */
export const noneLabel = (place: Place) => t(place === "text" ? "web-pages.appearance.fonts.followUi" : "web-pages.appearance.fonts.default");

/** The faces still.fail keeps that suit a place: code's are all one width, the others' not. */
export function facesFor(place: Place, list: FontFace[]): FontFace[] {
  return list.filter((f) => f.mono === (place === "code"));
}

/** A face's name in itself (its stylesheet fetched for the characters of its name). */
export function FaceName({ face, place }: { face: FontFace; place: Place }) {
  useEffect(() => loadFace(face), [face]);
  return <span style={{ fontFamily: familyOf(face, place === "code") ?? undefined }}>{face.name}</span>;
}

/** The choice of each place, a row each, and the preview under them. */
export function FontSetting() {
  const chosen = usePrefs((p) => p.fonts);
  const list = usePrefs((p) => p.faces?.list) ?? [];
  const local = useLocalFonts();
  const [failed, setFailed] = useState<string | null>(null);
  const choose = (place: Place, value: string) => setPrefs({ fonts: { [place]: value === "" ? null : value } });
  return (
    <div className={css.setting}>
      <div className={css.rows}>
        {PLACES.map((place) => {
          const value = chosen[place] ?? "";
          const theirs = local ?? [];
          // One chosen before the list was asked for (or since gone): still named.
          const kept = value.startsWith(LOCAL) && !theirs.includes(value.slice(LOCAL.length)) ? [value.slice(LOCAL.length)] : [];
          const options: { value: string; label: ReactNode; group?: string }[] = [
            { value: "", label: noneLabel(place) },
            ...facesFor(place, list).map((f) => ({ value: f.id, label: <FaceName face={f} place={place} />, group: t("web-pages.appearance.fonts.offered") })),
            ...[...kept, ...theirs].map((family) => ({ value: LOCAL + family, label: <span style={{ fontFamily: `"${family}"` }}>{family}</span>, group: t("web-pages.appearance.fonts.local") })),
          ];
          return (
            <div key={place} className={css.row}>
              <span className={css.label}>{placeLabel(place)}</span>
              <Select label={placeLabel(place)} value={value} onChange={(v) => choose(place, v)} options={options} />
            </div>
          );
        })}
      </div>
      {canListLocal && local === null && (
        <div>
          <Button variant="secondary" onClick={() => { setFailed(null); listLocal().catch((e: unknown) => setFailed(e instanceof Error ? e.message : String(e))); }}>
            {t("web-pages.appearance.fonts.listLocal")}
          </Button>
          {failed && <p className={css.failed} role="alert">{t("web-pages.appearance.fonts.localFailed", { error: failed })}</p>}
        </div>
      )}
      <FontPreview />
    </div>
  );
}

const CODE_SAMPLE = `const font = { code: "maple-mono" };\n// 0O 1lI {}[] => != 注释`;

/** The three as the page is set in them now, on a card (`card`: the phone's, else the wide screen's). */
export function FontPreview({ card = pagesCss.card }: { card?: string }) {
  return (
    <div className={card} aria-label={t("web-pages.appearance.fonts.preview")}>
      <div className={css.samples}>
        <div className={css.sample}>
          <span className={css.sampleLabel}>{placeLabel("ui")}</span>
          <span className={css.sampleUi}>{t("web-pages.appearance.fonts.sampleUi")}</span>
        </div>
        <div className={css.sample}>
          <span className={css.sampleLabel}>{placeLabel("text")}</span>
          <p className={css.sampleText}>{t("web-pages.appearance.fonts.sampleText")}</p>
        </div>
        <div className={css.sample}>
          <span className={css.sampleLabel}>{placeLabel("code")}</span>
          <pre className={css.sampleCode}>{CODE_SAMPLE}</pre>
        </div>
      </div>
    </div>
  );
}
