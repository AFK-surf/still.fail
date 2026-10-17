// 设置 › 密钥 on the wide screen (and the desktop app): the workspace's vault as this device sees it (docs/vault.md).
// What it is waiting for first (security mode on, this device confirmed in it, the vault turned on here: the recovery
// words shown that once), then the requests waiting on the viewer, each vault's items, and the devices holding its key.
// An item opens in a dialog (its fields masked, shown or copied), and is edited in another. A web page only lists the
// names it is told. All of it is the core's (`vaults`, `vaultItems`, `vault.*`; ../vault.ts): this only draws.
import { useState, type ReactNode } from "react";
import { Link, useNavigate } from "react-router";
import { Copy, Devices, Eye, Key, Plus, Server, ShieldCheck, User } from "@stillfail/ui/icons.tsx";
import { useToast } from "@stillfail/ui/toast.tsx";
import { useDoing } from "../doing.ts";
import { Button, Confirm, Dialog, Field, IconButton, Loading, MobileBack, ProviderLogo, Section, Segmented, SwitchRow } from "../ui.tsx";
import { useProfiles, useStations } from "../api.ts";
import { profilePath } from "../ProfilesNav.tsx";
import { profileGroups } from "./settings.tsx";
import { addProfilePath } from "../pages/AddProfile.tsx";
import { AddKinds } from "../VaultAdd.tsx";
import { stationBase } from "../station.tsx";
import { VaultChoices } from "../VaultApproval.tsx";
import {
  ITEM_SECTIONS, KINDS, blankForm, copySecret, itemPath, listLine, fieldsOf, formOf, formProblem, howLine, itemLine, kindName, masked, modeName, modesOf, putOf, useForm,
  useVaultCall, useVaultItems, useVaults, type Form, type Kind, type Mode, type Opened, type VaultItemRow, type VaultRequest, type VaultRow, type VaultsView,
} from "../vault.ts";
import { t } from "../i18n.ts";
import type { WorkspaceEntry } from "./workspace.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import * as spinnerCss from "@stillfail/ui/styles/spinner.css.ts";
import * as css from "./Vault.css.ts";

const KIND_ICON = { token: Key, ssh_key: Server, login: User } as const;

export function KindIcon({ kind, size = 16 }: { kind: string | undefined; size?: number }) {
  const Icon = KIND_ICON[kind as Kind] ?? Key;
  return <Icon size={size} strokeWidth={1.6} />;
}

/** In the settings' sidebar, after 密钥: how many requests wait on the viewer (nothing when none). */
export function VaultWaiting({ workspace }: { workspace: string }) {
  const n = useVaults(workspace)?.requests.length ?? 0;
  return n > 0 ? <span className={css.navCount} aria-label={t("web-pages.vault.waitingCount", { n })}>{n}</span> : null;
}

/** 设置 › 密钥. */
export function VaultSettings({ entry }: { entry: WorkspaceEntry }) {
  const view = useVaults(entry.id);
  // The recovery words, the once the core gives them (`vault.setup`): shown until they are written down.
  const [words, setWords] = useState<string[] | null>(null);
  const [adding, setAdding] = useState(false);
  // The library as it is used (not locked, or locked and set up here): what it holds, and adding to it.
  const library = !!view && !words && (view.plain === true || (view.available && view.locked && view.canSign && view.setUp));
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={`/w/${entry.id}/settings`} label={t("web-pages.settings.title")} />
      <header className={pagesCss.pageHead}>
        <div><h1>{t("web-pages.vault.title")}</h1><p className={css.sub}>{t("web-pages.vault.lead")}</p></div>
        {library && <Button variant="ghost" icon={Plus} onClick={() => setAdding(true)}>{t("web-pages.vault.add")}</Button>}
      </header>
      {!view ? <Loading label={t("web-pages.settings.reading")} />
        : words ? <Words entry={entry} view={view} words={words} onDone={() => setWords(null)} />
        : view.plain === true ? <Library entry={entry} view={view} adding={adding} onAdded={() => setAdding(false)} />
        : !view.available ? <ReadOnly entry={entry} view={view} />
        : !view.locked ? <Gate entry={entry} title={t("web-pages.vault.needsLock")} why={t("web-pages.vault.needsLockWhy")} />
        : !view.canSign ? <Gate entry={entry} title={t("web-pages.vault.notSigner")} why={t("web-pages.vault.notSignerWhy")} />
        : !view.setUp ? <SetUp entry={entry} onWords={setWords} />
        : <Library entry={entry} view={view} adding={adding} onAdded={() => setAdding(false)} />}
    </div>
  );
}

