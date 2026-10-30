// 设置 › 密钥 and 全部密钥 under it on a narrow screen: the workspace's vault as this device sees it (docs/vault.md), the
// app's pages' structure (apps/mbui sfdesk vault.mbt). What it waits for first (security mode, this device in it, the
// vault turned on: the recovery words shown that once), on either; then on 密钥 the requests waiting on the viewer, a
// row to 全部密钥, how it keeps its secrets (a row each on one card), deleting the vault at the foot; on 全部密钥 the
// profiles' accounts and each vault's items, a section a kind, and adding. An item opens on a page of its own and is
// edited in a sheet. A web page only lists the names it is told. All of it is the core's (`vaults`, `vaultItems`,
// `vault.*`; ../vault.ts): this only draws.
import { useState, type ReactNode } from "react";
import { ChevronDown, ChevronRight, ChevronUp, Copy, Edit, Eye, Plus, Quota, Search } from "@stillfail/ui/icons.tsx";
import { useParams } from "react-router";
import { useProfiles } from "../api.ts";
import { hosts } from "../cloud/settings.tsx";
import { useToast } from "@stillfail/ui/toast.tsx";
import { useDoing } from "../doing.ts";
import { KindIcon } from "../cloud/Vault.tsx";
import { ProviderLogo } from "../ui.tsx";
import { stationBase } from "../station.tsx";
import { VaultActions } from "../VaultApproval.tsx";
import { AskCard } from "../VaultAsk.tsx";
import {
  ITEM_SECTIONS, KINDS, LASTS, SCOPES, scopeOf, blankForm, copySecret, lastsChoice, lastsName, useVaultUses, type Kind, fileSize, formOf, formProblem, kindName, masked, modeName, modesOf, pickInto, putOf, useForm,
  useVaultCall, useVaultItems, useVaults, useVaultsItems, type Form, type Opened, type VaultItemRow, type VaultRequest, type VaultRow, type VaultsView, type VaultUse,
} from "../vault.ts";
import { t } from "../i18n.ts";
import { StationInWords } from "../StationNamed.tsx";
import { SheetGrab, SheetHead, useApp } from "./app.tsx";
import { confirm } from "./sheets.tsx";
import { Button, LargeTitle, LinkButton, ListCard, ListRow, NavBar, NavButton, PickRow, SectionHeader, Seg, TopBack } from "./parts.tsx";
import { Spinner, Waiting } from "@stillfail/ui/waiting.tsx";
import { sampleVaultItems, sampleVaults, sampleVaultUses } from "../samples.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import * as sheetsCss from "./styles/sheets.css.ts";
import * as connectsCss from "./Connects.css.ts";
import * as securityCss from "./Security.css.ts";
import * as rootCss from "./styles/root.css.ts";
import * as homeCss from "./Home.css.ts";
import * as css from "./Vault.css.ts";

export function VaultScreen() {
  const app = useApp();
  const { view, first, foot } = useFirst(<Library view={SAMPLE_VAULTS} />);
  return (
    <div className={pagesCss.mScreen}>
      <div className={pagesCss.mScroll}>
        <TopBack label={t("web-mobile.settings.title")} onBack={app.pop} />
        <LargeTitle small="" big={t("web-pages.vault.title")} />
        {first ?? <Library view={view!} />}
        <div style={{ height: 30 }} />
      </div>
      {foot && <div className={securityCss.mFoot}>{foot}</div>}
    </div>
  );
}

/** 全部密钥: what the library keeps, 添加 at its top; what has to come first, as on 密钥. */
export function VaultAllScreen() {
  const app = useApp();
  const { view, first, foot } = useFirst(<All view={SAMPLE_VAULTS} />);
  return (
    <div className={pagesCss.mScreen}>
      <div className={pagesCss.mScroll}>
        <TopBack label={t("web-pages.vault.title")} onBack={app.pop}
          trailing={first ? undefined : <NavButton icon={Plus} label={t("web-pages.vault.add")} onClick={() => openAdd(app)} />} />
        <LargeTitle small="" big={t("web-pages.vault.all")} />
        {first ?? <All view={view!} />}
        <div style={{ height: 30 }} />
      </div>
      {foot && <div className={securityCss.mFoot}>{foot}</div>}
    </div>
  );
}

