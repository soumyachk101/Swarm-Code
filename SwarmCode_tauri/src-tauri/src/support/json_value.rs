//! JsonValue - flexible JSON representation.
//!
//! Mirrors the Swift `JSONValue` enum for representing arbitrary JSON data
//! (Null, Bool, Number, String, Array, Object).

use serde::{Deserialize, Deserializer, Serialize, Serializer};
use std::collections::HashMap;
use std::fmt;

// ---------------------------------------------------------------------------
// JsonValue
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq)]
pub enum JsonValue {
 Null,
 Bool(bool),
 Number(f64),
 String(String),
 Array(Vec<JsonValue>),
 Object(HashMap<String, JsonValue>),
}

impl JsonValue {
 /// Whether this value is null.
 pub fn is_null(&self) -> bool {
 matches!(self, JsonValue::Null)
 }

 /// Whether this value is a boolean.
 pub fn is_bool(&self) -> bool {
 matches!(self, JsonValue::Bool(_))
 }

 /// Whether this value is a number.
 pub fn is_number(&self) -> bool {
 matches!(self, JsonValue::Number(_))
 }

 /// Whether this value is a string.
 pub fn is_string(&self) -> bool {
 matches!(self, JsonValue::String(_))
 }

 /// Whether this value is an array.
 pub fn is_array(&self) -> bool {
 matches!(self, JsonValue::Array(_))
 }

 /// Whether this value is an object.
 pub fn is_object(&self) -> bool {
 matches!(self, JsonValue::Object(_))
 }

 /// Extract a boolean value if possible.
 pub fn as_bool(&self) -> Option<bool> {
 match self {
 JsonValue::Bool(b) => Some(*b),
 _ => None,
 }
 }

 /// Extract a string value if possible.
 pub fn as_string(&self) -> Option<&str> {
 match self {
 JsonValue::String(s) => Some(s),
 _ => None,
 }
 }

 /// Extract a number value if possible.
 pub fn as_number(&self) -> Option<f64> {
 match self {
 JsonValue::Number(n) => Some(*n),
 _ => None,
 }
 }

 /// Extract an integer value if possible.
 pub fn as_int(&self) -> Option<i64> {
 match self {
 JsonValue::Number(n) => Some(*n as i64),
 _ => None,
 }
 }

 /// Extract an array value if possible.
 pub fn as_array(&self) -> Option<&Vec<JsonValue>> {
 match self {
 JsonValue::Array(a) => Some(a),
 _ => None,
 }
 }

 /// Extract an object value if possible.
 pub fn as_object(&self) -> Option<&HashMap<String, JsonValue>> {
 match self {
 JsonValue::Object(o) => Some(o),
 _ => None,
 }
 }

 /// Convert to a serde_json::Value.
 pub fn to_serde_value(&self) -> serde_json::Value {
 match self {
 JsonValue::Null => serde_json::Value::Null,
 JsonValue::Bool(b) => serde_json::Value::Bool(*b),
 JsonValue::Number(n) => serde_json::Value::Number(
 serde_json::Number::from_f64(*n).unwrap_or(serde_json::Number::from(0)),
 ),
 JsonValue::String(s) => serde_json::Value::String(s.clone()),
 JsonValue::Array(arr) => {
 serde_json::Value::Array(arr.iter().map(|v| v.to_serde_value()).collect())
 }
 JsonValue::Object(obj) => {
 let map: serde_json::Map<String, serde_json::Value> = obj
 .iter()
 .map(|(k, v)| (k.clone(), v.to_serde_value()))
 .collect();
 serde_json::Value::Object(map)
 }
 }
 }

 /// Parse a JSON string into a JsonValue.
 pub fn parse(text: &str) -> Result<Self, String> {
 serde_json::from_str(text).map_err(|e| e.to_string())
 }

 /// Serialize to a JSON string.
 pub fn to_json(&self) -> Result<String, String> {
 serde_json::to_string(self).map_err(|e| e.to_string())
 }

 /// Serialize to a pretty JSON string.
 pub fn to_json_pretty(&self) -> Result<String, String> {
 serde_json::to_string_pretty(self).map_err(|e| e.to_string())
 }

 /// Deep clone.
 pub fn deep_clone(&self) -> Self {
 match self {
 JsonValue::Null => JsonValue::Null,
 JsonValue::Bool(b) => JsonValue::Bool(*b),
 JsonValue::Number(n) => JsonValue::Number(*n),
 JsonValue::String(s) => JsonValue::String(s.clone()),
 JsonValue::Array(arr) => JsonValue::Array(arr.iter().map(|v| v.deep_clone()).collect()),
 JsonValue::Object(obj) => {
 let mut new_obj = HashMap::new();
 for (k, v) in obj {
 new_obj.insert(k.clone(), v.deep_clone());
 }
 JsonValue::Object(new_obj)
 }
 }
 }
}

impl Default for JsonValue {
 fn default() -> Self {
 JsonValue::Null
 }
}

// ---------------------------------------------------------------------------
// Serde impls
// ---------------------------------------------------------------------------

