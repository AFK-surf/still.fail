// A link's life against a peer that answers by itself (stood_wbtest.mbt, `Stood::with_peer`): its hello and what a
// refusal of it tells its caller, its pings and what missing them does, its credential's renewal, its end by the
// peer, and its peer dialled again. On the test's clock, at the times the TypeScript mesh keeps
// (client/core-ts/src/mesh.ts): a tick 5 s, a ping's answer 3 s, three misses, a renewal 5 min, an opening 10 s.

///|
/// The first line the peer heard that says `credential`, "" where none does.
fn first_saying(heard : Array[String], credential : String) -> String {
  for line in heard {
    if line.contains("\"credential\":\"\{credential}\"") {
      return line
    }
  }
  ""
}

///|
test "a hello is the credential, what the mesh says in every line and what came with the credential; a ping the first two; the peer's answer is the link's, whole" {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh(says={ "protocol": Json::number(2) })
  let source = Source::new()
  far.answers = (_, hello) => Some(if hello { "{\"ok\":true,\"name\":\"far\"}" } else { "{\"ok\":true}" })
  let link = stood.opened(mesh, source.gives(also={ "claim": Json::string("x") }))
  let admitted = stood.go(() => link.admitted())
  guard admitted.poll() is Some(Succeeded(answer)) else { fail("not let in: \{ended_as(admitted)}") }
  assert_eq(answer.stringify(), "{\"ok\":true,\"name\":\"far\"}")
  stood.rt.advance(tick_ms)
  // (byte for byte what JSON.stringify({ credential, ...says, ...also }) writes, and no `also` after the first)
  assert_eq(
    far.heard.join("\n"),
    (
      #|0 2 {"credential":"c1","protocol":2,"claim":"x"}
      #|5000 2 {"credential":"c1","protocol":2}
    ),
  )
  assert_eq(source.asked, ["kept"])
  assert_eq(far.dials, [0L])
}

///|
test "a link is handed out as its credential goes, the peer's answer still to come: a request goes on it already, and what must know it was let in waits for that answer" {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  far.holds = true
  let link = stood.opened(mesh, Source::new().gives())
  let admitted = stood.go(() => link.admitted())
  assert_eq(ended_as(admitted), "waiting")
  assert_true(link.usable())
  // (a request's reply is not kept back: only the hello's answer is still to come)
  far.holds = false
  let asked = stood.go(() => link.request("GET", "/x"))
  guard asked.poll() is Some(Succeeded(reply)) else { fail("no reply before the hello's answer: \{ended_as(asked)}") }
  assert_eq(reply.status, 200)
  assert_eq(ended_as(admitted), "waiting")
  far.release()
  assert_eq(ended_as(admitted), "ok")
}

///|
test "a request is its head line and its body on a stream of its own, finished; its reply the head and the body the peer wrote" {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  far.serves = (_, body) => replied(201, b"got " + body)
  let link = stood.opened(mesh, Source::new().gives())
  let asked = stood.go(() => {
    let reply = link.request("POST", "/things", headers=[("x-a", "1")], body=b"abc")
    (reply.status, reply.rest())
  })
  guard asked.poll() is Some(Succeeded(got)) else { fail("no reply: \{ended_as(asked)}") }
  assert_eq(got, (201, b"got abc"))
  assert_eq(far.asked.join("\n"), (#|0 2 {"method":"POST","path":"/things","headers":{"x-a":"1"}} 3
  ))
  // (its stream, handle 4, was read to its end and not reset)
  assert_eq(stood.times("istream.reset 4"), 0)
}

// ── a hello refused ──

///|
/// A hello the peer answers with `answer` (None: its stream ended instead), on a mesh whose program names refusals
/// by `refusal`: what `Link::admitted` then says, what a request on the link says, and how the credential's source
/// was asked as the link was asked for once more ("fresh": a new credential, "kept": the one it has).
fn hello_answered(answer : String?, refusal? : (Json, String) -> Error?) -> (String, String, String) raise {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh(refusal?)
  let source = Source::new()
  far.answers = (_, hello) => if hello && far.dials.length() == 1 { answer } else { Some("{\"ok\":true}") }
  let link = stood.opened(mesh, source.gives())
  let admitted = ended_as(stood.go(() => link.admitted()))
  let asked = ended_as(stood.go(() => link.request("GET", "/x")))
  // Refused, it is closed here, in the same words as the TypeScript mesh closes one, and is no more usable.
  assert_eq(far.closes, ["2 credential refused"])
  assert_true(!link.usable())
  assert_eq(far.asked.length(), 0)
  // And the next asked for is another, dialled anew and let in.
  let again = stood.opened(mesh, source.gives())
  assert_true(!physical_equal(again, link))
  assert_eq(ended_as(stood.go(() => again.admitted())), "ok")
  assert_eq(far.dials.length(), 2)
  (admitted, asked, source.asked[1])
}

