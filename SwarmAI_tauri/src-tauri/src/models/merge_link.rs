use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Forge {
 Gitlab,
 Github,
 Gitea,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MergeRequestLink {
 pub url: String,
 pub forge: Forge,
 pub number: u32,
}

impl MergeRequestLink {
 pub fn label(&self) -> String {
 match self.forge {
 Forge::Gitlab => format!("!{}", self.number),
 _ => format!("#{}", self.number),
 }
 }

 pub fn title(&self) -> String {
 format!("Merge {}", self.label())
 }
}