/** What 密钥 and 全部密钥 show before the library, and the button at their foot: waiting for the core (the page as it
 * will be, `sample`, in its bones); the recovery words to write down; a web page's names; what has to come first.
 * `first` null where the library is there to be used (in plain text on the station, or locked, signed and set up here). */
function useFirst(sample: ReactNode): { view: VaultsView | undefined; first: ReactNode | null; foot: ReactNode | null } {
  const app = useApp();
  const ws = app.entry.id;
  const view = useVaults(ws);
  const run = useVaultCall();
  const settingUp = useDoing("vault.setup", { workspace: ws });
  const creating = useDoing("vault.create", { workspace: ws });
  // The recovery words, the once the core gives them (`vault.setup`): shown until they are written down.
  const [words, setWords] = useState<string[] | null>(null);
  // (the person's own vault made with it when they have none; offered on its own when that did not take)
  const create = () => run("vault.create", { workspace: ws, name: t("web-pages.vault.personal") }, t("web-pages.vault.createWhat"));
  const setUp = () => void run<{ words: string | null }>("vault.setup", { workspace: ws }, t("web-pages.vault.setUpWhat")).then((r) => {
    if (r?.words) setWords(r.words.trim().split(/\s+/));
  });
  const foot = !view ? null
    : words ? <Button primary label={t("web-pages.vault.words.done")} onClick={() => setWords(null)} />
    : view.available && view.locked && view.canSign && (!view.setUp || view.vaults.length === 0)
      ? <Button primary busy={settingUp || creating} label={t("web-pages.vault.setUp")} onClick={view.setUp ? () => void create() : setUp} />
    : null;
  const first = !view ? <Waiting sample={sample} />
    : words ? <Words words={words} />
    : view.plain === true ? null
    : !view.available ? <ReadOnly view={view} />
    : !view.locked ? <Gate title={t("web-pages.vault.needsLock")} why={t("web-pages.vault.needsLockWhy")} />
    : !view.canSign ? <Gate title={t("web-pages.vault.notSigner")} why={t("web-pages.vault.notSignerWhy")} />
    : !view.setUp ? <Intro />
    : null;
  return { view, first, foot };
}

/** The vault, its secrets and a secret's uses made up, for what its pages show while they are read (in their bones). */
const SAMPLE_VAULTS = sampleVaults();
const SAMPLE_ITEMS = sampleVaultItems();
const SAMPLE_USES = sampleVaultUses();

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
        : view.vaults.map((v) => <VaultItems key={v.id} v={v} />)}
    </>
  );
}

/** The library (docs/vault.md 一个库): the requests waiting on the viewer, each one's card as in its chat; a row to
 * 全部密钥; how it keeps its secrets, a row each on one card; deleting the person's vault in red at the foot. */
function Library({ view }: { view: VaultsView }) {
  const app = useApp();
  const plain = view.plain === true;
  const mine = view.vaults.filter((v) => v.mine);
  return (
    <>
      {view.requests.length > 0 && <>
        <SectionHeader title={`${t("web-pages.vault.requests")} · ${view.requests.length}`} start={24} />
        {view.requests.map((r) => <Request key={r.id} r={r} />)}
      </>}
      {!plain && view.vaults.filter((v) => !v.keyed).map((v) => <NoKey key={v.id} v={v} />)}
      <ListCard>
        <ListRow onClick={() => app.push(app.at("/settings/vault/all"))}>
          <span className={`${partsCss.mGrow} ${listsCss.mRowTitle}`}>{t("web-pages.vault.all")}</span>
          <ChevronRight size={14} className={partsCss.mSubtle} />
        </ListRow>
      </ListCard>
      <Kept view={view} />
      {!plain && mine.length > 0 && <ListCard>{mine.map((v) => <DeleteRow key={v.id} v={v} many={view.vaults.length > 1} />)}</ListCard>}
    </>
  );
}

/** 全部密钥, as a password manager's list (cloud/Vault.tsx All's): a field to find one by any of its words; then every
 * one on one card, a row each: its mark, its name, its kind and what is worth knowing of it under it; each vault's
 * secrets (a vault this device has no key to, the names it is told), locked, a row of those it does not name; then the
 * profiles' accounts on a card of their own, folded under a row naming them, open where what is looked for is among
 * them. */
