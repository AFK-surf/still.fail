// How much of its machine a station takes, and cleaning it up (the core's `footprint` topic, client/core/src/footprint.rs):
// the wide screen's page (settings, a station each), the disk's bar both screens share, and how a clean-up runs: its
// choice picked when it has several, each of its questions agreed to in turn (deleting is asked twice), then its call.
import { useState } from "react";
import { Link } from "react-router";
import { useStationCall } from "./api.ts";
import { useTopic, type TopicState } from "./core/react.ts";
import type { FootprintAction, FootprintChoice, FootprintView } from "./core/shapes.ts";
import { stationBase } from "./station.tsx";
import { useToast } from "./toast.tsx";
import { Button, Confirm, Dialog, Loading, Menu, Section } from "./ui.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as css from "./Footprint.css.ts";

export function useFootprint(station: string): TopicState<FootprintView> {
  return useTopic<FootprintView>({ topic: "footprint", station });
}

/** The disk in one bar (the station's parts, the rest used, what is free) and its legend. */
export function FootprintBar({ view }: { view: FootprintView }) {
  if (view.bar.length === 0) return null;
  return (
    <>
      <div className={css.bar}>
        {view.bar.map((s) => <i key={s.id} className={css.barPiece} style={{ width: `${s.percent}%`, background: css.TONES[s.tone] }} />)}
      </div>
      <div className={css.legend}>
        {view.legend.map((l) => (
          <span key={l.text} className={css.legendItem} data-level={l.level}>
            {l.tone && <span className={css.dot} style={{ background: css.TONES[l.tone] }} />}{l.text}
          </span>
        ))}
      </div>
    </>
  );
}

export function Dot({ tone }: { tone: string }) {
  return tone ? <span className={css.dot} style={{ background: css.TONES[tone] }} /> : null;
}

/** A clean-up under way: which choice (none picked yet: `pick`), at which of its questions. */
export interface Cleaning {
  action: FootprintAction | null;
  choice: FootprintChoice | null;
  step: number;
  busy: boolean;
  error: string | null;
}

/** Runs clean-ups on `station`: `start` one (an action, or a single choice), `agree` to the question asked, `cancel`. */
export function useCleaning(station: string) {
  const call = useStationCall(station);
  const toast = useToast();
  const idle: Cleaning = { action: null, choice: null, step: 0, busy: false, error: null };
  const [state, setState] = useState<Cleaning>(idle);
  const begin = (choice: FootprintChoice) => setState({ ...idle, choice });
  return {
    state,
    /** An action asks which of its choices first when it has several. */
    start(action: FootprintAction) {
      if (action.choices.length === 1) begin(action.choices[0]!);
      else setState({ ...idle, action });
    },
    choose: begin,
    agree() {
      const choice = state.choice;
      if (!choice) return;
      if (state.step + 1 < choice.confirms.length) {
        setState({ ...state, step: state.step + 1 });
        return;
      }
      setState({ ...state, busy: true, error: null });
      call.op(choice.call, { keys: choice.keys }).then(
        () => { setState(idle); toast(choice.done); },
        (e: unknown) => setState({ ...state, busy: false, error: e instanceof Error ? e.message : String(e) }),
      );
    },
    cancel: () => setState(idle),
  };
}

/** The wide screen's questions for a clean-up: which choice, then each confirmation in turn. */
function CleaningDialogs({ cleaning }: { cleaning: ReturnType<typeof useCleaning> }) {
  const { state } = cleaning;
  const confirm = state.choice?.confirms[state.step];
  return (
    <>
      <Dialog open={!!state.action && !state.choice} title={state.action?.pick ?? ""} onClose={cleaning.cancel}>
        <div className={css.choices}>
          {state.action?.choices.map((c) => <Button key={c.label} onClick={() => cleaning.choose(c)}>{c.label}</Button>)}
        </div>
      </Dialog>
      {/* A dialog of its own for each question, so the second is seen as another one. */}
      {state.choice?.confirms.map((c, i) => (
        <Confirm key={`${state.choice!.label}-${i}`} open={!!confirm && state.step === i} title={c.title} description={c.text} action={c.action}
          busy={state.busy} error={state.error} onClose={cleaning.cancel} onConfirm={cleaning.agree} />
      ))}
    </>
  );
}

