// Logging a station in to the command-line tools its agents use (docs/remote-login.md): an agent starts the login and
// answers the command's questions; the person only does the step that needs them, in their own browser. The login card
// is all of it (no panel, no second layer): in the chat under the agent's message, on 奏, and on the station page's 登录
// while it is under way. What it shows is the core's (`machineLogins`, `machineLogin`); what is done goes through its
// calls, under way on its button (doing.ts), a failure said by a toast (useAct).
//
// The browser's step is opened by the person's press: a device code's page (the code copied as it opens) or a page to
// open goes straight to the browser (in the press, so a web page's browser lets it open); a loopback login's needs this
// device to take the browser's callback back to the station, which only the desktop app can (`canRelay`): the core
// listens, then answers what to open. A step this client cannot do is said in the card.
import { useEffect, useRef, useState } from "react";
import type { MachineLoginShown, MachineLoginsView } from "./core/shapes.ts";
import { useCall, useTopic } from "./core/react.ts";
import { Link } from "react-router";
import { stationBase } from "./station.tsx";
import { useDoing } from "./doing.ts";
import { useThisMachineAddress } from "./thisMachine.ts";
import { PanelButton, Section } from "./ui.tsx";
import { useAct } from "@stillfail/ui/toast.tsx";
import { Key } from "@stillfail/ui/icons.tsx";
import * as spinnerCss from "@stillfail/ui/styles/spinner.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as css from "./MachineLogins.css.ts";
import { t } from "./i18n.ts";

const loginsTopic = (station: string) => ({ topic: "machineLogins", station }) as const;
const loginTopic = (station: string, id: string) => ({ topic: "machineLogin", station, id }) as const;

/** A station's logins as the core has them: undefined until it answers, null where it has nothing to say. */
export function useMachineLogins(station: string): MachineLoginsView | null | undefined {
  return useTopic<MachineLoginsView | null>(loginsTopic(station)).value;
}

/** One login as it stands: undefined until the core answers, null for one it does not know (ended long ago). */
function useLogin(station: string, id: string): MachineLoginShown | null | undefined {
  return useTopic<MachineLoginShown | null>(loginTopic(station, id)).value;
}

/** The browser's page, opened by the press itself (a web page's browser lets only that open one). */
function openPage(url: string | undefined): void {
  if (url) window.open(url, "_blank", "noopener");
}

/** Copying the code and opening its page, in one press: the code stays on show, for a clipboard that refused it. */
function copyAndOpen(login: MachineLoginShown): void {
  // Both in the press itself: the copy asked first (the page's window taking the focus could refuse it after), the page
  // opened whatever the clipboard says.
  if (login.code) void navigator.clipboard?.writeText(login.code).catch(() => {});
  openPage(login.codeUrl ?? login.url);
}

/**
 * A loopback login's browser, on this device: the core listens for the browser's callback (not on the station's own
 * machine: the browser comes back there by itself), then the page opens. `opened`: this device listens for it now (the
 * core's `listening`), or the page was opened here on the station's own machine.
 */
function useRelay(station: string, login: MachineLoginShown): { open(): void; busy: boolean; opened: boolean } {
  const call = useCall();
  const act = useAct();
  const here = useThisMachineAddress() === station;
  const busy = useDoing("machineLogin.open", { station, id: login.id });
  const [openedHere, setOpenedHere] = useState(false);
  return {
    busy, opened: login.listening || openedHere,
    open: () => act(call("machineLogin.open", { station, id: login.id, here }).then((answer) => {
      if (here) setOpenedHere(true);
      openPage((answer as { url?: string }).url);
    }), t("web-main.logins.openWhat")),
  };
}

// ── the card ──

/**
 * A login, as a card (in a chat under the agent's message, on 奏, on the station page while under way): its title, then
 * what the person does now (a code with 复制并打开; 在浏览器里登录; a step this client cannot do, said), or how it stands
 * (its agent answering the command, done, failed, cancelled), and 取消 while it is under way. Pressing it elsewhere does
 * nothing. A login the core does not know (ended long ago) draws nothing: the message's words say it. `marked`: the one
 * a link pointed to, brought into view.
 */
export function LoginCard({ station, id, marked = false }: { station: string; id: string; marked?: boolean }) {
  const login = useLogin(station, id);
  const logins = useMachineLogins(station);
  const box = useRef<HTMLDivElement>(null);
  useEffect(() => { if (marked && login) box.current?.scrollIntoView({ block: "center" }); }, [marked, login === undefined]); // eslint-disable-line react-hooks/exhaustive-deps
  if (!login) return null;
  const canLogin = logins?.canLogin ?? false;
  return (
    <div ref={box} className={css.card} data-login-card="" data-marked={marked || undefined}>
      <span className={css.cardTitle}>{login.title}</span>
      {login.active && canLogin ? <CardStep station={station} login={login} canRelay={logins?.canRelay ?? false} />
        : <span className={login.state === "failed" ? css.cardFailed : login.state === "done" ? css.cardDone : css.cardStatus}>{login.statusText}</span>}
      {login.active && canLogin && <CardCancel station={station} login={login} />}
    </div>
  );
}

