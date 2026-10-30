// 设置 › 密钥 and 全部密钥 under it on the wide screen (and the desktop app): the workspace's vault as this device sees it
// (docs/vault.md), the app's pages' structure (apps/mbui sfdesk vault.mbt). What it is waiting for first (security mode
// on, this device confirmed in it, the vault turned on here: the recovery words shown that once), on either; then on 密钥
// the requests waiting on the viewer, a row to 全部密钥, how it keeps its secrets (a row each on one list card), deleting
// the vault at the foot; on 全部密钥 the profiles' accounts and each vault's items, a section a kind, and adding. An
// item opens on a page of its own, and is edited in a dialog. A web page only lists the names it is told. All of it is
// the core's (`vaults`, `vaultItems`, `vault.*`; ../vault.ts): this only draws.
import { useState, type ReactNode } from "react";
import { Link, useNavigate } from "react-router";
import { ChevronDown, ChevronRight, ChevronUp, Copy, Devices, Eye, FileText, Key, Plus, Server, ShieldCheck, User } from "@stillfail/ui/icons.tsx";
import { useToast } from "@stillfail/ui/toast.tsx";
import { useDoing } from "../doing.ts";
import { BackLink, Button, Confirm, Dialog, Field, IconButton, Menu, MobileBack, ProviderLogo, Section, Segmented, SwitchRow, Spinner, Waiting } from "../ui.tsx";
import { useProfiles, useStations } from "../api.ts";
import { profilePath } from "../ProfilesNav.tsx";
import { addProfilePath } from "../pages/AddProfile.tsx";
import { AddKinds } from "../VaultAdd.tsx";
import { stationBase } from "../station.tsx";
import { VaultActions } from "../VaultApproval.tsx";
import { AskCard } from "../VaultAsk.tsx";
import {
  KINDS, LASTS, SCOPES, scopeOf, blankForm, copySecret, itemPath, lastsChoice, lastsName, fileSize, formOf, formProblem, kindName, masked, modeName, modesOf, pickInto, putOf, useForm,
  useVaultCall, useVaultItems, useVaults, useVaultsItems, type Form, type Kind, type Mode, type Opened, type VaultItemRow, type VaultRequest, type VaultRow, type VaultsView,
} from "../vault.ts";
import { sampleVaultItems, sampleVaults } from "../samples.ts";
import { t } from "../i18n.ts";
import type { WorkspaceEntry } from "./workspace.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import * as css from "./Vault.css.ts";

const KIND_ICON = { token: Key, ssh_key: Server, login: User, file: FileText } as const;

export function KindIcon({ kind, size = 16 }: { kind: string | undefined; size?: number }) {
  const Icon = KIND_ICON[kind as Kind] ?? Key;
  return <Icon size={size} strokeWidth={1.6} />;
}

/** 设置 › 密钥. */
export function VaultSettings({ entry }: { entry: WorkspaceEntry }) {
  const { view, first } = useFirst(entry, <Library entry={entry} view={SAMPLE_VAULTS} />);
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={`/w/${entry.id}/settings`} label={t("web-pages.settings.title")} />
      <header className={pagesCss.pageHead}>
        <div><h1>{t("web-pages.vault.title")}</h1><p className={css.sub}>{t("web-pages.vault.lead")}</p></div>
      </header>
      {first ?? <Library entry={entry} view={view!} />}
    </div>
  );
}

/** 设置 › 密钥 › 全部密钥: what the library keeps, 添加 at its head; what has to come first, as on 密钥. */
export function VaultAll({ entry }: { entry: WorkspaceEntry }) {
  const { view, first } = useFirst(entry, <All entry={entry} view={SAMPLE_VAULTS} adding={false} onAdded={() => undefined} />);
  const [adding, setAdding] = useState(false);
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <BackLink to={`/w/${entry.id}/settings/vault`} label={t("web-pages.vault.title")} />
      <header className={pagesCss.pageHead}>
        <div><h1>{t("web-pages.vault.all")}</h1></div>
        {!first && <Button variant="ghost" icon={Plus} onClick={() => setAdding(true)}>{t("web-pages.vault.add")}</Button>}
      </header>
      {first ?? <All entry={entry} view={view!} adding={adding} onAdded={() => setAdding(false)} />}
    </div>
  );
}

