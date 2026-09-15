use std::path::PathBuf;

pub struct Coding;

impl Coding {
 pub fn json_parse_loose(_text: &str) -> Option<Vec<String>> {
 None
 }
}

pub struct Lenient<T>(pub T);

use serde::Deserialize;

impl<'de, T: Deserialize<'de>> Deserialize<'de> for Lenient<T> {
 fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
 where
 D: serde::Deserializer<'de>,
 {
 let value = serde_json::Value::deserialize(deserializer)?;
 T::deserialize(value).map(Lenient).map_err(|_| serde::de::Error::custom("decode failed"))
 }
}
