//! The `Host` of a web worker. Everything goes through the global scope
//! (`fetch`, `setTimeout`, `crypto`, `indexedDB`, `location`) rather than
//! `window`, so the same build also runs on a page when debugging.

use ember_core::host::{Host, HostError, HttpRequest, HttpResponse, StreamResponse};
use ember_core::{ClientId, CoreError, CoreMessage};
use futures::future::LocalBoxFuture;
use futures::stream::{self, StreamExt};
use js_sys::{Array, Function, Promise, Reflect, Uint8Array};
use serde::Serialize;
use wasm_bindgen::prelude::*;
use wasm_bindgen_futures::JsFuture;
use web_sys::{AbortController, Crypto, Headers, ReadableStreamDefaultReader, Request, RequestInit, Response};

use crate::idb::Storage;

#[wasm_bindgen]
extern "C" {
    #[wasm_bindgen(js_name = fetch)]
    fn global_fetch(request: &Request) -> Promise;
    #[wasm_bindgen(js_name = setTimeout)]
    fn set_timeout(handler: &Function, ms: i32) -> JsValue;
}

pub struct WebHost {
    emit: Function,
    storage: Storage,
}

impl WebHost {
    pub fn new(emit: Function) -> WebHost {
        WebHost { emit, storage: Storage::default() }
    }
}

pub fn js_error(error: JsValue) -> HostError {
    if let Some(error) = error.dyn_ref::<js_sys::Error>() {
        return HostError(error.message().into());
    }
    match error.as_string() {
        Some(text) => HostError(text),
        None => HostError(format!("{error:?}")),
    }
}

fn global(name: &str) -> JsValue {
    Reflect::get(&js_sys::global(), &JsValue::from_str(name)).unwrap_or(JsValue::UNDEFINED)
}

fn request(request: HttpRequest, controller: Option<&AbortController>) -> Result<Request, HostError> {
    let init = RequestInit::new();
    init.set_method(&request.method);
    let headers = Headers::new().map_err(js_error)?;
    for (name, value) in &request.headers {
        headers.append(name, value).map_err(js_error)?;
    }
    init.set_headers(&headers);
    if let Some(body) = &request.body {
        init.set_body(&Uint8Array::from(body.as_slice()));
    }
    if let Some(controller) = controller {
        init.set_signal(Some(&controller.signal()));
    }
    Request::new_with_str_and_init(&request.url, &init).map_err(js_error)
}

async fn send(request: Request) -> Result<Response, HostError> {
    let response = JsFuture::from(global_fetch(&request)).await.map_err(js_error)?;
    Ok(response.unchecked_into())
}

fn headers(response: &Response) -> Vec<(String, String)> {
    let mut out = Vec::new();
    if let Ok(Some(entries)) = js_sys::try_iter(&response.headers()) {
        for entry in entries.flatten() {
            let pair: Array = entry.unchecked_into();
            out.push((pair.get(0).as_string().unwrap_or_default(), pair.get(1).as_string().unwrap_or_default()));
        }
    }
    out
}

/// A streamed body. Dropping it before the end aborts the fetch, so an event
/// stream the core lets go of does not stay open.
struct Body {
    reader: Option<ReadableStreamDefaultReader>,
    controller: AbortController,
}

impl Drop for Body {
    fn drop(&mut self) {
        if self.reader.is_some() {
            self.controller.abort();
        }
    }
}

async fn next_chunk(mut body: Body) -> Option<(Result<Vec<u8>, HostError>, Body)> {
    let reader = body.reader.clone()?;
    match JsFuture::from(reader.read()).await {
        Ok(chunk) => {
            let done = Reflect::get(&chunk, &JsValue::from_str("done")).ok().and_then(|d| d.as_bool()).unwrap_or(true);
            if done {
                body.reader = None;
                return None;
            }
            let value = Reflect::get(&chunk, &JsValue::from_str("value")).unwrap_or(JsValue::UNDEFINED);
            Some((Ok(Uint8Array::new(&value).to_vec()), body))
        }
        Err(error) => {
            body.reader = None;
            Some((Err(js_error(error)), body))
        }
    }
}

