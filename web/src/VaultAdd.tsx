// What 添加 in the library offers (ProfilesNav.tsx, the phone's list): a subscription or a model's key (a profile, made
// on a station: pages/AddProfile.tsx), or a secret for agents (a vault's item: cloud/Vault.tsx Editor). In a library
// not locked, that a secret is kept in plain text is said with it (docs/vault.md 不加锁的库).
import { Quota } from "@stillfail/ui/icons.tsx";
import { ICON } from "./ui.tsx";
import { KindIcon } from "./cloud/Vault.tsx";
import { ITEM_SECTIONS, type Kind } from "./vault.ts";
import { t } from "./i18n.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as accountsCss from "./pages/Accounts.css.ts";
import * as css from "./cloud/Vault.css.ts";

export type AddKind = "profile" | Kind;

/** `secrets`: the viewer has a vault to put one in. */
export function AddKinds({ secrets, plain, onPick }: { secrets: boolean; plain: boolean; onPick(kind: AddKind): void }) {
  const kinds: AddKind[] = ["profile", ...(secrets ? ITEM_SECTIONS : [])];
  return (
    <>
      <ul className={pagesCss.list}>
        {kinds.map((k) => (
          <li key={k}>
            <button type="button" className={`${pagesCss.listRow} ${accountsCss.pickRow}`} onClick={() => onPick(k)}>
              <span className={css.rowIcon}>{k === "profile" ? <Quota {...ICON} /> : <KindIcon kind={k} />}</span>
              <span className={pagesCss.listRowText}>
                <span className={pagesCss.listRowTitle}>{t(`web-pages.vault.addKind.${k}`)}</span>
                <span className={css.rowMeta}>{t(`web-pages.vault.addKind.${k}Detail`)}</span>
              </span>
            </button>
          </li>
        ))}
      </ul>
      {plain && secrets && <p className={css.warn}>{t("web-pages.vault.risk.editor")}</p>}
    </>
  );
}
