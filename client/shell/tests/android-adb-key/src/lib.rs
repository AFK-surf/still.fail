use libadb::keys::rsa::rand_core::OsRng;
use libadb::keys::store;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

const ROOT: &str = "/data/user/0/fail.still.adbprobe/files";

fn check() -> Result<(), String> {
    let keydir = Path::new(ROOT).join("adb");
    let key = store::load_or_generate(&keydir, &mut OsRng, "still.fail")
        .map_err(|e| format!("first key: {e}"))?;
    let again = store::load_or_generate(&keydir, &mut OsRng, "still.fail")
        .map_err(|e| format!("reloaded key: {e}"))?;
    if key.public_key_line() != again.public_key_line() {
        return Err("identity changed on reload".into());
    }
    let mode = fs::metadata(keydir.join("adbkey")).map_err(|e| e.to_string())?.permissions().mode() & 0o777;
    if mode != 0o600 { return Err(format!("private-key mode is {mode:o}")); }

    let invalid = Path::new(ROOT).join("invalid");
    fs::create_dir_all(&invalid).map_err(|e| e.to_string())?;
    fs::write(invalid.join("adbkey"), b"existing invalid key").map_err(|e| e.to_string())?;
    if store::load_or_generate(&invalid, &mut OsRng, "still.fail").is_ok() {
        return Err("invalid identity was accepted".into());
    }
    if fs::read(invalid.join("adbkey")).map_err(|e| e.to_string())? != b"existing invalid key" {
        return Err("invalid identity was overwritten".into());
    }

    let race = Path::new(ROOT).join("race");
    let barrier = std::sync::Arc::new(std::sync::Barrier::new(2));
    let threads: Vec<_> = (0..2).map(|_| {
        let race = race.clone();
        let barrier = barrier.clone();
        std::thread::spawn(move || {
            barrier.wait();
            store::load_or_generate(&race, &mut OsRng, "still.fail")
                .map(|key| key.public_key_line().to_owned()).map_err(|e| e.to_string())
        })
    }).collect();
    let mut identities = Vec::new();
    for thread in threads { identities.push(thread.join().map_err(|_| "key race panicked")??); }
    if identities[0] != identities[1] { return Err("concurrent writers selected different identities".into()); }
    Ok(())
}

#[no_mangle]
pub extern "system" fn Java_fail_still_adbprobe_MainActivity_probe(
    _: *mut core::ffi::c_void, _: *mut core::ffi::c_void,
) -> i32 {
    match check() {
        Ok(()) => { let _ = fs::write(Path::new(ROOT).join("result.txt"), "pass"); 0 }
        Err(error) => { let _ = fs::write(Path::new(ROOT).join("result.txt"), error); 1 }
    }
}
