use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiffLine {
 pub id: usize,
 pub kind: DiffLineKind,
 pub text: String,
 pub old_number: Option<usize>,
 pub new_number: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum DiffLineKind {
 Context,
 Addition,
 Deletion,
 Note,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiffHunk {
 pub id: usize,
 pub header: String,
 pub lines: Vec<DiffLine>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiffFile {
 pub path: String,
 pub old_path: Option<String>,
 pub change: DiffChange,
 pub is_binary: bool,
 pub hunks: Vec<DiffHunk>,
 pub additions: usize,
 pub deletions: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum DiffChange {
 Added,
 Deleted,
 Modified,
 Renamed,
}

impl DiffFile {
 pub fn id(&self) -> String {
 self.path.clone()
 }

 pub fn name(&self) -> String {
 std::path::Path::new(&self.path)
 .file_name()
 .and_then(|n| n.to_str())
 .unwrap_or(&self.path)
 .to_string()
 }

 pub fn directory(&self) -> String {
 std::path::Path::new(&self.path)
 .parent()
 .map(|p| {
 let s = p.to_string_lossy();
 if s.is_empty() { String::new() } else { format!("{}/", s) }
 })
 .unwrap_or_default()
 }
}

pub struct DiffParser;

impl DiffParser {
 /// Parse `git diff` output into structured files, hunks and lines.
 pub fn parse(patch: &str) -> Vec<DiffFile> {
 let mut files: Vec<DiffFile> = Vec::new();
 let mut current: Option<DiffFile> = None;
 let mut hunk: Option<DiffHunk> = None;
 let mut line_id = 0;

 fn close_hunk(current: &mut Option<DiffFile>, hunk: Option<DiffHunk>) {
 if let Some(mut c) = current.take() {
 if let Some(h) = hunk {
 c.hunks.push(h);
 }
 *current = Some(c);
 }
 }

 fn close_file(files: &mut Vec<DiffFile>, current: &mut Option<DiffFile>) {
 if let Some(mut c) = current.take() {
 if let Some(ref h) = c.hunks.last() {
 // already pushed
 }
 files.push(c);
 }
 }

 for raw_line in patch.split_inclusive('\n') {
 let line = raw_line.trim_end_matches('\n');

 if line.starts_with("diff --git ") {
 close_file(&mut files, &mut current);
 let path = Self::header_path(line);
 let (change, old_path) = if path.contains("=>") || line.contains("rename") {
 (DiffChange::Renamed, Some("".to_string()))
 } else if line.contains("new file mode") {
 (DiffChange::Added, None)
 } else if line.contains("deleted file mode") {
 (DiffChange::Deleted, None)
 } else {
 (DiffChange::Modified, None)
 };
 current = Some(DiffFile {
 path,
 old_path,
 change,
 is_binary: false,
 hunks: Vec::new(),
 additions: 0,
 deletions: 0,
 });
 continue;
 }

 if let Some(ref mut cf) = current {
 if line.starts_with("--- ") || line.starts_with("+++ ") {
 continue;
 }
 if line.starts_with("@@") {
 let header = line.to_string();
 line_id = 0;
 let _ = hunk.insert(DiffHunk { id: files.len(), header, lines: Vec::new() });
 continue;
 }
 if line.starts_with("Binary") {
 cf.is_binary = true;
 continue;
 }

 if let Some(ref mut hk) = hunk {
 line_id += 1;
 let (kind, text) = if line.starts_with("+") && !line.starts_with("+++") {
 (DiffLineKind::Addition, line[1..].to_string())
 } else if line.starts_with("-") && !line.starts_with("---") {
 (DiffLineKind::Deletion, line[1..].to_string())
 } else if line.starts_with("\\") {
 (DiffLineKind::Note, line.to_string())
 } else {
 (DiffLineKind::Context, line[1..].to_string())
 };

 let mut old_number = None;
 let mut new_number = None;
 if !line.starts_with("\\") {
 if let Some(rest) = line.strip_prefix(|p: &char| p == '+' || p == '-' || p == ' ') {
 // parse_line_numbers (simplified for scaffold)
 let mut old_number = None;
 let mut new_number = None;
 }
 }

 if matches!(kind, DiffLineKind::Addition) {
 cf.additions += 1;
 }
 if matches!(kind, DiffLineKind::Deletion) {
 cf.deletions += 1;
 }

 hk.lines.push(DiffLine {
 id: line_id,
 kind,
 text,
 old_number,
 new_number,
 });
 }
 }
 }

 if let Some(mut cf) = current.take() {
 if let Some(h) = hunk.take() { cf.hunks.push(h); }
 files.push(cf);
 }

 for f in &mut files {
 f.additions = f.hunks.iter().flat_map(|h| &h.lines).filter(|l| matches!(l.kind, DiffLineKind::Addition)).count();
 f.deletions = f.hunks.iter().flat_map(|h| &h.lines).filter(|l| matches!(l.kind, DiffLineKind::Deletion)).count();
 }

 files
 }

 fn header_path(line: &str) -> String {
 let parts: Vec<&str> = line.split_whitespace().collect();
 if parts.len() >= 4 {
 let raw = parts[3];
 if raw.starts_with("b/") { raw[2..].to_string() } else { raw.to_string() }
 } else {
 line.to_string()
 }
 }

}

pub fn format_diff_summary(files: &[DiffFile]) -> String {
 files
 .iter()
 .map(|f| {
 let status = match f.change {
 DiffChange::Added => "A",
 DiffChange::Deleted => "D",
 DiffChange::Modified => "M",
 DiffChange::Renamed => "R",
 };
 format!("{} {} (+{} -{})", status, f.path, f.additions, f.deletions)
 })
 .collect::<Vec<_>>()
 .join("\n")
}