function All({ view }: { view: VaultsView }) {
  const app = useApp();
  const [find, setFind] = useState("");
  // (the profiles' accounts folded at the foot: seen on the profiles' pages first)
  const [opened, setOpened] = useState(false);
  const plain = view.plain === true;
  const profiles = useProfiles(app.entry.id).value;
  const lists = useVaultsItems(app.entry.id, view.vaults.map((v) => v.id));
  const many = view.vaults.length > 1;
  const q = find.trim().toLowerCase();
  const shows = (...words: (string | null | undefined)[]) => q === "" || words.some((w) => (w ?? "").toLowerCase().includes(q));
  const accounts = (profiles?.items ?? []).filter((e) => shows(e.title, e.groupTitle, e.where));
  const secrets = view.vaults.flatMap((v, i) => (lists[i]?.items ?? []).filter((row) => row.name && shows(row.name, row.kindText, row.lineText, row.howText)).map((row) => ({ v, row })));
  const unnamed = view.vaults.flatMap((v, i) => {
    const hidden = (lists[i]?.items ?? []).filter((row) => !row.name);
    return hidden.length > 0 ? [{ v, hidden }] : [];
  });
  const reading = !profiles || lists.some((l) => !l);
  const open = opened || q !== "";
  // (a row's line: what is said of it, those words that are not empty, a dot between)
  const said = (...words: (string | null | undefined)[]) => words.filter((w) => w).join(" · ");
  return (
    <>
      <div className={css.mFind}>
        <label className={homeCss.mSearchInput}>
          <Search size={17} />
          <input type="search" enterKeyHint="search" value={find} spellCheck={false} placeholder={t("web-pages.vault.find")} aria-label={t("web-pages.vault.find")}
            onChange={(e) => setFind(e.target.value)} />
        </label>
      </div>
      <Secrets secrets={secrets} unnamed={unnamed} plain={plain} many={many} />
      {/* The accounts, folded under a row naming them (open where what is looked for is among them). */}
      {accounts.length > 0 && (
        <ListCard>
          <ListRow onClick={q !== "" ? undefined : () => setOpened(!opened)}>
            <span className={css.mMark} />
            <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
              <span className={listsCss.mRowTitle}>{t("web-pages.vault.accounts")}</span>
              {!open && <span className={css.mLine}>{accounts.map((e) => e.title).join("、")}</span>}
            </span>
            {open ? <ChevronUp size={14} className={partsCss.mSubtle} /> : <ChevronDown size={14} className={partsCss.mSubtle} />}
          </ListRow>
          {open && accounts.map((e) => (
            <ListRow key={e.key} onClick={() => app.push(app.at(hosts(e).length > 1 ? `/settings/profiles/account/${encodeURIComponent(e.key)}` : `/s/${e.stationId}/settings/accounts/${encodeURIComponent(e.profile.id)}`))}>
              <span className={css.mMark}><ProviderLogo runtime={e.profile.runtime} kind={e.profile.access.kind} mark={e.profile.providerMark} size={16} /></span>
              <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
                <span className={listsCss.mRowTitle}>{e.title}</span>
                <span className={css.mLine}>{said(e.groupTitle, e.where)}</span>
                {e.profile.checkTone === "red" && <span className={css.mBad}>{e.profile.checkText}</span>}
              </span>
              <ChevronRight size={14} className={partsCss.mSubtle} />
            </ListRow>
          ))}
        </ListCard>
      )}
      {reading ? <Waiting sample={<Secrets secrets={SAMPLE_ITEMS.map((row) => ({ v: SAMPLE_VAULTS.vaults[0]!, row }))} unnamed={[]} plain={false} many={false} />} />
        : q !== "" && accounts.length + secrets.length === 0 ? <p className={securityCss.mLead}>{t("web-pages.vault.noMatch", { q: find.trim() })}</p>
        : (profiles?.items.length ?? 0) + secrets.length + unnamed.length === 0 && <p className={securityCss.mLead}>{t("web-pages.vault.empty")}</p>}
    </>
  );
}

