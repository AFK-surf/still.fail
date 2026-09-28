//! Keeps one chat connection per enabled connect, following config edits: a new or re-credentialed connect is
//! (re)connected, a removed or disabled one disconnected, the rest left alone.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use anyhow::Result;
use async_trait::async_trait;
use futures_util::future::BoxFuture;
use serde::Serialize;
use tokio::sync::{Mutex as AsyncMutex, watch};
use tracing::{error, info};

use crate::chat::slack::{SlackIdentity, SocketStatus};
use crate::chat::{ChatEvent, ChatSurface, Handler};
use crate::config::{Config, Connect};

/// A connect's link to its platform, as the pages show it.
#[derive(Serialize, Debug, Clone, PartialEq)]
#[serde(tag = "state", rename_all = "snake_case")]
pub enum ConnectState {
    Disabled,
    NoTokens,
    Starting,
    Connected {
        #[serde(rename = "botUserId")]
        bot_user_id: String,
        #[serde(rename = "lastError")]
        last_error: Option<String>,
        workspace: Option<SlackIdentity>,
    },
    Reconnecting {
        #[serde(rename = "botUserId")]
        bot_user_id: String,
        #[serde(rename = "lastError")]
        last_error: Option<String>,
        workspace: Option<SlackIdentity>,
    },
    Error {
        error: String,
    },
}

/// A live chat connection: a surface, and how its link stands.
#[async_trait]
pub trait Connection: ChatSurface {
    fn socket(&self) -> SocketStatus;
    fn identity(&self) -> Option<SlackIdentity>;
    /// Moves whenever `socket` or `identity` changes.
    fn changes(&self) -> watch::Receiver<SocketStatus>;
    /// Reads again who the bot is and where (its name changed in Slack, say); listeners hear of it.
    async fn refresh_identity(&self) -> Result<()>;
}

#[async_trait]
impl Connection for crate::chat::slack::SlackSurface {
    fn socket(&self) -> SocketStatus {
        self.status()
    }
    fn identity(&self) -> Option<SlackIdentity> {
        crate::chat::slack::SlackSurface::identity(self)
    }
    fn changes(&self) -> watch::Receiver<SocketStatus> {
        self.status_changes()
    }
    async fn refresh_identity(&self) -> Result<()> {
        crate::chat::slack::SlackSurface::refresh_identity(self).await
    }
}

pub type Create = Box<dyn Fn(&Connect) -> Result<Arc<dyn Connection>> + Send + Sync>;
pub type OnEvent = Arc<dyn Fn(String, ChatEvent) -> BoxFuture<'static, Result<()>> + Send + Sync>;

pub struct Connections {
    /// Live connections by connect id; the hub reads it on every use.
    chats: Mutex<HashMap<String, Arc<dyn Connection>>>,
    tokens: Mutex<HashMap<String, String>>,
    errors: Mutex<HashMap<String, String>>,
    create: Create,
    on_event: OnEvent,
    /// Rapid edits apply in order.
    chain: AsyncMutex<()>,
    /// Moves whenever what state() reports may have changed.
    changes: watch::Sender<u64>,
}

fn token_key(connect: &Connect) -> String {
    format!("{}\n{}", connect.slack.app_token, connect.slack.bot_token)
}

impl Connections {
    pub fn new(create: Create, on_event: OnEvent) -> Arc<Connections> {
        Arc::new(Connections {
            chats: Mutex::default(),
            tokens: Mutex::default(),
            errors: Mutex::default(),
            create,
            on_event,
            chain: AsyncMutex::new(()),
            changes: watch::channel(0).0,
        })
    }

    pub fn chat(&self, id: &str) -> Option<Arc<dyn Connection>> {
        self.chats.lock().unwrap().get(id).cloned()
    }

    pub fn ids(&self) -> Vec<String> {
        self.chats.lock().unwrap().keys().cloned().collect()
    }

    pub fn changes(&self) -> watch::Receiver<u64> {
        self.changes.subscribe()
    }

    fn changed(&self) {
        self.changes.send_modify(|n| *n += 1);
    }