/** What 密钥 and 全部密钥 show before the library: waiting for the core (the page as it will be, `sample`, in its bones);
 * the recovery words to write down; a web page's names; what has to come first. `first` null where the library is there
 * to be used (in plain text on the station, or locked, signed and set up here). */
function useFirst(entry: WorkspaceEntry, sample: ReactNode): { view: VaultsView | undefined; first: ReactNode | null } {
  const view = useVaults(entry.id);
  // The recovery words, the once the core gives them (`vault.setup`): shown until they are written down.
  const [words, setWords] = useState<string[] | null>(null);
  const first = !view ? <Waiting sample={sample} />
    : words ? <Words words={words} onDone={() => setWords(null)} />
    : view.plain === true ? null
    : !view.available ? <ReadOnly entry={entry} view={view} />
    : !view.locked ? <Gate entry={entry} title={t("web-pages.vault.needsLock")} why={t("web-pages.vault.needsLockWhy")} />
    : !view.canSign ? <Gate entry={entry} title={t("web-pages.vault.notSigner")} why={t("web-pages.vault.notSignerWhy")} />
    : !view.setUp ? <SetUp entry={entry} onWords={setWords} />
    : null;
  return { view, first };
}

/** The vault and its secrets made up, for what its pages show while they are read (in their bones). */
const SAMPLE_VAULTS = sampleVaults();
const SAMPLE_ITEMS = sampleVaultItems();

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
  // (the person's own vault made with it when they have none) The first device sets the words; one set up after takes
  // the person's (none shown): straight on.
  const setUp = () => void run<{ words: string | null }>("vault.setup", { workspace: entry.id }, t("web-pages.vault.setUpWhat")).then((r) => {
    if (r?.words) onWords(r.words.trim().split(/\s+/));
  });
  return (
    <div className={pagesCss.card}>
      <div className={css.state}>{t("web-pages.vault.setUpTitle")}</div>
      <div className={css.points}>
        <Point icon={Devices} title={t("web-pages.vault.point.ask")} how={t("web-pages.vault.point.askHow")} />
        <Point icon={ShieldCheck} title={t("web-pages.vault.point.proxy")} how={t("web-pages.vault.point.proxyHow")} />
        <Point icon={Server} title={t("web-pages.vault.point.zero")} how={t("web-pages.vault.point.zeroHow")} />
      </div>
      <div className={css.actions}><Button variant="primary" busy={settingUp} onClick={setUp}>{t("web-pages.vault.setUp")}</Button></div>
    </div>
  );
}

function Point({ icon: Icon, title, how }: { icon: typeof Key; title: string; how: string }) {
  return <div className={css.point}><Icon size={18} strokeWidth={1.6} className={css.pointIcon} /><span>{title}<span className={css.sub}>{how}</span></span></div>;
}

/** The 24 words, numbered in three columns, the once they are shown; written down, the person's vault is made (if
 * they have none). */