/** 全部密钥's secrets on one card, a row each (`secrets`, each with its vault), and a row for each vault's unnamed ones, to unlock it. */
function Secrets({ secrets, unnamed, plain, many }: { secrets: { v: VaultRow; row: VaultItemRow }[]; unnamed: { v: VaultRow; hidden: VaultItemRow[] }[]; plain: boolean; many: boolean }) {
  const app = useApp();
  const run = useVaultCall();
  if (secrets.length + unnamed.length === 0) return null;
  // (a row's line: what is said of it, those words that are not empty, a dot between)
  const said = (...words: (string | null | undefined)[]) => words.filter((w) => w).join(" · ");
  return (
    <ListCard>
      {secrets.map(({ v, row }) => {
        const keyed = plain || v.keyed;
        return (
          <ListRow key={`${v.id}/${row.id}`} onClick={keyed ? () => app.push(app.at(`/settings/vault/${encodeURIComponent(v.id)}/${encodeURIComponent(row.id)}`)) : undefined}>
            <span className={css.mMark}><KindIcon kind={row.kind ?? undefined} /></span>
            <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
              <span className={listsCss.mRowTitle}>{row.name}</span>
              {/* (its kind, its vault where there are more than one; the core's: how an agent gets it, when and where
                  it was last used) */}
              <span className={css.mLine}>{said(row.kindText, many ? v.name : null, keyed ? row.lineText : row.agentText)}</span>
            </span>
            {keyed && <ChevronRight size={14} className={partsCss.mSubtle} />}
          </ListRow>
        );
      })}
      {/* (unlocked by opening one of them: the vault's key kept a while, every name shown) */}
      {unnamed.map(({ v, hidden }) => (
        <ListRow key={`${v.id}/hidden`} onClick={plain || v.keyed ? () => void run("vault.open", { workspace: app.entry.id, item: hidden[0]!.id }, t("web-pages.vault.unlockWhat")) : undefined}>
          <span className={css.mMark} />
          <span className={`${partsCss.mGrow} ${listsCss.mRowTitle}`}>{t("web-pages.vault.hidden", { n: hidden.length })}</span>
          {(plain || v.keyed) && <span className={partsCss.mAccent}>{t("web-pages.vault.unlock")}</span>}
        </ListRow>
      ))}
    </ListCard>
  );
}

/** A request waiting on the viewer (to use an item, or to keep one): its card, as in its chat (the wide screen's parts,
 * as they stand there), and a way to that chat. */
function Request({ r }: { r: VaultRequest }) {
  const app = useApp();
  const chat = r.station ? `${stationBase(`${app.entry.id}/${r.station}`)}/chats/${encodeURIComponent(r.session)}` : null;
  return (
    <div className={`${css.mRequest} ${rootCss.wide}`}>
      <AskCard fill ask={{ name: r.itemName ?? r.item, mode: r.mode, command: r.command, save: r.save }}>
        <VaultActions workspace={app.entry.id} id={r.id} extra={chat && <LinkButton label={t("web-pages.vault.openChat")} onClick={() => app.push(chat)} />} />
      </AskCard>
    </div>
  );
}

/** A vault this device has no key to, under its name: that it has none, and the recovery words typed where they can
 * give it one. */
function NoKey({ v }: { v: VaultRow }) {
  const app = useApp();
  return <>
    <SectionHeader title={v.name} start={24} />
    <ListCard><div className={securityCss.mBody}>
      <div className={securityCss.mState}><span className={securityCss.mDot} data-tone="amber" />{t("web-pages.vault.notKeyed")}</div>
      <span className={partsCss.mSubtle}>{t("web-pages.vault.notKeyedWhy")}</span>
      {v.recoverable && v.mine && <LinkButton label={t("web-pages.vault.recover")} className={css.mStart} onClick={() => app.sheet({ height: 0.6, content: () => <RecoverSheet /> })} />}
    </div></ListCard>
  </>;
}

/** A vault known by its items' names only (a web page's, or one this device has no key to): the names it is told (the
 * listed ones' always), how many more it does not name. */
