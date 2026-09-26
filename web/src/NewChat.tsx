// A new chat, after Zork's: say what to do, having picked where it runs
// (station), on what (runtime and model) and how hard it thinks. The first
// message (or file) makes the session and its chat on that station.
import { Check, ChevronDown, Server } from "lucide-react";
import { DropdownMenu } from "radix-ui";
import { Link } from "react-router";
import { useEffect, useMemo, useRef, useState } from "react";
import { useApi, useStations, type RuntimeKind, type StationView } from "./api.ts";
import { Composer } from "./Chat.tsx";
import { EFFORTS, EFFORT_LABEL, RUNTIME_LABEL } from "./format.ts";
import { StationContext, stationBase, type Station } from "./station.tsx";
import { ModelLogo, RuntimeLogo } from "./ui.tsx";
import { Illustration } from "./brand.tsx";

interface Choice { runtime: RuntimeKind | ""; model: string; effort: string }
const LAST = "ember.newChat";

function lastChoice(station: string): Partial<Choice> {
  try {
    return (JSON.parse(localStorage.getItem(LAST) ?? "{}") as Record<string, Partial<Choice>>)[station] ?? {};
  } catch {
    return {};
  }
}
function keepChoice(station: string, choice: Choice): void {
  try {
    const all = JSON.parse(localStorage.getItem(LAST) ?? "{}") as Record<string, Choice>;
    localStorage.setItem(LAST, JSON.stringify({ ...all, [station]: choice, last: station }));
  } catch {
    // storage full or blocked: choices are just not remembered
  }
}

/** A new chat in a scope (a workspace, or "local"); `onCreated` gets the station's address and the new session. */
export function NewChat({ scope, onCreated }: { scope: string; onCreated(station: string, key: string): void }) {
  const stations = useStations(scope);
  const online = (stations.value ?? []).filter((s) => s.online);
  const [stationId, setStationId] = useState(() => {
    try {
      return (JSON.parse(localStorage.getItem(LAST) ?? "{}") as { last?: string }).last ?? "";
    } catch {
      return "";
    }
  });
  const view = online.find((s) => s.id === stationId) ?? online[0];
  if (!stations.value) {
    return <div className="new-chat"><div className="new-chat-inner"><Illustration name="new-chat" /><h1 className="new-chat-title">新对话</h1><p className={stations.error ? "field-error" : "muted"}>{stations.error?.message ?? "正在读取 station…"}</p></div></div>;
  }
  if (!view) {
    return <div className="new-chat"><div className="new-chat-inner"><Illustration name="station-offline" /><h1 className="new-chat-title">新对话</h1><p className="muted">没有在线的 station。到设置里添加一台，或者启动已添加的 station。</p></div></div>;
  }
  // The composer's files and links belong to the station the chat goes to.
  const station: Station = { id: view.id, name: scope === "local" ? "" : view.name, base: stationBase(view.station), address: view.station, online: true, settings: scope === "local" ? "/settings" : `/w/${scope}/settings` };
  return (
    <StationContext.Provider value={station}>
      <NewChatOn key={view.station} view={view} station={station} stations={online} onStation={setStationId} onCreated={onCreated} />
    </StationContext.Provider>
  );
}