/** A station's footprint on the wide screen: what it takes, what can be cleaned, by part, its chats, its memory. */
export function StationFootprint({ station }: { station: string }) {
  const usage = useFootprint(station);
  const call = useStationCall(station);
  const cleaning = useCleaning(station);
  const [chats, setChats] = useState(false);
  const view = usage.value;
  if (!view) return <Loading label={usage.error ? `读不到：${usage.error.message}` : "正在读取…"} fill={false} />;
  return (
    <>
      <div className={`${pagesCss.card} ${css.summary}`}>
        <div className={css.lead}>{view.lead}</div>
        <div className={css.total}>{view.totalText}</div>
        <FootprintBar view={view} />
        <div className={css.checked}>
          <span>{view.checkedText}</span>
          {view.measured && !view.scanning && <Button variant="ghost" onClick={() => void call.op("footprint.scan")}>重新统计</Button>}
        </div>
      </div>
      {view.measured && (
        <Section title="可以清理" description={view.actionsNote ?? undefined}>
          {view.actions.length > 0 && (
            <div className={pagesCss.card}>
              {view.actions.map((a) => (
                <div key={a.id} className={pagesCss.cardRow}>
                  <div className={pagesCss.cardRowText}><strong>{a.title}</strong><span className={css.rowNote}>{a.note}</span></div>
                  <Button variant={a.danger ? "danger" : "secondary"} onClick={() => cleaning.start(a)}>{a.action}</Button>
                </div>
              ))}
            </div>
          )}
        </Section>
      )}
      {view.parts.length > 0 && (
        <Section title="磁盘 · 按用途">
          <div className={`${pagesCss.card} ${css.rows}`}>
            {view.parts.map((p) => (
              <div key={p.id} className={css.row}>
                <Dot tone={p.tone} />
                <div className={css.rowText}><span>{p.label}</span><span className={css.rowNote}>{p.note}</span></div>
                {p.opens && <Button variant="ghost" onClick={() => setChats(!chats)}>{chats ? "收起" : "看每个 chat"}</Button>}
                <span className={css.size}>{p.text}</span>
              </div>
            ))}
          </div>
        </Section>
      )}
      {chats && (
        <Section title="chat 工作区" description={view.chatsText}>
          <div className={`${pagesCss.card} ${css.rows}`}>
            {view.chats.map((c) => (
              <div key={c.key} className={css.row}>
                <div className={css.rowText}>
                  <span>{c.chat ? <Link to={`${stationBase(station)}/chats/${encodeURIComponent(c.chat)}`}>{c.title}</Link> : c.title}{c.archived && <span className={css.badge}>已归档</span>}</span>
                  <span className={css.rowNote}>{c.note}</span>
                </div>
                <span className={css.size}>{c.text}</span>
                {c.choices.length > 0 && <Menu items={c.choices.map((ch) => ({ label: ch.label, danger: ch.call === "footprint.delete", onSelect: () => cleaning.choose(ch) }))} />}
              </div>
            ))}
            {view.unseenText && <div className={css.row}><span className={css.rowNote}>{view.unseenText}</span></div>}
          </div>
        </Section>
      )}
      {view.elsewhere.length > 0 && (
        <Section title="这台机器上的其它" description={view.elsewhereNote}>
          <div className={`${pagesCss.card} ${css.rows}`}>
            {view.elsewhere.map((p) => (
              <div key={p.id} className={css.row}>
                <div className={css.rowText}><span>{p.label}</span><span className={css.rowNote}>{p.note}</span></div>
                <span className={css.size}>{p.text}</span>
              </div>
            ))}
          </div>
        </Section>
      )}
      <Section title={view.memoryTitle}>
        <div className={`${pagesCss.card} ${css.rows}`}>
          {view.memory.map((r, i) => (
            <div key={i} className={css.row} data-nested={r.nested || undefined}>
              <div className={css.rowText}>
                <span>{r.chat ? <Link to={`${stationBase(station)}/chats/${encodeURIComponent(r.chat)}`}>{r.label}</Link> : r.label}</span>
                {r.note && <span className={css.rowNote}>{r.note}</span>}
              </div>
              <span className={css.size}>{r.text}</span>
              {r.choice && <Button variant="ghost" onClick={() => cleaning.choose(r.choice!)}>{r.choice.label}</Button>}
            </div>
          ))}
        </div>
      </Section>
      <CleaningDialogs cleaning={cleaning} />
    </>
  );
}
