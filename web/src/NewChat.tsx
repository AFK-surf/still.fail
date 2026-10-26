// A new chat, after Zork's: say what to do, having picked where it runs
// (station), on what (runtime and model) and how hard it thinks. The first
// message (or file) makes the chat and its agent's session on that station.
import { Folder, Key, PanelClose, Plus } from "@stillfail/ui/icons.tsx";
import { StationMark } from "./StationMark.tsx";
import { Link, useNavigate } from "react-router";
import { useEffect, useMemo, useRef, useState } from "react";
import { Tabs } from "radix-ui";
import type { RuntimeKind, StationView } from "./api.ts";
import type { NewChatView } from "./core/shapes.ts";
import { core, useReady } from "./core/react.ts";
import { useNewChat, usePick } from "./pick.ts";
import { useAct } from "@stillfail/ui/toast.tsx";
import { ComposerSlot, useCarryDraft } from "./dock.tsx";
import { profilesPage, StationContext, stationBase, type Station } from "./station.tsx";
import { Button, Chooser, ChooserItem as Item, FirstOne, IconButton, ResizeHandle, WaitLine } from "./ui.tsx";
import { MachineLoginOffers, PROFILE_LEAD } from "./pages/Accounts.tsx";
import { addProfilePath } from "./pages/AddProfile.tsx";
import { ModelTriple } from "./ModelTriple.tsx";
import { Illustration } from "./brand.tsx";
import { track } from "./telemetry.ts";
import { changeTabs } from "./chatTabs.ts";
import { usePrefs } from "./prefs.ts";
import { useShortcut } from "./keymap.ts";
import { DriveTab } from "./pages/DriveTab.tsx";
import { DropHint, FILES, FilesTab, keepFocus, PANEL_MAX, PANEL_MIN, SidePane, useChatDrop, useSidePanel, useStationDrive } from "./pages/ChatSide.tsx";
import * as css from "./NewChat.css.ts";
import { FrequentCombos } from "./FrequentCombos.tsx";
import type { PickPatch } from "./pick.ts";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import * as shellCss from "./styles/shell.css.ts";
import * as sessionCss from "./styles/session.css.ts";
import * as jobsCss from "./styles/jobs.css.ts";
import * as sidebarCss from "./styles/sidebar.css.ts";
import * as chatCss from "./pages/ChatPage.css.ts";
import { MachineSessions } from "./MachineSessions.tsx";
import { RetryPill } from "./Connection.tsx";
import { composerText } from "./Chat.css.ts";
import { notSent, sendingFirst } from "./madeChat.ts";
import { OVER_DOCK } from "./Chat.tsx";
import { LOCAL_MS } from "@stillfail/ui/motion.ts";
import { t } from "./i18n.ts";
import { StationInWords } from "./StationNamed.tsx";

/** What a station is shown by (StationMark): its icon and emoji, none for a station not listed. */
const markOf = (s: { emoji?: string | null | undefined; icon?: string | null | undefined } | undefined) => ({ emoji: s?.emoji, icon: s?.icon });

