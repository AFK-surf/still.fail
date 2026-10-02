use super::*;

fn settings(dir: &Path, profiles: Value) -> Arc<Settings> {
    std::fs::write(dir.join("config.json"), json!({"profiles": profiles}).to_string()).unwrap();
    Settings::open(&dir.join("config.json"), dir).unwrap()
}

/// A ChatGPT access token (only its `exp` is read) that runs out `days` from now.
fn jwt(days: i64) -> String {
    let claims = json!({"exp": now_ms() / 1000 + days * 24 * 3600});
    format!("h.{}.s", base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(claims.to_string()))
}

fn codex_login(days: i64, refresh: &str) -> Value {
    json!({"auth_mode": "chatgpt", "OPENAI_API_KEY": null, "tokens": {"id_token": "id", "access_token": jwt(days), "refresh_token": refresh, "account_id": "acct"}, "last_refresh": "2026-10-01T00:00:00Z"})
}

#[tokio::test]
async fn what_is_marked_shared_is_lent_but_never_an_environment_and_only_over_the_lan() {
    let dir = tempfile::tempdir().unwrap();
    let s = settings(
        dir.path(),
        json!([
            {"id": "cc", "name": "Max", "runtime": "claude", "access": {"kind": "subscription"}, "home": "homes/cc", "models": ["claude-opus-5-5"], "shareOnLan": true},
            {"id": "kept", "runtime": "claude", "access": {"kind": "subscription"}, "home": "homes/kept"},
            {"id": "api", "runtime": "claude", "access": {"kind": "anthropic-api", "key": "sk-ant-1"}, "home": "homes/api", "env": {"HTTPS_PROXY": "http://10.0.0.1:1"}, "shareOnLan": true},
            {"id": "custom", "runtime": "claude", "access": {"kind": "env"}, "home": "homes/custom", "env": {"ANTHROPIC_BASE_URL": "http://localhost:1"}, "shareOnLan": true},
        ]),
    );
    let store = Store::open(dir.path().join("stillfail.db").to_str().unwrap(), None).unwrap();
    store.set_profile_quota("cc", &json!({"state": "ok", "windows": [], "checkedAt": 1})).unwrap();
    let lent = answer(&s, &store, true, &json!({"method": ASK_LENT})).await.unwrap();
    let offers = lent["profiles"].as_array().unwrap();
    let ids: Vec<&str> = offers.iter().map(|p| p["profile"]["id"].as_str().unwrap()).collect();
    assert_eq!(ids, ["cc", "api"]);
    assert_eq!(offers[0]["profile"]["models"], json!(["claude-opus-5-5"]));
    assert_eq!(offers[0]["quota"]["state"], "ok");
    assert!(offers[0]["profile"]["access"]["key"].is_null(), "a subscription's login is handed over turn by turn, not listed");
    assert_eq!(offers[1]["profile"]["access"]["key"], "sk-ant-1");
    assert!(offers[1]["profile"].get("env").is_none(), "its own environment stays its own");
    let refused = answer(&s, &store, false, &json!({"method": ASK_LENT})).await.unwrap_err();
    assert_eq!(refused.to_string(), NOT_ON_LAN);
    assert!(answer(&s, &store, false, &json!({"method": ASK_TOKEN, "profile": "cc"})).await.is_err());
    for id in ["kept", "api"] {
        let not_lent = answer(&s, &store, true, &json!({"method": ASK_TOKEN, "profile": id})).await.unwrap_err();
        assert!(not_lent.to_string().contains("not lent"), "{not_lent}");
    }
}

#[tokio::test]
async fn a_lent_codex_login_is_handed_over_without_its_refresh_token_and_renewed_near_its_end() {
    let dir = tempfile::tempdir().unwrap();
    let s = settings(dir.path(), json!([{"id": "cx", "runtime": "codex", "access": {"kind": "subscription"}, "home": "homes/cx", "shareOnLan": true}]));
    let store = Store::open(dir.path().join("stillfail.db").to_str().unwrap(), None).unwrap();
    let file = dir.path().join("homes/cx/auth.json");
    std::fs::create_dir_all(file.parent().unwrap()).unwrap();
    std::fs::write(&file, codex_login(9, "refresh-1").to_string()).unwrap();
    let renewed = Arc::new(Mutex::new(0));
    let (count, written) = (renewed.clone(), file.clone());
    s.lan.on_renew_codex(Arc::new(move |_| {
        *count.lock().unwrap() += 1;
        std::fs::write(&written, codex_login(10, "refresh-2").to_string()).unwrap();
        Box::pin(async { Ok(()) })
    }));
    let ask = json!({"method": ASK_TOKEN, "profile": "cx"});
    let handed = answer(&s, &store, true, &ask).await.unwrap();
    assert_eq!(handed["auth"]["tokens"]["refresh_token"], "", "never the refresh token");
    assert_eq!(handed["auth"]["tokens"]["account_id"], "acct");
    assert_eq!(*renewed.lock().unwrap(), 0, "9 days left: no renewing");
    std::fs::write(&file, codex_login(2, "refresh-1").to_string()).unwrap();
    let handed = answer(&s, &store, true, &ask).await.unwrap();
    assert_eq!(*renewed.lock().unwrap(), 1, "2 days left: renewed by its own codex first");
    assert!(handed["expiresAt"].as_i64().unwrap() - now_ms() > 9 * 24 * 3600 * 1000);
    assert_eq!(read_auth(&file).unwrap().0["tokens"]["refresh_token"], "refresh-2", "the lender's own login is untouched");
}

