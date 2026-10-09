// A new chat on a narrow screen, as the Android app has it (apps/android/…/screens/NewChat.kt): it rises from the
// bottom; say what to do, having picked where it runs (station), on what (model) and how hard it thinks. The first
// message (or file) makes the session on that station; then the page becomes the chat.
import { useLayoutEffect, useRef, type ReactNode } from "react";
import type { ModelOption, RuntimeKind, StationView } from "../api.ts";
import { FrequentCombos } from "../FrequentCombos.tsx";
import type { NewChatView } from "../core/shapes.ts";
import { useNewChat, type PickPatch } from "../pick.ts";
import { RUNTIME_LABEL } from "../format.ts";
import { StationMark } from "../StationMark.tsx";
import { sendDraft } from "../Chat.tsx";
import { useEnsureChat, type Made } from "../NewChat.tsx";
import { StationContext, stationBase, type Station } from "../station.tsx";
import { useNavigate } from "react-router";
import { notSent, sendingFirst, toMadeChat } from "../madeChat.ts";
import { SheetGrab, SheetHead, useApp, type MobileApp } from "./app.tsx";
import type { Draft } from "./Chat.tsx";
import { useHost } from "./ChatHost.tsx";
import { Button, Illustration, Loading, MakerIcon, ModelMark, NavBar, PickRow } from "./parts.tsx";
import { MachineLoginOffers } from "./Profiles.tsx";
import { Buddy, FirstStation } from "./Stations.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as css from "./NewChat.css.ts";
import * as hostCss from "./ChatHost.css.ts";
import * as chatCss from "./styles/chat.css.ts";
import * as newChatCss from "./styles/new-chat.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as sheetsCss from "./styles/sheets.css.ts";
import * as settingsCss from "./styles/settings.css.ts";

import { NAME } from "../channel.ts";
import { t } from "../i18n.ts";
export function NewChatScreen() {
  const app = useApp();
  // The station last started on (or picked) in this workspace and what it runs there, on either screen (../pick.ts).
  const chat = useNewChat(app.entry.id);
  const choice = chat.value;
  const view = choice?.station;
  return (
    <div className={`${pagesCss.mScreen} ${css.mNewchatScreen}`}>
      <NavBar back={t("common.cancel")} onBack={app.pop} title={t("web-mobile.newChat.title")} />
      {!choice?.stations ? <Loading text={choice?.error ?? chat.error?.message ?? t("web-mobile.memory.readingStations")} />
        : !view ? (
          !choice.any ? <FirstStation /> : (
            <div className={newChatCss.mNewNone}>
              <Illustration name="station-offline" width={240} />
              <b>{t("web-mobile.newChat.noneOnline")}</b>
              <p>{t("web-mobile.newChat.noneOnlineNote", { name: NAME })}</p>
            </div>
          )
        )
        : <NewChatOn key={view.station} choice={choice} view={view} stations={choice.stations} pick={chat.pick} create={chat.create} />}
    </div>
  );
}

