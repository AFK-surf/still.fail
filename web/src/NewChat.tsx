// A new chat, after Zork's: say what to do, having picked where it runs
// (station), on what (runtime and model) and how hard it thinks. The first
// message (or file) makes the chat and its agent's session on that station.
import { Key, Plus } from "./icons.tsx";
import { StationMark } from "./StationMark.tsx";
import { Link, useNavigate } from "react-router";
import { useMemo, useRef, useState } from "react";
import type { RuntimeKind, StationView } from "./api.ts";
import type { NewChatView } from "./core/shapes.ts";
import { useReady } from "./core/react.ts";
import { useNewChat, usePick } from "./pick.ts";
import { useAct } from "./toast.tsx";
import { ComposerSlot, useCarryDraft } from "./dock.tsx";
import { profilesPage, StationContext, stationBase, type Station } from "./station.tsx";
import { Button, Chooser, ChooserItem as Item, FirstOne } from "./ui.tsx";
import { MachineLoginOffers, PROFILE_LEAD } from "./pages/Accounts.tsx";
import { addProfilePath } from "./pages/AddProfile.tsx";
import { ModelTriple } from "./ModelTriple.tsx";
import { Illustration } from "./brand.tsx";
import { track } from "./telemetry.ts";
import { keepTabs } from "./chatTabs.ts";
import * as css from "./NewChat.css.ts";
import { FrequentCombos } from "./FrequentCombos.tsx";
import type { PickPatch } from "./pick.ts";
import * as controlsCss from "./styles/controls.css.ts";
import * as shellCss from "./styles/shell.css.ts";
import * as chatCss from "./styles/chat.css.ts";
import { MachineSessions } from "./MachineSessions.tsx";
import { composerText } from "./Chat.css.ts";
import { notSent, sendingFirst } from "./madeChat.ts";
import { OVER_DOCK } from "./Chat.tsx";
import { LOCAL_MS } from "./motion.ts";
import { t } from "./i18n.ts";

/** A new chat in a workspace; `onCreated` gets the station's address and the new item's session (its address). */
export function NewChat({ scope, onCreated }: { scope: string; onCreated(station: string, session: string): void }) {
  // What the core keeps of it (../pick.ts): held back a moment for its first value from the device (LOCAL_MS, not for
  // the network), so the page comes as it will be.
  useReady({ topic: "newChat", scope }, LOCAL_MS);
  const chat = useNewChat(scope);
  const choice = chat.value;
  const onStation = (id: string) => chat.pick({ station: id });
  const view = choice?.station;
  if (!choice?.stations) {
    // The station it will most likely be, by the one last written to (its draft comes with it).
    const stationId = choice?.kept ?? "";
    const error = choice?.error ?? chat.error?.message;
    const address = `${scope}/${stationId}`;
    const held: Station = { id: stationId, name: "", base: stationBase(address), address, online: true, settings: `/w/${scope}/settings` };
    // Laid out as the page will be (the composer's place held, the words under it), so nothing moves when it comes.
    return (
      <div className={css.newChat}><div className={css.newChatInner}>
        <Illustration name="new-chat" /><h1 className={css.newChatTitle}>{t("web-main.newChat.title")}</h1><p className={css.newChatSub}>{t("web-main.newChat.subChosen")}</p>
        {/* The composer itself (dock.tsx), locked until there is a station to write to: it goes on from the page before
            without leaving the screen for as long as the stations take to come (the first time the page is opened). */}
        <ComposerSlot variant="new" station={held} draftKey={`new:${held.address}`} thread={null} sessionKey={null} placeholder={t("web-main.newChat.placeholder")} locked roomy />
        <p className={`${css.newChatStatus}${error ? ` ${controlsCss.fieldError}` : ""}`}>{error ?? t("web-main.newChat.readingStation")}</p>
      </div></div>
    );
  }
  if (!view) {
    return <div className={css.newChat}><div className={css.newChatInner}><Illustration name="station-offline" /><h1 className={css.newChatTitle}>{t("web-main.newChat.title")}</h1><p className={shellCss.muted}>{t("web-main.newChat.noStation")}</p></div></div>;
  }
  // The composer's files and links belong to the station the chat goes to.
  const station: Station = { id: view.id, name: view.name, base: stationBase(view.station), address: view.station, online: true, settings: `/w/${scope}/settings` };
  return (
    <StationContext.Provider value={station}>
      <NewChatOn key={view.station} choice={choice} view={view} station={station} stations={choice.stations} onStation={onStation} pickCombo={chat.pick} create={chat.create} onCreated={onCreated} />
    </StationContext.Provider>
  );
}