/// A fake workspace: the studio station lends what `lends` says while `lan` says so; `gone` takes it out of the roster.
struct Fake {
    lan: Mutex<bool>,
    gone: Mutex<bool>,
    codex_days: Mutex<i64>,
    asked: Mutex<usize>,
}

const STUDIO: &str = "abcdef0123456789";

fn call(fake: Arc<Fake>) -> Call {
    Arc::new(move |target: String, request: Value| {
        let fake = fake.clone();
        Box::pin(async move {
            match (target.as_str(), request["method"].as_str().unwrap()) {
                ("", "peers") => {
                    let mut stations = vec![json!({"id": "me0000000000", "name": "here"})];
                    if !*fake.gone.lock().unwrap() {
                        stations.push(json!({"id": STUDIO, "name": "studio"}));
                    }
                    Ok(json!({"self": "me0000000000", "stations": stations, "current": true}))
                }
                (STUDIO, ASK_LENT) if *fake.lan.lock().unwrap() => Ok(json!({"profiles": [
                    {"profile": {"id": "cc", "name": "Max", "runtime": "claude", "access": {"kind": "subscription"}, "home": "", "models": ["claude-opus-5-5"]},
                     "check": {"state": "ok", "detail": "", "models": null, "checkedAt": 1}, "quota": null},
                    {"profile": {"id": "cx", "name": "Pro", "runtime": "codex", "access": {"kind": "subscription"}, "home": "", "models": ["gpt-6"]}, "check": null, "quota": null},
                    {"profile": {"id": "router", "runtime": "claude", "access": {"kind": "api-provider", "key": "or-key", "provider": "openrouter"}, "home": "", "models": ["anthropic/claude-opus-5-5"]}, "check": null, "quota": null},
                    {"profile": {"id": "custom", "runtime": "claude", "access": {"kind": "env"}, "home": "", "env": {"A": "b"}}, "check": null, "quota": null},
                ]})),
                (STUDIO, ASK_LENT) => Err(Refused(NOT_ON_LAN.into()).into()),
                (STUDIO, ASK_TOKEN) if request["profile"] == "cc" => Ok(json!({"token": "access", "expiresAt": 99})),
                (STUDIO, ASK_TOKEN) => {
                    *fake.asked.lock().unwrap() += 1;
                    let mut auth = codex_login(*fake.codex_days.lock().unwrap(), "");
                    auth["tokens"]["refresh_token"] = json!("");
                    Ok(json!({"auth": auth}))
                }
                other => panic!("unexpected {other:?}"),
            }
        })
    })
}

