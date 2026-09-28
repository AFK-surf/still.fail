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
async fn a_job_stopped_from_the_pages_tells_its_agent_who_did() {
    let r = rig();
    let job = r.jobs.start("s1", "watch", "sleep 5", &r.work, None).unwrap();
    let stopped = r.jobs.stop_for(&job.id, "ann@example.com").await.unwrap();
    assert_eq!(stopped.state, "stopped");
    assert_eq!(r.said(), [format!("Job \"watch\" ({}) was stopped by ann@example.com from ember's page.", job.id)]);
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

#[tokio::test]
async fn what_ran_when_the_station_stopped_runs_again_when_it_starts() {
    let dir = tempfile::tempdir().unwrap();
    let store = Arc::new(Store::open(&dir.path().join("ember.db").to_string_lossy(), None).unwrap());
    let before = rig_on(tempfile::tempdir().unwrap(), store.clone());
    let job = before.jobs.start("s1", "watch", "sleep 30", &before.work, None).unwrap();
    before.jobs.shutdown().await;
    tokio::time::sleep(Duration::from_millis(200)).await;
    assert_eq!(before.state(&job.id), "running", "still running on record");
    let after = rig_on(dir, store);
    after.jobs.relaunch();
    let again = after.store.get_job(&job.id).unwrap().unwrap();
    assert!(again.pgid.is_some() && again.restarts == 1);
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