/** What the person does now, by its step; or, while its agent answers the command (or it is starting), how it stands. */
function CardStep({ station, login, canRelay }: { station: string; login: MachineLoginShown; canRelay: boolean }) {
  const relay = useRelay(station, login);
  const step = login.waiting ? undefined : login.step;
  const waiting = (words: string) => <span className={css.cardStatus}><span className={spinnerCss.spinner} aria-hidden="true" />{words}</span>;
  const domain = login.domain ? <span className={css.cardStatus}>{t("web-main.logins.domain", { domain: login.domain })}</span> : null;
  if (step === "device" && login.code) {
    return (
      <>
        <span className={css.cardStatus}>{t("web-main.logins.device", { domain: login.domain ?? "" })}</span>
        <span className={css.cardCode}>{login.code}</span>
        <span className={css.cardActions}><CardButton label={t("web-main.logins.copyOpen")} onClick={() => copyAndOpen(login)} /></span>
      </>
    );
  }
  if (step === "loopback") {
    // A web page cannot take the browser's callback: said here, the page's host all the same.
    if (!canRelay) return <><span className={css.cardStatus}>{t("web-main.logins.needsDesktop")}</span>{domain}</>;
    return (
      <>
        {relay.opened ? waiting(t("web-main.logins.waitingBrowser")) : domain}
        <span className={css.cardActions}><CardButton label={relay.opened ? t("web-main.logins.openAgain") : t("web-main.logins.signIn")} busy={relay.busy} onClick={relay.open} /></span>
      </>
    );
  }
  if (step === "open" && login.url) {
    return <>{domain}<span className={css.cardActions}><CardButton label={t("web-main.logins.signIn")} onClick={() => openPage(login.url)} /></span></>;
  }
  return waiting(login.statusText);
}

function CardButton({ label, busy = false, onClick }: { label: string; busy?: boolean; onClick(): void }) {
  return (
    <PanelButton tone="filled" disabled={busy} aria-busy={busy || undefined} onClick={onClick}>
      <span className={css.cardButtonText}>{label}</span>
    </PanelButton>
  );
}

/** 取消, small, at the card's foot (starting one again is its agent's). */
function CardCancel({ station, login }: { station: string; login: MachineLoginShown }) {
  const call = useCall();
  const act = useAct();
  const busy = useDoing("machineLogin.cancel", { station, id: login.id });
  return (
    <span className={css.cardFoot}>
      <PanelButton disabled={busy} aria-busy={busy || undefined} onClick={() => act(call("machineLogin.cancel", { station, id: login.id }), t("web-main.logins.cancelWhat"))}>
        <span className={css.cardButtonText}>{t("common.cancel")}</span>
      </PanelButton>
    </span>
  );
}

// ── the station page ──

/**
 * A station page's 登录 (docs/remote-login.md): only the logins done there through still.fail. Agents start them (用户定:
 * nobody types a command); one under way is its card, as in its chat; one ended a row saying how it ended, which chat's
 * agent started it (a link) and who ended it. Nothing at all when there are none (or the station is from before them).
 * `marked`: the login a link pointed to (`?login=`), brought into view.
 */
export function LoginsSection({ station, marked }: { station: string; marked?: string | null }) {
  const view = useMachineLogins(station);
  if (!view || !view.supported || view.logins.length === 0) return null;
  const active = view.logins.filter((l) => l.active);
  const past = view.logins.filter((l) => !l.active);
  return (
    <Section title={t("web-main.logins.title")} description={t("web-main.logins.lead")}>
      {active.length > 0 && <div className={css.cards}>{active.map((l) => <LoginCard key={l.id} station={station} id={l.id} marked={l.id === marked} />)}</div>}
      {past.length > 0 && <div className={pagesCss.list}>{past.map((l) => <PastRow key={l.id} station={station} login={l} marked={l.id === marked} />)}</div>}
    </Section>
  );
}

/** Which chat's agent started a login: its title, a link to it. */
function StartedIn({ station, login }: { station: string; login: MachineLoginShown }) {
  if (!login.chat) return null;
  const title = login.chatTitle || t("web-main.logins.aChat");
  const words = t("web-main.logins.startedIn", { chat: "\u0000" }).split("\u0000");
  return <>{words[0]}<Link className={css.chatLink} to={`${stationBase(station)}/chats/${encodeURIComponent(login.chat)}`}>{title}</Link>{words[1]}</>;
}

/** A login that ended: its command, which chat's agent started it, who ended it and how, when (pressed: nothing). */
function PastRow({ station, login, marked }: { station: string; login: MachineLoginShown; marked: boolean }) {
  const box = useRef<HTMLDivElement>(null);
  useEffect(() => { if (marked) box.current?.scrollIntoView({ block: "center" }); }, [marked]);
  // Who ended it says how it ended (张三 取消): the status then says nothing more.
  const rest = [login.doneByText, login.whenText, login.doneByText ? null : login.statusText].filter(Boolean).join(" · ");
  return (
    <div ref={box} className={`${pagesCss.listRow} ${css.pastRow}`} data-marked={marked || undefined}>
      <span className={`${pagesCss.mark} ${css.mark}`}><Key size={18} strokeWidth={1.7} /></span>
      <span className={pagesCss.cardRowText}>
        <strong className={css.name}>{login.command}</strong>
        <span className={login.state === "failed" ? css.stateFailed : css.state}>
          {login.chat && <><StartedIn station={station} login={login} />{" · "}</>}{rest}
        </span>
      </span>
    </div>
  );
}
