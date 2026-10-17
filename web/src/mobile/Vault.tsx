// 设置 › 密钥 on a narrow screen (as the Android app has it, screens/Vault.kt): the workspace's vault as this device sees
// it (docs/vault.md). What it waits for first (security mode, this device in it, the vault turned on: the recovery words
// shown that once), then the requests waiting on the viewer, each vault's items, the devices holding its key. An item
// opens in a bottom sheet (its fields masked, shown or copied) and is edited in another. A web page only lists the
// names it is told. All of it is the core's (`vaults`, `vaultItems`, `vault.*`; ../vault.ts): this only draws.
import { useState } from "react";
import { ChevronRight, Copy, Edit, Eye, Plus, Quota, ShieldCheck } from "@stillfail/ui/icons.tsx";
import { useParams } from "react-router";
import { useProfiles } from "../api.ts";
import { hosts, profileGroups } from "../cloud/settings.tsx";
import { useToast } from "@stillfail/ui/toast.tsx";
import { useDoing } from "../doing.ts";
import { KindIcon } from "../cloud/Vault.tsx";
import { VaultChoices } from "../VaultApproval.tsx";
import { stationBase } from "../station.tsx";
import {
  ITEM_SECTIONS, KINDS, blankForm, copySecret, listLine, useVaultUses, type Kind, fieldsOf, formOf, formProblem, howLine, itemLine, kindName, masked, modeName, modesOf, putOf, useForm,
  useVaultCall, useVaultItems, useVaults, type Form, type Opened, type VaultItemRow, type VaultRequest, type VaultRow, type VaultsView,
} from "../vault.ts";
import { t } from "../i18n.ts";
import { SheetGrab, SheetHead, useApp } from "./app.tsx";
import { confirm } from "./sheets.tsx";
import { Button, LargeTitle, LinkButton, ListCard, ListRow, Loading, NavBar, NavButton, ProviderMark, SectionHeader, Seg, Spinner, TopBack } from "./parts.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import * as connectsCss from "./Connects.css.ts";
import * as securityCss from "./Security.css.ts";
import * as css from "./Vault.css.ts";

export function VaultScreen() {
  const app = useApp();
  const ws = app.entry.id;
  const view = useVaults(ws);
  const run = useVaultCall();
  const settingUp = useDoing("vault.setup", { workspace: ws });
  const creating = useDoing("vault.create", { workspace: ws });
  // The recovery words, the once the core gives them (`vault.setup`): shown until they are written down.
  const [words, setWords] = useState<string[] | null>(null);
  const create = () => run("vault.create", { workspace: ws, name: t("web-pages.vault.personal") }, t("web-pages.vault.createWhat"));
  const setUp = () => void run<{ words: string | null }>("vault.setup", { workspace: ws }, t("web-pages.vault.setUpWhat")).then((r) => {
    if (!r) return;
    if (r.words) setWords(r.words.trim().split(/\s+/));
    else void create();
  });
  const written = () => {
    if (view?.vaults.some((v) => v.mine)) return setWords(null);
    void create().then(() => setWords(null));
  };
  const ready = !!view && !words && (view.plain === true || (view.available && view.locked && view.canSign && view.setUp));
  const foot = !view ? null
    : words ? <Button primary busy={creating} label={t("web-pages.vault.words.done")} onClick={written} />
    : view.available && view.locked && view.canSign && (!view.setUp || view.vaults.length === 0)
      ? <Button primary busy={settingUp || creating} label={t("web-pages.vault.setUp")} onClick={view.setUp ? () => void create() : setUp} />
    : null;
  return (
    <div className={pagesCss.mScreen}>
      <div className={pagesCss.mScroll}>
        <TopBack label={t("web-mobile.settings.title")} onBack={app.pop}
          trailing={ready ? <NavButton icon={Plus} label={t("web-pages.vault.add")} onClick={() => openAdd(app)} /> : undefined} />
        <LargeTitle small="" big={t("web-pages.vault.title")} />
        {!view ? <Loading text={t("web-pages.settings.reading")} />
          : words ? <Words words={words} />
          : view.plain === true ? <Vaults view={view} />
          : !view.available ? <ReadOnly view={view} />
          : !view.locked ? <Gate title={t("web-pages.vault.needsLock")} why={t("web-pages.vault.needsLockWhy")} />
          : !view.canSign ? <Gate title={t("web-pages.vault.notSigner")} why={t("web-pages.vault.notSignerWhy")} />
          : !view.setUp ? <Intro />
          : <Vaults view={view} />}
        <div style={{ height: 30 }} />
      </div>
      {foot && <div className={securityCss.mFoot}>{foot}</div>}
    </div>
  );
}