function VaultItems({ v }: { v: VaultRow }) {
  const app = useApp();
  const items = useVaultItems(app.entry.id, v.id);
  const named = items?.items.filter((i) => i.name) ?? [];
  const hidden = (items?.items.length ?? 0) - named.length;
  return <>
    <SectionHeader title={v.name} start={24} />
    {!items ? <Waiting sample={<ListCard>{SAMPLE_ITEMS.map((row) => <ItemRow key={row.id} row={row} />)}</ListCard>} /> : (
      <ListCard>
        {items.items.length === 0 && <ListRow><span className={partsCss.mSubtle}>{t("web-pages.vault.empty")}</span></ListRow>}
        {named.map((row) => <ItemRow key={row.id} row={row} />)}
        {hidden > 0 && (
          <ListRow>
            <span className={css.mIcon} />
            <span className={`${partsCss.mGrow} ${partsCss.mSubtle}`}>{t("web-pages.vault.hidden", { n: hidden })}</span>
          </ListRow>
        )}
      </ListCard>
    )}
  </>;
}

function ItemRow({ row }: { row: VaultItemRow }) {
  return (
    <ListRow>
      <span className={css.mIcon}><KindIcon kind={row.kind} /></span>
      <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
        <span className={listsCss.mRowTitle}>{row.name}</span>
        <span className={listsCss.mRowNote}>{row.agentText}</span>
      </span>
    </ListRow>
  );
}

// ── the sheets ──

function openEditor(app: ReturnType<typeof useApp>, vault: string, first: Form, id: string | null, plain = false, kinds = true) {
  app.sheet({ height: 0.9, content: () => <EditorSheet vault={vault} first={first} id={id} plain={plain} kinds={kinds} /> });
}