function Words({ words, onDone }: { words: string[]; onDone(): void }) {
  return (
    <div className={pagesCss.card}>
      <div className={css.state}>{t("web-pages.vault.words.title")}</div>
      <p className={css.sub}>{t("web-pages.vault.words.lead")}</p>
      <ol className={css.words}>{words.map((w, i) => <li key={i} className={css.word}><span className={css.wordN}>{i + 1}</span>{w}</li>)}</ol>
      <div className={css.actions}>
        <span className={css.note}>{t("web-pages.vault.words.once")}</span>
        <span className={css.grow} />
        <Button variant="primary" onClick={onDone}>{t("web-pages.vault.words.done")}</Button>
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

/** The library (docs/vault.md 一个库), as the app's page (apps/mbui sfdesk vault.mbt): the requests waiting on the
 * viewer, each one's card as in its chat; a row to 全部密钥; how it keeps its secrets, a row each on one list card;
 * deleting the person's vault in red at the foot. */
function Library({ entry, view }: { entry: WorkspaceEntry; view: VaultsView }) {
  const run = useVaultCall();
  const creating = useDoing("vault.create", { workspace: entry.id });
  const plain = view.plain === true;
  const mine = view.vaults.find((v) => v.mine);
  const many = view.vaults.length > 1;
  return (
    <>
      {view.requests.length > 0 && (
        <Section title={<>{t("web-pages.vault.requests")} <span className={css.count}>{view.requests.length}</span></>}>
          <div className={css.requests}>{view.requests.map((r) => <Request key={r.id} entry={entry} r={r} />)}</div>
        </Section>
      )}
      {view.vaults.length === 0 && !plain && (
        <div className={pagesCss.card}>
          <p className={css.sub}>{t("web-pages.vault.none")}</p>
          <div className={css.actions}><Button variant="primary" busy={creating}
            onClick={() => void run("vault.create", { workspace: entry.id, name: t("web-pages.vault.personal") }, t("web-pages.vault.createWhat"))}>{t("web-pages.vault.setUp")}</Button></div>
        </div>
      )}
      {!plain && view.vaults.filter((v) => !v.keyed).map((v) => <NoKey key={v.id} entry={entry} v={v} />)}
      <ul className={pagesCss.list}>
        <li>
          <Link className={`${pagesCss.listRow} ${css.rowButton}`} to={`/w/${entry.id}/settings/vault/all`}>
            <span className={pagesCss.listRowTitle}>{t("web-pages.vault.all")}</span>
            <span className={css.grow} />
            <ChevronRight size={14} className={css.chevron} />
          </Link>
        </li>
      </ul>
      <Kept entry={entry} view={view} />
      {!plain && mine && <ul className={pagesCss.list}>{view.vaults.filter((v) => v.mine).map((v) => <DeleteVault key={v.id} entry={entry} v={v} many={many} />)}</ul>}
    </>
  );
}

/** 全部密钥, as a password manager's list (the user, 2026-10-26: a section a kind of one row each was 「信息密度极低，找也
 * 找不到有意义的东西」; apps/mbui sfdesk vault.mbt vault_all): a field to find one by any of its words; then every one on
 * one list, a row each: its mark (the profile's service, a secret's kind), its name, and under it its kind and what is
 * worth knowing of it (an account's station and what is wrong with it; a secret's way to an agent and its last
 * use, the core's lineText), each leading to its page: each vault's secrets (a vault this device has no key to, the
 * names it is told, going nowhere), locked, a row of those it does not name; then the profiles' accounts on a list of
 * their own, folded under a row naming them (seen on the profiles' pages first: the user, 2026-10-26), open where
 * what is looked for is among them. Adding to it. */
function All({ entry, view, adding, onAdded }: { entry: WorkspaceEntry; view: VaultsView; adding: boolean; onAdded(): void }) {
  const navigate = useNavigate();
  const plain = view.plain === true;
  const mine = view.vaults.find((v) => v.mine);
  const [editing, setEditing] = useState<Kind | null>(null);
  const [find, setFind] = useState("");
  // (the profiles' accounts folded at the foot: seen on the profiles' pages first)
  const [opened, setOpened] = useState(false);
  const stations = useStations(entry.id).value ?? [];
  const online = stations.filter((s) => s.online);
  const profiles = useProfiles(entry.id).value;
  const lists = useVaultsItems(entry.id, view.vaults.map((v) => v.id));
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
      <div className={css.find}>
        <input className={controlsCss.input} type="search" value={find} onChange={(e) => setFind(e.target.value)} placeholder={t("web-pages.vault.find")} aria-label={t("web-pages.vault.find")} />
      </div>
      <Secrets entry={entry} secrets={secrets} unnamed={unnamed} plain={plain} many={many} />
      {/* The accounts, folded under a row naming them (open where what is looked for is among them). */}
      {accounts.length > 0 && (
        <ul className={pagesCss.list}>
          <li>
            <button type="button" className={`${pagesCss.listRow} ${css.rowButton}`} aria-expanded={open} disabled={q !== ""} onClick={() => setOpened(!opened)}>
              <span className={css.rowIcon} />
              <span className={pagesCss.listRowText}>
                <span className={pagesCss.listRowTitle}>{t("web-pages.vault.accounts")}</span>
                {!open && <span className={css.rowMeta}>{accounts.map((e) => e.title).join("、")}</span>}
              </span>
              {open ? <ChevronUp size={14} className={css.chevron} /> : <ChevronDown size={14} className={css.chevron} />}
            </button>
          </li>
          {open && accounts.map((e) => (
            <li key={e.key}>
              <Link className={`${pagesCss.listRow} ${css.rowButton}`} to={profilePath(e)}>
                <span className={css.rowIcon}><ProviderLogo runtime={e.profile.runtime} kind={e.profile.access.kind} mark={e.profile.providerMark} size={16} /></span>
                <span className={pagesCss.listRowText}>
                  <span className={pagesCss.listRowTitle}>{e.title}</span>
                  <span className={css.rowMeta}>{said(e.groupTitle, e.where)}</span>
                  {e.profile.checkTone === "red" && <span className={css.bad}>{e.profile.checkText}</span>}
                </span>
                <ChevronRight size={14} className={css.chevron} />
              </Link>
            </li>
          ))}
        </ul>
      )}
      {reading ? <Waiting sample={<Secrets entry={entry} secrets={SAMPLE_ITEMS.map((row) => ({ v: SAMPLE_VAULTS.vaults[0]!, row }))} unnamed={[]} plain={false} many={false} />} />
        : q !== "" && accounts.length + secrets.length === 0 ? <p className={css.note}>{t("web-pages.vault.noMatch", { q: find.trim() })}</p>
        : (profiles?.items.length ?? 0) + secrets.length + unnamed.length === 0 && <p className={css.note}>{t("web-pages.vault.empty")}</p>}
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

/** 全部密钥's secrets, a row each (`secrets`, each with its vault), and a row for each vault's unnamed ones, to unlock it. */
function Secrets({ entry, secrets, unnamed, plain, many }: {
  entry: WorkspaceEntry; secrets: { v: VaultRow; row: VaultItemRow }[]; unnamed: { v: VaultRow; hidden: VaultItemRow[] }[]; plain: boolean; many: boolean;
}) {
  const run = useVaultCall();
  if (secrets.length + unnamed.length === 0) return null;
  // (a row's line: what is said of it, those words that are not empty, a dot between)
  const said = (...words: (string | null | undefined)[]) => words.filter((w) => w).join(" · ");
  return (
    <ul className={pagesCss.list}>
      {secrets.map(({ v, row }) => {
        const keyed = plain || v.keyed;
        const body = <>
          <span className={css.rowIcon}><KindIcon kind={row.kind ?? undefined} /></span>
          <span className={pagesCss.listRowText}>
            <span className={pagesCss.listRowTitle}>{row.name}</span>
            {/* (its kind, its vault where there are more than one; the core's: how an agent gets it, when and where it was
                last used) */}
            <span className={css.rowMeta}>{said(row.kindText, many ? v.name : null, keyed ? row.lineText : row.agentText)}</span>
          </span>
        </>;
        return (
          <li key={`${v.id}/${row.id}`}>
            {keyed ? <Link className={`${pagesCss.listRow} ${css.rowButton}`} to={itemPath(entry.id, v.id, row.id)}>{body}<ChevronRight size={14} className={css.chevron} /></Link>
              : <div className={pagesCss.listRow}>{body}</div>}
          </li>
        );
      })}
      {/* (unlocked by opening one of them: the vault's key kept a while, every name shown) */}
      {unnamed.map(({ v, hidden }) => (
        <li key={`${v.id}/hidden`}>
          {plain || v.keyed
            ? <button type="button" className={`${pagesCss.listRow} ${css.rowButton}`} onClick={() => void run("vault.open", { workspace: entry.id, item: hidden[0]!.id }, t("web-pages.vault.unlockWhat"))}>
                <span className={css.rowIcon} />
                <span className={pagesCss.listRowTitle}>{t("web-pages.vault.hidden", { n: hidden.length })}</span>
                <span className={css.link}>{t("web-pages.vault.unlock")}</span>
              </button>
            : <div className={pagesCss.listRow}><span className={css.rowIcon} /><span className={css.rowMeta}>{t("web-pages.vault.hidden", { n: hidden.length })}</span></div>}
        </li>
      ))}
    </ul>
  );
}

/** A request waiting on the viewer (to use an item, or to keep one): its card, as in its chat, and a way to that chat. */
function Request({ entry, r }: { entry: WorkspaceEntry; r: VaultRequest }) {
  const go = useNavigate();
  const chat = r.station ? `${stationBase(`${entry.id}/${r.station}`)}/chats/${encodeURIComponent(r.session)}` : null;
  return (
    <AskCard fill ask={{ name: r.itemName ?? r.item, mode: r.mode, command: r.command, save: r.save }}>
      <VaultActions workspace={entry.id} id={r.id} extra={chat && <Button variant="ghost" onClick={() => go(chat)}>{t("web-pages.vault.openChat")}</Button>} />
    </AskCard>
  );
}

/** A vault this device has no key to, under its name: that it has none, and the recovery words typed where they can
 * give it one. */
function NoKey({ entry, v }: { entry: WorkspaceEntry; v: VaultRow }) {
  const [recovering, setRecovering] = useState(false);
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

/** How the library keeps its secrets, a row each on one list card (as a page's own settings stand first): encrypted, or
 * in plain text on the station (the way to security mode at its end), unlocked here a while (locked again from its
 * end); those still in plain text from before (encrypted from its end); the longest an approval lasts (picked from a
 * menu, each with what it means); the devices holding each vault's key (given to new ones from its end). A row that
 * does something does it pressed, saying what at its end (ActionRow); what is not as it should be said in amber. */
function Kept({ entry, view }: { entry: WorkspaceEntry; view: VaultsView }) {
  const run = useVaultCall();
  const toast = useToast();
  const navigate = useNavigate();
  const locking = useDoing("vault.lock", { workspace: entry.id });
  const moving = useDoing("vault.migrate", { workspace: entry.id });
  const plain = view.plain === true;
  const open = view.vaults.some((v) => v.open);
  const left = view.plainLeft ?? 0;
  const mine = view.vaults.find((v) => v.mine);
  const migrate = () => void run<{ moved: number; left: number }>("vault.migrate", { workspace: entry.id }, t("web-pages.vault.migrate.what")).then((r) => {
    if (r) toast(r.left > 0 ? t("web-pages.vault.migrate.partly", { n: r.moved, left: r.left }) : t("web-pages.vault.migrate.done", { n: r.moved }));
  });
  return (
    <ul className={pagesCss.list}>
      {plain ? <ActionRow title={t("web-pages.vault.lib.plain")} note={t("web-pages.vault.lib.plainWhy")} warn
          action={t("web-pages.vault.lib.turnOn")} onPress={() => navigate(`/w/${entry.id}/settings/security`)} />
        : open ? <ActionRow title={t("web-pages.vault.lib.sealed")} note={t("web-pages.vault.opened")} action={t("web-pages.vault.lockNow")} busy={locking}
          onPress={() => void run("vault.lock", { workspace: entry.id }, t("web-pages.vault.lockNow"))} />
        : <li className={pagesCss.listRow}><RowWords title={t("web-pages.vault.lib.sealed")} note={t("web-pages.vault.lib.sealedWhy")} /></li>}
      {!plain && left > 0 && <ActionRow title={t("web-pages.vault.migrate.title", { n: left })} note={t("web-pages.vault.migrate.body")} warn
        action={t("web-pages.vault.migrate.go")} busy={moving} onPress={migrate} />}
      {mine && <LastsRow entry={entry} v={mine} />}
      {!plain && view.vaults.map((v) => <DevicesRow key={v.id} entry={entry} v={v} many={view.vaults.length > 1} />)}
    </ul>
  );
}

/** A row that does one thing (as 解锁's: LibraryVault): pressed anywhere, it does it; what it does, in the link's ink,
 * at its end (a spinner while it is done). */
function ActionRow({ title, note, warn = false, action, busy = false, onPress }: { title: string; note: string; warn?: boolean; action: string; busy?: boolean; onPress(): void }) {
  return (
    <li>
      <button type="button" className={`${pagesCss.listRow} ${css.rowButton}`} disabled={busy} onClick={onPress}>
        <RowWords title={title} note={note} warn={warn} />
        {busy ? <Spinner inline /> : <span className={css.link}>{action}</span>}
      </button>
    </li>
  );
}

/** A row's words: what it is, how it stands under it (in amber where it is not as it should be). */
function RowWords({ title, note, warn = false }: { title: string; note: string; warn?: boolean }) {
  return (
    <span className={pagesCss.listRowText}>
      <span className={pagesCss.listRowTitle}>{title}</span>
      <span className={warn ? css.warn : css.rowMeta}>{note}</span>
    </span>
  );
}

/** The longest an agent's request for the person's secrets is approved for, where a secret does not say its own: the
 * one now under it; pressed, the choices, each with what it means. */
function LastsRow({ entry, v }: { entry: WorkspaceEntry; v: VaultRow }) {
  const run = useVaultCall();
  const setting = useDoing("vault.setLasts", { workspace: entry.id, vault: v.id });
  const now = scopeOf(v.lasts);
  return (
    <li>
      <Menu label={t("web-pages.vault.lasts.title")}
        trigger={<button type="button" className={pagesCss.listRow} disabled={setting}>
          <RowWords title={t("web-pages.vault.lasts.title")} note={lastsName(now)} />
          {setting ? <Spinner inline /> : <ChevronRight size={14} className={css.chevron} />}
        </button>}
        items={SCOPES.map((s) => ({
          label: lastsName(s), note: t(`web-pages.vault.lasts.${s}Detail`), checked: s === now,
          onSelect: () => { if (s !== now) void run("vault.setLasts", { workspace: entry.id, vault: v.id, lasts: s }, t("web-pages.vault.lasts.what")); },
        }))} />
    </li>
  );
}

/** The devices holding a vault's key (its name where there are more than one): how many; where some new ones have none
 * yet, how many, in amber, given it from its end by its owner's device holding it (done by itself as the owner's
 * device next has the key in hand). */
function DevicesRow({ entry, v, many }: { entry: WorkspaceEntry; v: VaultRow; many: boolean }) {
  const run = useVaultCall();
  const adding = useDoing("vault.addDevice", { workspace: entry.id, vault: v.id });
  const title = many ? v.name : t("web-pages.security.devices");
  if (v.missing > 0 && v.mine && v.keyed) {
    return <ActionRow title={title} note={t("web-pages.vault.missing", { n: v.missing })} warn action={t("web-pages.vault.addDevice")} busy={adding}
      onPress={() => void run("vault.addDevice", { workspace: entry.id, vault: v.id }, t("web-pages.vault.addDeviceWhat"), t("web-pages.vault.addedDevice"))} />;
  }
  return (
    <li className={pagesCss.listRow}>
      <RowWords title={title} warn={v.missing > 0} note={v.missing > 0 ? t("web-pages.vault.missing", { n: v.missing }) : t("web-pages.vault.devicesHold", { n: v.devices })} />
    </li>
  );
}

/** Deleting a vault of the person's own (its name after where there are more than one), in red: asked first, saying
 * what goes with it. */
function DeleteVault({ entry, v, many }: { entry: WorkspaceEntry; v: VaultRow; many: boolean }) {
  const run = useVaultCall();
  const deleting = useDoing("vault.delete", { workspace: entry.id, vault: v.id });
  const [asking, setAsking] = useState(false);
  return (
    <li>
      <button type="button" className={pagesCss.listRow} disabled={deleting} onClick={() => setAsking(true)}>
        <span className={`${pagesCss.listRowTitle} ${css.danger}`}>{t("web-pages.vault.deleteVault")}{many ? ` · ${v.name}` : ""}</span>
        {deleting && <Spinner inline />}
      </button>
      <Confirm open={asking} onClose={() => setAsking(false)} title={t("web-pages.vault.deleteTitle", { name: v.name })} action={t("common.delete")}
        description={v.items > 0 ? t("web-pages.vault.deleteVaultBody", { n: v.items }) : t("web-pages.vault.deleteVaultEmpty")}
        onConfirm={() => { setAsking(false); void run("vault.delete", { workspace: entry.id, vault: v.id }, t("web-pages.vault.deleteWhat"), t("web-pages.vault.deleted")); }} />
    </li>
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
      ) : !items ? <Waiting sample={<ul className={pagesCss.list}>{SAMPLE_ITEMS.map((row) => <ItemRow key={row.id} entry={entry} row={row} readOnly onOpen={() => undefined} />)}</ul>} />
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
      <span className={css.rowMeta}>{row.agentText}</span>
    </span>
    {opening && <Spinner inline />}
  </>;
  return <li>{readOnly ? <div className={pagesCss.listRow}>{body}</div>
    : <button type="button" className={`${pagesCss.listRow} ${css.rowButton}`} disabled={opening} onClick={onOpen}>{body}</button>}</li>;
}

/** An item opened: its fields (masked; shown, copied), how agents may ask for it, and editing it. */
function ItemDialog({ opened, row, onClose, onEdit }: { opened: Opened; row: VaultItemRow | undefined; onClose(): void; onEdit(): void }) {
  const p = opened.plain;
  return (
    <Dialog open title={p.name} description={opened.kindText} onClose={onClose}
      footer={<><span className={css.grow} /><Button variant="primary" onClick={onEdit}>{t("common.edit")}</Button></>}>
      <div className={css.fields}>{opened.shown.map((f) => <Secret key={f.key} label={f.label} value={f.value} secret={f.secret} mono={f.mono} />)}</div>
      <div className={css.agentBox}>
        <span className={css.fieldLabel}>{t("web-pages.vault.forAgents")}</span>
        {row?.listed
          ? <span>{row.howText}{row.env ? <> · <code className={css.mono}>{row.env}</code></> : null}</span>
          : <span className={css.rowMeta}>{t("web-pages.vault.notForAgents")}</span>}
      </div>
    </Dialog>
  );
}

/** A field of an item: masked until shown (a while), copied as it is. `revealed`: opened to be seen, shown at once. */
export function Secret({ label, value, secret, mono, revealed = false }: { label: string; value: string; secret: boolean; mono: boolean; revealed?: boolean }) {
  const toast = useToast();
  const [shown, setShown] = useState(!secret || revealed);
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
  const toast = useToast();
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
        {input("name", t("web-pages.vault.editor.name"), { placeholder: t(f.kind === "file" ? "web-pages.vault.editor.fileNamePlaceholder" : "web-pages.vault.editor.namePlaceholder") })}
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
        {f.kind === "file" && (
          <Field label={t("web-pages.vault.editor.file")}>
            <div className={css.fileLine}>
              <Button variant="secondary" onClick={() => void pickInto(change, toast)}>{t("web-pages.vault.editor.pickFile")}</Button>
              {f.fileContent && <span className={css.fileName}>{f.fileName || t("web-pages.vault.kind.file")} · {fileSize(f.fileContent)}</span>}
            </div>
          </Field>
        )}
        <div className={css.agentBox}>
          <SwitchRow title={t("web-pages.vault.editor.agent")} description={t("web-pages.vault.editor.agentNote")} checked={f.agent} onChange={(agent) => change({ agent })} />
          {f.agent && <>
            <Field label={t("web-pages.vault.editor.how")}>
              {modes.length > 1
                ? <div><Segmented label={t("web-pages.vault.editor.how")} value={f.mode} onChange={(mode) => change({ mode: mode as Mode })} options={modes.map((m) => ({ value: m, label: modeName(m) }))} /></div>
                : <span>{modeName(modes[0]!)}</span>}
            </Field>
            <p className={css.note}>{f.kind === "ssh_key" ? t("web-pages.vault.editor.sshNote") : f.kind === "file" ? t("web-pages.vault.editor.fileNote") : f.mode === "proxy" ? t("web-pages.vault.editor.proxyNote") : t("web-pages.vault.editor.envNote")}</p>
            {f.kind !== "ssh_key" && f.mode === "proxy" && input("hosts", t("web-pages.vault.editor.hosts"), { placeholder: t("web-pages.vault.editor.hostsPlaceholder"), error: problem === "hosts" && f.hosts !== "" ? t("web-pages.vault.editor.hostsNeeded") : undefined })}
            {f.kind !== "ssh_key" && input("env", t("web-pages.vault.editor.env"), { mono: true, placeholder: t(f.kind === "file" ? "web-pages.vault.editor.fileEnvPlaceholder" : "web-pages.vault.editor.envPlaceholder") })}
            <Field label={t("web-pages.vault.editor.lasts")}>
              <div><Segmented label={t("web-pages.vault.editor.lasts")} value={f.lasts} onChange={(lasts) => change({ lasts })} options={LASTS.map((l) => ({ value: l, label: lastsChoice(l) }))} /></div>
            </Field>
            <p className={css.note}>{t("web-pages.vault.editor.lastsNote")}</p>
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