function NewChatOn({ choice, view, station, stations, onStation, pickCombo, create, onCreated }: {
  choice: NewChatView; view: StationView; station: Station; stations: StationView[]; onStation(id: string): void;
  pickCombo(patch: PickPatch): void;
  create(station: string): Promise<Made>; onCreated(station: string, session: string): void;
}) {
  // What it runs on, as the core resolved it against what the station has (its model control: ../pick.ts).
  const model = choice.model?.model;
  const runtime = choice.runtime;
  const pick = usePick(station.address, "new", choice);
  const act = useAct();
  const navigate = useNavigate();
  const workspace = station.address.split("/")[0]!;
  // Made with what is picked here; the next new chat starts here too (the core keeps it).
  const ensureChat = useEnsureChat(station.address, create);
  const toolbar = useMemo(() => (
    <>
      {station.name && (
        <Chooser side="top" label={<><StationMark emoji={stations.find((s) => s.station === station.address)?.emoji} />{station.name}</>}>
          {stations.map((s) => <Item key={s.station} checked={s.station === station.address} onSelect={() => onStation(s.id)}><StationMark emoji={s.emoji} />{s.name}</Item>)}
        </Chooser>
      )}
      {!runtime || !model ? (
        // Nothing to choose from: the chooser leads to where models are enabled.
        <Link className={chatCss.chooser} to={profilesPage(station)}>{t("web-main.newChat.noModels")}</Link>
      ) : (
        <ModelTriple side="top" pick={pick} onConfirm={() => act(pick.save(), t("web-main.newChat.changeModelWhat"))} />
      )}
    </>
  ), [stations, station, runtime, model, pick, act]);

  const carry = useCarryDraft();
  // The chat pages' one composer (dock.tsx): here in the page, then, once the first message is sent, in the chat's page,
  // where that message already waits for the chat to be made.
  const composer = (
    <ComposerSlot variant="new" station={station} draftKey={`new:${station.address}`} thread={null} sessionKey={null} ensureChat={ensureChat}
      placeholder={t("web-main.newChat.placeholder")} toolbar={toolbar} locked={!runtime || !model} roomy
      // Its words stay where they were until the chat's page takes them (../madeChat.ts), over the composer.
      onSending={(text) => {
        const field = document.querySelector<HTMLElement>(`[data-made-composer] .${composerText}`);
        const layer = field?.closest<HTMLElement>("[data-made-composer]")?.offsetParent;
        if (text === null) notSent();
        else if (field && layer instanceof HTMLElement) sendingFirst(field, text, layer, OVER_DOCK);
      }}
      onSent={(to) => {
        const key = String(to);
        // What is being typed goes on in the chat, in the same composer.
        carry(`${station.address}:${key}`);
        // Made here, the chat opens without its agent's history beside: it is opened from the agent when wanted.
        keepTabs(`${station.address}:${key}`, { tabs: [], active: null });
        onCreated(station.address, key);
      }} />
  );
  // Nothing to run a chat with yet: its first step is the page (the composer comes once it can send).
  const blocked = choice.blocked;
  if (blocked) {
    return (
      <div className={css.newChat}>
        <div className={css.newChatInner}>
          <FirstOne art={<Illustration name="no-profile" />} title={blocked === "profile" ? t("web-main.newChat.addProfileFor", { name: station.name || t("web-main.newChat.thisMachine") }) : t("web-main.newChat.pickModels")}
            lead={blocked === "profile" ? PROFILE_LEAD : t("web-main.newChat.noModelsLead", { name: station.name || t("web-main.newChat.thisMachine") })}>
            {blocked === "profile"
              ? <Button variant="primary" icon={Plus} onClick={() => navigate(addProfilePath(workspace, station.address))}>{t("web-main.newChat.addProfile")}</Button>
              : <Link className={`${controlsCss.btn} ${controlsCss.btnPrimary}`} to={profilesPage(station)}>{t("web-main.newChat.goPickModels")}</Link>}
            {stations.length > 1 && (
              <Chooser side="bottom" label={<><StationMark emoji={stations.find((s) => s.station === station.address)?.emoji} />{station.name}</>}>
                {stations.map((s) => <Item key={s.station} checked={s.station === station.address} onSelect={() => onStation(s.id)}><StationMark emoji={s.emoji} />{s.name}</Item>)}
              </Chooser>
            )}
            {blocked === "profile" && <MachineLoginOffers logins={view.overview?.machineLogins} onAdd={(c) => navigate(addProfilePath(workspace, station.address, c === "claude-sub" ? "anthropic" : "openai", "plan"))} />}
          </FirstOne>
        </div>
      </div>
    );
  }
  return (
    <div className={css.newChat}>
      <div className={css.newChatInner}>
        {/* What leaves as the chat comes (../madeChat.ts): the scene above the composer out of view, what is by it where it is. */}
        <Illustration name="new-chat" data-made-leave="up" />
        <h1 className={css.newChatTitle} data-made-leave="up">{t("web-main.newChat.title")}</h1>
        <p className={css.newChatSub} data-made-leave="up">{t("web-main.newChat.sub", { name: station.name || t("web-main.newChat.thisMachine") })}</p>
        {/* Chosen anyway (it is the person's call), but said: what is sent waits for its quota. */}
        {choice.spent && <p className={css.spentNotice} role="status" data-made-leave="up">{choice.spent}</p>}
        {composer}
        <FrequentCombos items={choice.frequent} onPick={pickCombo} />
        {/* What it waits for, in a line of its own under the composer, kept whether or not there is anything to say. */}
        <p className={css.newChatStatus} data-made-leave="fade">{choice.waiting ? choice.problem : ""}</p>
        {/* Out of the page's flow: it comes once the station has said what there is, and would move the composer. */}
        <div className={css.newChatOffer} data-made-leave="fade">
          <MachineSessions name={station.name} models={view.models} onContinued={(key) => {
            keepTabs(`${station.address}:${key}`, { tabs: [], active: null });
            onCreated(station.address, key);
          }} />
        </div>
      </div>
    </div>
  );
}

/** A chat made (`newChat.create`): its key, and what it runs on. */
export interface Made { key: string; runtime: RuntimeKind; model: string; effort?: string }

/**
 * What makes a new chat with its first message, on either screen (the phone's, mobile/NewChat.tsx): on the station at
 * `address`, with what is picked there (the core has it: `newChat.create`). The core has the chat at once (its page,
 * its row, the message waiting in it); the station makes it behind it. Made once: what is sent meanwhile goes to the
 * same chat; if it could not be made, the next message tries again.
 */
export function useEnsureChat(address: string, create: (station: string) => Promise<Made>) {
  const made = useRef<Promise<{ key: string; thread: string }> | null>(null);
  return () => {
    made.current ??= create(address).then(({ key, runtime, model, effort }) => {
      track("chat_created", { runtime, model, ...(effort ? { effort } : {}) });
      return { key, thread: key };
    }).catch((error: unknown) => { made.current = null; throw error; });
    return made.current;
  };
}