///|
test "a hello refused for its credential: the caller is told the peer's reason, and a new credential is asked of its source for the next link" {
  let told = "credential_refused: " + say("credential_refused_why", args={ "reason": "credential_expired" })
  assert_eq(hello_answered(Some("{\"error\":\"credential_expired\"}")), (told, told, "fresh"))
}

///|
test "a hello refused with an error that is no string: the reason told is that error as written" {
  let told = "credential_refused: " + say("credential_refused_why", args={ "reason": "{\"why\":7}" })
  assert_eq(hello_answered(Some("{\"error\":{\"why\":7}}")), (told, told, "fresh"))
}

///|
test "a hello refused as from a program too old: the caller is told so by its code, in the peer's words" {
  let told = "client_upgrade_required: update to 9"
  assert_eq(
    hello_answered(Some("{\"error\":\"update to 9\",\"code\":\"client_upgrade_required\"}")),
    // (a new credential is asked for after it too: as the TypeScript mesh, which asks one after every refusal its
    // program did not name)
    (told, told, "fresh"),
  )
}

///|
test "a hello refused for what its program named: the caller is told the program's error, and the credential is kept for the next link" {
  let refusal = (answer : Json, reason : String) => {
    let named : Error? = if answer is { "code": String(code), .. } && code == "not_yet" {
      Some(MeshError(code~, message="named: " + reason, cause=""))
    } else {
      None
    }
    named
  }
  assert_eq(
    hello_answered(Some("{\"error\":\"wait\",\"code\":\"not_yet\"}"), refusal~),
    ("not_yet: named: wait", "not_yet: named: wait", "kept"),
  )
  // (and what it does not name is the credential's, as with no program)
  let told = "credential_refused: " + say("credential_refused_why", args={ "reason": "wait" })
  assert_eq(hello_answered(Some("{\"error\":\"wait\",\"code\":\"other\"}"), refusal~), (told, told, "fresh"))
}

///|
test "a hello answered with no line, or with what is no JSON: the caller is told the peer did not answer it" {
  let closed = "mesh: " + say("credential_closed")
  assert_eq(hello_answered(None), (closed, closed, "fresh"))
  let unreadable = "mesh: " + say("credential_unreadable")
  assert_eq(hello_answered(Some("not json")), (unreadable, unreadable, "fresh"))
}

// ── pings ──

///|
test "a link is pinged every tick with the credential it last presented, and one answered has missed none" {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  let link = stood.opened(mesh, Source::new().gives())
  stood.rt.advance(3 * tick_ms)
  assert_eq(link.missed, 0)
  assert_eq(
    far.heard.join("\n"),
    (
      #|0 2 {"credential":"c1"}
      #|5000 2 {"credential":"c1"}
      #|10000 2 {"credential":"c1"}
      #|15000 2 {"credential":"c1"}
    ),
  )
  assert_true(physical_equal(stood.opened(mesh, Source::new().gives()), link))
  assert_eq(far.dials, [0L])
}

///|
test "three pings in a row not answered: the link is let go at the third, and its peer dialled anew at once with the credential's source it had" {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  let source = Source::new()
  let link = stood.opened(mesh, source.gives())
  stood.rt.advance(tick_ms)
  assert_eq(link.missed, 0)
  // The peer goes quiet. The next ping is sent at 10 s and is missed 3 s after;
  far.quiet = true
  stood.rt.advance(tick_ms + ping_timeout_ms - 1)
  assert_eq(link.missed, 0)
  stood.rt.advance(1)
  assert_eq(link.missed, 1)
  // a tick after that verdict (18 s) it is still not answered, so no other is sent, and that is one more missed;
  stood.rt.advance(tick_ms)
  assert_eq(link.missed, 2)
  assert_eq(far.heard.length(), 3)
  // and a tick after (23 s) the third: 13 s after the first unanswered ping was sent.
  stood.rt.advance(tick_ms - 1)
  assert_true(link.usable())
  assert_true(physical_equal(stood.opened(mesh, source.gives()), link))
  far.quiet = false
  stood.rt.advance(1)
  assert_eq(link.missed, 3)
  assert_true(!link.usable())
  // (closed here saying "closed": the TypeScript mesh says "woke" there, mesh.ts `dropLink`)
  assert_eq(far.closes, ["2 closed"])
  guard link.ended() is Some(why) else { fail("a link let go says it has not ended") }
  assert_eq((why.kind, why.words()), ("local", say("closed")))
  // Dialled anew in that turn, nobody asking: connection 4, its hello the next credential of the same source.
  assert_eq(far.dials, [0L, 23000L])
  assert_eq(
    far.heard.join("\n"),
    (
      #|0 2 {"credential":"c1"}
      #|5000 2 {"credential":"c1"}
      #|10000 2 {"credential":"c1"}
      #|23000 4 {"credential":"c2"}
    ),
  )
  assert_eq(source.asked, ["kept", "kept"])
  let again = stood.opened(mesh, source.gives())
  assert_true(!physical_equal(again, link) && again.usable())
  assert_eq(far.dials.length(), 2)
  // And the new one is pinged in its turn.
  stood.rt.advance(tick_ms)
  assert_eq(far.heard[4], "28000 4 {\"credential\":\"c2\"}")
}

