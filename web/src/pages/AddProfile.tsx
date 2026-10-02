// A new profile, on a page of its own (desktop): the providers in Cue's groups, then how to connect the one picked (a
// plan or a key) and the form. What is picked and typed, and what each step says, is the core's (profileFlow.ts); this
// draws it. Routes: settings/profiles/add (the picker) and settings/profiles/add/<provider> (connecting it);
// `?station=` says where it is added.
import { useEffect, useRef, useState } from "react";
import { Navigate, useNavigate, useParams, useSearchParams } from "react-router";
import { useAction, useApi, useOverview, useStations } from "../api.ts";
import { Plus } from "../icons.tsx";
import { StationContext, stationBase } from "../station.tsx";
import { useProfileFlow } from "../profileFlow.ts";
import { useToast } from "../toast.tsx";
import { BackLink, Button, Field, Loading, ProviderLogo, Segmented, Select } from "../ui.tsx";
import type { ApiProvider, ProfileFlowView } from "../core/shapes.ts";
import { MachineLoginOffers, LoginSteps } from "./Accounts.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as controlsCss from "../styles/controls.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as css from "./AddProfile.css.ts";
import { t } from "../i18n.ts";

/** Where the add page of a workspace is (the station it adds on, and a vendor to go straight to). */
export function addProfilePath(workspace: string, station: string, provider?: string, method?: "plan"): string {
  const query = new URLSearchParams({ station, ...(method ? { method } : {}) });
  return `/w/${workspace}/settings/profiles/add${provider ? `/${provider}` : ""}?${query}`;
}

export function AddProfile({ workspace }: { workspace: string }) {
  const stations = useStations(workspace).value;
  const [params, setParams] = useSearchParams();
  const online = (stations ?? []).filter((s) => s.online);
  if (!stations) return <div className={pagesCss.page}><Loading label={t("web-pages.settings.reading")} /></div>;
  const chosen = online.find((s) => s.station === params.get("station")) ?? online[0];
  if (!chosen) return <Navigate to={`/w/${workspace}/settings/profiles`} replace />;
  const station = { id: chosen.id, name: chosen.name, online: chosen.online, address: chosen.station, base: stationBase(chosen.station), settings: `/w/${workspace}/settings` };
  return (
    <StationContext.Provider value={station}>
      {/* Another station is another draft. */}
      <Flow key={chosen.station} workspace={workspace} address={chosen.station}
        stations={online.length > 1 ? online.map((s) => ({ value: s.station, label: s.name })) : null}
        onStation={(value) => setParams((p) => { p.set("station", value); return p; }, { replace: true })} />
    </StationContext.Provider>
  );
}

