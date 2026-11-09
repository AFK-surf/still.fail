//! Signatures checked by formally verified implementations (Cryspen's libcrux: HACL*'s Ed25519 and P-256, proved in
//! F*), for the station in TypeScript (src/cloud/lock.ts `verifyWith`): the workspace lock's entries, a device's proof of
//! its endpoint, the vault's records. The same implementation a native app's shell checks them with
//! (client/shell `crypto.verify`).

use napi::bindgen_prelude::Buffer;
use napi_derive::napi;

/// Whether `signature` is `key`'s over `message`: `Ed25519` (a 32-byte key, a 64-byte signature), `ES256` (ECDSA P-256
/// over SHA-256: an uncompressed point, r‖s) or `ES256-der` (the signature DER, as WebAuthn gives it); false for
/// anything else, or anything malformed.
#[napi]
pub fn verify(alg: String, key: Buffer, signature: Buffer, message: Buffer) -> bool {
    match alg.as_str() {
        "Ed25519" => match (<[u8; 32]>::try_from(&key[..]), <[u8; 64]>::try_from(&signature[..])) {
            (Ok(k), Ok(s)) => libcrux_ed25519::verify(&message, &k, &s).is_ok(),
            _ => false,
        },
        "ES256" | "ES256-der" => {
            use libcrux_ecdsa::p256::{PublicKey, Signature, verify};
            let s = if alg == "ES256" { <[u8; 64]>::try_from(&signature[..]).ok().map(Signature::from_bytes) } else { Signature::from_der(&signature).ok() };
            match (s, PublicKey::try_from(&key[..])) {
                (Some(s), Ok(k)) if key.len() == 65 => verify(libcrux_ecdsa::DigestAlgorithm::Sha256, &message, &s, &k).is_ok(),
                _ => false,
            }
        }
        _ => false,
    }
}