impl Host for WebHost {
    fn cloud_origin(&self) -> String {
        Reflect::get(&global("location"), &JsValue::from_str("origin")).ok().and_then(|o| o.as_string()).unwrap_or_default()
    }

    fn fetch(&self, req: HttpRequest) -> LocalBoxFuture<'static, Result<HttpResponse, HostError>> {
        Box::pin(async move {
            let response = send(request(req, None)?).await?;
            let body = JsFuture::from(response.array_buffer().map_err(js_error)?).await.map_err(js_error)?;
            Ok(HttpResponse { status: response.status(), headers: headers(&response), body: Uint8Array::new(&body).to_vec() })
        })
    }

    fn fetch_stream(&self, req: HttpRequest) -> LocalBoxFuture<'static, Result<StreamResponse, HostError>> {
        Box::pin(async move {
            let controller = AbortController::new().map_err(js_error)?;
            let response = send(request(req, Some(&controller))?).await?;
            let reader = response.body().map(|body| body.get_reader().unchecked_into::<ReadableStreamDefaultReader>());
            let body = stream::unfold(Body { reader, controller }, next_chunk).boxed_local();
            Ok(StreamResponse { status: response.status(), headers: headers(&response), body })
        })
    }

    fn storage_get(&self, key: &str) -> LocalBoxFuture<'static, Result<Option<Vec<u8>>, HostError>> {
        let (storage, key) = (self.storage.clone(), key.to_owned());
        Box::pin(async move { storage.get(key).await })
    }

    fn storage_set(&self, key: &str, value: Vec<u8>) -> LocalBoxFuture<'static, Result<(), HostError>> {
        let (storage, key) = (self.storage.clone(), key.to_owned());
        Box::pin(async move { storage.set(key, value).await })
    }

    fn storage_delete(&self, key: &str) -> LocalBoxFuture<'static, Result<(), HostError>> {
        let (storage, key) = (self.storage.clone(), key.to_owned());
        Box::pin(async move { storage.delete(key).await })
    }

    fn now_ms(&self) -> f64 {
        js_sys::Date::now()
    }

    fn utc_offset_min(&self, at_ms: f64) -> i32 {
        -js_sys::Date::new(&JsValue::from_f64(at_ms)).get_timezone_offset() as i32
    }

    fn sleep(&self, ms: u64) -> LocalBoxFuture<'static, ()> {
        // setTimeout takes a signed 32-bit delay; anything longer fires at once.
        let ms = ms.min(i32::MAX as u64) as i32;
        let promise = Promise::new(&mut |resolve, _| {
            set_timeout(&resolve, ms);
        });
        Box::pin(async move {
            let _ = JsFuture::from(promise).await;
        })
    }

    fn spawn(&self, task: LocalBoxFuture<'static, ()>) {
        wasm_bindgen_futures::spawn_local(task);
    }

    fn random_bytes(&self, buf: &mut [u8]) {
        let crypto: Crypto = global("crypto").unchecked_into();
        // getRandomValues fills at most 64 KiB per call.
        for chunk in buf.chunks_mut(65536) {
            crypto.get_random_values_with_u8_array(chunk).expect("crypto.getRandomValues");
        }
    }

    fn emit(&self, client: ClientId, message: CoreMessage) {
        let serializer = serde_wasm_bindgen::Serializer::json_compatible();
        let value = match message.serialize(&serializer) {
            Ok(value) => value,
            Err(error) => {
                // Someone is waiting on this id: tell them instead of dropping it.
                let id = match &message {
                    CoreMessage::Ok { id, .. } | CoreMessage::Error { id, .. } | CoreMessage::Value { id, .. } | CoreMessage::Delta { id, .. } => *id,
                };
                let error = CoreMessage::Error { id, error: CoreError::new("host", format!("无法传给页面：{error}")) };
                match error.serialize(&serializer) {
                    Ok(value) => value,
                    Err(_) => return,
                }
            }
        };
        // The worker's callback routes by client id; its own failures are its to handle.
        let _ = self.emit.call2(&JsValue::NULL, &JsValue::from_f64(client as f64), &value);
    }
}
