use async_trait::async_trait;
use std::sync::Arc;
use uuid::Uuid;

use crate::models::provider::ProviderKind;
use crate::providers::session::{
 ProviderError, ProviderSession, SessionConfiguration, SessionEvent, SessionStatus, TurnInput,
};

pub struct AntigravitySession;

#[async_trait]
impl ProviderSession for AntigravitySession {
 fn on_event(&self) -> Option<Arc<dyn Fn(SessionEvent) + Send + Sync>> {
 None
 }
 fn set_on_event(&mut self, _handler: Arc<dyn Fn(SessionEvent) + Send + Sync>) {}

 fn status(&self) -> SessionStatus {
 SessionStatus::Idle
 }
 fn is_running(&self) -> bool {
 false
 }

 fn provider_kind(&self) -> ProviderKind {
 ProviderKind::Antigravity
 }

 async fn start(&mut self, _config: SessionConfiguration) -> Result<String, ProviderError> {
 Ok(Uuid::new_v4().to_string())
 }

 async fn send(&mut self, _input: TurnInput) -> Result<(), ProviderError> {
 Ok(())
 }

 async fn interrupt(&mut self) {}

 async fn resolve_approval(&mut self, _request_id: String, _option_id: String) {}

 async fn answer_question(
 &mut self,
 _request_id: String,
 _answers: std::collections::HashMap<String, Vec<String>>,
 ) {
 }

 async fn compact(&mut self) -> Result<(), ProviderError> {
 Ok(())
 }

 async fn stop(&mut self) {}
}