/** What the vault waits for before anything else (security mode; this device in it): said, with the way there. */
function Gate({ entry, title, why }: { entry: WorkspaceEntry; title: string; why: string }) {
  return (
    <div className={pagesCss.card}>
      <div className={css.state}>{title}</div>
      <p className={css.sub}>{why}</p>
      <div className={css.actions}><Link to={`/w/${entry.id}/settings/security`}><Button variant="primary">{t("web-pages.vault.toSecurity")}</Button></Link></div>
    </div>
  );
}

/** Not turned on here yet: what it does, and the button. */
function SetUp({ entry, onWords }: { entry: WorkspaceEntry; onWords(words: string[]): void }) {
  const run = useVaultCall();
  const settingUp = useDoing("vault.setup", { workspace: entry.id });
  const creating = useDoing("vault.create", { workspace: entry.id });
  const setUp = () => void run<{ words: string | null }>("vault.setup", { workspace: entry.id }, t("web-pages.vault.setUpWhat")).then((r) => {
    if (!r) return;
    // The first device sets the words; one set up after takes the person's (none shown): straight on.
    if (r.words) onWords(r.words.trim().split(/\s+/));
    else void run("vault.create", { workspace: entry.id, name: t("web-pages.vault.personal") }, t("web-pages.vault.createWhat"));
  });
  return (
    <div className={pagesCss.card}>
      <div className={css.state}>{t("web-pages.vault.setUpTitle")}</div>
      <div className={css.points}>
        <Point icon={Devices} title={t("web-pages.vault.point.ask")} how={t("web-pages.vault.point.askHow")} />
        <Point icon={ShieldCheck} title={t("web-pages.vault.point.proxy")} how={t("web-pages.vault.point.proxyHow")} />
        <Point icon={Server} title={t("web-pages.vault.point.zero")} how={t("web-pages.vault.point.zeroHow")} />
      </div>
      <div className={css.actions}><Button variant="primary" busy={settingUp || creating} onClick={setUp}>{t("web-pages.vault.setUp")}</Button></div>
    </div>
  );
}

function Point({ icon: Icon, title, how }: { icon: typeof Key; title: string; how: string }) {
  return <div className={css.point}><Icon size={18} strokeWidth={1.6} className={css.pointIcon} /><span>{title}<span className={css.sub}>{how}</span></span></div>;
}

/** The 24 words, numbered in three columns, the once they are shown; written down, the person's vault is made (if
 * they have none). */
function Words({ entry, view, words, onDone }: { entry: WorkspaceEntry; view: VaultsView; words: string[]; onDone(): void }) {
  const run = useVaultCall();
  const creating = useDoing("vault.create", { workspace: entry.id });
  const done = () => {
    if (view.vaults.some((v) => v.mine)) return onDone();
    void run("vault.create", { workspace: entry.id, name: t("web-pages.vault.personal") }, t("web-pages.vault.createWhat")).then(() => onDone());
  };
  return (
    <div className={pagesCss.card}>
      <div className={css.state}>{t("web-pages.vault.words.title")}</div>
      <p className={css.sub}>{t("web-pages.vault.words.lead")}</p>
      <ol className={css.words}>{words.map((w, i) => <li key={i} className={css.word}><span className={css.wordN}>{i + 1}</span>{w}</li>)}</ol>
      <div className={css.actions}>
        <span className={css.note}>{t("web-pages.vault.words.once")}</span>
        <span className={css.grow} />
        <Button variant="primary" busy={creating} onClick={done}>{t("web-pages.vault.words.done")}</Button>
      </div>
    </div>
  );
}

/** A web page: the vaults' names and the items' it is told (their listings), and that the app opens them. */
function ReadOnly({ entry, view }: { entry: WorkspaceEntry; view: VaultsView }) {
  return (
    <>
      <div className={`${pagesCss.card} ${css.lead}`}>
        <div className={css.state}>{t("web-pages.vault.appOnly")}</div>
        <p className={css.sub}>{t("web-pages.vault.appOnlyWhy")}</p>
      </div>
      {view.vaults.length === 0 ? <p className={css.note}>{t("web-pages.vault.none")}</p>
        : view.vaults.map((v) => <VaultSection key={v.id} entry={entry} v={v} readOnly />)}
    </>
  );
}

