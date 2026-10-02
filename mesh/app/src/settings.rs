//! The configuration as a live, editable document. config.json stays the source of truth: edits are checked by
//! parse_config, written atomically (mode 600: it holds secrets), and then announced to whoever applies them.

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use anyhow::Result;
use tokio::sync::watch;

use crate::config::{Config, Profile, RawConfig, parse_config, read_raw};

pub struct Settings {
    pub path: PathBuf,
    pub data_dir: PathBuf,
    raw: Mutex<RawConfig>,
    config: watch::Sender<Arc<Config>>,
    /// Profiles other stations lend this one over the LAN (lan_share.rs): in the config after its own, never written.
    lent: Mutex<Vec<Profile>>,
    /// What the lending stations last said of them, and how to reach them.
    pub lan: Arc<crate::lan_share::Borrowed>,
}

/// The config as written, with the borrowed profiles after its own (whose ids they never take).
fn with_lent(mut config: Config, lent: &[Profile]) -> Config {
    let more: Vec<Profile> = lent.iter().filter(|l| !config.profiles.iter().any(|p| p.id == l.id)).cloned().collect();
    config.profiles.extend(more);
    config
}

impl Settings {
    pub fn open(path: &Path, data_dir: &Path) -> Result<Arc<Settings>> {
        let raw = read_raw(path)?;
        let config = parse_config(&raw, data_dir)?;
        crate::lang::set_station(raw.language.as_deref());
        Ok(Arc::new(Settings {
            path: path.to_path_buf(),
            data_dir: data_dir.to_path_buf(),
            raw: Mutex::new(raw),
            config: watch::channel(Arc::new(config)).0,
            lent: Mutex::default(),
            lan: Arc::default(),
        }))
    }

    /// The config now.
    pub fn config(&self) -> Arc<Config> {
        self.config.borrow().clone()
    }

    /// The config as stored, for reading what an edit would change.
    pub fn raw(&self) -> RawConfig {
        self.raw.lock().unwrap().clone()
    }

    /// Hears each config an edit makes (the current one first).
    pub fn subscribe(&self) -> watch::Receiver<Arc<Config>> {
        self.config.subscribe()
    }

    /// Applies an edit. Fails (and changes nothing) if the result does not check out, or the edit itself refuses.
    pub fn update(&self, edit: impl FnOnce(&mut RawConfig) -> Result<()>) -> Result<Arc<Config>> {
        let mut raw = self.raw.lock().unwrap();
        let mut next = raw.clone();
        edit(&mut next)?;
        let config = Arc::new(with_lent(parse_config(&next, &self.data_dir)?, &self.lent.lock().unwrap()));
        write(&self.path, &next)?;
        crate::lang::set_station(next.language.as_deref());
        *raw = next;
        drop(raw);
        self.config.send_replace(config.clone());
        Ok(config)
    }

    /// The profiles lent to this station now (lan_share.rs); announced as an edit is when they change.
    pub fn set_lent(&self, profiles: Vec<Profile>) {
        let raw = self.raw.lock().unwrap();
        let mut lent = self.lent.lock().unwrap();
        if *lent == profiles {
            return;
        }
        let Ok(config) = parse_config(&raw, &self.data_dir) else { return };
        *lent = profiles;
        self.config.send_replace(Arc::new(with_lent(config, &lent)));
    }
}

fn write(path: &Path, raw: &RawConfig) -> Result<()> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let tmp = path.with_extension(format!("json.tmp-{}", std::process::id()));
    let text = format!("{}\n", serde_json::to_string_pretty(raw)?);
    {
        use std::io::Write;
        use std::os::unix::fs::OpenOptionsExt;
        let mut file = std::fs::OpenOptions::new().write(true).create(true).truncate(true).mode(0o600).open(&tmp)?;
        file.write_all(text.as_bytes())?;
    }
    std::fs::rename(&tmp, path)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::RawProfile;
    use std::os::unix::fs::PermissionsExt;

    #[test]
    fn an_edit_is_checked_written_privately_and_announced() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("config.json");
        let settings = Settings::open(&path, dir.path()).unwrap();
        let mut changes = settings.subscribe();
        let profile = RawProfile { id: "cc".into(), name: None, runtime: Some(stillfail_shapes::RuntimeKind::Claude), access: None, home: "homes/cc".into(), env: None, model: None, models: None, machine: None, fast: None, background_on_message: None, share_on_lan: None };
        settings.update(|raw| { raw.profiles = Some(vec![profile.clone()]); Ok(()) }).unwrap();
        assert!(changes.has_changed().unwrap());
        assert_eq!(changes.borrow_and_update().profiles[0].id, "cc");
        assert_eq!(std::fs::metadata(&path).unwrap().permissions().mode() & 0o777, 0o600);
        assert_eq!(read_raw(&path).unwrap().profiles.unwrap()[0].id, "cc");
        // One that does not check out changes nothing.
        let bad = settings.update(|raw| { raw.profiles.as_mut().unwrap()[0].id = "Bad".into(); Ok(()) });
        assert!(bad.is_err());
        assert_eq!(settings.config().profiles[0].id, "cc");
        assert_eq!(read_raw(&path).unwrap().profiles.unwrap()[0].id, "cc");
    }
}
