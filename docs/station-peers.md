# Station peers and remote tasks

Stations in the same workspace can discover each other and call named services over iroh. The first service runs shell tasks and transfers files. It has no dependency on a machine name, toolchain, repository, model or SSH. A command runs in a fresh task directory on the destination as its OS user; this is **not a sandbox**.

## Permission and compatibility

The destination administrator opts in by adding the **source station's full public key** to its `config.json` (use the existing station configuration editor, or restart after a manual file edit):

```json
{"remoteTasks":{"allow":["SOURCE_STATION_PUBLIC_KEY"]}}
```

This trusts agents on that source to execute shell commands on the target. It does not forward a person's admin credential or open the target's management APIs. Request metadata records the source station, source session and its creator (`requestedBy`, asserted by the trusted source station, not an independently verified user identity).

Cloud sends an additional `peers` field on station presence state frames. Enrollment, removal, movement and renaming update the workspace roster. A peer's iroh public key must match that roster; the request must name the same workspace. New calls fail closed while the control-plane connection is unavailable, or before a fresh roster arrives. Membership removal and permission withdrawal stop affected running tasks on the next check (every five seconds). Losing connectivity alone does not kill running commands.

Deploy cloud first, then the stations that participate. Old stations ignore the new field; an old cloud provides no roster, so peer calls remain disabled. Existing member connections and existing local job tools keep their behavior. No database version change or data migration is required.

## Agent tools

- `station_list {}` returns the workspace's registered stations and whether the roster is current. A listed station is not necessarily online. `station_list {station}` connects to one and returns its protocol, OS, architecture, task permission and file limits.
- `station_task {station, action:"prepare", key, name, command}` records the task specification and creates its directory. Pick a stable key for one execution. Preparing that key with a different specification is refused.
- `station_file {station, key, direction:"upload", local, path}` uploads a local session file into a relative path in that task directory. Finish uploading before starting.
- `station_task {station, action:"start", key}` starts the prepared command. A retry with the same key returns the original job; it never deliberately starts another copy.
- `station_task {station, action:"get"|"log"|"stop", key}` reads status, tails logs or cancels the task. `action:"list"` lists this source session's tasks on the target, including prepared tasks.
- `station_file {station, key, direction:"download", path, local}` downloads an artifact after the task finishes. It creates a new file inside the source session workspace and does not overwrite existing files. The agent can attach it to its original conversation with `chat_post`.

Files use 256 KiB chunks, up to 1 GiB per file. Binary files work. Paths cannot escape the task directory and transfers refuse symbolic links. Inputs cannot be written through the transfer API after execution starts. An interrupted upload can be repeated; an incomplete upload blocks start. Downloads publish the final filename only once the transfer succeeds. For a repository, upload a bundle/archive and explicitly unpack/check out the desired revision in the command; automatic Git synchronization is not part of this service.

The source persists a receipt before sending start, follows task status across network and process restarts, and delivers completion/log tails and `stillfail-job notify` notices to the originating session. This first version follows every five seconds rather than keeping a push stream. Notifications may be repeated if the source crashes between delivery and saving the receipt.

A task is keyed by **workspace + source station + source session + caller key**. A different peer or session cannot read, stop or fetch its files through this service. The remote job record is durable before process spawn. If a process disappears during a station/machine failure and no exit status can be recovered, it becomes `failed` with a null exit code; it is **not automatically re-executed**. That result is uncertain, not evidence that the command had no effects. Inspect it and use a new key only when another execution is intended.

Task files and records remain under the target's data directory `remote/incoming`; source receipts are under `remote/outgoing`. Automatic retention/cleanup, remote long-lived services, and delegating to another model are not provided in this first service.

## Chats on other stations

Any station of the workspace may read another's chats and write to its sessions; no `remoteTasks.allow` is needed, as these are what a workspace member sees and does on the chats' pages, not execution.

- `chat_read` / `session_history` with a chat's link on another station ask it (`session.read`). Its answer lists the attachments of the messages read; the reader fetches each (`session.file`, 256 KiB chunks) into its session's `uploads/<station>/` and names them by their path there. Those up to 16 MB come by themselves (up to 64 MB per read); larger ones are fetched when the agent names them in `fetch`. `session.file` gives only a file in the uploads directory of one of that chat's sessions — the files its page shows, also from an archived workspace — never another path.
- `session_send` to a session on another station sends its `files` first (`session.put`, at most 10 of 50 MB each), staged under the target's data directory `remote/staged`, then the message naming them (`session.message`); the target moves them into the uploads of the chat's agent and posts them with the message. Files no message claims are removed after a day. On the same station the files are copied there directly.

A station from before these methods takes them for tasks and refuses them; the reader then gets the text and is told the files were left there, and a message with files is not sent.

## Shares

Stations also share profiles and skills over this transport (`share.get`, `share.lend`, `share.status`, `share.put`, `share.take`; [station-share.md](station-share.md)). Any station of the workspace may ask; what each share allows is checked by its host, which keeps it (still.fail cloud keeps nothing of shares). No `remoteTasks.allow` is needed: these are not execution.

## Transport

ALPN `stillfail/station/1` is separate from the member/admin protocol. Each bounded request contains `{workspace, request:{method,...}}`, answered with `{result}` or `{error}` on a QUIC bidirectional stream. Services accept explicit methods (`describe`, `task.*`, `file.*`); this is not an arbitrary management-path proxy. Network timeouts explicitly report uncertain execution. The transport can carry further services without encoding build-specific concepts.

Tests exercise workspace roster isolation/removal, real local iroh connections with temporary station data, task ownership, repeated starts, file transfer, cancellation and withdrawn permissions. No production station is used for verification.
