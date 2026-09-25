import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { useNavigate } from "react-router";
import { api, keys, useOverview, type RuntimeKind } from "../api.ts";
import { RUNTIME_LABEL } from "../format.ts";
import { CreateAppSteps, emptyTokens, TokenFields, type TokenState } from "../slack.tsx";
import { useToast } from "../toast.tsx";
import { Button, Dialog, Field, Segmented } from "../ui.tsx";

/** A readable id from a name: "Ember DS" → "ember-ds". */
export function slug(name: string): string {
  return name.toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 32);
}

export function NewBotDialog({ open, onClose }: { open: boolean; onClose(): void }) {
  const overview = useOverview();
  const client = useQueryClient();
  const navigate = useNavigate();
  const toast = useToast();
  const [step, setStep] = useState<1 | 2>(1);
  const [name, setName] = useState("");
  const [id, setId] = useState("");
  const [idTouched, setIdTouched] = useState(false);
  const [runtime, setRuntime] = useState<RuntimeKind>("claude");
  const [account, setAccount] = useState("");
  const [model, setModel] = useState("");
  const [tokens, setTokens] = useState<TokenState>(emptyTokens);

  const accounts = (overview.data?.profiles ?? []).filter((p) => p.runtime === runtime);
  const chosen = accounts.find((p) => p.id === account) ?? accounts[0];
  const models = chosen?.check?.models ?? [];
  const botId = idTouched ? id : slug(name);
  const taken = overview.data?.bots.some((b) => b.id === botId) ?? false;
  const idValid = /^[a-z0-9][a-z0-9-]*$/.test(botId) && !taken;

  const reset = () => {
    setStep(1); setName(""); setId(""); setIdTouched(false); setAccount(""); setModel(""); setTokens(emptyTokens);
  };
  const close = () => { reset(); onClose(); };
  const create = useMutation({
    mutationFn: (withTokens: boolean) => api.putBot(botId, {
      name: name.trim(), runtime, profiles: chosen ? [chosen.id] : [], model: model.trim(),
      ...(withTokens ? { slack: { appToken: tokens.appToken, botToken: tokens.botToken } } : {}),
    }),
    onSuccess: (data, withTokens) => {
      client.setQueryData(keys.overview, data);
      toast(withTokens ? "已添加 bot，正在连接 Slack" : "已添加 bot");
      close();
      navigate(`/bots/${botId}`);
    },
  });

  return (
    <Dialog open={open} onClose={close} title={step === 1 ? "添加 Bot" : "连接 Slack"}
      footer={step === 1 ? (
        <>
          <Button variant="ghost" onClick={close}>取消</Button>
          <Button variant="primary" disabled={!name.trim() || !idValid || !chosen} onClick={() => setStep(2)}>下一步</Button>
        </>
      ) : (
        <>
          <Button variant="ghost" onClick={() => setStep(1)}>上一步</Button>
          <Button onClick={() => create.mutate(false)} busy={create.isPending && create.variables === false}>稍后连接</Button>
          <Button variant="primary" disabled={!tokens.verified} busy={create.isPending && create.variables === true} onClick={() => create.mutate(true)}>添加并连接</Button>
        </>
      )}>
      {step === 1 ? (
        <>
          <p className="dialog-lead">每个 bot 是一个 Slack app，绑定一种运行时和模型。在 Slack 里 @ 哪个 bot，就用哪个模型干活。</p>
          <Field label="名称" htmlFor="new-bot-name" hint="Slack 里显示的名字，也是 agent 对自己的称呼。">
            <input id="new-bot-name" className="input" value={name} autoFocus onChange={(e) => setName(e.target.value)} placeholder="例如 ember-claude" />
          </Field>
          <Field label="ID" htmlFor="new-bot-id" error={taken ? "这个 ID 已经被别的 bot 用了" : undefined} hint="会话记录用它区分 bot，创建后不能改。">
            <input id="new-bot-id" className="input mono" value={botId} onChange={(e) => { setIdTouched(true); setId(e.target.value); }} />
          </Field>
          <Field label="运行时" htmlFor="">
            <Segmented label="运行时" value={runtime} onChange={(r) => { setRuntime(r); setAccount(""); setModel(""); }}
              options={[{ value: "claude", label: "Claude Code" }, { value: "codex", label: "Codex" }]} />
          </Field>
          <Field label="运行时账号" htmlFor="new-bot-account"
            error={accounts.length === 0 ? `还没有 ${RUNTIME_LABEL[runtime]} 账号，先到「设置 → 运行时账号」添加。` : undefined}>
            <select id="new-bot-account" className="select" value={chosen?.id ?? ""} onChange={(e) => setAccount(e.target.value)} disabled={accounts.length === 0}>
              {accounts.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
          </Field>
          <Field label="模型" htmlFor="new-bot-model" hint={models.length ? `这个账号有 ${models.length} 个可用模型。` : "留空用运行时或账号的默认模型。"}>
            <input id="new-bot-model" className="input mono" list="new-bot-models" value={model} onChange={(e) => setModel(e.target.value)} placeholder={chosen?.model ?? "默认"} />
            <datalist id="new-bot-models">{models.map((m) => <option key={m} value={m} />)}</datalist>
          </Field>
        </>
      ) : (
        <>
          <CreateAppSteps name={name} />
          <TokenFields value={tokens} onChange={setTokens} />
          {create.error && <p className="field-error" role="alert">{create.error.message}</p>}
        </>
      )}
    </Dialog>
  );
}