/** The library (docs/vault.md 一个库): what waits on the viewer, whether it is locked, the profiles' accounts kept in it
 * (each leading to its profile), each vault's secrets a section a kind (each leading to its page), the devices. */
function Library({ entry, view, adding, onAdded }: { entry: WorkspaceEntry; view: VaultsView; adding: boolean; onAdded(): void }) {
  const run = useVaultCall();
  const navigate = useNavigate();
  const creating = useDoing("vault.create", { workspace: entry.id });
  const plain = view.plain === true;
  const mine = view.vaults.find((v) => v.mine);
  const [editing, setEditing] = useState<Kind | null>(null);
  const stations = useStations(entry.id).value ?? [];
  const online = stations.filter((s) => s.online);
  return (
    <>
      {view.requests.length > 0 && (
        <Section title={<>{t("web-pages.vault.requests")} <span className={css.count}>{view.requests.length}</span></>}>
          <div className={css.requests}>{view.requests.map((r) => <Request key={r.id} entry={entry} r={r} />)}</div>
        </Section>
      )}
      <div className={`${pagesCss.card} ${css.lead}`}>
        <div className={css.state}><ShieldCheck size={16} strokeWidth={1.6} /><span className={plain ? css.riskTitle : undefined}>{plain ? t("web-pages.vault.lib.plain") : t("web-pages.vault.lib.sealed")}</span></div>
        <p className={css.sub}>{plain ? t("web-pages.vault.lib.plainLong") : t("web-pages.vault.lib.sealedWhy")}</p>
        {plain && <div className={css.actions}><Link to={`/w/${entry.id}/settings/security`}><Button variant="primary">{t("web-pages.vault.lib.turnOn")}</Button></Link></div>}
      </div>
      {!plain && (view.plainLeft ?? 0) > 0 && <Migrate entry={entry} n={view.plainLeft!} />}
      <ProfileAccounts entry={entry} />
      {view.vaults.length === 0 && !plain && (
        <div className={pagesCss.card}>
          <p className={css.sub}>{t("web-pages.vault.none")}</p>
          <div className={css.actions}><Button variant="primary" busy={creating}
            onClick={() => void run("vault.create", { workspace: entry.id, name: t("web-pages.vault.personal") }, t("web-pages.vault.createWhat"))}>{t("web-pages.vault.setUp")}</Button></div>
        </div>
      )}
      {view.vaults.map((v) => <LibraryVault key={v.id} entry={entry} v={v} plain={plain} many={view.vaults.length > 1} />)}
      {!plain && view.vaults.length > 0 && (
        <Section title={t("web-pages.vault.devices")}>
          <div className={pagesCss.card}><div className={css.rows}>{view.vaults.map((v) => <DevicesRow key={v.id} entry={entry} v={v} many={view.vaults.length > 1} />)}</div></div>
        </Section>
      )}
      <Dialog open={adding} onClose={onAdded} title={t("web-pages.vault.addKind.title")}>
        <AddKinds secrets={mine !== undefined} plain={plain} onPick={(k) => {
          onAdded();
          if (k !== "profile") return setEditing(k);
          // A profile is made on a station: the one up, or the profiles' page to choose there.
          navigate(online.length === 1 ? addProfilePath(entry.id, online[0]!.station) : `/w/${entry.id}/settings/profiles`);
        }} />
      </Dialog>
      {editing && mine && <Editor workspace={entry.id} vault={mine.id} first={{ ...blankForm(), kind: editing }} id={null} plain={plain} kinds={false} onClose={() => setEditing(null)} />}
    </>
  );
}