/** What the vault waits for first (security mode; this device in it), and the way there. */
function Gate({ title, why }: { title: string; why: string }) {
  const app = useApp();
  return (
    <ListCard><div className={securityCss.mBody}>
      <div className={securityCss.mState}><span className={securityCss.mDot} />{title}</div>
      <span className={partsCss.mSubtle}>{why}</span>
      <LinkButton label={t("web-pages.vault.toSecurity")} onClick={() => app.push(app.at("/settings/security"))} className={css.mStart} />
    </div></ListCard>
  );
}

function Intro() {
  return (
    <ListCard><div className={securityCss.mBody}>
      <div className={securityCss.mState}><span className={securityCss.mDot} />{t("web-pages.vault.setUpTitle")}</div>
      <div>{t("web-pages.vault.point.ask")}<span className={securityCss.mSub}>{t("web-pages.vault.point.askHow")}</span></div>
      <div>{t("web-pages.vault.point.proxy")}<span className={securityCss.mSub}>{t("web-pages.vault.point.proxyHow")}</span></div>
      <div>{t("web-pages.vault.point.zero")}<span className={securityCss.mSub}>{t("web-pages.vault.point.zeroHow")}</span></div>
    </div></ListCard>
  );
}

/** The 24 words, numbered in three columns, the once they are shown. */
function Words({ words }: { words: string[] }) {
  return (
    <ListCard><div className={securityCss.mBody}>
      <b>{t("web-pages.vault.words.title")}</b>
      <span className={partsCss.mSubtle}>{t("web-pages.vault.words.lead")}</span>
      <ol className={css.mWords}>{words.map((w, i) => <li key={i}><span className={css.mWordN}>{i + 1}</span>{w}</li>)}</ol>
      <span className={securityCss.mNote}>{t("web-pages.vault.words.once")}</span>
    </div></ListCard>
  );
}

/** A web page: the names it is told, and that the app opens them. */
function ReadOnly({ view }: { view: VaultsView }) {
  return (
    <>
      <ListCard><div className={securityCss.mBody}>
        <div className={securityCss.mState}><span className={securityCss.mDot} />{t("web-pages.vault.appOnly")}</div>
        <span className={partsCss.mSubtle}>{t("web-pages.vault.appOnlyWhy")}</span>
      </div></ListCard>
      {view.vaults.length === 0 ? <p className={securityCss.mLead}>{t("web-pages.vault.none")}</p>
        : view.vaults.map((v) => <VaultItems key={v.id} v={v} readOnly />)}
    </>
  );
}

/** The library (docs/vault.md 一个库): what waits on the viewer, whether it is locked, the profiles' accounts kept in it,
 * each vault's secrets a section a kind, the devices holding its key (locked). */
function Vaults({ view }: { view: VaultsView }) {
  const plain = view.plain === true;
  return (
    <>
      {view.requests.length > 0 && <>
        <SectionHeader title={`${t("web-pages.vault.requests")} · ${view.requests.length}`} start={24} />
        {view.requests.map((r) => <Request key={r.id} r={r} />)}
      </>}
      <LibraryState />
      {!plain && (view.plainLeft ?? 0) > 0 && <Migrate n={view.plainLeft!} />}
      <ProfileAccounts />
      {view.vaults.map((v) => (plain || v.keyed ? <LibraryVault key={v.id} v={v} plain={plain} /> : <VaultItems key={v.id} v={v} />))}
      {!plain && view.vaults.length > 0 && <>
        <SectionHeader title={t("web-pages.vault.devices")} start={24} />
        <ListCard>{view.vaults.map((v) => <Devices key={v.id} v={v} many={view.vaults.length > 1} />)}</ListCard>
      </>}
    </>
  );
}