function Flow({ workspace, address, stations, onStation }: { workspace: string; address: string; stations: { value: string; label: string }[] | null; onStation(address: string): void }) {
  const { provider } = useParams();
  const [params, setParams] = useSearchParams();
  const navigate = useNavigate();
  const toast = useToast();
  const api = useApi();
  const { d, edit, submit, submitting } = useProfileFlow(address);
  const list = `/w/${workspace}/settings/profiles`;
  const here = (id?: string) => addProfilePath(workspace, address, id);

  // The address says which provider the core is on: a link lands on its page, back lands on the picker.
  const tile = d?.tile?.id ?? "";
  useEffect(() => {
    if (!d) return;
    if ((provider ?? "") !== tile) edit({ provider: provider ?? "" });
  }, [d === null || d === undefined, provider, tile]); // eslint-disable-line react-hooks/exhaustive-deps
  // `?method=plan`: a machine's login signed in again as the vendor's plan.
  useEffect(() => {
    if (d?.step === "method" && params.get("method") === "plan") {
      edit({ method: "plan" });
      setParams((p) => { p.delete("method"); return p; }, { replace: true });
    }
  }, [d?.step, params.get("method")]); // eslint-disable-line react-hooks/exhaustive-deps

  // A plan's sign-in (the existing login steps): started when the plan is chosen, dropped when left unfinished.
  const overview = useOverview(address);
  const [login, setLogin] = useState<string | null>(null);
  const [code, setCode] = useState("");
  const runtime = d?.tile?.runtime === "codex" ? "codex" : "claude";
  const pending = login ? overview.value?.logins.find((l) => l.id === login) : undefined;
  const start = useAction(() => api.newLogin(runtime), ({ id }) => setLogin(id));
  const send = useAction(() => api.newLoginCode(login!, code), () => setCode(""));
  const started = useRef(false);
  const planning = d?.step === "connect" && d.method === "plan";
  useEffect(() => {
    if (planning && !started.current) { started.current = true; void start.run(); }
    if (!planning && started.current) { started.current = false; if (login && !pending?.created) void api.dropLogin(login).catch(() => undefined); setLogin(null); setCode(""); }
  }, [planning]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => { if (pending?.created) { toast(t("web-pages.profiles.signedInAdded")); navigate(list); } }, [pending?.created]); // eslint-disable-line react-hooks/exhaustive-deps

  const added = () => { toast(t("web-pages.profiles.verifiedAdded")); navigate(list); };

  if (!d) return <div className={pagesCss.page}><Loading label={t("web-pages.settings.reading")} /></div>;
  const picking = d.step === "pick";
  return (
    <div className={pagesCss.page}>
      {picking ? <BackLink to={list} label="Profile" /> : <BackLink to={here()} label={t("web-pages.addProfile.pick")} />}
      <header className={pagesCss.pageHead}>
        <div>
          <h1>{d.title}</h1>
          {d.hint && <p className={shellCss.muted}>{d.hint}</p>}
        </div>
      </header>
      {picking ? (
        <>
          {stations && (
            <div className={css.stations}>
              <Field label={t("web-pages.addProfile.station")}>
                <Segmented label={t("web-pages.addProfile.station")} value={address} options={stations} onChange={onStation} />
              </Field>
            </div>
          )}
          <MachineLoginOffers logins={overview.value?.machineLogins} onAdd={(c) => navigate(addProfilePath(workspace, address, c === "claude-sub" ? "anthropic" : "openai", "plan"))} />
          {d.groups.map((g) => (
            <section key={g.id} className={css.group} aria-label={g.title}>
              <h3 className={css.groupHead}>{g.title}</h3>
              <div className={css.tiles}>
                {g.providers.map((p) => (
                  <button key={p.id} type="button" className={css.tile} onClick={() => navigate(here(p.id))}>
                    <span className={pagesCss.mark} style={{ width: 28, height: 28 }}><Mark p={p} /></span>
                    <span className={css.tileName}>{p.name}</span>
                  </button>
                ))}
              </div>
            </section>
          ))}
        </>
      ) : d.step === "method" ? (
        <div className={css.methods}>
          {d.choices.map((c) => (
            <button key={c.id} type="button" className={css.method} onClick={() => edit({ method: c.id })}>
              <strong>{c.title}</strong>
              <span className={css.methodHint}>{c.hint}</span>
            </button>
          ))}
        </div>
      ) : d.method === "plan" ? (
        pending?.error || pending?.job?.state === "failed" || pending?.job?.state === "cancelled"
          ? <div className={css.form}><p className={controlsCss.fieldError}>{pending?.error ?? pending?.job?.error ?? t("web-pages.profiles.signInUnfinished")}</p><Button onClick={() => { if (login) void api.dropLogin(login).catch(() => undefined); setLogin(null); void start.run(); }}>{t("web-pages.profiles.restart")}</Button></div>
          : <div className={css.form}><LoginSteps job={pending?.job ?? null} provider={runtime === "claude" ? "Claude" : "ChatGPT"} code={code} setCode={setCode} send={() => void send.run()} sending={send.busy} sendError={send.error?.message ?? null} /></div>
      ) : (
        <ConnectForm key={d.tile?.id} d={d} edit={edit} submitting={submitting} onSubmit={() => void submit().then(added, () => undefined)} />
      )}
      {d.method === "plan" && d.usesLine && <p className={css.uses}>{d.usesLine}</p>}
    </div>
  );
}

/** A provider's mark: its maker's, or the generic plug (the variables by hand have their own). */
function Mark({ p }: { p: ApiProvider }) {
  return <ProviderLogo runtime={p.runtime === "codex" ? "codex" : "claude"} kind={p.kind === "env" ? "env" : p.kind || "api-provider"} mark={p.mark} size={16} />;
}

/** The form of a key: what is typed is kept here as it is typed (the core has it as it is named, and judges it). */
function ConnectForm({ d, edit, submitting, onSubmit }: { d: ProfileFlowView; edit(input: Record<string, unknown>): void; submitting: boolean; onSubmit(): void }) {
  const [endpoint, setEndpoint] = useState(d.endpoint);
  const [key, setKey] = useState(d.key);
  return (
    <form className={css.form} onSubmit={(e) => { e.preventDefault(); if (d.canSubmit) onSubmit(); }}>
      {d.showEndpoint && (
        <Field label={t("common.provider.endpoint")} htmlFor="add-endpoint" hint={d.endpointHint}>
          <input id="add-endpoint" className={`${controlsCss.input} ${shellCss.mono}`} spellCheck={false} autoComplete="off" disabled={d.pending} value={endpoint}
            onChange={(e) => { setEndpoint(e.target.value); edit({ endpoint: e.target.value }); }} placeholder={d.tile?.endpointExample ?? "https://"} />
        </Field>
      )}
      {d.protocols.length > 1 && (
        <Field label={t("web-pages.addProfile.protocol")} htmlFor="add-protocol">
          <Select id="add-protocol" value={d.protocol ?? ""} onChange={(protocol) => edit({ protocol })} disabled={d.pending} options={d.protocols.map((p) => ({ value: p.id, label: p.label }))} />
        </Field>
      )}
      {d.showKey && (
        <Field label={d.keyLabel} htmlFor="add-key" hint={d.keyHint} error={d.error}>
          <input id="add-key" className={`${controlsCss.input} ${shellCss.mono}`} spellCheck={false} type="password" autoComplete="off" disabled={d.pending} value={key}
            onChange={(e) => { setKey(e.target.value); edit({ key: e.target.value }); }} />
        </Field>
      )}
      <div>
        <Button variant="primary" type="submit" {...(d.showKey ? {} : { icon: Plus })} disabled={!d.canSubmit} busy={submitting || d.pending}>{d.submitLabel}</Button>
      </div>
      {d.usesLine && <p className={css.uses}>{d.usesLine}</p>}
    </form>
  );
}