/** Security mode on, what the plain library still holds from before: moved into the person's vault, encrypted. */
function Migrate({ entry, n }: { entry: WorkspaceEntry; n: number }) {
  const run = useVaultCall();
  const toast = useToast();
  const moving = useDoing("vault.migrate", { workspace: entry.id });
  const go = () => void run<{ moved: number; left: number }>("vault.migrate", { workspace: entry.id }, t("web-pages.vault.migrate.what")).then((r) => {
    if (r) toast(r.left > 0 ? t("web-pages.vault.migrate.partly", { n: r.moved, left: r.left }) : t("web-pages.vault.migrate.done", { n: r.moved }));
  });
  return (
    <div className={`${pagesCss.card} ${css.lead}`}>
      <div className={css.state}><span className={css.riskTitle}>{t("web-pages.vault.migrate.title", { n })}</span></div>
      <p className={css.sub}>{t("web-pages.vault.migrate.body")}</p>
      <div className={css.actions}><Button variant="primary" busy={moving} onClick={go}>{t("web-pages.vault.migrate.go")}</Button></div>
    </div>
  );
}

/** The profiles' accounts the library keeps (a subscription's sign-in, a model's key), a section a kind as the profiles
 * list them: each one's name, and where it is; it leads to its profile, whose page is where it is set. */