/** `revealed`: opened to be seen (its 显示), shown at once rather than masked for a second press. */
function Secret({ label, value, secret, mono, revealed = false }: { label: string; value: string; secret: boolean; mono: boolean; revealed?: boolean }) {
  const toast = useToast();
  const [shown, setShown] = useState(!secret || revealed);
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
  const toast = useToast();
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
        {field("name", t(f.kind === "file" ? "web-pages.vault.editor.fileNamePlaceholder" : "web-pages.vault.editor.namePlaceholder"))}
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
        {f.kind === "file" && <>
          <span className={css.mLabel}>{t("web-pages.vault.editor.file")}</span>
          {f.fileContent && <span className={css.mFileName}>{f.fileName || t("web-pages.vault.kind.file")} · {fileSize(f.fileContent)}</span>}
          <Button label={t("web-pages.vault.editor.pickFile")} primary={false} onClick={() => void pickInto(change, toast)} />
        </>}
        <button type="button" className={connectsCss.mSwitchRow} onClick={() => change({ agent: !f.agent })}>
          <span className={partsCss.mGrow}><b>{t("web-pages.vault.editor.agent")}</b><span>{t("web-pages.vault.editor.agentNote")}</span></span>
          <span className={connectsCss.mSwitch} data-on={f.agent || undefined} />
        </button>
        {f.agent && <>
          <span className={css.mLabel}>{t("web-pages.vault.editor.how")}</span>
          {modes.length > 1 ? <Seg fill options={modes.map(modeName)} selected={Math.max(0, modes.indexOf(f.mode))} onSelect={(i) => change({ mode: modes[i]! })} /> : <span>{modeName(modes[0]!)}</span>}
          <span className={securityCss.mNote}>{f.kind === "ssh_key" ? t("web-pages.vault.editor.sshNote") : f.kind === "file" ? t("web-pages.vault.editor.fileNote") : f.mode === "proxy" ? t("web-pages.vault.editor.proxyNote") : t("web-pages.vault.editor.envNote")}</span>
          {f.kind !== "ssh_key" && f.mode === "proxy" && <><span className={css.mLabel}>{t("web-pages.vault.editor.hosts")}</span>{field("hosts", t("web-pages.vault.editor.hostsPlaceholder"))}</>}
          {f.kind !== "ssh_key" && <><span className={css.mLabel}>{t("web-pages.vault.editor.env")}</span>{field("env", t(f.kind === "file" ? "web-pages.vault.editor.fileEnvPlaceholder" : "web-pages.vault.editor.envPlaceholder"), { mono: true })}</>}
          <span className={css.mLabel}>{t("web-pages.vault.editor.lasts")}</span>
          <Seg fill options={LASTS.map(lastsChoice)} selected={LASTS.indexOf(f.lasts)} onSelect={(i) => change({ lasts: LASTS[i]! })} />
          <span className={securityCss.mNote}>{t("web-pages.vault.editor.lastsNote")}</span>
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

/** How the library keeps its secrets, a row each on one card, first (as a page's own settings stand): encrypted, or in
 * plain text on the station (the way to security mode at its end), unlocked here a while (locked again from its end);
 * those still in plain text from before (encrypted from its end); the longest an approval lasts (picked in a sheet);
 * the devices holding each vault's key (given to new ones from its end). What is not as it should be in amber. */
function Kept({ view }: { view: VaultsView }) {
  const app = useApp();
  const ws = app.entry.id;
  const run = useVaultCall();
  const toast = useToast();
  const locking = useDoing("vault.lock", { workspace: ws });
  const moving = useDoing("vault.migrate", { workspace: ws });
  const plain = view.plain === true;
  const open = view.vaults.some((v) => v.open);
  const left = view.plainLeft ?? 0;
  const mine = view.vaults.find((v) => v.mine);
  const migrate = () => void run<{ moved: number; left: number }>("vault.migrate", { workspace: ws }, t("web-pages.vault.migrate.what")).then((r) => {
    if (r) toast(r.left > 0 ? t("web-pages.vault.migrate.partly", { n: r.moved, left: r.left }) : t("web-pages.vault.migrate.done", { n: r.moved }));
  });
  return (
    <ListCard>
      <ListRow>
        <RowWords title={t(plain ? "web-pages.vault.lib.plain" : "web-pages.vault.lib.sealed")}
          note={t(plain ? "web-pages.vault.lib.plainWhy" : open ? "web-pages.vault.opened" : "web-pages.vault.lib.sealedWhy")} warn={plain} />
        {plain ? <LinkButton label={t("web-pages.vault.lib.turnOn")} onClick={() => app.push(app.at("/settings/security"))} />
          : open && <LinkButton label={t("web-pages.vault.lockNow")} busy={locking} onClick={() => void run("vault.lock", { workspace: ws }, t("web-pages.vault.lockNow"))} />}
      </ListRow>
      {!plain && left > 0 && (
        <ListRow>
          <RowWords title={t("web-pages.vault.migrate.title", { n: left })} note={t("web-pages.vault.migrate.body")} warn />
          <LinkButton label={t("web-pages.vault.migrate.go")} busy={moving} onClick={migrate} />
        </ListRow>
      )}
      {mine && <LastsRow v={mine} />}
      {!plain && view.vaults.map((v) => <DevicesRow key={v.id} v={v} many={view.vaults.length > 1} />)}
    </ListCard>
  );
}

/** A row's words: what it is, how it stands under it (in amber where it is not as it should be). */
function RowWords({ title, note, warn = false }: { title: string; note: string; warn?: boolean }) {
  return (
    <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
      <span className={listsCss.mRowTitle}>{title}</span>
      <span className={warn ? securityCss.mWarn : listsCss.mRowNote}>{note}</span>
    </span>
  );
}

/** The longest an agent's request for the person's secrets is approved for, where a secret does not say its own: the
 * one now under it; pressed, the choices in a sheet, each with what it means. */
function LastsRow({ v }: { v: VaultRow }) {
  const app = useApp();
  const setting = useDoing("vault.setLasts", { workspace: app.entry.id, vault: v.id });
  return (
    <ListRow onClick={setting ? undefined : () => app.sheet({ height: 0.42, content: () => <LastsSheet v={v} /> })}>
      <RowWords title={t("web-pages.vault.lasts.title")} note={lastsName(v.lasts)} />
      {setting ? <Spinner inline /> : <ChevronRight size={14} className={partsCss.mSubtle} />}
    </ListRow>
  );
}

function LastsSheet({ v }: { v: VaultRow }) {
  const app = useApp();
  const run = useVaultCall();
  const now = scopeOf(v.lasts);
  const pick = (s: string) => {
    app.sheet(null);
    if (s !== now) void run("vault.setLasts", { workspace: app.entry.id, vault: v.id, lasts: s }, t("web-pages.vault.lasts.what"));
  };
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-pages.vault.lasts.title")} />
      <div className={sheetsCss.mSheetScroll}>
        {SCOPES.map((s) => <PickRow key={s} label={lastsName(s)} sub={t(`web-pages.vault.lasts.${s}Detail`)} checked={s === now} onClick={() => pick(s)} />)}
      </div>
    </>
  );
}

/** The devices holding a vault's key (its name where there are more than one): how many; where some new ones have none
 * yet, how many, in amber, given it from its end by its owner's device holding it. */
function DevicesRow({ v, many }: { v: VaultRow; many: boolean }) {
  const app = useApp();
  const ws = app.entry.id;
  const run = useVaultCall();
  const adding = useDoing("vault.addDevice", { workspace: ws, vault: v.id });
  return (
    <ListRow>
      <RowWords title={many ? v.name : t("web-pages.security.devices")} warn={v.missing > 0}
        note={v.missing > 0 ? t("web-pages.vault.missing", { n: v.missing }) : t("web-pages.vault.devicesHold", { n: v.devices })} />
      {v.missing > 0 && v.mine && v.keyed && <LinkButton label={t("web-pages.vault.addDevice")} busy={adding}
        onClick={() => void run("vault.addDevice", { workspace: ws, vault: v.id }, t("web-pages.vault.addDeviceWhat"), t("web-pages.vault.addedDevice"))} />}
    </ListRow>
  );
}

/** Deleting a vault of the person's own (its name after where there are more than one), in red: asked first, saying
 * what goes with it. */
function DeleteRow({ v, many }: { v: VaultRow; many: boolean }) {
  const app = useApp();
  const ws = app.entry.id;
  const run = useVaultCall();
  const deleting = useDoing("vault.delete", { workspace: ws, vault: v.id });
  const remove = () => confirm(app, {
    title: t("web-pages.vault.deleteTitle", { name: v.name }), action: t("common.delete"), danger: true,
    text: v.items > 0 ? t("web-pages.vault.deleteVaultBody", { n: v.items }) : t("web-pages.vault.deleteVaultEmpty"),
    run: () => run("vault.delete", { workspace: ws, vault: v.id }, t("web-pages.vault.deleteWhat"), t("web-pages.vault.deleted")),
  });
  return (
    <ListRow onClick={deleting ? undefined : remove}>
      <span className={`${partsCss.mGrow} ${listsCss.mRowTitle} ${partsCss.mRed}`}>{t("web-pages.vault.deleteVault")}{many ? ` · ${v.name}` : ""}</span>
      {deleting && <Spinner inline />}
    </ListRow>
  );
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
  const { vault = "", item = "" } = useParams();
  const view = useVaults(app.entry.id);
  const items = useVaultItems(app.entry.id, vault);
  const v = view?.vaults.find((x) => x.id === vault);
  const row = items?.items.find((i) => i.id === item);
  const back = t("web-pages.vault.all");
  if (!view || !items || !v || !row) {
    return <div className={pagesCss.mScreen}><NavBar back={back} onBack={app.pop} title={back} />
      <Waiting sample={<ItemBody v={SAMPLE_VAULTS.vaults[0]!} row={SAMPLE_ITEMS[0]!} plain={false} opened={null} revealed={false} opening={false} onShow={() => undefined} />} /></div>;
  }
  return <ItemScreen v={v} row={row} plain={view.plain === true} />;
}

/** A secret's page: `row`, kept in `v` (`plain`: a library not locked), opened to be shown or edited. */
function ItemScreen({ v, row, plain }: { v: VaultRow; row: VaultItemRow; plain: boolean }) {
  const app = useApp();
  const ws = app.entry.id;
  const vault = v.id, item = row.id;
  const back = t("web-pages.vault.all");
  const run = useVaultCall();
  const [opened, setOpened] = useState<Opened | null>(null);
  const [revealed, setRevealed] = useState(false);
  const opening = useDoing("vault.open", { workspace: ws, item });
  const open = (then?: (o: Opened) => void) => void run<Opened>("vault.open", { workspace: ws, item }, t("web-pages.vault.openWhat")).then((o) => { if (o) { setOpened(o); then?.(o); } });
  const edit = () => (opened ? openEditor(app, vault, formOf(opened, row), opened.id, plain) : open((o) => openEditor(app, vault, formOf(o, row), o.id, plain)));
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <NavBar back={back} onBack={app.pop} title={row.name ?? ""} sub={<span>{<StationInWords station={v.station} text={[row.kindText, t("web-pages.vault.storedOn", { station: v.stationName })].join(" · ")} />}</span>}
        trailing={<NavButton icon={Edit} label={t("common.edit")} onClick={edit} />} />
      <ItemBody v={v} row={row} plain={plain} opened={opened} revealed={revealed} opening={opening} onShow={() => open(() => setRevealed(true))} />
    </div>
  );
}