/** A request waiting on the viewer: which item, why, the command, how, its chat; then the approval's rows. */
function Request({ r }: { r: VaultRequest }) {
  const app = useApp();
  return (
    <div className={css.mRequest}>
      <ListCard><div className={securityCss.mBody}>
        <b>{t("web-pages.vault.approve.wants", { name: r.itemName ?? r.item })}</b>
        <dl className={css.mFacts}>
          <dt>{t("web-pages.vault.reason")}</dt><dd>{r.reason}</dd>
          {r.command && <><dt>{t("web-pages.vault.command")}</dt><dd><code className={css.mMono}>{r.command}</code></dd></>}
          <dt>{t("web-pages.vault.how")}</dt><dd>{howLine(r.mode, r.hosts)}</dd>
        </dl>
        {r.station && <LinkButton label={t("web-pages.vault.openChat")} className={css.mStart}
          onClick={() => app.push(`${stationBase(`${app.entry.id}/${r.station}`)}/chats/${encodeURIComponent(r.session)}`)} />}
      </div></ListCard>
      <div className={css.mChoices}><VaultChoices workspace={app.entry.id} id={r.id} /></div>
    </div>
  );
}

/** A vault's items: names once unlocked here (the listed ones' always); a tap opens one in a sheet. */
function VaultItems({ v, readOnly = false }: { v: VaultRow; readOnly?: boolean }) {
  const app = useApp();
  const ws = app.entry.id;
  const items = useVaultItems(ws, v.id);
  const run = useVaultCall();
  const named = items?.items.filter((i) => i.name) ?? [];
  const hidden = (items?.items.length ?? 0) - named.length;
  const unlocking = useDoing("vault.open", { workspace: ws, item: items?.items.find((i) => !i.name)?.id ?? "" });
  const open = (row: VaultItemRow) => void run<Opened>("vault.open", { workspace: ws, item: row.id }, t("web-pages.vault.openWhat")).then((o) => {
    if (o) app.sheet({ height: 0.62, content: () => <ItemSheet vault={v.id} opened={o} row={row} /> });
  });
  const unlock = () => {
    const first = items?.items.find((i) => !i.name);
    if (first) void run("vault.open", { workspace: ws, item: first.id }, t("web-pages.vault.unlockWhat"));
  };
  const header = <SectionHeader title={v.name} trailing={readOnly ? undefined : v.open ? t("web-pages.vault.opened") : t("web-pages.vault.sealed")} start={24} />;
  if (!readOnly && !v.keyed) return <>
    {header}
    <ListCard><div className={securityCss.mBody}>
      <div className={securityCss.mState}><span className={securityCss.mDot} data-tone="amber" />{t("web-pages.vault.notKeyed")}</div>
      <span className={partsCss.mSubtle}>{t("web-pages.vault.notKeyedWhy")}</span>
      {v.recoverable && v.mine && <LinkButton label={t("web-pages.vault.recover")} className={css.mStart} onClick={() => app.sheet({ height: 0.6, content: () => <RecoverSheet /> })} />}
    </div></ListCard>
  </>;
  return <>
    {header}
    <ListCard>
      {!items ? <ListRow><span className={partsCss.mSubtle}>{t("web-pages.settings.reading")}</span></ListRow> : <>
        {items.items.length === 0 && <ListRow><span className={partsCss.mSubtle}>{t("web-pages.vault.empty")}</span></ListRow>}
        {named.map((row) => <ItemRow key={row.id} row={row} onOpen={readOnly ? undefined : () => open(row)} />)}
        {hidden > 0 && (
          <ListRow onClick={readOnly ? undefined : unlock}>
            <span className={css.mIcon} />
            <span className={`${partsCss.mGrow} ${partsCss.mSubtle}`}>{t("web-pages.vault.hidden", { n: hidden })}</span>
            {!readOnly && (unlocking ? <Spinner size={14} /> : <span className={partsCss.mAccent}>{t("web-pages.vault.unlock")}</span>)}
          </ListRow>
        )}
        {!readOnly && <ListRow onClick={() => openEditor(app, v.id, blankForm(), null)}><span className={css.mIcon}><Plus size={16} className={partsCss.mAccent} /></span><span className={partsCss.mLink}>{t("web-pages.vault.add")}</span></ListRow>}
        {!readOnly && v.open && <ListRow onClick={() => void run("vault.lock", { workspace: ws }, t("web-pages.vault.lockNow"))}><span className={css.mIcon} /><span className={partsCss.mLink}>{t("web-pages.vault.lockNow")}</span></ListRow>}
      </>}
    </ListCard>
  </>;
}

function ItemRow({ row, onOpen }: { row: VaultItemRow; onOpen: (() => void) | undefined }) {
  const app = useApp();
  const opening = useDoing("vault.open", { workspace: app.entry.id, item: row.id });
  return (
    <ListRow onClick={opening ? undefined : onOpen}>
      <span className={css.mIcon}><KindIcon kind={row.kind} /></span>
      <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
        <span className={listsCss.mRowTitle}>{row.name}</span>
        <span className={listsCss.mRowNote}>{itemLine(row)}</span>
      </span>
      {opening ? <Spinner size={14} /> : onOpen && <ChevronRight size={14} className={partsCss.mSubtle} />}
    </ListRow>
  );
}