function NewChatOn({ choice, view, stations, pick, create }: {
  choice: NewChatView; view: StationView; stations: StationView[]; pick(p: PickPatch & { station?: string }): void; create(station: string): Promise<Made>;
}) {
  const app = useApp();
  // The page's composer is its host's (ChatHost.tsx): kept as this new chat becomes its chat.
  const { draft, use } = useHost();
  // What it runs on, as the core resolved it against what the station has now (the same on both screens).
  const entry = choice.model;
  const model = entry?.model;
  const runtime = choice.runtime;
  const effort = choice.effort ?? "";
  const navigate = useNavigate();
  const problem = choice.problem;
  // The first message makes the chat as the wide screen's does (../NewChat.tsx's useEnsureChat, then ../Chat.tsx's
  // sendDraft: the message waits in its outbox, its quotes and files with it), and the page becomes it; what follows
  // goes in after it. The chat is started on this station: the next new chat starts here too.
  const ensureChat = useEnsureChat(view.station, create);
  const opened = useRef(false);
  const send = (draft: Draft) => {
    if (!model || !runtime) return draft.setError(t("web-mobile.newChat.enableModel"));
    // Its words stay where they were in the composer until the chat's page takes them (../madeChat.ts).
    const host = scene.current?.closest<HTMLElement>(`.${hostCss.mChatHost}`);
    const field = host?.querySelector<HTMLElement>(`[data-made-composer] textarea:not([aria-hidden])`);
    if (host && field) sendingFirst(field, draft.text, host, "7");
    void sendDraft(draft, null, ensureChat).then((to) => {
      if (to === null || opened.current) { notSent(); return; }
      opened.current = true;
      // The new item's page (its address from now on, until its station's key takes over: ChatScreen), its first
      // message coming up out of the composer, over it.
      toMadeChat(() => navigate(`${stationBase(view.station)}/chats/${encodeURIComponent(String(to))}`, { replace: true }), {
        scope: host ?? document, layer: () => host ?? null, z: "7", list: () => host?.querySelector<HTMLElement>(`.${chatCss.mMessages}`) ?? null, wait: 90,
      });
    });
  };
  useLayoutEffect(() => use({ station: view.station, placeholder: t("web-mobile.newChat.placeholder"), offline: false, send }));
  const scene = useRef<HTMLDivElement>(null);
  // The scene's end clear of the choices standing over it, whatever their height.
  const foot = useRef<HTMLDivElement>(null);
  useLayoutEffect(() => {
    const el = foot.current;
    const body = scene.current;
    if (!el || !body) return;
    const set = () => body.style.setProperty("--m-new-foot", `${el.offsetHeight}px`);
    set();
    const observer = new ResizeObserver(set);
    observer.observe(el);
    return () => observer.disconnect();
  }, []);
  return (
    <>
      <div className={css.mNewBody} ref={scene} data-made-leave="up">
        <Illustration name="new-chat" width={230} />
        <h2>{t("web-mobile.newChat.ask")}</h2>
        <p className={partsCss.mMuted}>{t("web-mobile.newChat.askNote", { station: view.name })}</p>
        <FrequentCombos items={choice.frequent} onPick={pick} />
        {problem && <p className={css.mNewProblem} data-wait={choice.waiting || undefined}>{problem}</p>}
        {/* No profile yet: adding one is the first step, here (the machine's own logins, when there are any, offered too). */}
        {choice.blocked === "profile" && <NoProfile view={view} />}
      </div>
      <div className={css.mNewFoot} ref={foot}>
        {/* Chosen anyway (it is the person's call), but said: what is sent waits for its quota. */}
        {choice.spent && <p className={css.mNewSpent}>{choice.spent}</p>}
        {/* The choices, then the composer as a floating capsule, as in a chat. */}
        <div className={css.mNewBottom} data-made-leave="fade">
          <div className={css.mChoosers}>
            <Chooser leading={<StationMark emoji={view.emoji} icon={view.icon} />} label={view.name} onClick={() => pickStation(app, stations, view.station, (id) => pick({ station: id }))} />
            {!runtime || !model ? (
              // Nothing to choose from: the chooser leads to where models are enabled.
              <Chooser label={t("web-mobile.newChat.noModels")} onClick={() => app.push(app.at("/settings/profiles"))} />
            ) : (
              <>
                <Chooser leading={<MakerIcon maker={entry.maker} runtime={runtime} size={14} />} label={entry.name}
                  onClick={() => pickModel(app, view, model, (m) => pick({ model: m.model }))} />
                {/* The runtime only when the model runs on more than one. */}
                {entry.runtimes.length > 1 && <Chooser leading={<MakerIcon runtime={runtime} size={14} />} label={RUNTIME_LABEL[runtime as RuntimeKind] ?? runtime}
                  onClick={() => pickRuntime(app, entry.runtimes, runtime, (rt) => pick({ runtime: rt as RuntimeKind }))} />}
                <Chooser label={effort || t("web-mobile.newChat.effortDefault")} onClick={() => pickEffort(app, choice.efforts, effort, (e) => pick({ effort: e || null }))} />
                {choice.pick?.fastAvailable && <Chooser label={choice.fast == null ? t("web-mobile.newChat.fastPlan") : choice.fast ? "Fast" : t("web-mobile.newChat.fastStandard")} onClick={() => app.sheet({ height: 0.36, content: () => <>
                  <SheetGrab /><SheetHead title={t("web-mobile.newChat.speed")} />
                  <div className={sheetsCss.mSheetScroll}>{([null, false, true] as const).map((fast) => <PickRow key={String(fast)} label={fast === null ? t("web-mobile.newChat.fastPlan") : fast ? "Fast" : t("web-mobile.newChat.fastStandard")} sub={fast ? t("web-mobile.newChat.fastNote") : undefined} checked={(choice.fast ?? null) === fast} onClick={() => { pick({ fast }); app.sheet(null); }} />)}</div>
                </> })} />}
              </>
            )}
          </div>
        </div>
      </div>
    </>
  );
}

