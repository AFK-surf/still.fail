//! What changed between two values of a topic, as a few ops, so a long
//! transcript that grew by one message goes out as one `append`.
//!
//! An op names a place by its path (object keys, array indexes) and either
//! sets it, appends to the array there, or removes the key. Objects are
//! compared key by key; an array that only grew gets an `append`, one of the
//! same length is compared item by item, anything else is `set` whole.

use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum Segment {
    Index(usize),
    Key(String),
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum Op {
    Set { path: Vec<Segment>, set: Value },
    Append { path: Vec<Segment>, append: Vec<Value> },
    Remove { path: Vec<Segment>, remove: bool },
}

/// The ops that turn `old` into `new`; empty when they are equal.
pub fn diff(old: &Value, new: &Value) -> Vec<Op> {
    let mut ops = Vec::new();
    diff_at(&mut Vec::new(), old, new, &mut ops);
    ops
}

fn diff_at(path: &mut Vec<Segment>, old: &Value, new: &Value, ops: &mut Vec<Op>) {
    match (old, new) {
        (Value::Object(old), Value::Object(new)) => {
            for (key, value) in new {
                path.push(Segment::Key(key.clone()));
                match old.get(key) {
                    Some(before) => diff_at(path, before, value, ops),
                    None => ops.push(Op::Set { path: path.clone(), set: value.clone() }),
                }
                path.pop();
            }
            for key in old.keys().filter(|k| !new.contains_key(*k)) {
                let mut path = path.clone();
                path.push(Segment::Key(key.clone()));
                ops.push(Op::Remove { path, remove: true });
            }
        }
        (Value::Array(old), Value::Array(new)) if old.len() == new.len() => {
            for (i, (before, value)) in old.iter().zip(new).enumerate() {
                path.push(Segment::Index(i));
                diff_at(path, before, value, ops);
                path.pop();
            }
        }
        (Value::Array(old), Value::Array(new)) if old.len() < new.len() && new.starts_with(old) => {
            ops.push(Op::Append { path: path.clone(), append: new[old.len()..].to_vec() });
        }
        _ if old == new => {}
        _ => ops.push(Op::Set { path: path.clone(), set: new.clone() }),
    }
}

/// Applies ops made by [`diff`]; an op whose path does not fit the value is skipped.
pub fn apply(value: &mut Value, ops: &[Op]) {
    for op in ops {
        match op {
            Op::Set { path, set } => {
                if let Some(place) = place(value, path) {
                    *place = set.clone();
                }
            }
            Op::Append { path, append } => {
                if let Some(Value::Array(items)) = place(value, path) {
                    items.extend(append.iter().cloned());
                }
            }
            Op::Remove { path, .. } => {
                let Some((Segment::Key(key), parent)) = path.split_last() else { continue };
                if let Some(Value::Object(map)) = place(value, parent) {
                    map.remove(key);
                }
            }
        }
    }
}

/// The value at `path`; a missing last key is created in its object.
fn place<'a>(value: &'a mut Value, path: &[Segment]) -> Option<&'a mut Value> {
    let mut at = value;
    for segment in path {
        at = match (at, segment) {
            (Value::Object(map), Segment::Key(key)) => map.entry(key.clone()).or_insert(Value::Null),
            (Value::Array(items), Segment::Index(i)) => items.get_mut(*i)?,
            _ => return None,
        };
    }
    Some(at)
}

/// Whether `ops` take more bytes as JSON than `value` itself: then the value is sent whole.
pub fn larger_than(ops: &[Op], value: &Value) -> bool {
    let size = serde_json::to_vec(ops).map(|b| b.len()).unwrap_or(usize::MAX);
    // Serializing the value stops as soon as it passes that size.
    serde_json::to_writer(Budget(size), value).is_ok()
}

/// A writer that fails once more than its budget of bytes went in.
struct Budget(usize);

impl std::io::Write for Budget {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        self.0 = self.0.checked_sub(buf.len()).ok_or_else(|| std::io::Error::other("over budget"))?;
        Ok(buf.len())
    }
    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn round_trip(old: Value, new: Value) -> Vec<Op> {
        let ops = diff(&old, &new);
        let mut patched = old.clone();
        apply(&mut patched, &ops);
        assert_eq!(patched, new, "ops {}", serde_json::to_string(&ops).unwrap());
        ops
    }

    #[test]
    fn equal_values_need_no_ops() {
        assert!(round_trip(json!({"a": [1, {"b": null}]}), json!({"a": [1, {"b": null}]})).is_empty());
    }

    #[test]
    fn a_grown_array_is_one_append() {
        let ops = round_trip(json!({"detail": {"timeline": [1, 2], "usage": {"n": 1}}}), json!({"detail": {"timeline": [1, 2, 3, 4], "usage": {"n": 1}}}));
        assert_eq!(serde_json::to_value(&ops).unwrap(), json!([{"path": ["detail", "timeline"], "append": [3, 4]}]));
    }

    #[test]
    fn an_edited_item_is_one_set() {
        let ops = round_trip(json!({"items": [{"text": "a"}, {"text": "b"}]}), json!({"items": [{"text": "a"}, {"text": "bc"}]}));
        assert_eq!(serde_json::to_value(&ops).unwrap(), json!([{"path": ["items", 1, "text"], "set": "bc"}]));
    }

    #[test]
    fn keys_are_added_and_removed() {
        let ops = round_trip(json!({"state": "offline", "message": "断了"}), json!({"state": "online", "since": 5}));
        let ops = serde_json::to_value(&ops).unwrap();
        assert_eq!(ops.as_array().unwrap().len(), 3);
        for op in [json!({"path": ["state"], "set": "online"}), json!({"path": ["since"], "set": 5}), json!({"path": ["message"], "remove": true})] {
            assert!(ops.as_array().unwrap().contains(&op), "{ops}");
        }
    }

    #[test]
    fn anything_else_is_set_whole() {
        // Shrunk, reordered, changed kind, or a new root.
        let ops = round_trip(json!({"a": [1, 2, 3]}), json!({"a": [1, 2]}));
        assert_eq!(serde_json::to_value(&ops).unwrap(), json!([{"path": ["a"], "set": [1, 2]}]));
        let ops = round_trip(json!({"a": [1, 2]}), json!({"a": [0, 1, 2]}));
        assert_eq!(serde_json::to_value(&ops).unwrap(), json!([{"path": ["a"], "set": [0, 1, 2]}]));
        round_trip(json!({"a": {"b": 1}}), json!({"a": [1]}));
        let ops = round_trip(json!([1]), json!("x"));
        assert_eq!(serde_json::to_value(&ops).unwrap(), json!([{"path": [], "set": "x"}]));
    }

    #[test]
    fn ops_parse_back() {
        let ops = diff(&json!({"a": [1], "b": {"c": 1}, "d": 0}), &json!({"a": [1, 2], "b": {"c": 2}}));
        let text = serde_json::to_string(&ops).unwrap();
        assert_eq!(serde_json::from_str::<Vec<Op>>(&text).unwrap(), ops);
    }

    #[test]
    fn knows_when_ops_outgrow_the_value() {
        let small = json!({"state": "online"});
        assert!(larger_than(&diff(&json!({"state": "offline"}), &small), &small));
        let long = json!({"timeline": (0..100).map(|i| format!("message {i}")).collect::<Vec<_>>()});
        let mut longer = long.clone();
        longer["timeline"].as_array_mut().unwrap().push(json!("one more"));
        assert!(!larger_than(&diff(&long, &longer), &longer));
    }
}
