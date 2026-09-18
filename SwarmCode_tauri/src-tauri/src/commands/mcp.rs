use super::*;

#[tauri::command]
pub async fn add_mcp_connection(
 connection: crate::mcp::store::MCPConnection,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<crate::mcp::store::MCPConnection, String> {
 let mut store = state.write().await;
 store.add_mcp_connection(connection.clone());
 Ok(connection)
}

#[tauri::command]
pub async fn delete_mcp_connection(
 catalog_id: String,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<(), String> {
 let mut store = state.write().await;
 if !store.delete_mcp_connection(&catalog_id) {
  return Err("Not found".to_string());
 }
 Ok(())
}

#[tauri::command]
pub async fn get_mcp_connections(
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<Vec<crate::mcp::store::MCPConnection>, String> {
 let store = state.read().await;
 Ok(store.mcp.connections.clone())
}

#[tauri::command]
pub async fn get_mcp_connection(
 catalog_id: String,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<Option<crate::mcp::store::MCPConnection>, String> {
 let store = state.read().await;
 Ok(store.get_mcp_connection(&catalog_id).cloned())
}

#[tauri::command]
pub async fn update_mcp_connection(
 connection: crate::mcp::store::MCPConnection,
 state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<crate::mcp::store::MCPConnection, String> {
 let mut store = state.write().await;
 store.update_mcp_connection(connection.clone());
 Ok(connection)
}

#[tauri::command]
pub async fn get_mcp_catalog(
 _state: State<'_, Arc<RwLock<AppStore>>>,
) -> Result<Vec<crate::mcp::MCPCatalogEntry>, String> {
 let catalog = crate::mcp::MCPCatalog::global();
 Ok(catalog.list_all())
}