function Chooser({ leading, label, onClick }: { leading?: ReactNode; label: string; onClick: () => void }) {
  // The same glass as the composer's capsule under it.
  return <button type="button" className={`${css.mChooser} ${pagesCss.mFloating}`} onClick={onClick}>{leading}<span>{label}</span></button>;
}

function pickStation(app: MobileApp, stations: StationView[], current: string, onPick: (s: string) => void) {
  app.sheet({ height: 0.5, content: () => (
    <>
      <SheetGrab /><SheetHead title={t("web-mobile.newChat.pickStation")} />
      <div className={sheetsCss.mSheetScroll}>{stations.map((s) => <PickRow key={s.station} label={s.emoji ? `${s.emoji} ${s.name}` : s.name} sub={s.summary} checked={s.station === current} leading={<Buddy s={s} size={36} />} onClick={() => { onPick(s.id); app.sheet(null); }} />)}</div>
    </>
  ) });
}

function pickModel(app: MobileApp, view: StationView, current: string, onPick: (m: ModelOption) => void) {
  app.sheet({ height: 0.5, content: () => (
    <>
      <SheetGrab /><SheetHead title={t("web-mobile.newChat.pickModel")} />
      <div className={sheetsCss.mSheetScroll}>
        {view.models.map((m) => (
          <PickRow key={m.model} label={m.name} sub={[m.runtimes.map((r) => RUNTIME_LABEL[r] ?? r).join(" · "), m.spent?.text].filter(Boolean).join(" · ")}
            checked={m.model === current} leading={<ModelMark maker={m.maker} runtime={m.runtimes[0]!} size={36} />} onClick={() => { onPick(m); app.sheet(null); }} />
        ))}
      </div>
    </>
  ) });
}

function pickRuntime(app: MobileApp, runtimes: string[], current: string, onPick: (r: string) => void) {
  app.sheet({ height: 0.36, content: () => (
    <>
      <SheetGrab /><SheetHead title={t("web-mobile.newChat.pickRuntime")} />
      <div className={sheetsCss.mSheetScroll}>{runtimes.map((rt) => <PickRow key={rt} label={RUNTIME_LABEL[rt as RuntimeKind] ?? rt} checked={rt === current} leading={<ModelMark runtime={rt as RuntimeKind} size={36} />} onClick={() => { onPick(rt); app.sheet(null); }} />)}</div>
    </>
  ) });
}

function pickEffort(app: MobileApp, efforts: string[], current: string, onPick: (e: string) => void) {
  app.sheet({ height: 0.48, content: () => (
    <>
      <SheetGrab /><SheetHead title={t("web-mobile.newChat.pickEffort")} />
      <div className={sheetsCss.mSheetScroll}>
        <PickRow label={t("web-mobile.newChat.default")} checked={current === ""} onClick={() => { onPick(""); app.sheet(null); }} />
        {efforts.map((e) => <PickRow key={e} label={e} checked={current === e} onClick={() => { onPick(e); app.sheet(null); }} />)}
      </div>
    </>
  ) });
}

/** A station with no profile: what one is, adding one, and the machine's own logins as ones to use right away. */
function NoProfile({ view }: { view: StationView }) {
  const app = useApp();
  const station: Station = { id: view.id, name: view.name, online: view.online, address: view.station, base: stationBase(view.station), settings: `/w/${app.entry.id}/settings` };
  return (
    <StationContext.Provider value={station}>
      <p className={css.mNewProblem} data-wait>{t("web-mobile.newChat.noProfile", { station: view.name })}</p>
      <Button label={t("web-mobile.newChat.addProfile")} primary onClick={() => app.push(app.at(`/s/${view.id}/profiles/new`))} />
      <div className={`${sheetsCss.mForm} ${settingsCss.mSteps}`} style={{ alignSelf: "stretch", marginTop: 12, padding: 0, textAlign: "left" }}>
        <MachineLoginOffers inForm logins={view.overview?.machineLogins}
          onSignIn={(kind) => app.push(app.at(`/s/${view.id}/profiles/new?kind=${kind}`))} />
      </div>
    </StationContext.Provider>
  );
}