///|
test "a ping answered late, before the next is due: missed until its answer comes, then none missed, and the link stays" {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  let link = stood.opened(mesh, Source::new().gives())
  // Each answer takes 4 s: a second more than a ping waits.
  far.takes = 4_000
  stood.rt.advance(tick_ms + ping_timeout_ms)
  assert_eq(link.missed, 1)
  stood.rt.advance(1_000)
  assert_eq(link.missed, 0)
  // So for every ping after: the next is sent a tick after the verdict (13 s), not after the answer.
  stood.rt.advance(60_000)
  assert_true(link.missed <= 1)
  assert_true(link.usable())
  assert_eq(far.heard[1:4].to_owned(), [
    "5000 2 {\"credential\":\"c1\"}", "13000 2 {\"credential\":\"c1\"}", "21000 2 {\"credential\":\"c1\"}",
  ])
  assert_eq(far.dials, [0L])
}

///|
test "a ping answered after the next was due: no other is sent while it is out, it counts twice missed, and its answer clears both" {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  let link = stood.opened(mesh, Source::new().gives())
  far.takes = 9_000
  // Sent at 5 s, missed at 8 s, missed again at 13 s where the next was due, answered at 14 s.
  stood.rt.advance(13_000)
  assert_eq(link.missed, 2)
  assert_eq(far.heard.length(), 2)
  stood.rt.advance(1_000)
  assert_eq(link.missed, 0)
  // (and so on: never three in a row, the link is kept)
  stood.rt.advance(120_000)
  assert_true(link.usable())
  assert_eq(far.dials, [0L])
  assert_eq(far.heard[2], "18000 2 {\"credential\":\"c1\"}")
}

///|
test "a ping not answered while a reply's body came is not missed: it waits behind those bytes on the line" {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  far.serves = (_, _) => [b"{\"status\":200,\"headers\":{}}\n", b"ab", b"cd", b"ef"]
  let link = stood.opened(mesh, Source::new().gives())
  let asked = stood.go(() => link.request("GET", "/long"))
  guard asked.poll() is Some(Succeeded(reply)) else { fail("no reply: \{ended_as(asked)}") }
  far.quiet = true
  // A piece of the body is read while each of two pings is out: neither is missed.
  stood.rt.advance(tick_ms)
  assert_true(stood.go(() => reply.take()).poll() is Some(Succeeded(Some(_))))
  stood.rt.advance(ping_timeout_ms)
  assert_eq(link.missed, 0)
  assert_true(stood.go(() => reply.take()).poll() is Some(Succeeded(Some(_))))
  stood.rt.advance(tick_ms)
  assert_eq(link.missed, 0)
  // Nothing came during the third wait: missed.
  stood.rt.advance(tick_ms)
  assert_eq(link.missed, 1)
}

// ── renewal ──

