#![allow(dead_code, unused_variables, unused_imports, unused_mut, non_camel_case_types, unused_must_use)]

mod bridge;
mod commands;
mod models;
mod store;

use bridge::MobileBridgeClient;
use commands::*;
use store::MobileStore;
use tokio::sync::RwLock;

use tauri::Manager;

#[cfg_attr(any(target_os = "ios", target_os = "android"), tauri::mobile_main_fn)]
fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_http::init())
        .plugin(tauri_plugin_notification::init())
        .setup(|app| {
            let store = std::sync::Arc::new(RwLock::new(MobileStore::new()));
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
            commands::pair_with_code,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
