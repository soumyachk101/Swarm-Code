//! Text utility helpers - word counting, line counting, truncation, indentation,
//! whitespace normalization, and code-block extraction.

use regex::Regex;

/// Count words in a string using whitespace as the delimiter.
///
/// Empty strings return 0. Multi-line content is treated as a single stream.
pub fn word_count(text: &str) -> usize {
    if text.is_empty() {
        return 0;
    }
    text.split_whitespace().count()
}

/// Count lines (split on `\n`). A trailing newline does not produce an extra empty line
/// unless the content itself ends with a newline character.
pub fn line_count(text: &str) -> usize {
    if text.is_empty() {
        return 0;
    }
    text.split('\n').count()
}

/// Crude token estimator. Roughly 4 characters per token, which is the conservative
/// end of the typical range for English prose.
pub fn token_estimate(text: &str) -> usize {
    if text.is_empty() {
        return 0;
    }
    // Use a ceiling division so very short texts still report at least 1 token.
    (text.chars().count() + 3) / 4
}

/// Truncate a string to a maximum number of characters. If the string is longer than
/// `limit`, it is replaced by the first `limit - 1` characters followed by an ellipsis
/// (U+2026). The total output length never exceeds `limit` characters.
pub fn truncate(text: &str, limit: usize) -> String {
    if limit == 0 {
        return String::new();
    }
    let char_count = text.chars().count();
    if char_count <= limit {
        return text.to_string();
    }
    let take = limit.saturating_sub(1);
    let prefix: String = text.chars().take(take).collect();
    format!("{}\u{2026}", prefix)
}

/// Indent every line of a string with the given prefix.
pub fn indent(text: &str, prefix: &str) -> String {
    if prefix.is_empty() || text.is_empty() {
        return text.to_string();
    }
    let mut out = String::with_capacity(text.len() + prefix.len() * 16);
    for (i, line) in text.split('\n').enumerate() {
        if i > 0 {
            out.push('\n');
        }
        out.push_str(prefix);
        out.push_str(line);
    }
    out
}

/// Whether the string is empty or contains only whitespace characters.
pub fn is_empty_or_whitespace(text: &str) -> bool {
    text.chars().all(|c| c.is_whitespace())
}

/// The first non-empty line of the text, stripped of leading/trailing whitespace.
/// Returns an empty string if the text is empty or only whitespace.
pub fn first_line(text: &str) -> String {
    text.lines()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .unwrap_or("")
        .to_string()
}

/// The last non-empty line of the text, stripped of leading/trailing whitespace.
/// Returns an empty string if the text is empty or only whitespace.
pub fn last_line(text: &str) -> String {
    text.lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .last()
        .unwrap_or("")
        .to_string()
}

/// Count the number of fenced code blocks (``` ... ```) in the text.
pub fn count_code_blocks(text: &str) -> usize {
    let fence = Regex::new(r"(?m)^```").unwrap();
    let count = fence.find_iter(text).count();
    count / 2
}

/// Extract every fenced code block from the text. Each returned entry is the
/// content between the fences, with the surrounding fence markers removed.
/// Returns an empty Vec if no code blocks are present.
pub fn extract_code_blocks(text: &str) -> Vec<String> {
    let mut blocks = Vec::new();
    let mut in_block = false;
    let mut current = String::new();

    for line in text.lines() {
        let trimmed = line.trim_start();
        if trimmed.starts_with("```") {
            if in_block {
                // Closing fence.
                blocks.push(current.trim_end_matches('\n').to_string());
                current.clear();
                in_block = false;
            } else {
                // Opening fence: discard the optional language tag and start fresh.
                current.clear();
                in_block = true;
            }
            continue;
        }
        if in_block {
            if !current.is_empty() {
                current.push('\n');
            }
            current.push_str(line);
        }
    }
    blocks
}

/// Collapse runs of whitespace into single spaces and trim leading/trailing
/// whitespace from each line.
pub fn normalize_whitespace(text: &str) -> String {
    let re_space = Regex::new(r"[ \t]+").unwrap();
    let re_blank = Regex::new(r"\n{3,}").unwrap();

    let trimmed = text.trim();
    if trimmed.is_empty() {
        return String::new();
    }

    let spaced = re_space.replace_all(trimmed, " ");
    let result = re_blank.replace_all(&spaced, "\n\n");
    result.to_string()
}