impl Serialize for JsonValue {
 fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
 self.to_serde_value().serialize(serializer)
 }
}

impl<'de> Deserialize<'de> for JsonValue {
 fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
 let value = serde_json::Value::deserialize(deserializer)?;
 Ok(serde_json_value_to_json_value(value))
 }
}

// ---------------------------------------------------------------------------
// Conversion helpers
// ---------------------------------------------------------------------------

fn serde_json_value_to_json_value(value: serde_json::Value) -> JsonValue {
 match value {
 serde_json::Value::Null => JsonValue::Null,
 serde_json::Value::Bool(b) => JsonValue::Bool(b),
 serde_json::Value::Number(n) => {
 n.as_f64().map(JsonValue::Number).unwrap_or(JsonValue::Null)
 }
 serde_json::Value::String(s) => JsonValue::String(s),
 serde_json::Value::Array(arr) => {
 JsonValue::Array(arr.into_iter().map(serde_json_value_to_json_value).collect())
 }
 serde_json::Value::Object(obj) => {
 let mut map = HashMap::new();
 for (k, v) in obj {
 map.insert(k, serde_json_value_to_json_value(v));
 }
 JsonValue::Object(map)
 }
 }
}

// ---------------------------------------------------------------------------
// Pretty printing
// ---------------------------------------------------------------------------

impl fmt::Display for JsonValue {
 fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
 match self {
 JsonValue::Null => write!(f, "null"),
 JsonValue::Bool(b) => write!(f, "{b}"),
 JsonValue::Number(n) => write!(f, "{n}"),
 JsonValue::String(s) => write!(f, "\"{s}\""),
 JsonValue::Array(arr) => {
 write!(f, "[")?;
 for (i, v) in arr.iter().enumerate() {
 if i > 0 {
 write!(f, ", ")?;
 }
 write!(f, "{v}")?;
 }
 write!(f, "]")
 }
 JsonValue::Object(obj) => {
 write!(f, "{{")?;
 for (i, (k, v)) in obj.iter().enumerate() {
 if i > 0 {
 write!(f, ", ")?;
 }
 write!(f, "\"{k}\": {v}")?;
 }
 write!(f, "}}")
 }
 }
 }
}

// ---------------------------------------------------------------------------
// Equality / comparison
// ---------------------------------------------------------------------------

impl Eq for JsonValue {}

// ---------------------------------------------------------------------------
// Constructors
// ---------------------------------------------------------------------------

impl From<bool> for JsonValue {
 fn from(v: bool) -> Self {
 JsonValue::Bool(v)
 }
}

impl From<i64> for JsonValue {
 fn from(v: i64) -> Self {
 JsonValue::Number(v as f64)
 }
}

impl From<i32> for JsonValue {
 fn from(v: i32) -> Self {
 JsonValue::Number(v as f64)
 }
}

impl From<f64> for JsonValue {
 fn from(v: f64) -> Self {
 JsonValue::Number(v)
 }
}

impl From<String> for JsonValue {
 fn from(v: String) -> Self {
 JsonValue::String(v)
 }
}

impl From<&str> for JsonValue {
 fn from(v: &str) -> Self {
 JsonValue::String(v.to_string())
 }
}

impl From<Vec<JsonValue>> for JsonValue {
 fn from(v: Vec<JsonValue>) -> Self {
 JsonValue::Array(v)
 }
}

impl From<HashMap<String, JsonValue>> for JsonValue {
 fn from(v: HashMap<String, JsonValue>) -> Self {
 JsonValue::Object(v)
 }
}

impl<T> From<Option<T>> for JsonValue
where
 T: Into<JsonValue>,
 {
 fn from(opt: Option<T>) -> Self {
 opt.map(Into::into).unwrap_or(JsonValue::Null)
 }
 }

// ---------------------------------------------------------------------------
// Iterator helpers
// ---------------------------------------------------------------------------

impl<'a> IntoIterator for &'a JsonValue {
 type Item = &'a JsonValue;
 type IntoIter = std::slice::Iter<'a, JsonValue>;

 fn into_iter(self) -> Self::IntoIter {
 match self {
 JsonValue::Array(arr) => arr.iter(),
 _ => [].iter(),
 }
 }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
 use super::*;

 #[test]
 fn test_parse_string() {
 let v = JsonValue::parse("{\"key\": \"value\"}").unwrap();
 assert_eq!(v.as_object().unwrap().get("key").unwrap().as_string(), Some("value"));
 }

 #[test]
 fn test_roundtrip() {
 let original = JsonValue::Object({
 let mut map = HashMap::new();
 map.insert("name".into(), JsonValue::String("test".into()));
 map.insert("count".into(), JsonValue::Number(42.0));
 map
 });

 let json = original.to_json().unwrap();
 let parsed = JsonValue::parse(&json).unwrap();
 assert_eq!(original, parsed);
 }

 #[test]
 fn test_display() {
 let v = JsonValue::String("hello".into());
 assert_eq!(v.to_string(), "\"hello\"");
 }
}
