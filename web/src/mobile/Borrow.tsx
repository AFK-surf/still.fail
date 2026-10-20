// Another station's model on the phone (docs/station-share.md 借用): where it comes from, after its name, and borrowing
// its account, asked again in a sheet of its own (the stations' environments may differ). The words are the core's
// (choose.ts PickBorrow).
import type { ModelOption } from "../api.ts";
import { usePick } from "../pick.ts";
import { StationMark } from "../StationMark.tsx";
import { SheetGrab, SheetHead, useApp, type MobileApp } from "./app.tsx";
import { Button } from "./parts.tsx";
import * as sheetsCss from "./styles/sheets.css.ts";
import * as css from "./Borrow.css.ts";
import { t } from "../i18n.ts";

/** Where another station's model comes from: its station's mark, else its name; faint while it is not borrowed. */
export function FromMark({ option, picked = false }: { option: ModelOption; picked?: boolean }) {
  const s = option.fromStation;
  if (!s) return null;
  return (
    <span className={css.mFrom} data-faded={(option.availability === "borrowable" && !picked) || undefined} title={option.fromText} aria-label={option.fromText}>
      {s.icon || s.emoji ? <StationMark emoji={s.emoji} icon={s.icon} size={14} /> : s.name}
    </span>
  );
}

/** Opens the second confirmation of borrowing the model picked in a control (`of` as pick.ts's). */
export function openBorrow(app: MobileApp, station: string, of: string) {
  app.sheet({ height: 0.6, content: () => <BorrowSheet station={station} of={of} /> });
}

function BorrowSheet({ station, of }: { station: string; of: string }) {
  const app = useApp();
  const pick = usePick(station, of);
  const b = pick.view?.borrow;
  if (!b) return <><SheetGrab /><SheetHead title={t("web-mobile.borrow.title")} /></>;
  const go = () => {
    void pick.borrow?.().then(() => { app.sheet(null); app.toast(t("web-mobile.borrow.done")); }, (e: unknown) => app.toast(e instanceof Error ? e.message : String(e)));
  };
  return (
    <>
      <SheetGrab /><SheetHead title={b.title} />
      <div className={`${sheetsCss.mSheetScroll} ${sheetsCss.mForm}`}>
        {b.lines.map((line, i) => <p key={i}>{line}</p>)}
        {!b.allowed && b.why && <p>{b.why}</p>}
      </div>
      <div className={sheetsCss.mSheetFoot}>
        <Button label={t("common.cancel")} primary={false} onClick={() => app.sheet(null)} />
        <Button label={b.action} primary enabled={b.allowed} busy={!!pick.borrowing} onClick={go} />
      </div>
    </>
  );
}