/// Strip ANSI escape sequences (colors, cursor movement) from a string.
///
/// Matches the standard CSI form `ESC [ <params> <intermediate> <final>` where
/// params are digits, semicolons, and a few punctuation characters, intermediates
/// are space or `/`, and the final byte is in the printable ASCII range.
pub fn strip_ansi(text: &str) -> String {
    let re = Regex::new(r"\x1B\[[0-9;?]*[ -/]*[@-~]").unwrap();
    re.replace_all(text, "").to_string()
}

/// The last `count` non-empty, trimmed lines of the input. Returns `None` if
/// the input has no meaningful content.
pub fn last_lines(text: &str, count: usize) -> Option<String> {
    let cleaned = strip_ansi(text);
    let lines: Vec<String> = cleaned
        .split('\n')
        .map(|line| line.trim())
        .filter(|line| !line.is_empty())
        .map(|line| line.to_string())
        .collect();
    if lines.is_empty() {
        return None;
    }
    let start = lines.len().saturating_sub(count);
    Some(lines[start..].join("\n"))
}

/// Reduce a multi-line string to a single trimmed line of at most `limit` chars.
/// If the original is longer, append an ellipsis.
pub fn single_line(text: &str, limit: usize) -> String {
    let first = text
        .split('\n')
        .map(str::trim)
        .find(|line| !line.is_empty())
        .unwrap_or("")
        .to_string();
    if first.chars().count() > limit {
        let take = limit.saturating_sub(1);
        let prefix: String = first.chars().take(take).collect();
        format!("{}\u{2026}", prefix)
    } else {
        first
    }
}

/// Replace em-dashes (and the horizontal bar, two-em dash, three-em dash) with
/// plain hyphens. The en-dash is preserved because it is the correct mark in a
/// numeric range.
pub fn without_em_dashes(text: &str) -> String {
    if !text.chars().any(is_em_dash) {
        return text.to_string();
    }
    text.chars()
        .map(|c| if is_em_dash(c) { '-' } else { c })
        .collect()
}

fn is_em_dash(c: char) -> bool {
    matches!(c, '\u{2014}' | '\u{2015}' | '\u{2E3A}' | '\u{2E3B}')
}

/// Compute simple unified-diff statistics between two strings. Returns a tuple of
/// (diff_text, additions, deletions).
///
/// The returned diff is a single hunk with up to 3 lines of unchanged context on
/// each side, prefixed with `+`, `-`, or ` `.
pub fn simple_diff(old: &str, new: &str) -> DiffStats {
    let old_lines: Vec<&str> = if old.is_empty() { Vec::new() } else { old.split('\n').collect() };
    let new_lines: Vec<&str> = if new.is_empty() { Vec::new() } else { new.split('\n').collect() };

    let mut prefix = 0usize;
    while prefix < old_lines.len()
        && prefix < new_lines.len()
        && old_lines[prefix] == new_lines[prefix]
    {
        prefix += 1;
    }

    let mut suffix = 0usize;
    while suffix < (old_lines.len() - prefix)
        && suffix < (new_lines.len() - prefix)
        && old_lines[old_lines.len() - 1 - suffix] == new_lines[new_lines.len() - 1 - suffix]
    {
        suffix += 1;
    }

    let removed = &old_lines[prefix..(old_lines.len() - suffix)];
    let added = &new_lines[prefix..(new_lines.len() - suffix)];

    let leading_start = prefix.saturating_sub(3);
    let leading = &old_lines[leading_start..prefix];

    let trailing_end = std::cmp::min(old_lines.len(), old_lines.len() - suffix + 3);
    let trailing = &old_lines[(old_lines.len() - suffix)..trailing_end];

    let old_start = (prefix - leading.len() + 1) as i64;
    let old_count = (leading.len() + removed.len() + trailing.len()) as i64;
    let new_count = (leading.len() + added.len() + trailing.len()) as i64;

    let mut lines: Vec<String> = Vec::new();
    lines.push(format!(
        "@@ -{},{} +{},{} @@",
        old_start, old_count, old_start, new_count
    ));
    for line in leading {
        lines.push(format!(" {}", line));
    }
    for line in removed {
        lines.push(format!("-{}", line));
    }
    for line in added {
        lines.push(format!("+{}", line));
    }
    for line in trailing {
        lines.push(format!(" {}", line));
    }

    DiffStats {
        diff: lines.join("\n"),
        additions: added.len(),
        deletions: removed.len(),
    }
}