/** A new chat in a workspace; `onCreated` gets the station's address and the new item's session (its address). */
export function NewChat({ scope, onCreated }: { scope: string; onCreated(station: string, session: string): void }) {
  // What the core keeps of it (../pick.ts): held back a moment for its first value from the device (LOCAL_MS, not for
  // the network), so the page comes as it will be.
  useReady({ topic: "newChat", scope }, LOCAL_MS);
  // What the workspace goes back to (settings left, another workspace's, the app opened again): this new chat, not the
  // chat shown before it (the core keeps it: views/marks.ts lastChat).
  useEffect(() => void core().focus({ newChat: scope }).catch(() => undefined), [scope]);
  const chat = useNewChat(scope);
  const choice = chat.value;
  const onStation = (id: string) => chat.pick({ station: id });
  const view = choice?.station;
  if (!choice?.stations) {
    // The station it will most likely be, by the one last written to (its draft is the workspace's, whichever it is).
    const stationId = choice?.kept ?? "";
    const error = choice?.error ?? chat.error?.message;
    const address = `${scope}/${stationId}`;
    const held: Station = { id: stationId, name: "", base: stationBase(address), address, online: true, settings: `/w/${scope}/settings` };
    // Laid out as the page will be (the composer's place held, the words under it), so nothing moves when it comes.
    return (
      <div className={css.newChat}><div className={`${css.newChatInner} ${css.newChatTall}`}>
        <div className={css.newChatScene}>
          <Illustration name="new-chat" /><h1 className={css.newChatTitle}>{t("web-main.newChat.title")}</h1><p className={css.newChatSub}>{t("web-main.newChat.subChosen")}</p>
        </div>
        {/* The composer itself (dock.tsx), locked until there is a station to write to: it goes on from the page before
            without leaving the screen for as long as the stations take to come (the first time the page is opened). */}
        <ComposerSlot variant="new" station={held} draftKey={`new:${scope}`} thread={null} sessionKey={null} placeholder={t("web-main.newChat.placeholder")} locked roomy />
        <div className={css.newChatUnder}>
          {error ? <p className={`${css.newChatStatus} ${controlsCss.fieldError}`}>{error}</p>
            : <WaitLine text={t("common.readingStations")} className={css.newChatStatus} />}
        </div>
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
        <Chooser side="top" label={<><StationMark {...markOf(stations.find((s) => s.station === station.address))} />{station.name}</>}>
          {stations.map((s) => <Item key={s.station} checked={s.station === station.address} onSelect={() => onStation(s.id)}><StationMark emoji={s.emoji} icon={s.icon} />{s.name}</Item>)}
        </Chooser>
      )}
      {!runtime || !model ? (
        // Nothing to choose from: the chooser leads to where models are enabled.
        <Link className={controlsCss.chooser} to={profilesPage(station)}>{t("web-main.newChat.noModels")}</Link>
      ) : (
        <ModelTriple side="top" pick={pick} onConfirm={() => act(pick.save(), t("web-main.newChat.changeModelWhat"))} />
      )}
    </>
  ), [stations, station, runtime, model, pick, act]);

  // The workspace's new chat, whichever station it is to run on: what is written (its files go up to that station),
  // and the workspace's stations' files beside it, as beside a chat (../pages/DriveTab.tsx): what is added goes into
  // its message, and dropped anywhere on the page too. Open or not for the workspace's new chat; open as the page
  // becomes the chat, open there.
  const draftKey = `new:${workspace}`;
  const kept = usePrefs((p) => p.chatTabs[draftKey]);
  const drive = useStationDrive(station.address);
  const open = drive && kept?.tabs.includes(FILES) ? [FILES] : [];
  const side = useSidePanel(open, open[0] ?? null);
  const setFiles = (on: boolean) => {
    side.changing(on);
    changeTabs(draftKey, on ? "open" : "close", FILES);
  };
  useShortcut("panel.close", open.length ? () => setFiles(false) : null);
  const drop = useChatDrop(draftKey);

  const carry = useCarryDraft();
  // The chat pages' one composer (dock.tsx): here in the page, then, once the first message is sent, in the chat's page,
  // where that message already waits for the chat to be made.
  const composer = (
    <ComposerSlot variant="new" station={station} draftKey={draftKey} thread={null} sessionKey={null} ensureChat={ensureChat}
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
        // Made here, the chat opens without its agent's history beside: it is opened from the agent when wanted. The
        // files open here stay open beside it.
        changeTabs(`${station.address}:${key}`, "clear");
        if (open.length) changeTabs(`${station.address}:${key}`, "open", FILES);
        onCreated(station.address, key);
      }} />
  );
  // Nothing to run a chat with yet: its first step is the page (the composer comes once it can send).
  const blocked = choice.blocked;
  if (blocked) {
    return (
      <div className={css.newChat}>
        <div className={css.newChatInner}>
          {/* A station this workspace joined, none of whose profiles is open here: whom to ask, and nothing to do here. */}
          <FirstOne art={<Illustration name="no-profile" />}
            title={<StationInWords station={station.address} text={blocked === "profile" ? t("web-main.newChat.addProfileFor", { name: station.name || t("web-main.newChat.thisMachine") })
              : blocked === "shared" ? t("web-main.newChat.notShared", { name: station.name || t("web-main.newChat.thisMachine") }) : t("web-main.newChat.pickModels")} />}
            lead={blocked === "profile" ? PROFILE_LEAD : blocked === "shared" ? choice.problem && <StationInWords station={station.address} text={choice.problem} />
              : <StationInWords station={station.address} text={t("web-main.newChat.noModelsLead", { name: station.name || t("web-main.newChat.thisMachine") })} />}>
            {blocked === "profile"
              ? <Button variant="primary" icon={Plus} onClick={() => navigate(addProfilePath(workspace, station.address))}>{t("web-main.newChat.addProfile")}</Button>
              : blocked === "shared" ? null
              : <Link className={`${controlsCss.btn} ${controlsCss.btnPrimary}`} to={profilesPage(station)}>{t("web-main.newChat.goPickModels")}</Link>}
            {stations.length > 1 && (
              <Chooser side="bottom" label={<><StationMark {...markOf(stations.find((s) => s.station === station.address))} />{station.name}</>}>
                {stations.map((s) => <Item key={s.station} checked={s.station === station.address} onSelect={() => onStation(s.id)}><StationMark emoji={s.emoji} icon={s.icon} />{s.name}</Item>)}
              </Chooser>
            )}
            {blocked === "profile" && <MachineLoginOffers logins={view.overview?.machineLogins} onAdd={(c) => navigate(addProfilePath(workspace, station.address, c === "claude-sub" ? "anthropic" : "openai", "plan"))} />}
          </FirstOne>
        </div>
      </div>
    );
  }
  return (
    <div ref={side.pageRef} className={sessionCss.sessionPage} data-panel={open.length > 0 || side.leaving !== null}>
      <div className={`${jobsCss.sessionMain} ${chatCss.dropZone}`} {...drop.handlers}>
        <DropHint drop={drop} />
        {/* The chat's bar's 文件 where the chat's page has it, over the page (what is centred in it stays where it was). */}
        {drive && (
          <header className={`${sidebarCss.pageBar} ${css.newChatBar}`}>
            <div className={chatCss.pageBarActions}>
              <IconButton label={t("web-pages.chat.files")} icon={Folder} onMouseDown={keepFocus} onClick={() => setFiles(open.length === 0)} />
            </div>
          </header>
        )}
        <div className={css.newChat}>
          <div className={`${css.newChatInner} ${css.newChatTall}`}>
            {/* What leaves as the chat comes (../madeChat.ts): the scene above the composer out of view, what is by it where it is. */}
            <div className={css.newChatScene}>
              <Illustration name="new-chat" data-made-leave="up" />
              <h1 className={css.newChatTitle} data-made-leave="up">{t("web-main.newChat.title")}</h1>
              <p className={css.newChatSub} data-made-leave="up">{<StationInWords station={station.address} text={t("web-main.newChat.sub", { name: station.name || t("web-main.newChat.thisMachine") })} />}</p>
            </div>
            {composer}
            {/* What differs by the station and what is picked on it, under the composer: it moves nothing over it. */}
            <div className={css.newChatUnder}>
              {/* Its station went down as it was written in (the network went): the page stays, said so, with 重试. */}
              {choice.down && <p className={css.spentNotice} role="status" data-made-leave="fade">{<StationInWords station={station.address} text={t("web-main.newChat.down", { name: station.name || t("web-main.newChat.thisMachine") })} />} <RetryPill /></p>}
              {/* Chosen anyway (it is the person's call), but said: what is sent waits for its quota. */}
              {choice.spent && <p className={css.spentNotice} role="status" data-made-leave="fade">{choice.spent}</p>}
              <FrequentCombos items={choice.frequent} onPick={pickCombo} />
              {/* What it waits for, in a line of its own under the composer, kept whether or not there is anything to say. */}
              {/* Also what to do on a station with no profile of its own but models it could borrow. */}
              <p className={css.newChatStatus} data-made-leave="fade">{choice.waiting || !choice.model ? (choice.problem ?? "") : ""}</p>
              {/* It comes once the station has said what there is. */}
              <div data-made-leave="fade">
                <MachineSessions name={station.name} models={view.models} onContinued={(key) => {
                  changeTabs(`${station.address}:${key}`, "clear");
                  onCreated(station.address, key);
                }} />
              </div>
            </div>
          </div>
        </div>
      </div>
      {side.side && (
        <Tabs.Root ref={side.panelRef} className={chatCss.sidePanel} data-over-composer value={side.side.shown} inert={side.side === side.leaving}>
          <ResizeHandle variable="--panel-w" edge="left" min={PANEL_MIN} max={PANEL_MAX} label={t("web-pages.chat.resizePanel")}
            press={{ label: t("web-pages.chat.closePanel"), run: () => setFiles(false) }} />
          <div className={chatCss.sideBar}>
            <Tabs.List className={chatCss.sideTabList} aria-label={t("web-pages.chat.files")}>
              <FilesTab onClose={() => setFiles(false)} />
            </Tabs.List>
            <IconButton label={t("web-pages.chat.closePanel")} icon={PanelClose} shortcut="panel.close" onMouseDown={keepFocus} onClick={() => setFiles(false)} />
          </div>
          <SidePane of={FILES} shown={side.side.shown} kept><DriveTab chat={draftKey} /></SidePane>
        </Tabs.Root>
      )}
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
