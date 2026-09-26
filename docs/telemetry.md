# Telemetry

## Tracing

When something is slow, one trace per user action shows where the time went,
hop by hop: the client core (the web's SharedWorker or a native app), ember
cloud, ember-mesh on the station, and the station's admin API. Spans are
OpenTelemetry (OTLP JSON) and end up in Axiom, dataset `ember`.

### What is traced

A **trace** starts in the client core (`client/core/src/trace.rs`) for each
user-facing operation:

| Trace (root span) | When |
| --- | --- |
| `chat.open`, `chats.open`, `stations.open`, `connects.open` | a view's first subscriber, until its first value goes out (the requests that make it are read inside it; a chat's agents too, when the value that names them is computed while it is still opening) |
| the call's name: `chat.send`, `chat.older`, `chat.read`, `station.request`, `cloud.request`, … | every call, until it answers |
| `station.connect`, `station.reconnect` | a station's events stream opening (when a view asked for it, `station.connect` is part of that view's trace), and opening again after it was down, until everything it may have missed is read again |

Inside a trace:

- **core**: a span per station request (`GET /admin/api/threads/:id/messages`),
  ending when the whole answer is read — an event stream's when it is open
  (`ember.stream`); `station.connect` for the events stream a view asked for;
  `mesh.connect` when a request has to open the link first (grant, iroh
  connection), with the ember cloud requests it made; ember cloud requests
  made inside the trace (`/v1/me`, grants, workspaces).
- **ember cloud**: a span of each `/v1/*` call that carries a recorded
  `traceparent`.
- **ember-mesh**: a span per request stream, from the stream accepted to the
  answer's last byte written (an event stream's: to its head).
- **the station's admin API**: a span per request, from arrival to the answer
  sent (an event stream's: to its head).

A request without a trace (one an event caused, a stream's later reads) is a
trace of its own, one span per hop.

Every station request carries a W3C `traceparent`; ember-mesh records its span
under it and passes its own on to the admin API, so the hops nest. Requests to
ember cloud carry one only inside a trace.

Attributes: `http.request.method`, `url.path` (the route with ids as `:id`,
no query), `http.response.status_code`, sizes (`http.request.body.size`,
`http.response.body.size`; the admin API's `http.response.size` counts its
head too), `ember.station` (the station's id), `ember.path` (`relay`,
`direct`, or `local` for a station's own page), `ember.via` (how the request
reached the admin API: `mesh`, `local`, `access`), `ember.stream`,
`ember.cancelled` (the span's task ended before it did: the chat was closed
before it opened), `error.type`. Never message content, titles, file names or
emails. `service.name` says which hop: `ember-web`, `ember-native`,
`ember-cloud`, `ember-mesh`, `ember-station`; a station's spans also carry the
resource attribute `ember.station`.

Times: the web core times with `performance.now()`, native with a monotonic
clock (`Host::monotonic_ms`), converted to Unix nanoseconds from the wall
clock read once when the trace started. ember-mesh and the admin API do the
same with their own clocks, so hops on different machines are only as aligned
as their clocks; durations are exact.

### Where spans go

Nothing ships Axiom's token: it lives only in ember cloud (`AXIOM_TOKEN`,
`AXIOM_DATASET`, which `cloud/deploy.py` uploads from
`~/ember-deploy/axiom.json`). Clients and stations send their spans to ember
cloud's `POST /v1/telemetry/traces` (OTLP JSON, at most 512 KB and 1000 spans a
batch), which forwards them to `https://api.axiom.co/v1/traces`:

- a client core batches for 3 s (`EXPORT_MS`) after a span ends and sends as
  its first signed-in account (`Authorization: Bearer`); with nobody signed in
  the batch is dropped.
- ember-mesh batches the same way, its own spans and the admin API's (ember
  writes them to its stdin, one JSON line each), and signs each batch with the
  station's key: headers `x-ember-station`, `x-ember-ts` (unix seconds, within
  5 minutes) and `x-ember-signature` over
  `ember-station-telemetry-v1:<origin>:<station>:<ts>:<sha256 of the body, hex>`;
  the station must be enrolled.
- ember cloud sends its own spans to Axiom directly, after answering
  (`ctx.waitUntil`).

A batch that cannot be sent is dropped, never retried. ember cloud allows each
sender (an account, a station) 60 batches a minute (`429` beyond), answers
`503` while it has no Axiom token and `502` when Axiom refuses.

### Sampling and opt-in

- Client cores record every trace (`trace::SAMPLE = 1.0`; lower it as use
  grows). A trace not sampled still sends its `traceparent`, with flags `00`,
  so no hop records it.
- Stations send spans only when their config says so:

  ```json
  { "telemetry": { "traces": true } }
  ```

  in `config.json` (off by default; read when ember starts ember-mesh, so
  restart ember after changing it). Off, ember-mesh and the admin API record
  nothing but still pass the `traceparent` on.
- ember cloud records a span only for a call whose `traceparent` is sampled.

### Looking in Axiom

Dataset `ember`. The slowest chat opens today, with the longest span of each
hop in them:

```kusto
['ember']
| where _time > startofday(now())
| summarize
    open_ms = maxif(duration / 1ms, name == "chat.open"),
    link_ms = maxif(duration / 1ms, name == "mesh.connect"),
    cloud_ms = maxif(duration / 1ms, ['service.name'] == "ember-cloud"),
    mesh_ms = maxif(duration / 1ms, ['service.name'] == "ember-mesh"),
    station_ms = maxif(duration / 1ms, ['service.name'] == "ember-station")
    by trace_id
| where open_ms > 0
| top 10 by open_ms desc
```

Read it as: `open_ms` is what the user waited; `link_ms` opening the link to
the station (grant plus iroh connection); `mesh_ms` a request's time on the
station, of which `station_ms` was the admin API's; what a core request span
took beyond its mesh span was the network (the relay, or the direct path).
One trace in order:

```kusto
['ember']
| where trace_id == "<trace id>"
| project _time, ['service.name'], name, duration, span_id, parent_span_id
| order by _time asc
```

The attributes above are under `attributes` (Axiom puts those OpenTelemetry
does not define under `attributes.custom`, e.g.
`['attributes.custom']['ember.path']`).