/** A vault's devices: how many hold its key; members' new ones its owner gives it to. */
function Devices({ v, many }: { v: VaultRow; many: boolean }) {
  const app = useApp();
  const run = useVaultCall();
  const adding = useDoing("vault.addDevice", { workspace: app.entry.id, vault: v.id });
  const can = v.missing > 0 && v.mine && v.keyed;
  return (
    <ListRow onClick={can && !adding ? () => void run("vault.addDevice", { workspace: app.entry.id, vault: v.id }, t("web-pages.vault.addDeviceWhat"), t("web-pages.vault.addedDevice")) : undefined}>
      <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
        <span className={listsCss.mRowTitle}>{many ? `${v.name} · ` : ""}{t("web-pages.vault.devicesHold", { n: v.devices })}</span>
        {v.missing > 0 && <span className={securityCss.mWarn}>{t("web-pages.vault.missing", { n: v.missing })}</span>}
      </span>
      {adding ? <Spinner size={14} /> : can && <span className={partsCss.mAccent}>{t("web-pages.vault.addDevice")}</span>}
    </ListRow>
  );
}

// ── the sheets ──

function openEditor(app: ReturnType<typeof useApp>, vault: string, first: Form, id: string | null, plain = false, kinds = true) {
  app.sheet({ height: 0.9, content: () => <EditorSheet vault={vault} first={first} id={id} plain={plain} kinds={kinds} /> });
}

/** An item opened: its fields (masked; shown, copied), how agents may ask for it, and editing it. */
function ItemSheet({ vault, opened, row }: { vault: string; opened: Opened; row: VaultItemRow }) {
  const app = useApp();
  const p = opened.plain;
  return (
    <>
      <SheetGrab />
      <SheetHead title={p.name} trailing={<LinkButton label={t("common.edit")} onClick={() => openEditor(app, vault, formOf(opened, row), opened.id)} />} />
      <div className={css.mSheetBody}>
        <span className={listsCss.mRowNote}>{kindName(p.kind)}</span>
        {fieldsOf(p).map((f) => <Secret key={f.key} label={f.label} value={f.value} secret={f.secret} mono={f.mono} />)}
        <div className={css.mSecret}>
          <span className={css.mLabel}>{t("web-pages.vault.forAgents")}</span>
          <span>{row.listed ? `${row.modes.map((m) => howLine(m, row.hosts)).join("、")}${row.env ? ` · ${row.env}` : ""}` : t("web-pages.vault.notForAgents")}</span>
        </div>
      </div>
    </>
  );
}

function Secret({ label, value, secret, mono }: { label: string; value: string; secret: boolean; mono: boolean }) {
  const toast = useToast();
  const [shown, setShown] = useState(!secret);
  return (
    <div className={css.mSecret}>
      <span className={css.mLabel}>{label}</span>
      <div className={css.mSecretLine}>
        <span className={`${css.mSecretValue} ${mono ? css.mMono : ""}`} data-multiline={(shown && value.includes("\n")) || undefined}>{shown ? value : masked(value)}</span>
        {secret && <button type="button" className={css.mIconButton} aria-label={shown ? t("web-pages.vault.hide") : t("web-pages.vault.show")} aria-pressed={shown} onClick={() => setShown(!shown)}><Eye size={18} /></button>}
        <button type="button" className={css.mIconButton} aria-label={t("common.copy")} onClick={() => copySecret(value, toast)}><Copy size={18} /></button>
      </div>
    </div>
  );
}

