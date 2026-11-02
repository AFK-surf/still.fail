// Cards an agent left to people (a post with options, a field to write in, a login, a vault request;
// client/core-ts/src/decisions.ts), in its chat: the post is a message like any other, its options right under it in
// one card, numbered, the recommended one last; once answered (or replaced), a quiet line saying how. A text card is
// answered in the chat's composer; a login card is the login an agent started (MachineLogins.tsx LoginCard).
//
// Everything said goes through the core's calls (decision.answer / dismiss); what is under way shows on its button
// (doing.ts), what failed in a toast (useAct).
import { useRef, useState, type ReactNode } from "react";
import type { ChatMessage, DecisionOption, MessageCard } from "./core/shapes.ts";
import { useCall } from "./core/react.ts";
import { scopeOf, useStation } from "./station.tsx";
import { doingMatches, failed, useDoingList } from "./doing.ts";
import { useAct } from "@stillfail/ui/toast.tsx";
import { ENTER, motionMs } from "@stillfail/ui/motion.ts";
import { listPaneOf, reserveRow } from "./listQueue.ts";
import { SaidInPlace, useSettling } from "./settling.tsx";
import { VaultCard } from "./VaultApproval.tsx";
import { LoginCard } from "./MachineLogins.tsx";
import * as css from "./Decisions.css.ts";
import { t } from "./i18n.ts";
import { Check, Option1, Option2, Option3, Option4, Option5, Option6 } from "@stillfail/ui/icons.tsx";
import { Spinner } from "@stillfail/ui/waiting.tsx";

/** Each option's number, drawn (a card has at most six; past that, set as text). */
const DIGITS = [Option1, Option2, Option3, Option4, Option5, Option6];

/** The options of one decision, in one card, numbered; pressing one answers with it (its label, quoting the post). */
export function DecisionOptions({ station, thread, seq, options, settled, locked = false, className }: {
  station: string; thread: number; seq: number; options: DecisionOption[];
  /** Answered, still drawn till they close (in a chat): none pressed any more, the one picked (its label) as it was. */
  settled?: string | null | undefined;
  /** Waiting, and its agent in a turn (the core's `locked`): an option that closes the card is not answerable until
   * that turn ends (the station refuses it meanwhile), so it is drawn so and says why. */
  locked?: boolean;
  className?: string;
}) {
  const call = useCall();
  const act = useAct();
  const doing = useDoingList();
  const sending = doing.find((d) => !failed(d) && doingMatches(d, "decision.answer", { station, thread, seq }));
  const pick = (o: DecisionOption, button: HTMLElement) => {
    if (sending || settled !== undefined || (locked && o.closes)) return;
    // The answer (its row, in the outbox) comes in first, in the turn taken now, the options closing after it; the
    // list follows its end for it, as for words sent (Chat.tsx useToEnd).
    reserveRow(button, motionMs(ENTER.duration));
    listPaneOf(button)?.dispatchEvent(new Event("sent"));
    act(call("decision.answer", { station, thread, seq, option: o.label }), t("web-main.decisions.answerWhat", { option: o.label }));
  };
  return (
    <div className={`${css.options} ${className ?? ""}`} role="group" aria-label={t("web-main.decisions.options")}>
      {options.map((o, i) => {
        const busy = sending?.params.option === o.label;
        const Digit = DIGITS[i];
        // (the one picked, answered: a check in its disc where its number was)
        const chosen = settled !== undefined && settled === o.label;
        // Its agent in a turn: closing the card waits for it (a pick answering in the chat does not).
        const shut = locked && o.closes === true;
        return (
          <button key={o.label} type="button" className={css.choice} data-recommended={o.recommended || undefined} data-busy={busy || undefined}
            data-chosen={chosen || undefined} data-locked={shut || undefined}
            disabled={!!sending || settled !== undefined || shut} aria-busy={busy || undefined}
            aria-description={[o.recommended && t("common.recommended"), shut && t("web-main.decisions.locked")].filter(Boolean).join(" ") || undefined}
            onClick={(e) => pick(o, e.currentTarget)}>
            <span className={css.choiceNumber} aria-hidden="true">{chosen ? <Check size={12} /> : Digit ? <Digit size={20} /> : i + 1}</span>
            <span className={css.choiceLabel}>{o.label}</span>
            {o.detail && <span className={css.choiceDetail}>{o.detail}</span>}
            {shut && <span className={css.choiceLocked}>{t("web-main.decisions.locked")}</span>}
            {busy && <Spinner inline className={css.choiceSpinner} />}
          </button>
        );
      })}
    </div>
  );
}

/** What kind of card it is: its `type`, or (a core before cards) options when it has some. */
export function cardType(card: MessageCard | undefined, options: readonly DecisionOption[] | undefined): string | undefined {
  return card?.type ?? (options?.length ? "options" : undefined);
}

/**
 * Under an agent's post with options, in its chat: the options while it waits for the viewer (none in a chat that
 * cannot be written to: `thread` null), else how it was settled, quietly, if the core says.
 */
export function MessageDecision({ message: m, thread, children }: { message: ChatMessage; thread: number | null;
  /** Under the options, going with them (its 忽略; not under a login card, which stays). */
  children?: ReactNode;
}) {
  const station = useStation().address;
  const d = m.decision;
  const open = !d?.resolved && !d?.dismissed;
  const box = useRef<HTMLDivElement>(null);
  // Settled on screen, the options stay as they were, the one picked marked, none pressed, till they are out of sight
  // (useSettling: then how it went, at once); open again (an answer that failed), they are back at once.
  const [drawnOpen, setDrawnOpen] = useState(open);
  const shown = open || drawnOpen;
  useSettling(box, open, drawnOpen, setDrawnOpen);
  if (!m.card && !m.options?.length) return null;
  // A login card stays as its login goes (waiting, done, failed, cancelled): it says how it ended itself, once closed.
  if (m.card?.type === "login" && m.card.login) {
    return (
      <div ref={box} className={css.decision}>
        {open && m.card.assigneeText && <p className={css.settledLine}>{m.card.assigneeText}</p>}
        <LoginCard station={loginStation(station, m.card)} id={m.card.login} />
      </div>
    );
  }
  return (
    <div ref={box} className={css.decision}>
      {shown ? <>
        {/* Who decides; settled while it shows, it fades out where it is (the one picked is marked among the options,
            an answer in words is the viewer's message under them); let go, 已忽略 in its place. */}
        {m.card?.assigneeText && <SaidInPlace className={css.settledLine} text={d?.dismissed && d.text ? d.text : m.card.assigneeText} gone={!open && !d?.dismissed} />}
        {/* An agent's request for a vault item: approved here (VaultApproval.tsx), not answered in words. */}
        {m.card?.vault ? <VaultCard address={station} id={m.card.vault} />
          : thread !== null && cardType(m.card, m.options) === "options" && !!m.options?.length &&
          <DecisionOptions station={station} thread={thread} seq={m.seq} options={m.options} settled={open ? undefined : d?.chosen ?? null} locked={open && d?.locked === true} />}
        {children}
      </> : d?.text ? <p className={css.settledLine}>{d.text}</p> : null}
    </div>
  );
}

/** Where a login card's login is: the chat's station, or another of its workspace (the card's `station`, its key). */
export function loginStation(chatStation: string, card: MessageCard): string {
  return card.station ? `${scopeOf(chatStation)}/${card.station}` : chatStation;
}
