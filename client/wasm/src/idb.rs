//! The core's storage on the web: one IndexedDB object store of keys → bytes
//! (`values`), and the core's database (docs/core-db.md) as another, records
//! by [table, key] (`records`). A worker has no localStorage, and IndexedDB is
//! shared by every tab's worker on the origin.

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
const VERSION: u32 = 2;
const STORE: &str = "values";
const RECORDS: &str = "records";

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
        self.transaction_on(STORE, mode).await
    }

    async fn transaction_on(&self, store: &str, mode: IdbTransactionMode) -> Result<IdbTransaction, HostError> {
        let db = self.db().await?;
        match db.transaction_with_str_and_mode(store, mode) {
            Ok(tx) => Ok(tx),
            Err(_) => {
                self.db.borrow_mut().take();
                self.db().await?.transaction_with_str_and_mode(store, mode).map_err(js_error)
            }
        }
    }

    /// A table's records with keys in `[from, to)`, in key order.
    pub async fn records(&self, table: String, from: String, to: String) -> Result<Vec<(String, Vec<u8>)>, HostError> {
        let tx = self.transaction_on(RECORDS, IdbTransactionMode::Readonly).await?;
        let store = tx.object_store(RECORDS).map_err(js_error)?;
        let bound = |key: &str| js_sys::Array::of2(&JsValue::from_str(&table), &JsValue::from_str(key));
        let range = web_sys::IdbKeyRange::bound_with_lower_open_and_upper_open(&bound(&from), &bound(&to), false, true).map_err(js_error)?;
        // Both in key order, in one transaction: they line up.
        let keys = store.get_all_keys_with_key(&range).map_err(js_error)?;
        let values = store.get_all_with_key(&range).map_err(js_error)?;
        let keys: js_sys::Array = done(&keys).await?.unchecked_into();
        let values: js_sys::Array = done(&values).await?.unchecked_into();
        Ok(keys
            .iter()
            .zip(values.iter())
            .filter_map(|(key, value)| {
                let key = js_sys::Array::from(&key).get(1).as_string()?;
                Some((key, Uint8Array::new(&value).to_vec()))
            })
            .collect())
    }

    /// A batch of changes, all or none.
    pub async fn write_records(&self, ops: Vec<ember_core::host::DbOp>) -> Result<(), HostError> {
        let tx = self.transaction_on(RECORDS, IdbTransactionMode::Readwrite).await?;
        let store = tx.object_store(RECORDS).map_err(js_error)?;
        for op in ops {
            match op {
                ember_core::host::DbOp::Put { table, key, value } => {
                    let at = js_sys::Array::of2(&JsValue::from_str(&table), &JsValue::from_str(&key));
                    store.put_with_key(&Uint8Array::from(value.as_slice()), &at).map_err(js_error)?;
                }
                ember_core::host::DbOp::Delete { table, key } => {
                    let at = js_sys::Array::of2(&JsValue::from_str(&table), &JsValue::from_str(&key));
                    store.delete(&at).map_err(js_error)?;
                }
            }
        }
        committed(&tx).await
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
        // Version 1 made `values`; version 2 adds `records`. Each store is made if it is not there yet.
        if let Ok(db) = upgrade_request.result() {
            let db = db.unchecked_into::<IdbDatabase>();
            let names = db.object_store_names();
            for store in [STORE, RECORDS] {
                if !names.contains(store) {
                    let _ = db.create_object_store(store);
                }
            }
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
