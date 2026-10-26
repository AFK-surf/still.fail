// A secret's page (设置 › 密钥 › 全部密钥 › it), as a profile's is (pages/Accounts.tsx): what it is and where it is kept, in a library not locked that it is not encrypted and the way to
// lock it (docs/vault.md 不加锁的库), its content masked until shown, how agents may use it, and when they did (the
// station's record of it: the core's `vaultUses`).
import { useState } from "react";
import { Link, useParams } from "react-router";
import { Edit, Eye } from "@stillfail/ui/icons.tsx";
import { useDoing } from "../doing.ts";
import { BackLink, Button, IconButton, Pill, Section, Spinner, Time, Waiting } from "../ui.tsx";
import { stationBase } from "../station.tsx";
import { Editor, KindIcon, Secret } from "./Vault.tsx";
import { formOf, useVaultCall, useVaultItems, useVaultUses, useVaults, type Opened, type VaultItemRow, type VaultRow, type VaultUse } from "../vault.ts";
import { sampleVaultItems, sampleVaults, sampleVaultUses } from "../samples.ts";
import { t } from "../i18n.ts";
import { StationInWords } from "../StationNamed.tsx";
import type { WorkspaceEntry } from "./workspace.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as css from "./Vault.css.ts";

export function VaultItemPage({ entry }: { entry: WorkspaceEntry }) {
  const { vault = "", item = "" } = useParams();
  const view = useVaults(entry.id);
  const items = useVaultItems(entry.id, vault);
  const v = view?.vaults.find((x) => x.id === vault);
  const row = items?.items.find((i) => i.id === item);
  const back = <BackLink to={`/w/${entry.id}/settings/vault/all`} label={t("web-pages.vault.all")} />;
  if (!view || !items) {
    return <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>{back}<Waiting sample={<ItemShown entry={entry} v={SAMPLE_VAULT} row={SAMPLE_ITEM} plain={false} />} /></div>;
  }
  if (!v || !row) return <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>{back}<p className={css.note}>{t("web-pages.vault.empty")}</p></div>;
  return <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>{back}<ItemShown entry={entry} v={v} row={row} plain={view.plain === true} /></div>;
}

/** A secret made up, in its vault, and its uses, for what its page shows while they are read (in their bones). */
const SAMPLE_VAULT = sampleVaults().vaults[0]!;
const SAMPLE_ITEM = sampleVaultItems()[0]!;
const SAMPLE_USES = sampleVaultUses();

/** A secret's page under its way back: `row`, kept in `v` (`plain`: a library not locked). */
function ItemShown({ entry, v, row, plain }: { entry: WorkspaceEntry; v: VaultRow; row: VaultItemRow; plain: boolean }) {
  const vault = v.id, item = row.id;
  const uses = useVaultUses(entry.id, vault, item);
  const run = useVaultCall();
  const [opened, setOpened] = useState<Opened | null>(null);
  // The field whose eye opened it: shown as it opens, not masked again for a second press.
  const [reveal, setReveal] = useState<string | null>(null);
  const [editing, setEditing] = useState(false);
  const opening = useDoing("vault.open", { workspace: entry.id, item });
  const open = (then?: (o: Opened) => void) => void run<Opened>("vault.open", { workspace: entry.id, item }, t("web-pages.vault.openWhat")).then((o) => {
    if (!o) return;
    setOpened(o);
    then?.(o);
  });
  return (
    <>
      <header className={pagesCss.identity}>
        <span className={pagesCss.mark} style={{ width: 48, height: 48 }}><KindIcon kind={row.kind} size={24} /></span>
        <div className={pagesCss.identityText}>
          <h1 className={pagesCss.identityName}>{row.name}</h1>
          <p className={pagesCss.identitySub}>{<StationInWords station={v.station} text={[row.kindText, t("web-pages.vault.storedOn", { station: v.stationName })].join(" · ")} />}</p>
        </div>
        <Button variant="ghost" icon={Edit} busy={opening && editing} onClick={() => (opened ? setEditing(true) : open(() => setEditing(true)))}>{t("common.edit")}</Button>
      </header>

      {plain && (
        <div className={`${pagesCss.card} ${css.lead}`}>
          <div className={css.state}><span className={css.riskTitle}>{t("web-pages.vault.risk.title")}</span></div>
          <p className={css.sub}>{<StationInWords station={v.station} text={t("web-pages.vault.risk.body", { station: v.stationName })} />}</p>
          <div className={css.actions}><Link to={`/w/${entry.id}/settings/security`}><Button variant="primary">{t("web-pages.vault.lib.turnOn")}</Button></Link></div>
        </div>
      )}

      {/* Each field's eye where its value is, before it is opened as after: pressed, it opens and shows that field. */}
      <Section title={t("web-pages.vault.content")}>
        <div className={css.fields}>
          {opened
            ? opened.shown.map((f) => <Secret key={f.key} label={f.label} value={f.value} secret={f.secret} mono={f.mono} revealed={f.key === reveal} />)
            : (row.shut ?? []).map((f) => (
              <div key={f.key} className={css.secret}>
                <span className={css.fieldLabel}>{f.label}</span>
                <div className={css.secretLine}>
                  <span className={`${css.secretValue} ${css.mono}`}>{f.value}</span>
                  {opening && !editing ? <Spinner inline /> : <IconButton label={t("web-pages.vault.show")} icon={Eye} onClick={() => open(() => setReveal(f.key))} />}
                </div>
              </div>
            ))}
        </div>
      </Section>

      <Section title={t("web-pages.vault.forAgents")}>
        {row.listed ? (
          <dl className={css.facts}>
            <dt>{t("web-pages.vault.how")}</dt><dd>{row.howText}</dd>
            {row.env && <><dt>{t("web-pages.vault.editor.env")}</dt><dd><code className={css.mono}>{row.env}</code></dd></>}
            <dt>{t("web-pages.vault.editor.lasts")}</dt><dd>{row.lastsText}</dd>
          </dl>
        ) : <p className={css.note}>{t("web-pages.vault.notForAgents")}</p>}
      </Section>

      <Section title={t("web-pages.vault.uses.title")}>
        {!uses ? <Waiting sample={<div className={css.uses}>{SAMPLE_USES.map((u, i) => <UseRow key={i} workspace={entry.id} use={u} />)}</div>} />
          : uses.uses.length === 0 ? <p className={css.note}>{t("web-pages.vault.uses.none")}</p>
          : <div className={css.uses}>{uses.uses.map((u, i) => <UseRow key={i} workspace={entry.id} use={u} />)}</div>}
      </Section>

      {editing && opened && <Editor workspace={entry.id} vault={vault} first={formOf(opened, row)} id={opened.id} plain={plain}
        onClose={() => { setEditing(false); setOpened(null); setReveal(null); }} />}
    </>
  );
}

/** A use: the chat it was in (its link), how (the command, or the mode), when; turned down, said. */
function UseRow({ workspace, use }: { workspace: string; use: VaultUse }) {
  const chat = use.chatTitle ?? use.session;
  return (
    <div className={css.use}>
      <div className={css.useText}>
        <span className={css.rowName}>
          {use.station ? <Link className={css.chatLink} to={`${stationBase(`${workspace}/${use.station}`)}/chats/${encodeURIComponent(use.session)}`}>{chat}</Link> : chat}
          {use.denied && <Pill tone="red">{t("web-pages.vault.uses.denied")}</Pill>}
        </span>
        <span className={`${css.rowMeta} ${use.command ? css.mono : ""}`}>{use.howText}</span>
      </div>
      <span className={css.useTime}><Time stamp={use.at} fixed /></span>
    </div>
  );
}
