use std::sync::Arc;
use tokio::sync::RwLock;
use tauri::Manager;

mod bridge;
mod commands;
mod models;
mod store;

use bridge::MobileBridgeClient;
use store::MobileStore;

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_http::init())
        .plugin(tauri_plugin_notification::init())
        .setup(|app| {
            let store = Arc::new(RwLock::new(MobileStore::new()));
            let bridge = MobileBridgeClient::new(store.clone());

            app.manage(store);
            app.manage(bridge);

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_connection_status,
            commands::connect_to_bridge,
            commands::disconnect_bridge,
            commands::discover_bridges,
            commands::get_threads,
            commands::get_thread_detail,
            commands::send_message,
            commands::approve_action,
            commands::reject_action,
            commands::create_thread,
            commands::get_models,
            commands::get_git_status,
            commands::save_pairing,
            commands::get_saved_pairings,
            commands::delete_pairing,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