function ProfileAccounts({ entry }: { entry: WorkspaceEntry }) {
  const profiles = useProfiles(entry.id).value;
  if (!profiles) return null;
  return (
    <>
      {profileGroups(profiles.items).map((g) => (
        <Section key={g[0]!.group} title={g[0]!.groupTitle}>
          <ul className={pagesCss.list}>
            {g.map((e) => (
              <li key={e.key}>
                <Link className={`${pagesCss.listRow} ${css.rowButton}`} to={profilePath(e)}>
                  <span className={css.rowIcon}><ProviderLogo runtime={e.profile.runtime} kind={e.profile.access.kind} mark={e.profile.providerMark} size={16} /></span>
                  <span className={pagesCss.listRowText}>
                    <span className={pagesCss.listRowTitle}>{e.profile.name}</span>
                    <span className={css.rowMeta}>{["Profile", e.where].filter(Boolean).join(" · ")}</span>
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        </Section>
      ))}
    </>
  );
}

/** A vault's secrets, a section a kind: each one's name and when an agent last used it (in a library not locked, that
 * it is not encrypted, first); locked, those it does not name, and unlocking. */
function LibraryVault({ entry, v, plain, many }: { entry: WorkspaceEntry; v: VaultRow; plain: boolean; many: boolean }) {
  const items = useVaultItems(entry.id, v.id);
  const run = useVaultCall();
  const [recovering, setRecovering] = useState(false);
  if (!plain && !v.keyed) {
    return (
      <Section title={v.name}>
        <div className={pagesCss.card}>
          <div className={css.state}>{t("web-pages.vault.notKeyed")}</div>
          <p className={css.sub}>{t("web-pages.vault.notKeyedWhy")}</p>
          {v.recoverable && v.mine && <div className={css.actions}><Button variant="primary" onClick={() => setRecovering(true)}>{t("web-pages.vault.recover")}</Button></div>}
        </div>
        {recovering && <Recover entry={entry} onClose={() => setRecovering(false)} />}
      </Section>
    );
  }
  if (!items) return <Loading label={t("web-pages.settings.reading")} fill={false} />;
  const hidden = items.items.filter((i) => !i.name);
  const unlock = () => { if (hidden[0]) void run("vault.open", { workspace: entry.id, item: hidden[0].id }, t("web-pages.vault.unlockWhat")); };
  return (
    <>
      {ITEM_SECTIONS.map((kind) => {
        const rows = items.items.filter((i) => i.name && i.kind === kind);
        if (rows.length === 0) return null;
        return (
          <Section key={kind} title={many ? `${kindName(kind)} · ${v.name}` : kindName(kind)}>
            <ul className={pagesCss.list}>
              {rows.map((row) => (
                <li key={row.id}>
                  <Link className={`${pagesCss.listRow} ${css.rowButton}`} to={itemPath(entry.id, v.id, row.id)}>
                    <span className={css.rowIcon}><KindIcon kind={row.kind} /></span>
                    <span className={pagesCss.listRowText}>
                      <span className={pagesCss.listRowTitle}>{row.name}</span>
                      <span className={css.rowMeta}>{plain && <><span className={css.riskTitle}>{t("web-pages.vault.risk.row")}</span> · </>}{listLine(row)}</span>
                    </span>
                  </Link>
                </li>
              ))}
            </ul>
          </Section>
        );
      })}
      {hidden.length > 0 && (
        <button type="button" className={`${pagesCss.listRow} ${css.rowButton}`} onClick={unlock}>
          <span className={css.rowIcon} /><span className={`${pagesCss.listRowText} ${css.rowMeta}`}>{t("web-pages.vault.hidden", { n: hidden.length })}</span>
          <span className={css.link}>{t("web-pages.vault.unlock")}</span>
        </button>
      )}
      {!plain && v.open && (
        <button type="button" className={`${pagesCss.listRow} ${css.rowButton}`} onClick={() => void run("vault.lock", { workspace: entry.id }, t("web-pages.vault.lockNow"))}>
          <span className={css.rowIcon} /><span className={`${pagesCss.listRowText} ${css.rowMeta}`}>{t("web-pages.vault.opened")}</span>
          <span className={css.link}>{t("web-pages.vault.lockNow")}</span>
        </button>
      )}
      {items.items.length === 0 && <p className={css.note}>{t("web-pages.vault.empty")}</p>}
    </>
  );
}

/** A request waiting on the viewer: which item, why, the command, how; its chat; the approval's rows. */
function Request({ entry, r }: { entry: WorkspaceEntry; r: VaultRequest }) {
  return (
    <div className={css.request}>
      <div className={css.requestHead}>
        <span className={css.rowName}>{t("web-pages.vault.approve.wants", { name: r.itemName ?? r.item })}</span>
        {r.station && <Link className={css.link} to={`${stationBase(`${entry.id}/${r.station}`)}/chats/${encodeURIComponent(r.session)}`}>{t("web-pages.vault.openChat")}</Link>}
      </div>
      <dl className={css.facts}>
        <dt>{t("web-pages.vault.reason")}</dt><dd>{r.reason}</dd>
        {r.command && <><dt>{t("web-pages.vault.command")}</dt><dd><code className={css.mono}>{r.command}</code></dd></>}
        <dt>{t("web-pages.vault.how")}</dt><dd>{howLine(r.mode, r.hosts)}</dd>
      </dl>
      <VaultChoices workspace={entry.id} id={r.id} />
    </div>
  );
}

/** A vault and its items: the names once it is unlocked here (the listed ones' always), a tap opening one. */
function VaultSection({ entry, v, readOnly = false }: { entry: WorkspaceEntry; v: VaultRow; readOnly?: boolean }) {
  const items = useVaultItems(entry.id, v.id);
  const run = useVaultCall();
  const [opened, setOpened] = useState<{ opened: Opened; row: VaultItemRow | undefined } | null>(null);
  const [editing, setEditing] = useState<{ form: Form; id: string | null; version?: number } | null>(null);
  const [recovering, setRecovering] = useState(false);
  const locking = useDoing("vault.lock", { workspace: entry.id });
  const named = items?.items.filter((i) => i.name) ?? [];
  const hidden = (items?.items.length ?? 0) - named.length;
  const open = (row: VaultItemRow) => {
    if (readOnly) return;
    void run<Opened>("vault.open", { workspace: entry.id, item: row.id }, t("web-pages.vault.openWhat")).then((o) => { if (o) setOpened({ opened: o, row }); });
  };
  // Unlocking is opening one of those it does not name: the vault's key kept a while, every name shown.
  const unlock = () => {
    const first = items?.items.find((i) => !i.name);
    if (first) void run("vault.open", { workspace: entry.id, item: first.id }, t("web-pages.vault.unlockWhat"));
  };
  const add = () => setEditing({ form: blankForm(), id: null });
  const actions = !readOnly && v.keyed ? <>
    {v.open && <Button variant="ghost" busy={locking} onClick={() => void run("vault.lock", { workspace: entry.id }, t("web-pages.vault.lockNow"))}>{t("web-pages.vault.lockNow")}</Button>}
    <Button variant="ghost" icon={Plus} onClick={add}>{t("web-pages.vault.add")}</Button>
  </> : undefined;
  return (
    <Section title={v.name} description={readOnly ? undefined : v.open ? t("web-pages.vault.opened") : t("web-pages.vault.sealed")} actions={actions}>
      {!readOnly && !v.keyed ? (
        <div className={pagesCss.card}>
          <div className={css.state}>{t("web-pages.vault.notKeyed")}</div>
          <p className={css.sub}>{t("web-pages.vault.notKeyedWhy")}</p>
          {v.recoverable && v.mine && <div className={css.actions}><Button variant="primary" onClick={() => setRecovering(true)}>{t("web-pages.vault.recover")}</Button></div>}
        </div>
      ) : !items ? <Loading label={t("web-pages.settings.reading")} fill={false} />
        : items.items.length === 0 ? <p className={css.note}>{t("web-pages.vault.empty")}</p>
        : (
          <ul className={pagesCss.list}>
            {named.map((row) => <ItemRow key={row.id} entry={entry} row={row} readOnly={readOnly} onOpen={() => open(row)} />)}
            {hidden > 0 && (
              <li>{readOnly
                ? <div className={pagesCss.listRow}><span className={css.rowIcon} /><span className={css.rowMeta}>{t("web-pages.vault.hidden", { n: hidden })}</span></div>
                : <button type="button" className={`${pagesCss.listRow} ${css.rowButton}`} onClick={unlock}>
                    <span className={css.rowIcon} /><span className={`${pagesCss.listRowText} ${css.rowMeta}`}>{t("web-pages.vault.hidden", { n: hidden })}</span>
                    <span className={css.link}>{t("web-pages.vault.unlock")}</span>
                  </button>}
              </li>
            )}
          </ul>
        )}
      {opened && <ItemDialog opened={opened.opened} row={opened.row} onClose={() => setOpened(null)}
        onEdit={() => { setEditing({ form: formOf(opened.opened, opened.row), id: opened.opened.id }); setOpened(null); }} />}
      {editing && <Editor workspace={entry.id} vault={v.id} first={editing.form} id={editing.id} onClose={() => setEditing(null)} />}
      {recovering && <Recover entry={entry} onClose={() => setRecovering(false)} />}
    </Section>
  );
}

function ItemRow({ entry, row, readOnly, onOpen }: { entry: WorkspaceEntry; row: VaultItemRow; readOnly: boolean; onOpen(): void }) {
  const opening = useDoing("vault.open", { workspace: entry.id, item: row.id });
  const body = <>
    <span className={css.rowIcon}><KindIcon kind={row.kind} /></span>
    <span className={pagesCss.listRowText}>
      <span className={pagesCss.listRowTitle}>{row.name}</span>
      <span className={css.rowMeta}>{itemLine(row)}</span>
    </span>
    {opening && <span className={spinnerCss.spinner} aria-hidden="true" />}
  </>;
  return <li>{readOnly ? <div className={pagesCss.listRow}>{body}</div>
    : <button type="button" className={`${pagesCss.listRow} ${css.rowButton}`} disabled={opening} onClick={onOpen}>{body}</button>}</li>;
}

/** A vault's devices: how many hold its key; members' new ones its owner gives it to. */
function DevicesRow({ entry, v, many }: { entry: WorkspaceEntry; v: VaultRow; many: boolean }) {
  const run = useVaultCall();
  const adding = useDoing("vault.addDevice", { workspace: entry.id, vault: v.id });
  return (
    <div className={css.row}>
      <div className={css.rowText}>
        <span>{many ? `${v.name} · ` : ""}{t("web-pages.vault.devicesHold", { n: v.devices })}</span>
        {v.missing > 0 && <span className={css.warn}>{t("web-pages.vault.missing", { n: v.missing })}</span>}
      </div>
      {v.missing > 0 && v.mine && v.keyed && <Button variant="ghost" busy={adding}
        onClick={() => void run("vault.addDevice", { workspace: entry.id, vault: v.id }, t("web-pages.vault.addDeviceWhat"), t("web-pages.vault.addedDevice"))}>{t("web-pages.vault.addDevice")}</Button>}
    </div>
  );
}

/** An item opened: its fields (masked; shown, copied), how agents may ask for it, and editing it. */
function ItemDialog({ opened, row, onClose, onEdit }: { opened: Opened; row: VaultItemRow | undefined; onClose(): void; onEdit(): void }) {
  const p = opened.plain;
  return (
    <Dialog open title={p.name} description={kindName(p.kind)} onClose={onClose}
      footer={<><span className={css.grow} /><Button variant="primary" onClick={onEdit}>{t("common.edit")}</Button></>}>
      <div className={css.fields}>{fieldsOf(p).map((f) => <Secret key={f.key} label={f.label} value={f.value} secret={f.secret} mono={f.mono} />)}</div>
      <div className={css.agentBox}>
        <span className={css.fieldLabel}>{t("web-pages.vault.forAgents")}</span>
        {row?.listed
          ? <span>{row.modes.map((m) => howLine(m, row.hosts)).join("、")}{row.env ? <> · <code className={css.mono}>{row.env}</code></> : null}</span>
          : <span className={css.rowMeta}>{t("web-pages.vault.notForAgents")}</span>}
      </div>
    </Dialog>
  );
}

/** A field of an item: masked until shown (a while), copied as it is. */
export function Secret({ label, value, secret, mono }: { label: string; value: string; secret: boolean; mono: boolean }) {
  const toast = useToast();
  const [shown, setShown] = useState(!secret);
  return (
    <div className={css.secret}>
      <span className={css.fieldLabel}>{label}</span>
      <div className={css.secretLine}>
        <span className={`${css.secretValue} ${mono ? css.mono : ""}`} data-multiline={value.includes("\n") && shown || undefined}>{shown ? value : masked(value)}</span>
        {secret && <IconButton label={shown ? t("web-pages.vault.hide") : t("web-pages.vault.show")} icon={Eye} aria-pressed={shown} onClick={() => setShown(!shown)} />}
        <IconButton label={t("common.copy")} icon={Copy} onClick={() => copySecret(value, toast)} />
      </div>
    </div>
  );
}

/** An item written: a new one (`id` null) or an opened one changed; deleted from here too. `plain`: the library is not
 * locked, which the secret's risk is said of. */
export function Editor({ workspace, vault, first, id, plain = false, kinds = true, onClose }: { workspace: string; vault: string; first: Form; id: string | null; plain?: boolean; kinds?: boolean; onClose(): void }) {
  const [f, change] = useForm(() => first);
  const run = useVaultCall();
  const [deleting, setDeleting] = useState(false);
  const saving = useDoing("vault.putItem", { workspace, vault });
  const removing = useDoing("vault.deleteItem", { workspace, vault });
  const problem = formProblem(f);
  const save = () => void run("vault.putItem", { workspace, vault, ...(id ? { id } : {}), ...putOf(f) }, t("web-pages.vault.saveWhat"), t("web-pages.vault.saved")).then((r) => { if (r !== undefined) onClose(); });
  const remove = () => void run("vault.deleteItem", { workspace, vault, item: id }, t("web-pages.vault.deleteWhat"), t("web-pages.vault.deleted")).then((r) => { setDeleting(false); if (r !== undefined) onClose(); });
  const input = (key: keyof Form, label: ReactNode, opts: { placeholder?: string; secret?: boolean; mono?: boolean; area?: boolean; error?: string | undefined } = {}) => {
    const fieldId = `vault-${key}`;
    const value = f[key] as string;
    return (
      <Field label={label} htmlFor={fieldId} error={opts.error}>
        {opts.area
          ? <textarea id={fieldId} className={`${controlsCss.input} ${css.area}`} rows={5} spellCheck={false} value={value} placeholder={opts.placeholder} onChange={(e) => change({ [key]: e.target.value })} />
          : <input id={fieldId} className={`${controlsCss.input}${opts.mono ? ` ${css.mono}` : ""}`} type={opts.secret ? "password" : "text"} autoComplete="off" spellCheck={false}
              value={value} placeholder={opts.placeholder} onChange={(e) => change({ [key]: e.target.value })} />}
      </Field>
    );
  };
  const modes = modesOf(f.kind);
  return (
    <>
      <Dialog open={!deleting} title={id ? first.name : t("web-pages.vault.editor.new")} onClose={onClose}
        footer={<>
          {id && <Button variant="ghost" className={controlsCss.btnDanger} busy={removing} onClick={() => setDeleting(true)}>{t("common.delete")}</Button>}
          <span className={css.grow} />
          <Button variant="ghost" onClick={onClose}>{t("common.cancel")}</Button>
          <Button variant="primary" busy={saving} disabled={problem !== null} onClick={save}>{t("common.save")}</Button>
        </>}>
        {plain && <p className={css.warn}>{t("web-pages.vault.risk.editor")}</p>}
        {!id && kinds && <div><Segmented label={t("web-pages.vault.editor.kind")} value={f.kind} onChange={(kind) => change({ kind })} options={KINDS.map((k) => ({ value: k, label: kindName(k) }))} /></div>}
        {input("name", t("web-pages.vault.editor.name"), { placeholder: t("web-pages.vault.editor.namePlaceholder") })}
        {f.kind === "token" && input("value", t("web-pages.vault.editor.value"), { secret: true, mono: true })}
        {f.kind === "ssh_key" && <>
          {input("privateKey", t("web-pages.vault.editor.privateKey"), { area: true, placeholder: "-----BEGIN OPENSSH PRIVATE KEY-----" })}
          {input("publicKey", t("web-pages.vault.editor.publicKey"), { mono: true, placeholder: "ssh-ed25519 AAAA…" })}
        </>}
        {f.kind === "login" && <>
          {input("username", t("web-pages.vault.editor.username"))}
          {input("password", t("web-pages.vault.editor.password"), { secret: true, mono: true })}
          {input("totp", t("web-pages.vault.editor.totp"), { secret: true, mono: true })}
        </>}
        <div className={css.agentBox}>
          <SwitchRow title={t("web-pages.vault.editor.agent")} description={t("web-pages.vault.editor.agentNote")} checked={f.agent} onChange={(agent) => change({ agent })} />
          {f.agent && <>
            <Field label={t("web-pages.vault.editor.how")}>
              {modes.length > 1
                ? <div><Segmented label={t("web-pages.vault.editor.how")} value={f.mode} onChange={(mode) => change({ mode: mode as Mode })} options={modes.map((m) => ({ value: m, label: modeName(m) }))} /></div>
                : <span>{modeName(modes[0]!)}</span>}
            </Field>
            <p className={css.note}>{f.kind === "ssh_key" ? t("web-pages.vault.editor.sshNote") : f.mode === "proxy" ? t("web-pages.vault.editor.proxyNote") : t("web-pages.vault.editor.envNote")}</p>
            {f.kind !== "ssh_key" && f.mode === "proxy" && input("hosts", t("web-pages.vault.editor.hosts"), { placeholder: t("web-pages.vault.editor.hostsPlaceholder"), error: problem === "hosts" && f.hosts !== "" ? t("web-pages.vault.editor.hostsNeeded") : undefined })}
            {f.kind !== "ssh_key" && input("env", t("web-pages.vault.editor.env"), { mono: true, placeholder: t("web-pages.vault.editor.envPlaceholder") })}
          </>}
        </div>
      </Dialog>
      <Confirm open={deleting} title={t("web-pages.vault.deleteTitle", { name: first.name })} description={t("web-pages.vault.deleteBody")} action={t("common.delete")}
        busy={removing} onConfirm={remove} onClose={() => setDeleting(false)} />
    </>
  );
}

/** The recovery words typed in: this device keyed into the person's vaults again. */
function Recover({ entry, onClose }: { entry: WorkspaceEntry; onClose(): void }) {
  const [words, setWords] = useState("");
  const run = useVaultCall();
  const toast = useToast();
  const recovering = useDoing("vault.recover", { workspace: entry.id });
  const count = words.trim() ? words.trim().split(/\s+/).length : 0;
  const go = () => void run<{ recovered: number }>("vault.recover", { workspace: entry.id, words: words.trim().toLowerCase() }, t("web-pages.vault.recoverWhat")).then((r) => {
    if (!r) return;
    toast(r.recovered > 0 ? t("web-pages.vault.recovered", { n: r.recovered }) : t("web-pages.vault.recoveredNone"));
    if (r.recovered > 0) onClose();
  });
  return (
    <Dialog open title={t("web-pages.vault.recover")} description={t("web-pages.vault.recoverLead")} onClose={onClose}
      footer={<><span className={css.note}>{count} / 24</span><span className={css.grow} /><Button variant="ghost" onClick={onClose}>{t("common.cancel")}</Button>
        <Button variant="primary" busy={recovering} disabled={count !== 24} onClick={go}>{t("web-pages.vault.recover")}</Button></>}>
      <textarea className={`${controlsCss.input} ${css.area} ${css.mono}`} rows={4} spellCheck={false} autoCapitalize="off" autoComplete="off" aria-label={t("web-pages.vault.recover")}
        value={words} onChange={(e) => setWords(e.target.value)} />
    </Dialog>
  );
}
