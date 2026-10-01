// How much a station takes of its machine on a narrow screen, as the Android app has it (apps/android/…/screens/
// Usage.kt), from the station's page: the wide screen's parts (../Footprint.tsx) on cards under section headers, the chats
// on a page of their own, and each clean-up in a sheet: its choice, then each question in turn (deleting is asked twice).
import { useState } from "react";
import { useStationCall } from "../api.ts";
import type { FootprintAction, FootprintChoice, FootprintView } from "../core/shapes.ts";
import { stationBase, useStation } from "../station.tsx";
import { Dot, FootprintBar, useFootprint } from "../Footprint.tsx";
import { SheetGrab, SheetHead, useApp } from "./app.tsx";
import { Button, Card, ListCard, ListRow, Loading, NavBar, PickRow, SectionHeader } from "./parts.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import * as sheetsCss from "./styles/sheets.css.ts";
import * as barsCss from "./styles/bars.css.ts";
import * as sheetCss from "./sheets.css.ts";
import * as footprintCss from "../Footprint.css.ts";
import * as css from "./Footprint.css.ts";

export function FootprintScreen() {
  const app = useApp();
  const station = useStation();
  const usage = useFootprint(station.address);
  const view = usage.value;
  const call = useStationCall(station.address);
  const clean = (action: FootprintAction) => app.sheet({ height: 0.5, content: () => <CleanSheet station={station.address} action={action} /> });
  return (
    <div className={pagesCss.mScreen}>
      <NavBar back={station.name} onBack={app.pop} title="占用" sub={view ? <span className={barsCss.mNavbarNote}>{view.checkedText}</span> : undefined} />
      {!view ? <Loading text={usage.error ? `读不到：${usage.error.message}` : "正在读取…"} /> : (
        <div className={pagesCss.mScroll} style={{ paddingTop: 4 }}>
          <Card>
            <span className={footprintCss.lead}>{view.lead}</span>
            <span className={footprintCss.total}>{view.totalText}</span>
            <FootprintBar view={view} />
            {view.measured && !view.scanning && <button type="button" className={css.mAgain} onClick={() => void call.op("footprint.scan")}>重新统计</button>}
          </Card>
          {view.measured && (
            <>
              <SectionHeader title="可以清理" start={24} />
              {view.actionsNote && <p className={css.mNote}>{view.actionsNote}</p>}
              {view.actions.length > 0 && (
                <ListCard>
                  {view.actions.map((a) => (
                    <ListRow key={a.id} onClick={() => clean(a)}>
                      <Lines title={a.title} note={a.note} />
                      <span className={css.mAction} data-danger={a.danger || undefined}>{a.action}</span>
                    </ListRow>
                  ))}
                </ListCard>
              )}
            </>
          )}
          {view.parts.length > 0 && (
            <>
              <SectionHeader title="磁盘 · 按用途" start={24} />
              <ListCard>
                {view.parts.map((p) => (
                  <ListRow key={p.id} onClick={p.opens ? () => app.push(app.at(`/s/${station.id}/footprint/chats`)) : undefined}>
                    <Dot tone={p.tone} />
                    <Lines title={p.label} note={p.note} />
                    <span className={css.mSize}>{p.text}{p.opens ? " ›" : ""}</span>
                  </ListRow>
                ))}
              </ListCard>
            </>
          )}
          {view.elsewhere.length > 0 && (
            <>
              <SectionHeader title="这台机器上的其它" start={24} />
              <p className={css.mNote}>{view.elsewhereNote}</p>
              <ListCard>
                {view.elsewhere.map((p) => <ListRow key={p.id}><Lines title={p.label} note={p.note} /><span className={css.mSize}>{p.text}</span></ListRow>)}
              </ListCard>
            </>
          )}
          <Memory view={view} station={station.address} />
          <div style={{ height: 30 }} />
        </div>
      )}
    </div>
  );
}

function Lines({ title, note, tag }: { title: string; note?: string | null | undefined; tag?: string | undefined }) {
  return (
    <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
      <span className={listsCss.mRowTitle}>{title}{tag && <span className={footprintCss.badge}>{tag}</span>}</span>
      {note && <span className={listsCss.mRowNote}>{note}</span>}
    </span>
  );
}

