//! The core's storage on the web: one IndexedDB object store of keys → bytes.
//! A worker has no localStorage, and IndexedDB is shared by every tab's worker
//! on the origin.

use std::cell::RefCell;
use std::rc::Rc;

use ember_core::host::HostError;
use futures::FutureExt;
use futures::future::{LocalBoxFuture, Shared};
use js_sys::{Promise, Reflect, Uint8Array};
use wasm_bindgen::prelude::*;
use wasm_bindgen_futures::JsFuture;
use web_sys::{IdbDatabase, IdbFactory, IdbRequest, IdbTransaction, IdbTransactionMode};

use crate::host::js_error;

const DATABASE: &str = "ember-core";
const VERSION: u32 = 1;
const STORE: &str = "values";

type Open = Shared<LocalBoxFuture<'static, Result<IdbDatabase, HostError>>>;

/// Opens the database once, on first use; a failed open is retried by the next use.
#[derive(Clone, Default)]
pub struct Storage {
    db: Rc<RefCell<Option<Open>>>,
}

impl Storage {
    async fn db(&self) -> Result<IdbDatabase, HostError> {
        let open = self.db.borrow_mut().get_or_insert_with(|| open().boxed_local().shared()).clone();
        let db = open.await;
        if db.is_err() {
            self.db.borrow_mut().take();
        }
        db
    }

    /// A transaction on the store. The browser can close the database under us
    /// (storage cleared, Safari evicting): then open it again.
    async fn transaction(&self, mode: IdbTransactionMode) -> Result<IdbTransaction, HostError> {
        let db = self.db().await?;
        match db.transaction_with_str_and_mode(STORE, mode) {
            Ok(tx) => Ok(tx),
            Err(_) => {
                self.db.borrow_mut().take();
                self.db().await?.transaction_with_str_and_mode(STORE, mode).map_err(js_error)
            }
        }
    }

    pub async fn get(&self, key: String) -> Result<Option<Vec<u8>>, HostError> {
        let tx = self.transaction(IdbTransactionMode::Readonly).await?;
        let request = tx.object_store(STORE).map_err(js_error)?.get(&JsValue::from_str(&key)).map_err(js_error)?;
        let value = done(&request).await?;
        Ok(if value.is_undefined() { None } else { Some(Uint8Array::new(&value).to_vec()) })
    }

    pub async fn set(&self, key: String, value: Vec<u8>) -> Result<(), HostError> {
        let tx = self.transaction(IdbTransactionMode::Readwrite).await?;
        let bytes = Uint8Array::from(value.as_slice());
        tx.object_store(STORE).map_err(js_error)?.put_with_key(&bytes, &JsValue::from_str(&key)).map_err(js_error)?;
        committed(&tx).await
    }

    pub async fn delete(&self, key: String) -> Result<(), HostError> {
        let tx = self.transaction(IdbTransactionMode::Readwrite).await?;
        tx.object_store(STORE).map_err(js_error)?.delete(&JsValue::from_str(&key)).map_err(js_error)?;
        committed(&tx).await
    }
}

async fn open() -> Result<IdbDatabase, HostError> {
    let factory: IdbFactory = Reflect::get(&js_sys::global(), &JsValue::from_str("indexedDB"))
        .ok()
        .filter(|f| !f.is_undefined() && !f.is_null())
        .ok_or_else(|| HostError("这个浏览器没有 IndexedDB".into()))?
        .unchecked_into();
    let request = factory.open_with_u32(DATABASE, VERSION).map_err(js_error)?;
    let upgrade_request = request.clone();
    let upgrade = Closure::<dyn FnMut()>::new(move || {
        // Version 1 is the first: the store is always new here.
        if let Ok(db) = upgrade_request.result() {
            let _ = db.unchecked_into::<IdbDatabase>().create_object_store(STORE);
        }
    });
    request.set_onupgradeneeded(Some(upgrade.as_ref().unchecked_ref()));
    let db = done(&request).await;
    request.set_onupgradeneeded(None);
    drop(upgrade);
    let db: IdbDatabase = db?.unchecked_into();
    // Another tab upgrading the schema later must not be blocked by us.
    let closing = db.clone();
    let on_version_change = Closure::<dyn FnMut()>::new(move || closing.close());
    db.set_onversionchange(Some(on_version_change.as_ref().unchecked_ref()));
    on_version_change.forget();
    Ok(db)
}

/// The result of one request.
async fn done(request: &IdbRequest) -> Result<JsValue, HostError> {
    let promise = Promise::new(&mut |resolve, reject| {
        request.set_onsuccess(Some(&resolve));
        request.set_onerror(Some(&reject));
    });
    let outcome = JsFuture::from(promise).await;
    request.set_onsuccess(None);
    request.set_onerror(None);
    match outcome {
        Ok(_) => request.result().map_err(js_error),
        Err(_) => Err(match request.error() {
            Ok(Some(error)) => HostError(error.message()),
            _ => HostError("IndexedDB 请求失败".into()),
        }),
    }
}

/// Waits until a write is durable, not merely queued.
async fn committed(tx: &IdbTransaction) -> Result<(), HostError> {
    let promise = Promise::new(&mut |resolve, reject| {
        tx.set_oncomplete(Some(&resolve));
        tx.set_onerror(Some(&reject));
        tx.set_onabort(Some(&reject));
    });
    let outcome = JsFuture::from(promise).await;
    match outcome {
        Ok(_) => Ok(()),
        Err(_) => Err(match tx.error() {
            Some(error) => HostError(error.message()),
            None => HostError("IndexedDB 写入没有完成".into()),
        }),
    }
}