///|
test "a link presents a new credential every renew_ms, and its pings present that one from then on: it stays its peer's link, usable" {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  let source = Source::new()
  let link = stood.opened(mesh, source.gives())
  // (each answer 20 ms away, so that no ping falls on the instant of a renewal: which of the two would go first then
  // is the runtime's order, not the mesh's)
  far.takes = 20
  stood.rt.advance(renew_ms - 1)
  assert_eq(source.asked, ["kept"])
  stood.rt.advance(1)
  // Asked of its source as one it has will do (not as after a refusal), and sent as a ping is: the credential alone.
  assert_eq(source.asked, ["kept", "kept"])
  assert_eq(first_saying(far.heard, "c2"), "300000 2 {\"credential\":\"c2\"}")
  // (the link's own is the new one once the peer took it)
  assert_eq(link.credential, "c1")
  stood.rt.advance(20)
  assert_eq(link.credential, "c2")
  // The next, renew_ms after that one was answered.
  stood.rt.advance(renew_ms - 1)
  assert_eq(source.asked.length(), 2)
  stood.rt.advance(1)
  assert_eq(first_saying(far.heard, "c3"), "600020 2 {\"credential\":\"c3\"}")
  stood.rt.advance(tick_ms)
  // Every line between the two renewals presented c2, every one after c3; none was missed, nothing dialled.
  let mut renewed = 0
  for line in far.heard {
    if line.contains("\"c3\"") {
      renewed = 2
    } else if line.contains("\"c2\"") {
      assert_eq(renewed < 2, true)
      renewed = 1
    } else {
      assert_eq(renewed, 0)
    }
  }
  assert_eq(renewed, 2)
  assert_eq(link.missed, 0)
  assert_true(link.usable())
  assert_true(physical_equal(stood.opened(mesh, source.gives()), link))
  assert_eq(far.dials, [0L])
  far.takes = 0
  assert_eq(ended_as(stood.go(() => link.request("GET", "/x"))), "ok")
}

///|
test "a renewal refused: the link is no more usable and is left to run out, the next link is another; a new credential is asked for only once a hello's was refused" {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  let source = Source::new()
  // The peer takes c1 and, at the end, c4; c2 (the renewal's) and c3 (the next hello's) it refuses.
  far.answers = (line, _) => {
    if line.contains("\"c2\"") || line.contains("\"c3\"") {
      Some("{\"error\":\"credential_revoked\"}")
    } else {
      Some("{\"ok\":true}")
    }
  }
  let link = stood.opened(mesh, source.gives())
  stood.rt.advance(renew_ms - 1)
  assert_true(link.usable())
  stood.rt.advance(1)
  assert_eq(first_saying(far.heard, "c2"), "300000 2 {\"credential\":\"c2\"}")
  assert_true(!link.usable())
  // Not closed here, and not ended: it runs out as the peer ends it. Its pings stop, and it is not renewed again.
  assert_true(link.ended() is None)
  assert_eq(far.closes.length(), 0)
  assert_eq(link.credential, "c1")
  let heard = far.heard.length()
  stood.rt.advance(renew_ms + tick_ms)
  assert_true(far.heard.length() <= heard + 1)
  assert_eq(source.asked, ["kept", "kept"])
  assert_eq(far.dials, [0L])
  // The next asked for is another, dialled anew. A renewal's refusal asks no new credential of the source: the one
  // it has is presented (c3), as the TypeScript mesh does.
  let second = stood.opened(mesh, source.gives())
  assert_true(!physical_equal(second, link))
  assert_eq(source.asked, ["kept", "kept", "kept"])
  assert_eq(far.dials.length(), 2)
  let refused = "credential_refused: " + say("credential_refused_why", args={ "reason": "credential_revoked" })
  assert_eq(ended_as(stood.go(() => second.admitted())), refused)
  assert_eq(far.closes, ["4 credential refused"])
  // That hello's refusal does: the third is opened with a new one, and let in.
  let third = stood.opened(mesh, source.gives())
  assert_eq(source.asked, ["kept", "kept", "kept", "fresh"])
  assert_eq(ended_as(stood.go(() => third.admitted())), "ok")
  assert_true(third.usable())
  // (and once let in, the next is not asked as after a refusal)
  stood.rt.advance(renew_ms)
  assert_eq(source.asked[4], "kept")
  assert_true(third.usable())
}

// ── its end ──

///|
test "a connection the peer ends with a reason: the link says which, in the words for it, whoever waited for its end is told, and the next link is dialled anew with the credential kept" {
  let cases = [
    ("application", "credential_refused", say("credential_refused")),
    ("application", "credential_revoked", say("credential_revoked")),
    ("application", "credential_expired", say("credential_expired")),
    ("timeout", "", say("timed_out")),
    ("other", "reset", say("cut")),
  ]
  for one in cases {
    let (kind, reason, words) = one
    let (stood, far) = Stood::with_peer()
    let mesh = stood.mesh()
    let source = Source::new()
    let link = stood.opened(mesh, source.gives())
    let closed = stood.go(() => link.closed())
    assert_true(link.ended() is None)
    far.end(2, reason, kind~)
    guard link.ended() is Some(why) else { fail("a link whose connection ended says it has not") }
    assert_eq((why.kind, why.reason, why.words()), (kind, reason, words))
    guard closed.poll() is Some(Succeeded(told)) else { fail("the wait for its end did not end: \{ended_as(closed)}") }
    assert_eq((told.kind, told.reason), (kind, reason))
    assert_true(!link.usable())
    assert_eq(ended_as(stood.go(() => link.request("GET", "/x"))), "mesh: " + say("cut"))
    // (not closed here but to be let go of, once its end was told)
    assert_eq(far.closes.length(), 0)
    assert_true(stood.forgot.contains(2))
    // Nothing dials by itself: the next asked for does, with the credential its source has.
    stood.rt.advance(3 * tick_ms)
    assert_eq(far.dials, [0L])
    let again = stood.opened(mesh, source.gives())
    assert_true(!physical_equal(again, link) && again.usable())
    assert_eq(far.dials.length(), 2)
    assert_eq(source.asked, ["kept", "kept"])
  }
}