function NewChatOn({ view, station, stations, onStation, onCreated }: { view: StationView; station: Station; stations: StationView[]; onStation(id: string): void; onCreated(station: string, key: string): void }) {
  const api = useApi();
  const profiles = view.overview?.profiles ?? [];
  const [choice, setChoice] = useState<Choice>(() => ({ runtime: "", model: "", effort: "", ...lastChoice(station.id) }));
  // Runtimes this station has models for; which profile runs the chat is the station's account pool's choice.
  const runtimes = view.runtimes.map((r) => r.runtime);
  const runtime: RuntimeKind | undefined = runtimes.includes(choice.runtime as RuntimeKind) ? (choice.runtime as RuntimeKind) : runtimes[0];
  const enabled = view.runtimes.find((r) => r.runtime === runtime)?.models ?? [];
  // Only enabled models can be used: a remembered one that is no longer enabled gives way to the first that is.
  const model = enabled.includes(choice.model) ? choice.model : enabled[0] ?? "";
  useEffect(() => {
    if (runtime && runtime !== choice.runtime) setChoice((c) => ({ ...c, runtime, effort: "" }));
  }, [runtime]);
  // The model menu lists what a profile's check found; profiles not checked since the station started are checked now, once.
  const checked = useRef(new Set<string>());
  useEffect(() => {
    for (const p of profiles) {
      if (p.check || checked.current.has(p.id)) continue;
      checked.current.add(p.id);
      void api.checkProfile(p.id).catch(() => {});
    }
  }, [profiles, api]);
  const made = useRef<Promise<string> | null>(null);
  const [making, setMaking] = useState(false);
  const pick = (next: Partial<Choice>) => {
    const c = { ...choice, ...next };
    setChoice(c);
    keepChoice(station.id, c);
  };
  const ensureSession = () => {
    if (!runtime || !model) return Promise.reject(new Error("先在 Profile 里启用模型"));
    made.current ??= (async () => {
      setMaking(true);
      const { key } = await api.newSession({
        runtime, model,
        ...(choice.effort ? { effort: choice.effort } : {}),
      });
      return key;
    })().catch((error: unknown) => { made.current = null; setMaking(false); throw error; });
    return made.current;
  };
  const efforts = runtime ? EFFORTS[runtime] : [];
  const modelLabel = model || "没有可用模型";
  const toolbar = useMemo(() => (
    <>
      {station.name && (
        <Chooser label={<><Server size={13} />{station.name}</>} title="在哪台 station 上运行">
          {stations.map((s) => <Item key={s.station} checked={s.station === station.address} onSelect={() => onStation(s.id)}>{s.name}</Item>)}
        </Chooser>
      )}
      {!runtime || !model ? (
        // Nothing to choose from: the chooser leads to where models are enabled.
        <Link className="chooser" to={`${station.base}/settings/accounts`} title="到 Profile 里勾选可以用的模型">没有可用模型 · 去勾选</Link>
      ) : (
      <Chooser label={<><ModelLogo model={model} runtime={runtime} size={13} />{modelLabel}</>} title="用哪个运行时和模型">
        {runtimes.map((rt) => (
          <DropdownMenu.Group key={rt}>
            <DropdownMenu.Label className="menu-label chooser-group"><RuntimeLogo runtime={rt} size={12} />{RUNTIME_LABEL[rt]}</DropdownMenu.Label>
            {(view.runtimes.find((r) => r.runtime === rt)?.models ?? []).map((m) => (
              <Item key={m} checked={rt === runtime && model === m} onSelect={() => pick({ runtime: rt, model: m, ...(rt !== runtime ? { effort: "" } : {}) })}>
                <ModelLogo model={m} runtime={rt} size={12} />{m}
              </Item>
            ))}
          </DropdownMenu.Group>
        ))}
      </Chooser>
      )}
      {runtime && (
        <Chooser label={<>思考 {choice.effort ? EFFORT_LABEL[choice.effort] ?? choice.effort : "默认"}</>} title="思考深度">
          <Item checked={!choice.effort} onSelect={() => pick({ effort: "" })}>运行时默认</Item>
          {efforts.map((e) => <Item key={e} checked={choice.effort === e} onSelect={() => pick({ effort: e })}>{EFFORT_LABEL[e] ?? e}（{e}）</Item>)}
        </Chooser>
      )}
    </>
  ), [stations, station, view, runtime, runtimes, choice, model, modelLabel, efforts]);

  return (
    <div className="new-chat">
      <div className="new-chat-inner">
        <Illustration name="new-chat" />
        <h1 className="new-chat-title">新对话</h1>
        <p className="new-chat-sub">说要做什么。它会在 {station.name || "这台机器"} 上用选好的模型开一个新会话。</p>
        {!view.overview ? <p className="muted">正在读取 {station.name} 的 Profile…</p>
          : profiles.length === 0 ? <p className="field-error">这台 station 还没有 Profile，先到 <Link className="inline-link" to={`${station.base}/settings/accounts`}>设置 → Profile</Link> 里加一个。</p>
          : !runtimes.length && <p className="field-error">这台 station 的 Profile 都还没有启用模型。到 <Link className="inline-link" to={`${station.base}/settings/accounts`}>设置 → Profile</Link> 里勾选可以用的模型。</p>}
        <Composer sessionKey={null} ensureSession={ensureSession} placeholder="做任何事" toolbar={toolbar} locked={!runtime || !model} roomy
          onSent={(key) => onCreated(station.address, key)} />
        {making && <p className="muted new-chat-making">正在 {station.name} 上创建会话…</p>}
      </div>
    </div>
  );
}

function Chooser({ label, title, children }: { label: React.ReactNode; title: string; children: React.ReactNode }) {
  return (
    <DropdownMenu.Root modal={false}>
      <DropdownMenu.Trigger className="chooser" title={title}>{label}<ChevronDown size={12} /></DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content className="popover menu-list chooser-menu" side="top" align="start" sideOffset={6}>{children}</DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}

function Item({ checked, onSelect, children }: { checked: boolean; onSelect(): void; children: React.ReactNode }) {
  return (
    <DropdownMenu.Item className="menu-item chooser-item" onSelect={onSelect}>
      <span className="chooser-check">{checked && <Check size={13} />}</span>{children}
    </DropdownMenu.Item>
  );
}