/** An item written: a new one (`id` null) or an opened one changed; deleted from here too. */
function EditorSheet({ vault, first, id, plain = false, kinds = true }: { vault: string; first: Form; id: string | null; plain?: boolean; kinds?: boolean }) {
  const app = useApp();
  const ws = app.entry.id;
  const [f, change] = useForm(() => first);
  const run = useVaultCall();
  const saving = useDoing("vault.putItem", { workspace: ws, vault });
  const problem = formProblem(f);
  const save = () => void run("vault.putItem", { workspace: ws, vault, ...(id ? { id } : {}), ...putOf(f) }, t("web-pages.vault.saveWhat"), t("web-pages.vault.saved")).then((r) => { if (r !== undefined) app.sheet(null); });
  const remove = () => confirm(app, {
    title: t("web-pages.vault.deleteTitle", { name: first.name }), text: t("web-pages.vault.deleteBody"), action: t("common.delete"), danger: true,
    run: () => run("vault.deleteItem", { workspace: ws, vault, item: id }, t("web-pages.vault.deleteWhat"), t("web-pages.vault.deleted")),
  });
  const field = (key: keyof Form, placeholder: string, opts: { secret?: boolean; mono?: boolean; area?: boolean } = {}) => opts.area
    ? <textarea className={`${listsCss.mField} ${css.mArea}`} data-mono rows={5} spellCheck={false} aria-label={placeholder} placeholder={placeholder} value={f[key] as string} onChange={(e) => change({ [key]: e.target.value })} />
    : <input className={listsCss.mField} data-mono={opts.mono || undefined} type={opts.secret ? "password" : "text"} autoComplete="off" spellCheck={false} autoCapitalize="off"
        aria-label={placeholder} placeholder={placeholder} value={f[key] as string} onChange={(e) => change({ [key]: e.target.value })} />;
  const modes = modesOf(f.kind);
  return (
    <>
      <SheetGrab />
      <SheetHead title={id ? first.name : t("web-pages.vault.editor.new")} />
      <div className={css.mSheetBody}>
        {plain && <span className={securityCss.mWarn}>{t("web-pages.vault.risk.editor")}</span>}
        {!id && kinds && <Seg fill options={KINDS.map(kindName)} selected={KINDS.indexOf(f.kind)} onSelect={(i) => change({ kind: KINDS[i]! })} />}
        <span className={css.mLabel}>{t("web-pages.vault.editor.name")}</span>
        {field("name", t("web-pages.vault.editor.namePlaceholder"))}
        {f.kind === "token" && <><span className={css.mLabel}>{t("web-pages.vault.editor.value")}</span>{field("value", t("web-pages.vault.editor.value"), { secret: true, mono: true })}</>}
        {f.kind === "ssh_key" && <>
          <span className={css.mLabel}>{t("web-pages.vault.editor.privateKey")}</span>{field("privateKey", "-----BEGIN OPENSSH PRIVATE KEY-----", { area: true })}
          <span className={css.mLabel}>{t("web-pages.vault.editor.publicKey")}</span>{field("publicKey", "ssh-ed25519 AAAA…", { mono: true })}
        </>}
        {f.kind === "login" && <>
          <span className={css.mLabel}>{t("web-pages.vault.editor.username")}</span>{field("username", t("web-pages.vault.editor.username"))}
          <span className={css.mLabel}>{t("web-pages.vault.editor.password")}</span>{field("password", t("web-pages.vault.editor.password"), { secret: true, mono: true })}
          <span className={css.mLabel}>{t("web-pages.vault.editor.totp")}</span>{field("totp", t("web-pages.vault.editor.totp"), { secret: true, mono: true })}
        </>}
        <button type="button" className={connectsCss.mSwitchRow} onClick={() => change({ agent: !f.agent })}>
          <span className={partsCss.mGrow}><b>{t("web-pages.vault.editor.agent")}</b><span>{t("web-pages.vault.editor.agentNote")}</span></span>
          <span className={connectsCss.mSwitch} data-on={f.agent || undefined} />
        </button>
        {f.agent && <>
          <span className={css.mLabel}>{t("web-pages.vault.editor.how")}</span>
          {modes.length > 1 ? <Seg fill options={modes.map(modeName)} selected={Math.max(0, modes.indexOf(f.mode))} onSelect={(i) => change({ mode: modes[i]! })} /> : <span>{modeName(modes[0]!)}</span>}
          <span className={securityCss.mNote}>{f.kind === "ssh_key" ? t("web-pages.vault.editor.sshNote") : f.mode === "proxy" ? t("web-pages.vault.editor.proxyNote") : t("web-pages.vault.editor.envNote")}</span>
          {f.kind !== "ssh_key" && f.mode === "proxy" && <><span className={css.mLabel}>{t("web-pages.vault.editor.hosts")}</span>{field("hosts", t("web-pages.vault.editor.hostsPlaceholder"))}</>}
          {f.kind !== "ssh_key" && <><span className={css.mLabel}>{t("web-pages.vault.editor.env")}</span>{field("env", t("web-pages.vault.editor.envPlaceholder"), { mono: true })}</>}
        </>}
        <div className={css.mTools}>
          {id && <LinkButton label={t("common.delete")} className={partsCss.mRed} onClick={remove} />}
          <span className={partsCss.mGrow} />
          <Button label={t("common.cancel")} primary={false} onClick={() => app.sheet(null)} />
          <Button label={t("common.save")} primary busy={saving} enabled={problem === null} onClick={save} />
        </div>
      </div>
    </>
  );
}