#[tokio::test]
async fn a_borrower_runs_what_is_lent_while_on_the_lan_and_keeps_it_unusable_off_it() {
    let dir = tempfile::tempdir().unwrap();
    let s = settings(dir.path(), json!([{"id": "own", "runtime": "claude", "access": {"kind": "subscription"}, "home": "homes/own"}]));
    let fake = Arc::new(Fake { lan: Mutex::new(true), gone: Mutex::new(false), codex_days: Mutex::new(10), asked: Mutex::new(0) });
    s.lan.attach(call(fake.clone()));
    let mut changes = s.subscribe();
    changes.borrow_and_update();

    round(&s).await;
    let config = s.config();
    let lent: Vec<&Profile> = config.profiles.iter().filter(|p| p.lent.is_some()).collect();
    assert_eq!(lent.iter().map(|p| p.id.as_str()).collect::<Vec<_>>(), ["lan-abcdef01-cc", "lan-abcdef01-cx", "lan-abcdef01-router"], "never an environment");
    let (cc, cx, router) = (lent[0], lent[1], lent[2]);
    assert_eq!(cc.name, "Max · studio");
    assert!(cc.runs("claude-opus-5-5"));
    assert!(cc.home.starts_with(dir.path().join("lan")) && cc.home.is_dir());
    assert!(s.lan.on_lan(&cc.id));
    assert_eq!(s.lan.check(&cc.id).unwrap().state, "ok");
    assert_eq!(s.lan.token(cc.lent.as_ref().unwrap()).await.unwrap(), ("access".into(), 99));
    // A key, in its environment as config.json's own would have it.
    assert_eq!(router.key, "or-key");
    assert!(router.env(RuntimeKind::Claude).values().any(|v| v == "or-key"), "{:?}", router.env(RuntimeKind::Claude));
    // A Codex login: written to its home without a refresh token, and not asked for again while it has days left.
    let codex = read_auth(&cx.home.join("auth.json")).unwrap().0;
    assert_eq!(codex["tokens"]["refresh_token"], "");
    assert!(s.lan.on_lan(&cx.id));
    assert!(changes.has_changed().unwrap());
    changes.borrow_and_update();
    assert!(read_raw_profiles(dir.path()).iter().all(|id| id == "own"), "never written to config.json");

    round(&s).await;
    assert!(!changes.has_changed().unwrap(), "the same profiles again change nothing");
    assert_eq!(*fake.asked.lock().unwrap(), 1);
    *fake.codex_days.lock().unwrap() = 2;
    std::fs::write(cx.home.join("auth.json"), codex_login(2, "").to_string()).unwrap();
    round(&s).await;
    assert_eq!(*fake.asked.lock().unwrap(), 2, "near its end, asked for again");

    *fake.lan.lock().unwrap() = false;
    round(&s).await;
    assert!(s.config().profiles.iter().any(|p| p.id == cc.id), "kept, so its sessions are moved");
    assert!(!s.lan.on_lan(&cc.id) && !s.lan.on_lan(&router.id));
    assert_eq!(s.lan.check(&cc.id).unwrap().state, "failed");
    assert!(!cx.home.join("auth.json").exists(), "off the LAN its Codex login is removed");

    // An edit of the station's own config keeps what is lent.
    s.update(|raw| {
        raw.max_nudges = Some(3);
        Ok(())
    })
    .unwrap();
    assert!(s.config().profiles.iter().any(|p| p.id == cc.id));

    *fake.lan.lock().unwrap() = true;
    round(&s).await;
    assert!(cx.home.join("auth.json").exists(), "back on the LAN, taken again");
    *fake.gone.lock().unwrap() = true;
    round(&s).await;
    assert!(s.config().profiles.iter().all(|p| p.lent.is_none()), "its station left the workspace");
    assert!(!cx.home.join("auth.json").exists());
}

fn read_raw_profiles(dir: &Path) -> Vec<String> {
    crate::config::read_raw(&dir.join("config.json")).unwrap().profiles.unwrap_or_default().into_iter().map(|p| p.id).collect()
}

/// Every provider there is (stillfail_shapes::providers), lent: the borrower runs it as the lender does, at the same
/// address, with the same key, the same runtimes and the same environment and Codex settings.
#[tokio::test]
async fn every_provider_is_borrowed_as_its_lender_runs_it() {
    let dir = tempfile::tempdir().unwrap();
    let profiles: Vec<Value> = stillfail_shapes::providers::SOURCES
        .iter()
        .enumerate()
        .map(|(i, source)| {
            let endpoint = source.endpoint_required.then_some("https://models.example.internal/v1");
            json!({"id": format!("p{i}"), "name": source.name, "access": {"kind": "api-provider", "provider": source.id, "key": format!("key-{i}"), "endpoint": endpoint}, "home": format!("homes/p{i}"), "models": ["m"], "env": {"OWN": "lender"}, "shareOnLan": true})
        })
        .collect();
    let lender = settings(dir.path(), json!(profiles));
    let store = Store::open(dir.path().join("stillfail.db").to_str().unwrap(), None).unwrap();
    let lent = answer(&lender, &store, true, &json!({"method": ASK_LENT})).await.unwrap();
    let offers = lent["profiles"].as_array().unwrap();
    assert_eq!(offers.len(), stillfail_shapes::providers::SOURCES.len(), "every provider is lent");
    let borrower_dir = tempfile::tempdir().unwrap();
    let borrower = settings(borrower_dir.path(), json!([]));
    for (own, offer) in lender.config().profiles.iter().zip(offers) {
        let p = borrowed(&borrower, STUDIO, "studio", offer).unwrap_or_else(|| panic!("{} not borrowed", own.id));
        let mut expected = own.envs.clone();
        for env in expected.values_mut() {
            env.remove("OWN");
        }
        assert_eq!((&p.provider, &p.endpoint, &p.protocol, &p.key), (&own.provider, &own.endpoint, &own.protocol, &own.key), "{}", own.name);
        assert_eq!(p.runtimes, own.runtimes, "{}", own.name);
        assert_eq!(p.envs, expected, "{}: the same environment, but not the lender's own variables", own.name);
        assert_eq!(
            crate::profiles::codex_overrides(p.access_kind, p.model.as_deref(), p.via()),
            crate::profiles::codex_overrides(own.access_kind, own.model.as_deref(), own.via()),
            "{}",
            own.name
        );
    }
}
