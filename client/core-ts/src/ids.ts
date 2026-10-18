// The names the core gives what it makes on this device (an outgoing message, a notice, a composer's file): the UIs
// keep them as identities (a list's keys, a message's row kept as it goes from the outbox into the chat, a notice shown
// once), and they outlive the core that gave them (a restarted core, the app's views still up). A count from 1 would
// give the same name again after a restart (out-1 twice, the Android chat's list crashed on its two rows, 2026-10), so
// each is random.
export function localId(prefix: string): string {
  return `${prefix}-${Array.from(crypto.getRandomValues(new Uint8Array(9)), (b) => b.toString(16).padStart(2, "0")).join("")}`;
}
