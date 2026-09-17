// Prevents additional console window on Windows in release
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod commands;
mod git;
mod models;
mod providers;
mod runtime;
mod store;
mod support;
mod terminal;
mod types;

use commands::init_commands;
use models::init_models;
use providers::init_providers;
use runtime::init_runtime;
use store::AppStore;
use support::init_support;
use terminal::init_terminal;
use tauri::Manager;
use types::init_types;
use std::sync::Arc;
use tokio::sync::RwLock;

pub struct AppState {
 pub store: Arc<RwLock<AppStore>>,
}

fn main() {
 tauri::Builder::default()
 .plugin(tauri_plugin_shell::init())
 .plugin(tauri_plugin_dialog::init())
 .plugin(tauri_plugin_fs::init())
 .plugin(tauri_plugin_http::init())
 .setup(|app| {
 // Initialize the app store
 let app_data_dir = app.path().app_data_dir()?;
 let store = AppStore::new(app_data_dir);

 // Manage both the raw Arc<RwLock<AppStore>> (so commands that reference
 // State<'_, Arc<RwLock<AppStore>>> resolve correctly) and the AppState
 // wrapper (for any future code that prefers named access).
 let shared_store: Arc<RwLock<AppStore>> = Arc::new(RwLock::new(store));
 app.manage(shared_store.clone());

 let state = AppState { store: shared_store };
 app.manage(state);

 // Initialize all modules
 init_types();
 init_models();
 init_providers();
 init_runtime();
 init_terminal();
 init_support();
 init_commands();

 Ok(())
 })
 .invoke_handler(tauri::generate_handler![
 // Projects
 commands::get_projects,
 commands::add_project,
 commands::delete_project,
 // Threads
 commands::get_threads,
 commands::create_thread,
 commands::delete_thread,
 commands::get_thread,
 commands::get_recent_threads,
 commands::get_thread_document,
 commands::update_thread_title,
 commands::search_threads,
 commands::pin_thread,
 commands::unpin_thread,
 commands::archive_thread,
 commands::get_thread_usage,
 // Messages
 commands::send_message,
 commands::get_messages,
 commands::delete_message,
 commands::regenerate_message,
 commands::stop_generation,
 commands::send_follow_up,
 commands::approve_request,
 commands::answer_question,
 // Providers
 commands::get_providers,
 commands::get_models_for_provider,
 commands::save_provider,
 commands::delete_provider,
 commands::test_provider,
 commands::get_available_models,
 commands::get_provider_credits,
 commands::refresh_provider_status,
 commands::get_provider_descriptors,
 // Settings
 commands::get_settings,
 commands::update_settings,
 commands::reset_settings,
 // Hydra
 commands::create_hydra,
 commands::get_hydra,
 commands::get_hydras,
 commands::update_hydra,
 commands::delete_hydra,
 commands::start_hydra_run,
 commands::stop_hydra_run,
 commands::launch_hydra_run,
 commands::stop_hydra_head,
 commands::land_hydra_head,
 // Library
 commands::get_library_items,
 commands::save_library_item,
 commands::delete_library_item,
 // Filesystem
 commands::get_file_preview,
 commands::read_file,
 commands::list_directory,
 commands::open_in_editor,
 // Git
 commands::git_status,
 commands::git_diff,
 commands::git_log,
 commands::git_blame,
 commands::get_touched_paths,
 commands::git_commit,
 commands::git_stage,
 commands::git_push,
 // Terminal
 commands::create_terminal_session,
 commands::execute_in_terminal,
 commands::write_terminal_input,
 commands::send_terminal_input,
 commands::send_terminal_signal,
 commands::resize_terminal,
 commands::close_terminal_session,
 commands::close_terminal,
 commands::get_terminal_sessions,
 // Shortcuts
 commands::get_registered_shortcuts,
 commands::register_shortcut,
 commands::unregister_shortcut,
 // Events
 commands::emit_message_chunk,
 commands::emit_hydra_progress,
 commands::emit_thread_update,
 commands::emit_terminal_output,
 // Misc
 commands::open_merge_link,
 commands::show_toast,
 commands::open_url,
 ])
 .run(tauri::generate_context!())
 .expect("error while running tauri application");
}