    /// Reads again who a connect's bot is (its name, its workspace), as Slack says now.
    pub async fn refresh_identity(&self, id: &str) -> Result<()> {
        let chat = self.chat(id);
        if let Some(chat) = chat {
            chat.refresh_identity().await?;
        }
        Ok(())
    }

    pub fn state(&self, connect: &Connect) -> ConnectState {
        if !connect.enabled {
            return ConnectState::Disabled;
        }
        if connect.slack.app_token.is_empty() || connect.slack.bot_token.is_empty() {
            return ConnectState::NoTokens;
        }
        if let Some(error) = self.errors.lock().unwrap().get(&connect.id).cloned() {
            return ConnectState::Error { error };
        }
        let Some(chat) = self.chat(&connect.id) else { return ConnectState::Starting };
        let bot_user_id = chat.bot_user_id();
        if bot_user_id.is_empty() {
            return ConnectState::Starting;
        }
        let socket = chat.socket();
        let workspace = chat.identity();
        if socket.connected {
            ConnectState::Connected { bot_user_id, last_error: socket.last_error, workspace }
        } else {
            ConnectState::Reconnecting { bot_user_id, last_error: socket.last_error, workspace }
        }
    }

    /// Brings connections in line with `config`. Serialized, so rapid edits apply in order.
    pub async fn reconcile(self: &Arc<Self>, config: &Config) {
        let _order = self.chain.lock().await;
        self.apply(config).await;
        self.changed();
    }

    pub async fn stop_all(&self) {
        let _order = self.chain.lock().await;
        let chats: Vec<Arc<dyn Connection>> = self.chats.lock().unwrap().drain().map(|(_, c)| c).collect();
        for chat in chats {
            chat.stop().await;
        }
    }

    async fn apply(self: &Arc<Self>, config: &Config) {
        let wanted: HashMap<String, Connect> = config
            .connects
            .iter()
            .filter(|c| c.enabled && !c.slack.app_token.is_empty() && !c.slack.bot_token.is_empty())
            .map(|c| (c.id.clone(), c.clone()))
            .collect();
        let current: Vec<(String, Arc<dyn Connection>)> = self.chats.lock().unwrap().iter().map(|(k, v)| (k.clone(), v.clone())).collect();
        for (id, chat) in current {
            let keep = wanted.get(&id).is_some_and(|c| self.tokens.lock().unwrap().get(&id) == Some(&token_key(c)));
            if !keep {
                info!(connect = id, "disconnecting");
                self.chats.lock().unwrap().remove(&id);
                self.tokens.lock().unwrap().remove(&id);
                chat.stop().await;
            }
        }
        self.errors.lock().unwrap().retain(|id, _| wanted.contains_key(id));
        for connect in wanted.values() {
            if self.chats.lock().unwrap().contains_key(&connect.id) {
                continue;
            }
            self.errors.lock().unwrap().remove(&connect.id);
            let started = async {
                let chat = (self.create)(connect)?;
                // Its link's changes are the connects' changes.
                let mut changes = chat.changes();
                let me = Arc::downgrade(self);
                tokio::spawn(async move {
                    while changes.changed().await.is_ok() {
                        match me.upgrade() {
                            Some(me) => me.changed(),
                            None => return,
                        }
                    }
                });
                let on_event = self.on_event.clone();
                let id = connect.id.clone();
                let handler: Handler = Arc::new(move |event| on_event(id.clone(), event));
                let surface: Arc<dyn ChatSurface> = chat.clone();
                surface.start(handler).await?;
                Ok::<_, anyhow::Error>(chat)
            };
            match started.await {
                Ok(chat) => {
                    info!(connect = connect.id, bot_user_id = chat.bot_user_id(), "connected");
                    self.chats.lock().unwrap().insert(connect.id.clone(), chat);
                    self.tokens.lock().unwrap().insert(connect.id.clone(), token_key(connect));
                }
                Err(e) => {
                    error!(connect = connect.id, error = %e, "failed to connect");
                    self.errors.lock().unwrap().insert(connect.id.clone(), e.to_string());
                }
            }
        }
    }
}