/// Statistics for a unified diff between two strings.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DiffStats {
    pub diff: String,
    pub additions: usize,
    pub deletions: usize,
}

impl DiffStats {
    pub fn is_empty(&self) -> bool {
        self.additions == 0 && self.deletions == 0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_word_count_basic() {
        assert_eq!(word_count(""), 0);
        assert_eq!(word_count("hello"), 1);
        assert_eq!(word_count("hello world"), 2);
        assert_eq!(word_count("  hello  world  "), 2);
    }

    #[test]
    fn test_line_count_basic() {
        assert_eq!(line_count(""), 0);
        assert_eq!(line_count("a"), 1);
        assert_eq!(line_count("a\nb"), 2);
    }

    #[test]
    fn test_token_estimate() {
        assert_eq!(token_estimate(""), 0);
        // 4 chars => 1 token
        assert_eq!(token_estimate("abcd"), 1);
        // 8 chars => 2 tokens
        assert_eq!(token_estimate("abcdefgh"), 2);
    }

    #[test]
    fn test_truncate() {
        assert_eq!(truncate("hello", 10), "hello");
        let out = truncate("hello world", 6);
        // "hell…" is 5 chars
        assert!(out.chars().count() <= 6);
        assert!(out.ends_with('\u{2026}'));
    }

    #[test]
    fn test_indent() {
        assert_eq!(indent("a\nb", "  "), "  a\n  b");
        assert_eq!(indent("a", ""), "a");
    }

    #[test]
    fn test_is_empty_or_whitespace() {
        assert!(is_empty_or_whitespace(""));
        assert!(is_empty_or_whitespace("   \n\t  "));
        assert!(!is_empty_or_whitespace("a"));
        assert!(!is_empty_or_whitespace("  a  "));
    }

    #[test]
    fn test_first_last_line() {
        let t = "\n  hello  \n\nworld\n";
        assert_eq!(first_line(t), "hello");
        assert_eq!(last_line(t), "world");
    }

    #[test]
    fn test_code_blocks() {
        let text = "intro\n```rust\nfn x() {}\n```\nmiddle\n```\nplain\n```\n";
        assert_eq!(count_code_blocks(text), 2);
        let blocks = extract_code_blocks(text);
        assert_eq!(blocks.len(), 2);
        assert_eq!(blocks[0], "fn x() {}");
        assert_eq!(blocks[1], "plain");
    }

    #[test]
    fn test_normalize_whitespace() {
        let input = "  hello   world  \n\n\n\nfoo  bar  ";
        let out = normalize_whitespace(input);
        assert!(!out.contains("    "));
        assert!(!out.contains("\n\n\n"));
    }

    #[test]
    fn test_strip_ansi() {
        let raw = "before \x1b[31mred\x1b[0m after";
        assert_eq!(strip_ansi(raw), "before red after");
    }

    #[test]
    fn test_last_lines() {
        let raw = "\n\nfirst\nsecond\nthird\nfourth\n";
        let out = last_lines(raw, 2).unwrap();
        assert_eq!(out, "third\nfourth");
        assert!(last_lines("", 4).is_none());
    }

    #[test]
    fn test_single_line() {
        assert_eq!(single_line("hello world", 100), "hello world");
        let out = single_line("very long first line of text", 8);
        assert!(out.ends_with('\u{2026}'));
    }

    #[test]
    fn test_without_em_dashes() {
        assert_eq!(without_em_dashes("works — every time"), "works - every time");
        assert_eq!(without_em_dashes("ships—sometimes"), "ships-sometimes");
        assert_eq!(without_em_dashes("lines 10–20"), "lines 10–20");
    }

    #[test]
    fn test_simple_diff() {
        let old = "a\nb\nc\nd";
        let new = "a\nb\nC\nd";
        let stats = simple_diff(old, new);
        assert_eq!(stats.additions, 1);
        assert_eq!(stats.deletions, 1);
        assert!(stats.diff.contains("-c"));
        assert!(stats.diff.contains("+C"));
    }
}
