use super::*;
use std::sync::Mutex as StdMutex;

struct Rig {
    _dir: tempfile::TempDir,
    store: Arc<Store>,
    jobs: Arc<Jobs>,
    told: Arc<StdMutex<Vec<(String, String)>>>,
    work: PathBuf,
}

fn rig_on(dir: tempfile::TempDir, store: Arc<Store>) -> Rig {
    let told: Arc<StdMutex<Vec<(String, String)>>> = Arc::default();
    let heard = told.clone();
    let jobs = Jobs::new(
        store.clone(),
        dir.path(),
        Arc::new(move |session, text| heard.lock().unwrap().push((session.to_string(), text))),
        Arc::new(|session, job| Some(format!("https://ember.test/o/ws/st/{session}?service={job}"))),
    )
    .unwrap();
    let work = dir.path().join("work");
    std::fs::create_dir_all(&work).unwrap();
    Rig { _dir: dir, store, jobs, told, work }
}

fn rig() -> Rig {
    rig_on(tempfile::tempdir().unwrap(), Arc::new(Store::open(":memory:", None).unwrap()))
}

async fn until(what: &str, check: impl Fn() -> bool) {
    for _ in 0..100 {
        if check() {
            return;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    panic!("never: {what}");
}

impl Rig {
    fn said(&self) -> Vec<String> {
        self.told.lock().unwrap().iter().map(|(_, t)| t.clone()).collect()
    }
    fn state(&self, id: &str) -> String {
        self.store.get_job(id).unwrap().unwrap().state
    }
}

#[tokio::test]
async fn a_job_runs_apart_its_output_logged_and_its_agent_told_how_it_ended() {
    let r = rig();
    let job = r.jobs.start("s1", "build", "echo compiling; echo done >&2; exit 3", &r.work, None).unwrap();
    assert_eq!(job.state, "running");
    until("it ends", || r.state(&job.id) == "exited").await;
    let ended = r.store.get_job(&job.id).unwrap().unwrap();
    assert_eq!(ended.exit_code, Some(3));
    assert_eq!(tail(Path::new(&ended.log), 10), "compiling\ndone");
    until("its agent is told", || !r.said().is_empty()).await;
    let said = r.said();
    assert!(said[0].starts_with(&format!("Job \"build\" ({}) ended with exit code 3.", job.id)), "{}", said[0]);
    assert!(said[0].contains("compiling\ndone"));
    assert_eq!(r.told.lock().unwrap()[0].0, "s1");
}

#[tokio::test]
async fn a_job_tells_its_agent_on_the_way_through_its_token() {
    let r = rig();
    let job = r.jobs.start("s1", "long", "sleep 5", &r.work, None).unwrap();
    r.jobs.notified(&job.token, "  half way  ").unwrap();
    assert_eq!(r.said(), [format!("Job \"long\" ({}) says: half way", job.id)]);
    assert!(r.jobs.notified("wrong", "x").is_err());
    // What it said is kept for the pages, newest first, with the job as they get it.
    r.jobs.notified(&job.token, "nearly there").unwrap();
    let notices: Vec<String> = r.store.job_notices(&job.id, 10).unwrap().into_iter().map(|n| n.text).collect();
    assert_eq!(notices, ["nearly there", "half way"]);
    let shown = shown(&r.store, &r.store.get_job(&job.id).unwrap().unwrap());
    assert_eq!(shown["notices"][0]["text"], "nearly there");
    assert!(shown.get("token").is_none());
    let stopped = r.jobs.stop(&job.id).await.unwrap();
    assert_eq!(stopped.state, "stopped");
    tokio::time::sleep(Duration::from_millis(200)).await;
    assert_eq!(r.said().len(), 2, "a stop asked for is no news");
}

#[tokio::test]
async fn a_job_has_its_command_under_the_new_name_and_the_old_and_its_variables_under_both() {
    let r = rig();
    let job = r.jobs.start("s1", "names", r#"stillfail-job 2>&1; ember-job 2>&1; [ "$STILLFAIL_JOB_ID" = "$EMBER_JOB_ID" ] && [ "$STILLFAIL_JOB_TOKEN" = "$EMBER_JOB_TOKEN" ] && echo same"#, &r.work, None).unwrap();
    // Three shells in a row: given longer than `until` gives, for a machine busy with the other tests.
    for _ in 0..400 {
        if r.state(&job.id) != "running" {
            break;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    let ended = r.store.get_job(&job.id).unwrap().unwrap();
    assert_eq!(ended.state, "exited");
    assert_eq!(tail(Path::new(&ended.log), 10), "usage: stillfail-job notify <words>\nusage: stillfail-job notify <words>\nsame");
    // Made again (a station starting over the same directory), the link stays one.
    let bin = r._dir.path().join("jobs").join("bin");
    Jobs::new(r.store.clone(), r._dir.path(), Arc::new(|_, _| {}), Arc::new(|_, _| None)).unwrap();
    assert_eq!(std::fs::read_link(bin.join("ember-job")).unwrap(), Path::new("stillfail-job"));
    assert_eq!(std::fs::read_dir(&bin).unwrap().count(), 2);
}

/// A job started before the rename has only the old variables; the command reads them.
#[tokio::test]
async fn the_job_command_reads_the_old_variables_of_a_job_started_before_the_rename() {
    use std::os::unix::fs::PermissionsExt;
    let r = rig();
    let bin = r._dir.path().join("jobs").join("bin");
    // A curl that says what it was asked.
    let fake = r._dir.path().join("fake");
    std::fs::create_dir_all(&fake).unwrap();
    std::fs::write(fake.join("curl"), "#!/bin/sh\ncat >/dev/null; echo \"$@\" >&2\n").unwrap();
    std::fs::set_permissions(fake.join("curl"), std::fs::Permissions::from_mode(0o755)).unwrap();
    let out = std::process::Command::new(bin.join("ember-job"))
        .args(["notify", "hi"])
        .env_clear()
        .env("EMBER_JOB_TOKEN", "t0k")
        .env("EMBER_JOB_NOTIFY", "http://127.0.0.1:9/jobs/notify")
        .env("PATH", format!("{}:{}:/usr/bin:/bin", fake.display(), bin.display()))
        .output()
        .unwrap();
    let asked = String::from_utf8_lossy(&out.stderr);
    assert!(asked.contains("Authorization: Bearer t0k") && asked.contains("http://127.0.0.1:9/jobs/notify"), "{asked}");
}

/// A session whose agent was last at work `ago` ago.
fn session_active(store: &Store, key: &str, ago: Duration) {
    let at = now_ms() - ago.as_millis() as i64;
    store
        .insert_session(&crate::store::NewSession {
            key: key.into(),
            connect: "ds".into(),
            runtime: "claude".into(),
            profile: "cc".into(),
            workspace: format!("/w/{key}"),
            token: key.into(),
            created_at: at,
            last_active_at: at,
            ..Default::default()
        })
        .unwrap();
}

#[tokio::test]
async fn a_job_stopped_from_the_pages_tells_its_agent_who_did() {
    let r = rig();
    session_active(&r.store, "s1", Duration::from_secs(60));
    let job = r.jobs.start("s1", "watch", "sleep 5", &r.work, None).unwrap();
    let stopped = r.jobs.stop_for(&job.id, "ann@example.com").await.unwrap();
    assert_eq!(stopped.state, "stopped");
    assert_eq!(r.said(), [format!("Job \"watch\" ({}) was stopped by ann@example.com from still.fail's page.", job.id)]);
}

#[tokio::test]
async fn a_job_stopped_from_the_pages_does_not_wake_an_idle_agent() {
    let r = rig();
    session_active(&r.store, "s1", Duration::from_secs(6 * 60));
    let job = r.jobs.start("s1", "watch", "sleep 5", &r.work, None).unwrap();
    assert_eq!(r.jobs.stop_for(&job.id, "ann@example.com").await.unwrap().state, "stopped");
    // Once it is at work again, it is told.
    let other = r.jobs.start("s1", "again", "sleep 5", &r.work, None).unwrap();
    r.store.set_running("s1", true).unwrap();
    r.jobs.stop_for(&other.id, "ann@example.com").await.unwrap();
    assert_eq!(r.said(), [format!("Job \"again\" ({}) was stopped by ann@example.com from still.fail's page.", other.id)]);
}

#[tokio::test]
async fn clearing_a_sessions_ended_jobs_takes_them_and_their_logs_away_and_leaves_the_rest() {
    let r = rig();
    let failed = r.jobs.start("s1", "boom", "echo x; exit 2", &r.work, None).unwrap();
    let done = r.jobs.start("s1", "done", "true", &r.work, None).unwrap();
    let live = r.jobs.start("s1", "watch", "sleep 5", &r.work, None).unwrap();
    let other = r.jobs.start("s2", "boom", "exit 2", &r.work, None).unwrap();
    until("they end", || [&failed, &done, &other].iter().all(|j| r.state(&j.id) == "exited")).await;
    r.store.add_job_notice(&failed.id, "broke").unwrap();
    let mut cleared = r.jobs.clear_ended("s1").unwrap();
    cleared.sort();
    let mut want = vec![failed.id.clone(), done.id.clone()];
    want.sort();
    assert_eq!(cleared, want);
    let left: Vec<String> = r.store.list_jobs(None).unwrap().into_iter().map(|j| j.id).collect();
    assert_eq!(left.len(), 2);
    assert!(left.contains(&live.id) && left.contains(&other.id));
    assert!(!Path::new(&failed.log).exists());
    assert!(r.store.job_notices(&failed.id, 5).unwrap().is_empty());
    r.jobs.stop(&live.id).await.unwrap();
}

#[tokio::test]
async fn a_service_is_kept_up_and_stays_down_once_stopped() {
    let r = rig();
    let job = r.jobs.start("s1", "web", "echo up on $PORT; exit 1", &r.work, Some(4999)).unwrap();
    until("it is started again", || r.store.get_job(&job.id).unwrap().unwrap().restarts >= 1).await;
    assert!(r.said()[0].contains("ended with exit code 1; the station starts it again in 1 s."), "{}", r.said()[0]);
    assert!(tail(Path::new(&job.log), 5).contains("up on 4999"));
    assert!(r.jobs.start("s2", "other", "true", &r.work, Some(4999)).is_err_and(|e| e.to_string().contains("port 4999")), "one service per port");
    r.jobs.stop(&job.id).await.unwrap();
    until("it is stopped", || r.state(&job.id) == "stopped").await;
    let restarts = r.store.get_job(&job.id).unwrap().unwrap().restarts;
    tokio::time::sleep(Duration::from_millis(2500)).await;
    assert_eq!(r.store.get_job(&job.id).unwrap().unwrap().restarts, restarts, "not started again");
}

/// The same store, and the same jobs directory, as a restarted station has.
fn restarted(before: &Rig, dir: &Path, store: Arc<Store>) -> Rig {
    let _ = before;
    let told: Arc<StdMutex<Vec<(String, String)>>> = Arc::default();
    let heard = told.clone();
    let jobs = Jobs::new(store.clone(), dir, Arc::new(move |session, text| heard.lock().unwrap().push((session.to_string(), text))), Arc::new(|_, _| None)).unwrap();
    Rig { _dir: tempfile::tempdir().unwrap(), store, jobs, told, work: before.work.clone() }
}

fn shared() -> (tempfile::TempDir, Arc<Store>) {
    let dir = tempfile::tempdir().unwrap();
    let store = Arc::new(Store::open(&dir.path().join("ember.db").to_string_lossy(), None).unwrap());
    (dir, store)
}

#[tokio::test]
async fn a_job_goes_on_through_a_restart_of_the_station_and_is_followed_to_its_end() {
    let (dir, store) = shared();
    let before = rig_on(tempfile::tempdir().unwrap(), store.clone());
    let data = before._dir.path().to_path_buf();
    let job = before.jobs.start("s1", "build", "sleep 1; echo built; exit 4", &before.work, None).unwrap();
    before.jobs.shutdown().await;
    tokio::time::sleep(Duration::from_millis(200)).await;
    let pgid = before.store.get_job(&job.id).unwrap().unwrap().pgid.unwrap() as i32;
    assert!(group_alive(pgid), "the station stopping does not stop it");
    let after = restarted(&before, &data, store);
    after.jobs.relaunch();
    let followed = after.store.get_job(&job.id).unwrap().unwrap();
    assert_eq!((followed.pgid, followed.restarts), (Some(pgid as i64), 0), "the same run, not started again");
    assert!(after.said().is_empty());
    until("it ends", || after.state(&job.id) == "exited").await;
    assert_eq!(after.store.get_job(&job.id).unwrap().unwrap().exit_code, Some(4), "how it ended, from what its shell wrote");
    until("its agent is told", || !after.said().is_empty()).await;
    assert!(after.said()[0].contains("ended with exit code 4"), "{}", after.said()[0]);
    drop(dir);
}

#[tokio::test]
async fn a_job_that_ended_while_no_station_ran_is_told_as_ended_not_run_again() {
    let (_dir, store) = shared();
    let before = rig_on(tempfile::tempdir().unwrap(), store.clone());
    let data = before._dir.path().to_path_buf();
    let job = before.jobs.start("s1", "quick", "sleep 0.3; exit 5", &before.work, None).unwrap();
    before.jobs.shutdown().await;
    tokio::time::sleep(Duration::from_millis(1000)).await;
    assert_eq!(before.state(&job.id), "running", "still running on record");
    let after = restarted(&before, &data, store);
    after.jobs.relaunch();
    until("it is told as ended", || after.state(&job.id) == "exited").await;
    let ended = after.store.get_job(&job.id).unwrap().unwrap();
    assert_eq!((ended.exit_code, ended.restarts), (Some(5), 0));
    until("its agent is told", || !after.said().is_empty()).await;
    assert!(after.said()[0].contains("ended with exit code 5"), "{}", after.said()[0]);
}

#[tokio::test]
async fn a_job_gone_without_a_word_runs_again_when_the_station_starts() {
    let (_dir, store) = shared();
    let before = rig_on(tempfile::tempdir().unwrap(), store.clone());
    let data = before._dir.path().to_path_buf();
    let job = before.jobs.start("s1", "watch", "sleep 30", &before.work, None).unwrap();
    before.jobs.shutdown().await;
    // What a restart of the machine does to it.
    let pgid = before.store.get_job(&job.id).unwrap().unwrap().pgid.unwrap() as i32;
    signal_group(pgid, libc::SIGKILL);
    tokio::time::sleep(Duration::from_millis(300)).await;
    let after = restarted(&before, &data, store);
    after.jobs.relaunch();
    let again = after.store.get_job(&job.id).unwrap().unwrap();
    assert!(again.pgid.is_some_and(|p| p != pgid as i64) && again.restarts == 1);
    assert_eq!(after.said(), [format!("The station restarted; Job \"watch\" ({}) was started again.", job.id)]);
    after.jobs.stop(&job.id).await.unwrap();
}

#[tokio::test]
async fn the_agents_tools_start_list_read_and_stop_their_sessions_jobs_only() {
    let r = rig();
    let work = r.work.clone();
    let tools = r.jobs.tools(Arc::new(move |_| Some(work.clone())));
    let call = |name: &str, key: &str, args: Value| {
        let tool = tools.iter().find(|t| t.name == name).unwrap().clone();
        let key = key.to_string();
        async move { (tool.run)(key, args.as_object().cloned().unwrap_or_default()).await }
    };
    let made: Value = serde_json::from_str(&call("job_start", "s1", json!({ "command": "echo hello; sleep 5", "name": "hi", "port": 5010 })).await.unwrap()).unwrap();
    let id = made["id"].as_str().unwrap().to_string();
    assert_eq!(made["link"], json!(format!("https://ember.test/o/ws/st/s1?service={id}")));
    assert!(made.get("token").is_none(), "its token is not said");
    until("it writes", || tail(&r.dir_log(&id), 5) == "hello").await;
    assert_eq!(call("job_log", "s1", json!({ "id": id })).await.unwrap(), "hello");
    assert!(call("job_log", "s2", json!({ "id": id })).await.unwrap_err().to_string().contains("another session's"));
    assert!(call("job_list", "s1", json!({})).await.unwrap().contains(&id));
    assert_eq!(call("job_list", "s2", json!({})).await.unwrap(), "No jobs.");
    assert!(call("job_stop", "s1", json!({ "id": id })).await.unwrap().ends_with("is stopped."));
}

impl Rig {
    fn dir_log(&self, id: &str) -> PathBuf {
        PathBuf::from(self.store.get_job(id).unwrap().unwrap().log)
    }
}
