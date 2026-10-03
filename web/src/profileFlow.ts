// The add-profile pages' state is the core's (client/core-ts/src/forms.ts): what is picked and typed, what each step
// shows, what the profile will be usable for. A page opens its draft, names what changed and submits; it draws what
// the core says.
import { useEffect, useId } from "react";
import { useCall, useTopic } from "./core/react.ts";
import type { ProfileFlowView } from "./core/shapes.ts";
import { useDoing } from "./doing.ts";
import { useAct } from "./toast.tsx";
import { t } from "./i18n.ts";

export function useProfileFlow(station: string) {
  const form = useId();
  const call = useCall();
  const act = useAct();
  const state = useTopic<ProfileFlowView | null>({ topic: "profileFlow", station, form });
  const submitting = useDoing("profile.flow.submit", { station, form });
  useEffect(() => {
    act(call("profile.flow.open", { station, form }), t("web-pages.addProfile.openAction"));
    return () => { void call("profile.flow.drop", { station, form }).catch(() => undefined); };
  }, [call, station, form, act]);
  const edit = (input: Record<string, unknown>) => { act(call("profile.flow.edit", { station, form, input }), t("web-pages.addProfile.editAction")); };
  /** Adds the profile (the key is verified first): answers its id; a refusal is said under the key by the core. */
  const submit = () => call("profile.flow.submit", { station, form }) as Promise<{ id: string }>;
  return { d: state.value, edit, submit, submitting };
}