/** The recovery words typed in: this device keyed into the person's vaults again. */
function RecoverSheet() {
  const app = useApp();
  const ws = app.entry.id;
  const run = useVaultCall();
  const [words, setWords] = useState("");
  const recovering = useDoing("vault.recover", { workspace: ws });
  const count = words.trim() ? words.trim().split(/\s+/).length : 0;
  const go = () => void run<{ recovered: number }>("vault.recover", { workspace: ws, words: words.trim().toLowerCase() }, t("web-pages.vault.recoverWhat")).then((r) => {
    if (!r) return;
    app.toast(r.recovered > 0 ? t("web-pages.vault.recovered", { n: r.recovered }) : t("web-pages.vault.recoveredNone"));
    if (r.recovered > 0) app.sheet(null);
  });
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-pages.vault.recover")} />
      <div className={css.mSheetBody}>
        <span className={partsCss.mSubtle}>{t("web-pages.vault.recoverLead")}</span>
        <textarea className={`${listsCss.mField} ${css.mArea}`} data-mono rows={5} spellCheck={false} autoCapitalize="off" autoComplete="off" aria-label={t("web-pages.vault.recover")}
          value={words} onChange={(e) => setWords(e.target.value)} />
        <div className={css.mTools}>
          <span className={securityCss.mNote}>{count} / 24</span>
          <span className={partsCss.mGrow} />
          <Button label={t("common.cancel")} primary={false} onClick={() => app.sheet(null)} />
          <Button label={t("web-pages.vault.recover")} primary busy={recovering} enabled={count === 24} onClick={go} />
        </div>
      </div>
    </>
  );
}

// ── the library's parts (docs/vault.md 一个库) ──

/** First in the library's list: whether it is locked (security mode on), and the way to lock it when not. */
function LibraryState() {
  const app = useApp();
  const view = useVaults(app.entry.id);
  if (!view) return null;
  const plain = view.plain === true;
  return (
    <ListCard>
      <ListRow onClick={() => app.push(app.at("/settings/security"))}>
        <span className={css.mIcon} style={plain ? { color: "var(--m-warn)" } : undefined}><ShieldCheck size={18} /></span>
        <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
          <span className={listsCss.mRowTitle} style={plain ? { color: "var(--m-warn)" } : undefined}>{plain ? t("web-pages.vault.lib.plain") : t("web-pages.vault.lib.sealed")}</span>
          <span className={listsCss.mRowNote}>{plain ? t("web-pages.vault.lib.plainWhy") : t("web-pages.vault.lib.sealedWhy")}</span>
        </span>
        {plain ? <span className={partsCss.mAccent}>{t("web-pages.vault.lib.turnOn")}</span> : <ChevronRight size={14} className={partsCss.mSubtle} />}
      </ListRow>
    </ListCard>
  );
}

/** Security mode on, what the plain library still holds from before: moved into the person's vault, encrypted. */
function Migrate({ n }: { n: number }) {
  const app = useApp();
  const run = useVaultCall();
  const toast = useToast();
  const moving = useDoing("vault.migrate", { workspace: app.entry.id });
  const go = () => void run<{ moved: number; left: number }>("vault.migrate", { workspace: app.entry.id }, t("web-pages.vault.migrate.what")).then((r) => {
    if (r) toast(r.left > 0 ? t("web-pages.vault.migrate.partly", { n: r.moved, left: r.left }) : t("web-pages.vault.migrate.done", { n: r.moved }));
  });
  return (
    <ListCard><div className={securityCss.mBody}>
      <div className={securityCss.mState}><span className={securityCss.mDot} data-tone="amber" />{t("web-pages.vault.migrate.title", { n })}</div>
      <span className={partsCss.mSubtle}>{t("web-pages.vault.migrate.body")}</span>
      <LinkButton label={t("web-pages.vault.migrate.go")} busy={moving} className={css.mStart} onClick={go} />
    </div></ListCard>
  );
}

