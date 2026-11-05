import { given, titleOf } from "../read/views.ts";
import type { Store } from "../store/store.ts";
import type { PhoneRequest } from "./grants.ts";

/// The grant is named by its original chat if that chat is still a member of the session.
export function grantChatTitle(store: Store, r: PhoneRequest): string | null {
  const slash = r.chat.indexOf("/");
  const own = slash < 0 ? null : store.sessionThread(r.session, r.chat.slice(0, slash), r.chat.slice(slash + 1))?.thread ?? null;
  if (own !== null) {
    const withoutText = titleOf(own, null, null);
    // A given name and a still.fail chat's name do not depend on the session's most recent chat.
    if (given(own) !== null || own.surface === "ember" || own.surface === "stillfail") return withoutText;
    const withText = titleOf(own, store.firstText(own.id), null);
    if (withText === withoutText) return withoutText;
    return store.sessionChat(r.session)?.thread.id === own.id ? withText : withoutText;
  }
  const latest = store.sessionChat(r.session);
  return latest === null ? null : titleOf(latest.thread, latest.firstText, null);
}
