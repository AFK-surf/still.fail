// What a published snapshot hides (docs/public-share.md): words that look like secrets, each replaced by `[已隐藏]`
// (`[hidden]` in English) before anyone outside the workspace can read them. A net, not a guarantee: the person
// publishing sees the preview, with how many were hidden in each message, before it goes out.

/// Secrets by their shape: providers' keys and tokens, private keys, JWTs, credentials in URLs, `password=…` and the like.
const SHAPES: (RegExp | [RegExp, (found: string) => boolean])[] = [
  /-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?(?:-----END [A-Z0-9 ]*PRIVATE KEY-----|$)/g,
  /\bsk-ant-[A-Za-z0-9_-]{16,}/g,
  /\bsk-(?:proj-|svcacct-|admin-)?[A-Za-z0-9_-]{20,}/g,
  /\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}/g,
  /\bgithub_pat_[A-Za-z0-9_]{40,}/g,
  /\bglpat-[A-Za-z0-9_-]{20,}/g,
  /\bxox[abposr]-[A-Za-z0-9-]{10,}/g,
  /\bxapp-[A-Za-z0-9-]{20,}/g,
  /\bAKIA[0-9A-Z]{16}\b/g,
  /\bAIza[0-9A-Za-z_-]{35}\b/g,
  /\b(?:sk|rk|pk)_(?:live|test)_[A-Za-z0-9]{16,}/g,
  /\bnpm_[A-Za-z0-9]{36}\b/g,
  /\bhf_[A-Za-z0-9]{30,}\b/g,
  /\bya29\.[A-Za-z0-9_-]{20,}/g,
  /\beyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/g,
  // user:password@ in a URL: the password.
  /(?<=[a-z][a-z0-9+.-]*:\/\/[^\s/:@]+:)[^\s/@]{3,}(?=@)/gi,
  // Bearer <token>
  /(?<=\bBearer\s+)[A-Za-z0-9._~+/=-]{16,}/g,
  // KEY=value, "token": "value", password: value … — the value, when it looks like one (not `tokens: 12000`).
  [/(?<=\b[A-Za-z0-9_.-]*(?:api[_-]?key|apikey|secret|token|passw(?:or)?d|passwd|pwd|private[_-]?key|access[_-]?key|client[_-]?secret|authorization)[A-Za-z0-9_.-]*["']?\s*[:=]\s*["']?)[^\s"',;)\]}]{8,}/gi, (v) => v.length >= 16 || (/[0-9]/.test(v) && /[A-Za-z]/.test(v))],
];

/// `text` with what looks like a secret replaced by `mark`, and how many were.
export function redact(text: string, mark: string): { text: string; count: number } {
  let count = 0;
  let out = text;
  for (const entry of SHAPES) {
    const [shape, looks] = Array.isArray(entry) ? entry : [entry, null];
    out = out.replace(shape, (found) => {
      // A value already hidden (by an earlier shape, or written so) is not counted again.
      if (found === mark || found.includes(mark) || (looks !== null && !looks(found))) return found;
      count++;
      return mark;
    });
  }
  return { text: out, count };
}
