// A new chat, after Zork's: say what to do, having picked where it runs
// (station), on what (profile and model) and how hard it thinks. The first
// message (or file) makes the session and its chat on that station.
import { Check, ChevronDown, Server } from "lucide-react";
import { DropdownMenu } from "radix-ui";
import { useEffect, useMemo, useRef, useState } from "react";
import { makeApi, useOverview, type ProfileView } from "./api.ts";
import { Composer } from "./Chat.tsx";
import { EFFORTS, EFFORT_LABEL } from "./format.ts";
import { StationContext, type Station } from "./station.tsx";
import { ModelLogo, RuntimeLogo } from "./ui.tsx";

interface Choice { profile: string; model: string; effort: string }
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

/** Models a profile offers: the ones its last check listed, and its own default. */
function modelsOf(p: ProfileView): string[] {
  return [...new Set([...(p.model ? [p.model] : []), ...(p.check?.models ?? [])])];
}

export function NewChat({ stations, onCreated }: { stations: Station[]; onCreated(station: Station, key: string): void }) {
  const online = stations.filter((s) => s.online);
  const [stationId, setStationId] = useState(() => {
    const last = (JSON.parse(localStorage.getItem(LAST) ?? "{}") as { last?: string }).last;
    return online.find((s) => s.id === last)?.id ?? online[0]?.id ?? "";
  });
  const station = online.find((s) => s.id === stationId) ?? online[0];
  if (!station) {
    return <div className="new-chat"><div className="new-chat-inner"><h1>新对话</h1><p className="muted">没有在线的 station。到设置里添加一台，或者启动已添加的 station。</p></div></div>;
  }
  return (
    <StationContext.Provider value={station}>
      <NewChatOn key={station.id} station={station} stations={online} onStation={setStationId} onCreated={onCreated} />
    </StationContext.Provider>
  );
}

function NewChatOn({ station, stations, onStation, onCreated }: { station: Station; stations: Station[]; onStation(id: string): void; onCreated(station: Station, key: string): void }) {
  const overview = useOverview();
  const profiles = overview.data?.profiles ?? [];
  const [choice, setChoice] = useState<Choice>(() => ({ profile: "", model: "", effort: "", ...lastChoice(station.id) }));
  const profile = profiles.find((p) => p.id === choice.profile) ?? profiles[0];
  // A remembered profile that is gone falls back to the first; its model with it.
  useEffect(() => {
    if (profile && profile.id !== choice.profile) setChoice((c) => ({ ...c, profile: profile.id, model: "", effort: "" }));
  }, [profile?.id]);
  const made = useRef<Promise<string> | null>(null);
  const [making, setMaking] = useState(false);
  const pick = (next: Partial<Choice>) => {
    const c = { ...choice, ...next };
    setChoice(c);
    keepChoice(station.id, c);
  };
  const ensureSession = () => {
    if (!profile) return Promise.reject(new Error("这台 station 还没有 Profile"));
    made.current ??= (async () => {
      setMaking(true);
      const { key } = await makeApi(station.transport).newSession({
        runtime: profile.runtime, profile: profile.id,
        ...(choice.model ? { model: choice.model } : {}), ...(choice.effort ? { effort: choice.effort } : {}),
      });
      return key;
    })().catch((error: unknown) => { made.current = null; setMaking(false); throw error; });
    return made.current;
  };
  const efforts = profile ? EFFORTS[profile.runtime] : [];
  const modelLabel = choice.model || profile?.model || "默认模型";
  const toolbar = useMemo(() => (
    <>
      {stations.length > 1 && (
        <Chooser label={<><Server size={13} />{station.name}</>} title="在哪台 station 上运行">
          {stations.map((s) => <Item key={s.id} checked={s.id === station.id} onSelect={() => onStation(s.id)}>{s.name}</Item>)}
        </Chooser>
      )}
      <Chooser label={profile ? <><ModelLogo model={choice.model || profile.model} runtime={profile.runtime} size={13} />{modelLabel}</> : "没有 Profile"} title="用哪个 Profile 和模型">
        {profiles.map((p) => (
          <DropdownMenu.Group key={p.id}>
            <DropdownMenu.Label className="menu-label chooser-group"><RuntimeLogo runtime={p.runtime} size={12} />{p.name}</DropdownMenu.Label>
            <Item checked={p.id === profile?.id && !choice.model} onSelect={() => pick({ profile: p.id, model: "", ...(p.runtime !== profile?.runtime ? { effort: "" } : {}) })}>
              {p.model ? `${p.model}（默认）` : "运行时默认模型"}
            </Item>
            {modelsOf(p).filter((m) => m !== p.model).map((m) => (
              <Item key={m} checked={p.id === profile?.id && choice.model === m} onSelect={() => pick({ profile: p.id, model: m, ...(p.runtime !== profile?.runtime ? { effort: "" } : {}) })}>
                <ModelLogo model={m} runtime={p.runtime} size={12} />{m}
              </Item>
            ))}
          </DropdownMenu.Group>
        ))}
      </Chooser>
      {profile && (
        <Chooser label={<>思考 {choice.effort ? EFFORT_LABEL[choice.effort] ?? choice.effort : "默认"}</>} title="思考深度">
          <Item checked={!choice.effort} onSelect={() => pick({ effort: "" })}>运行时默认</Item>
          {efforts.map((e) => <Item key={e} checked={choice.effort === e} onSelect={() => pick({ effort: e })}>{EFFORT_LABEL[e] ?? e}（{e}）</Item>)}
        </Chooser>
      )}
    </>
  ), [stations, station, profiles, profile, choice, modelLabel, efforts]);

  return (
    <div className="new-chat">
      <div className="new-chat-inner">
        <h1 className="new-chat-title">新对话</h1>
        <p className="new-chat-sub">说要做什么。它会在 {station.name || "这台机器"} 上用选好的模型开一个新会话。</p>
        {overview.isPending ? <p className="muted">正在读取 {station.name} 的 Profile…</p> : profiles.length === 0 && <p className="field-error">这台 station 还没有 Profile，先到设置里加一个。</p>}
        <Composer sessionKey={null} ensureSession={ensureSession} placeholder="做任何事" toolbar={toolbar} locked={!profile} roomy
          onSent={(key) => onCreated(station, key)} />
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
