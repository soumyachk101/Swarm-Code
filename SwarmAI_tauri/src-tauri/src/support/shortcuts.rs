use std::path::PathBuf;
use std::process::Command;

pub fn launch_url(url: &str) {
 let _ = Command::new("open").arg(url).spawn();
}

pub fn reveal_in_finder(path: &PathBuf) {
 let _ = Command::new("open").arg("-R").arg(path).spawn();
}

pub fn open_in_editor(path: &PathBuf, line: Option<u32>) {
 let mut args: Vec<String> = vec!["-n".into(), "--args".into()];
 if let Some(l) = line {
 args.extend([format!("--goto").into(), format!("{}:{}", path.display(), l).into()]);
 }
 args.push(path.to_string_lossy().into());

 // Try Xcode first, then other editors
 for editor in ["xed", "code", "vim"] {
 let mut cmd_args = args.clone();
 if editor == "xed" && line.is_some() {
 cmd_args.clear();
 cmd_args.extend(["-l".into(), line.unwrap().to_string(), "-n".into(), path.to_string_lossy().into()]);
 }
 let _ = Command::new(editor).args(&cmd_args).spawn();
 return;
 }
}
