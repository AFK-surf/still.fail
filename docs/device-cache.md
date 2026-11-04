# What a person's other devices hold of a station that is down

A device holds what it read of every station (docs/core-db.md), but a device that was away has nowhere to get what it
missed once the station is gone: still.fail cloud keeps no messages. So it asks the person's other devices, straight,
over iroh (`client/core-ts/src/views/device-cache.ts`, ALPN `stillfail/cache/1`). Nothing new is kept anywhere, and
nothing goes through the cloud.

## Who answers whom

Only in a workspace with a lock (docs/workspace-lock.md), whose chain says which devices are whose. A workspace without
one is not served: the cloud's word on its devices names no session, so a device signed out would still be listed.

A device answers a connection only if, in the workspace it names:

- the lock is good and not turned off, and names the connection's key as a live device of this device's own account;
- its member credential is signed by the lock's cloud keys, for that workspace, that account and that very key;
- the credential's login session (`sid`) is among the account's sessions as the cloud last told them.

Then it answers of that workspace's stations alone, read only. Only apps take these connections; a web page can ask but
not answer.

## What goes

The wire is a line of JSON each way on one stream: `hello {ws, credential}` → `ok` | `no`; `list {station}` →
`{rows, threads}`; `entries {station, thread, after, limit}` → `{entries, last}`.

Chats and messages alone. An agent's transcript and files stay on the station. Messages sent still wait for the station.

## When

Nothing is asked on a timer. A station's other holders are asked once as the device finds it down (its link, or the cloud
saying it is not online), and once each time the UI comes back while it still is: the person's other apps in the lock,
one after another, 15 s to be reached and 15 s for each answer. A device not reached then is asked again only at the next
of those. It stops as the station comes back.

Entries are numbered and never change, so the station coming back goes on from what was brought; its lists, read then,
replace what a device said. While it is down, the line over a chat's composer says some of it came from another device
(held in memory: an app started again no longer says so).