/** The profiles' accounts the library keeps (a subscription's sign-in, a model's key), a section a kind as the profiles
 * list them; each leads to its profile, whose page is where it is set. */
function ProfileAccounts() {
  const app = useApp();
  const profiles = useProfiles(app.entry.id).value;
  if (!profiles) return null;
  return <>{profileGroups(profiles.items).map((g) => (
    <div key={g[0]!.group}>
      <SectionHeader title={g[0]!.groupTitle} start={24} />
      <ListCard>
        {g.map((e) => (
          <ListRow key={e.key} onClick={() => app.push(app.at(hosts(e).length > 1 ? `/settings/profiles/account/${encodeURIComponent(e.key)}` : `/s/${e.stationId}/settings/accounts/${encodeURIComponent(e.profile.id)}`))}>
            <span className={css.mIcon}><ProviderMark runtime={e.profile.runtime} kind={e.profile.access.kind} mark={e.profile.providerMark} size={18} /></span>
            <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
              <span className={listsCss.mRowTitle}>{e.profile.name}</span>
              <span className={listsCss.mRowNote}>{["Profile", e.where].filter(Boolean).join(" · ")}</span>
            </span>
            <ChevronRight size={14} className={partsCss.mSubtle} />
          </ListRow>
        ))}
      </ListCard>
    </div>
  ))}</>;
}

/** A vault's secrets after the profiles' accounts: a section each kind, each one's name and when an agent last used it
 * (in a library not locked, that it is not encrypted, first). */
function LibraryVault({ v, plain }: { v: VaultRow; plain: boolean }) {
  const app = useApp();
  const items = useVaultItems(app.entry.id, v.id);
  if (!items) return null;
  return <>{ITEM_SECTIONS.map((kind) => {
    const rows = items.items.filter((i) => i.name && i.kind === kind);
    if (rows.length === 0) return null;
    return (
      <div key={kind}>
        <SectionHeader title={kindName(kind)} start={24} />
        <ListCard>
          {rows.map((row) => (
            <ListRow key={row.id} onClick={() => app.push(app.at(`/settings/vault/${encodeURIComponent(v.id)}/${encodeURIComponent(row.id)}`))}>
              <span className={css.mIcon}><KindIcon kind={row.kind} size={18} /></span>
              <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
                <span className={listsCss.mRowTitle}>{row.name}</span>
                <span className={listsCss.mRowNote}>{plain && <span className={securityCss.mWarn}>{t("web-pages.vault.risk.row")} · </span>}{listLine(row)}</span>
              </span>
              <ChevronRight size={14} className={partsCss.mSubtle} />
            </ListRow>
          ))}
        </ListCard>
      </div>
    );
  })}</>;
}

/** 添加 in the library: a subscription or a model's key (a profile, made on the profiles' page), or a secret of a kind. */
function openAdd(app: ReturnType<typeof useApp>) {
  app.sheet({ height: 0.55, content: () => <AddSheet /> });
}

function AddSheet() {
  const app = useApp();
  const view = useVaults(app.entry.id);
  const mine = view?.vaults.find((v) => v.mine);
  const plain = view?.plain === true;
  const kinds: ("profile" | Kind)[] = ["profile", ...(mine ? ITEM_SECTIONS : [])];
  const pick = (k: "profile" | Kind) => {
    if (k === "profile") { app.sheet(null); app.push(app.at("/settings/profiles")); return; }
    if (mine) openEditor(app, mine.id, { ...blankForm(), kind: k }, null, plain, false);
  };
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-pages.vault.addKind.title")} />
      <div className={css.mSheetBody}>
        <ListCard>
          {kinds.map((k) => (
            <ListRow key={k} onClick={() => pick(k)}>
              <span className={css.mIcon}>{k === "profile" ? <Quota size={18} /> : <KindIcon kind={k} size={18} />}</span>
              <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
                <span className={listsCss.mRowTitle}>{t(`web-pages.vault.addKind.${k}`)}</span>
                <span className={listsCss.mRowNote}>{t(`web-pages.vault.addKind.${k}Detail`)}</span>
              </span>
            </ListRow>
          ))}
        </ListCard>
        {plain && mine && <span className={securityCss.mWarn}>{t("web-pages.vault.risk.editor")}</span>}
      </div>
    </>
  );
}

/** A secret's page (as cloud/VaultItem.tsx): what it is, in a library not locked that it is not encrypted, its content
 * masked until shown, how agents may use it, and when they did. */