///|
test "a connection the peer ends with a reason of its own: the words say that reason" {
  let (stood, far) = Stood::with_peer()
  let link = stood.opened(stood.mesh(), Source::new().gives())
  far.end(2, "bye")
  guard link.ended() is Some(why) else { fail("a link whose connection ended says it has not") }
  assert_eq((why.kind, why.reason), ("application", "bye"))
  assert_true(why.words().contains("bye"))
  assert_true(why.words() != say("cut") && why.words() != "bye")
}

// ── dialled again ──

///|
test "a link let go for its pings whose peer does not answer the dial: the mesh tries once, whoever asks meanwhile shares that try, and one that joined it late dials again" {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  let source = Source::new()
  ignore(stood.opened(mesh, source.gives()))
  far.quiet = true
  far.away = true
  // Let go at 18 s (its first ping, at 5 s, already unanswered), and dialled anew then.
  stood.rt.advance(18_000)
  assert_eq(far.dials, [0L, 18000L])
  // One asks 7 s into that dial, and shares it: no dial of its own.
  stood.rt.advance(7_000)
  let asking = stood.go(() => mesh.link(peer, source.gives()))
  assert_eq(far.dials.length(), 2)
  // The dial gives up connect_timeout_ms after it began. Whoever waited on it less than that long is not told so:
  // begun before they asked, it says nothing of now, and the peer is dialled again for them.
  stood.rt.advance(3_000)
  assert_eq(ended_as(asking), "waiting")
  assert_eq(far.dials, [0L, 18000L, 28000L])
  stood.rt.advance(connect_timeout_ms - 1)
  assert_eq(ended_as(asking), "waiting")
  stood.rt.advance(1)
  assert_eq(ended_as(asking), "mesh: " + say("no_answer"))
  // And nothing dials after that by itself: the next try is whoever asks next.
  stood.rt.advance(10 * 60_000)
  assert_eq(far.dials.length(), 3)
  assert_eq(stood.held.length(), 0)
}

///|
test "a peer that does not answer: a program's tries, each given up after connect_timeout_ms, are spaced by its backoff, 1 s doubling to 30 s, and start over once one went well" {
  let (stood, far) = Stood::with_peer()
  let mesh = stood.mesh()
  let source = Source::new()
  far.away = true
  let backoff = Backoff::new()
  let failures : Array[String] = []
  let linked = async fn() -> Link {
    while true {
      match attempt(() => mesh.link(peer, source.gives())) {
        Did(link) => {
          backoff.reset()
          return link
        }
        Fell(e) => failures.push(said(e))
      }
      backoff.pause()
    }
    panic()
  }
  let trying = stood.go(linked)
  // A try 10 s, then 1, 2, 4, 8, 16, 30 s between tries.
  stood.rt.advance(150_000)
  assert_eq(far.dials, [0L, 11000L, 23000L, 37000L, 55000L, 81000L, 121000L])
  assert_eq(ended_as(trying), "waiting")
  far.away = false
  stood.rt.advance(11_000)
  assert_eq(far.dials.length(), 8)
  assert_eq(far.dials[7], 161000L)
  assert_eq(ended_as(trying), "ok")
  assert_eq(failures.length(), 7)
  for failure in failures {
    assert_eq(failure, "mesh: " + say("no_answer"))
  }
  // (every try asked the source for the credential it has: none was refused)
  assert_eq(source.asked.filter(how => how == "kept").length(), 8)
  // Once it went well the wait is the first again.
  let before = stood.rt.now()
  let paused = stood.go(() => backoff.pause())
  stood.rt.advance(999)
  assert_eq(ended_as(paused), "waiting")
  stood.rt.advance(1)
  assert_eq(ended_as(paused), "ok")
  assert_eq(stood.rt.now() - before, 1000L)
}