/** A secret's page under its bar: in a library not locked (`plain`) that it is not encrypted, its content (masked until
 * `opened`; `onShow` opens it), how agents may use it, and when they did. */
function ItemBody({ v, row, plain, opened, revealed, opening, onShow }: {
  v: VaultRow; row: VaultItemRow; plain: boolean; opened: Opened | null; revealed: boolean; opening: boolean; onShow(): void;
}) {
  const app = useApp();
  const ws = app.entry.id;
  const uses = useVaultUses(ws, v.id, row.id);
  return (
    <>
      {plain && (
        <ListCard><div className={securityCss.mBody}>
          <div className={securityCss.mState}><span className={securityCss.mDot} data-tone="amber" />{t("web-pages.vault.risk.title")}</div>
          <span className={partsCss.mSubtle}>{<StationInWords station={v.station} text={t("web-pages.vault.risk.body", { station: v.stationName })} />}</span>
          <LinkButton label={t("web-pages.vault.lib.turnOn")} className={css.mStart} onClick={() => app.push(app.at("/settings/security"))} />
        </div></ListCard>
      )}
      <SectionHeader title={t("web-pages.vault.content")} start={24} />
      <ListCard>
        {opened
          ? <div className={securityCss.mBody}>{opened.shown.map((f) => <Secret key={f.key} label={f.label} value={f.value} secret={f.secret} mono={f.mono} revealed={revealed} />)}</div>
          : <div className={securityCss.mBody}><div className={css.mSecretLine}>
              <span className={`${css.mSecretValue} ${css.mMono}`}>{masked("x".repeat(20))}</span>
              <LinkButton label={t("web-pages.vault.show")} busy={opening} onClick={onShow} />
            </div></div>}
      </ListCard>
      <SectionHeader title={t("web-pages.vault.forAgents")} start={24} />
      <ListCard><div className={securityCss.mBody}>
        {row.listed ? (
          <dl className={css.mFacts}>
            <dt>{t("web-pages.vault.how")}</dt><dd>{row.howText}</dd>
            {row.env && <><dt>{t("web-pages.vault.editor.env")}</dt><dd className={css.mMono}>{row.env}</dd></>}
            <dt>{t("web-pages.vault.editor.lasts")}</dt><dd>{row.lastsText}</dd>
          </dl>
        ) : <span className={partsCss.mSubtle}>{t("web-pages.vault.notForAgents")}</span>}
      </div></ListCard>
      <SectionHeader title={t("web-pages.vault.uses.title")} start={24} />
      {!uses ? <Waiting sample={<ListCard><UseRows ws={ws} uses={SAMPLE_USES} /></ListCard>} /> : (
        <ListCard>
          {uses.uses.length === 0 ? <ListRow><span className={partsCss.mSubtle}>{t("web-pages.vault.uses.none")}</span></ListRow> : <UseRows ws={ws} uses={uses.uses} />}
        </ListCard>
      )}
      <div style={{ height: 30 }} />
    </>
  );
}

/** A secret's `uses`, a row each: the chat it was in (opening it), how, when; turned down, said. */
function UseRows({ ws, uses }: { ws: string; uses: VaultUse[] }) {
  const app = useApp();
  return uses.map((u, i) => (
    <ListRow key={i} onClick={u.station ? () => app.push(`${stationBase(`${ws}/${u.station}`)}/chats/${encodeURIComponent(u.session)}`) : undefined}>
      <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
        <span className={listsCss.mRowTitle}>{u.chatTitle ?? u.session}{u.denied && <span className={securityCss.mWarn}> · {t("web-pages.vault.uses.denied")}</span>}</span>
        <span className={`${listsCss.mRowNote} ${css.mMono}`}>{u.howText}</span>
      </span>
      <span className={listsCss.mRowNote}>{u.at.ago}</span>
    </ListRow>
  ));
}