function Memory({ view, station }: { view: FootprintView; station: string }) {
  const app = useApp();
  return (
    <>
      <SectionHeader title={view.memoryTitle} start={24} />
      <ListCard>
        {view.memory.map((r, i) => (
          <ListRow key={i} onClick={r.choice || r.chat ? () => app.sheet({ height: 0.4, content: () => <ChatSheet station={station} title={r.label} chat={r.chat ?? null} choices={r.choice ? [r.choice] : []} /> }) : undefined}>
            <span className={css.mNested} data-nested={r.nested || undefined}><Lines title={r.label} note={r.note} /></span>
            <span className={css.mSize}>{r.text}</span>
          </ListRow>
        ))}
      </ListCard>
    </>
  );
}

/** Every chat's directory, largest first; a chat opens its sheet (open it, clean it, delete it). */
export function FootprintChatsScreen() {
  const app = useApp();
  const station = useStation();
  const view = useFootprint(station.address).value;
  return (
    <div className={pagesCss.mScreen}>
      <NavBar back="占用" onBack={app.pop} title="chat 工作区" sub={view ? <span className={barsCss.mNavbarNote}>{view.chatsText}</span> : undefined} />
      {!view ? <Loading text="正在读取…" /> : (
        <div className={pagesCss.mScroll} style={{ paddingTop: 4 }}>
          <ListCard>
            {view.chats.map((c) => (
              <ListRow key={c.key} onClick={() => app.sheet({ height: 0.4, content: () => <ChatSheet station={station.address} title={c.title} chat={c.chat ?? null} choices={c.choices} /> })}>
                <Lines title={c.title} note={c.note} tag={c.archived ? "已归档" : undefined} />
                <span className={css.mSize}>{c.text}</span>
              </ListRow>
            ))}
          </ListCard>
          {view.unseenText && <p className={css.mNote}>{view.unseenText}</p>}
          <div style={{ height: 30 }} />
        </div>
      )}
    </div>
  );
}

/** A chat's sheet: open it, or one of the clean-ups it has. */
function ChatSheet({ station, title, chat, choices }: { station: string; title: string; chat: string | null; choices: FootprintChoice[] }) {
  const app = useApp();
  return (
    <>
      <SheetGrab />
      <SheetHead title={title} />
      <div className={sheetsCss.mSheetScroll}>
        {chat && <PickRow label="打开 chat" onClick={() => { app.sheet(null); app.push(`${stationBase(station)}/chats/${encodeURIComponent(chat)}`); }} />}
        {choices.map((c) => <PickRow key={c.label} label={c.label} accent={c.call === "footprint.delete"}
          onClick={() => app.sheet({ height: 0.42, content: () => <CleanSheet station={station} choice={c} /> })} />)}
      </div>
    </>
  );
}

/** A clean-up: which choice when it has several, then each question in turn; the sheet stays, with what went wrong,
 * until it is done. */
function CleanSheet({ station, action, choice: given }: { station: string; action?: FootprintAction; choice?: FootprintChoice }) {
  const app = useApp();
  const call = useStationCall(station);
  const [choice, setChoice] = useState<FootprintChoice | null>(given ?? (action?.choices.length === 1 ? action.choices[0]! : null));
  const [step, setStep] = useState(0);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  if (!choice) {
    return (
      <>
        <SheetGrab />
        <SheetHead title={action?.pick ?? ""} />
        <div className={sheetsCss.mSheetScroll}>
          {action?.choices.map((c) => <PickRow key={c.label} label={c.label} onClick={() => setChoice(c)} />)}
        </div>
      </>
    );
  }
  const confirm = choice.confirms[step]!;
  const agree = () => {
    if (step + 1 < choice.confirms.length) return setStep(step + 1);
    setBusy(true); setError(null);
    call.op(choice.call, { keys: choice.keys }).then(() => { app.sheet(null); app.toast(choice.done); }, (e: unknown) => setError(e instanceof Error ? e.message : String(e))).finally(() => setBusy(false));
  };
  return (
    <>
      <SheetGrab />
      <SheetHead key={step} title={confirm.title} />
      <div className={`${sheetsCss.mSheetScroll} ${sheetsCss.mForm}`}>
        <p className={partsCss.mMuted}>{confirm.text}</p>
        {error && <p className={partsCss.mError}>{error}</p>}
        <div className={sheetsCss.mFormActions}>
          <Button label="取消" primary={false} onClick={() => app.sheet(null)} />
          <span data-danger={confirm.danger || undefined} className={sheetCss.mDangerButton}>
            <Button label={confirm.action} primary busy={busy} onClick={agree} />
          </span>
        </div>
      </div>
    </>
  );
}
