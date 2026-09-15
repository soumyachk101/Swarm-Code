use serde::{Deserialize, Serialize};

use super::thread::{ChatThread, Project};

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Library {
 pub projects: Vec<Project>,
 pub threads: Vec<ChatThread>,
}

impl Library {
 pub fn new() -> Self {
 Self::default()
 }
}