export function VaultItemScreen() {
  const app = useApp();
  const ws = app.entry.id;
  const { vault = "", item = "" } = useParams();
  const view = useVaults(ws);
  const items = useVaultItems(ws, vault);
  const uses = useVaultUses(ws, vault, item);
  const run = useVaultCall();
  const [opened, setOpened] = useState<Opened | null>(null);
  const opening = useDoing("vault.open", { workspace: ws, item });
  const v = view?.vaults.find((x) => x.id === vault);
  const row = items?.items.find((i) => i.id === item);
  const back = t("web-pages.vault.title");
  if (!view || !items || !v || !row) return <div className={pagesCss.mScreen}><NavBar back={back} onBack={app.pop} title={back} /><Loading text={t("web-pages.settings.reading")} /></div>;
  const plain = view.plain === true;
  const open = (then?: (o: Opened) => void) => void run<Opened>("vault.open", { workspace: ws, item }, t("web-pages.vault.openWhat")).then((o) => { if (o) { setOpened(o); then?.(o); } });
  const edit = () => (opened ? openEditor(app, vault, formOf(opened, row), opened.id, plain) : open((o) => openEditor(app, vault, formOf(o, row), o.id, plain)));
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <NavBar back={back} onBack={app.pop} title={row.name ?? ""} sub={<span>{[kindName(row.kind), t("web-pages.vault.storedOn", { station: v.stationName })].join(" · ")}</span>}
        trailing={<NavButton icon={Edit} label={t("common.edit")} onClick={edit} />} />
      {plain && (
        <ListCard><div className={securityCss.mBody}>
          <div className={securityCss.mState}><span className={securityCss.mDot} data-tone="amber" />{t("web-pages.vault.risk.title")}</div>
          <span className={partsCss.mSubtle}>{t("web-pages.vault.risk.body", { station: v.stationName })}</span>
          <LinkButton label={t("web-pages.vault.lib.turnOn")} className={css.mStart} onClick={() => app.push(app.at("/settings/security"))} />
        </div></ListCard>
      )}
      <SectionHeader title={t("web-pages.vault.content")} start={24} />
      <ListCard>
        {opened
          ? <div className={securityCss.mBody}>{fieldsOf(opened.plain).map((f) => <Secret key={f.key} label={f.label} value={f.value} secret={f.secret} mono={f.mono} />)}</div>
          : <div className={securityCss.mBody}><div className={css.mSecretLine}>
              <span className={`${css.mSecretValue} ${css.mMono}`}>{masked("x".repeat(20))}</span>
              <LinkButton label={t("web-pages.vault.show")} busy={opening} onClick={() => open()} />
            </div></div>}
      </ListCard>
      <SectionHeader title={t("web-pages.vault.forAgents")} start={24} />
      <ListCard><div className={securityCss.mBody}>
        {row.listed ? (
          <dl className={css.mFacts}>
            <dt>{t("web-pages.vault.how")}</dt><dd>{row.modes.map((m) => howLine(m, row.hosts)).join("、")}</dd>
            {row.env && <><dt>{t("web-pages.vault.editor.env")}</dt><dd className={css.mMono}>{row.env}</dd></>}
          </dl>
        ) : <span className={partsCss.mSubtle}>{t("web-pages.vault.notForAgents")}</span>}
      </div></ListCard>
      <SectionHeader title={t("web-pages.vault.uses.title")} start={24} />
      <ListCard>
        {!uses ? <ListRow><span className={partsCss.mSubtle}>{t("web-pages.settings.reading")}</span></ListRow>
          : uses.uses.length === 0 ? <ListRow><span className={partsCss.mSubtle}>{t("web-pages.vault.uses.none")}</span></ListRow>
          : uses.uses.map((u, i) => (
            <ListRow key={i} onClick={u.station ? () => app.push(`${stationBase(`${ws}/${u.station}`)}/chats/${encodeURIComponent(u.session)}`) : undefined}>
              <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
                <span className={listsCss.mRowTitle}>{u.chatTitle ?? u.session}{u.denied && <span className={securityCss.mWarn}> · {t("web-pages.vault.uses.denied")}</span>}</span>
                <span className={`${listsCss.mRowNote} ${css.mMono}`}>{u.command ?? howLine(u.mode, u.hosts)}</span>
              </span>
              <span className={listsCss.mRowNote}>{u.at.ago}</span>
            </ListRow>
          ))}
      </ListCard>
      <div style={{ height: 30 }} />
    </div>
  );
}
