//! Merge request / pull request link model.
//!
//! Represents a URL pointing at a merge request (GitLab), pull request
//! (GitHub), or pull request (Gitea, Forgejo, Codeberg) discovered in a chat
//! message.  The struct parses the URL to extract the forge type and request
//! number, and provides the prompt text the helper thread should follow to
//! land the request.

use serde::{Deserialize, Serialize};
use url::Url;

// ---------------------------------------------------------------------------
// Forge
// ---------------------------------------------------------------------------

/// Which forge platform the URL belongs to.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Forge {
    Gitlab,
    Github,
    /// Gitea and its forks (Forgejo, Codeberg) are served by the same `tea`
    /// CLI.
    Gitea,
}

impl Forge {
    pub fn as_str(self) -> &'static str {
        match self {
            Forge::Gitlab => "gitlab",
            Forge::Github => "github",
            Forge::Gitea => "gitea",
        }
    }
}

// ---------------------------------------------------------------------------
// MergeRequestLink
// ---------------------------------------------------------------------------

/// A link in the chat that points at a merge request or pull request.
///
/// Parsed from a URL, the struct identifies the forge and request number.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MergeRequestLink {
    pub id: String,
    pub url: String,
    pub forge: Forge,
    pub number: u32,
    pub title: String,
    pub provider: String,
    pub status: MergeRequestStatus,
    pub created_at: i64,
    pub merged_at: Option<i64>,
}

impl MergeRequestLink {
    /// Try to parse a URL into a MergeRequestLink.
    ///
    /// Supported patterns:
    /// * `.../group/project/-/merge_requests/<N>` -- GitLab
    /// * `.../owner/repo/pull/<N>` -- GitHub
    /// * `.../owner/repo/pulls/<N>` -- Gitea
    pub fn from_url(url_str: &str) -> Result<Self, String> {
        let url = Url::parse(url_str).map_err(|e| e.to_string())?;
        let parts: Vec<&str> = url
            .path_segments()
            .map(|s| s.filter(|s| !s.is_empty()).collect::<Vec<_>>())
            .unwrap_or_default();

        let (forge, number) = Self::parse_forge_and_number(&parts)?;

        Ok(Self {
            id: format!(
                "{}_{}",
                forge.as_str(),
                number
            ),
            url: url_str.to_string(),
            forge,
            number,
            title: format!("Merge #{}", number),
            provider: "git".to_string(),
            status: MergeRequestStatus::Open,
            created_at: chrono::Utc::now().timestamp(),
            merged_at: None,
        })
    }

    fn parse_forge_and_number(parts: &[&str]) -> Result<(Forge, u32), String> {
        // GitLab: .../merge_requests/<N>
        if let Some(idx) = parts.iter().position(|&p| p == "merge_requests") {
            if idx + 1 < parts.len() {
                let n: u32 = parts[idx + 1].parse().map_err(|_| {
                    format!("Invalid MR number: {}", parts[idx + 1])
                })?;
                if n > 0 {
                    return Ok((Forge::Gitlab, n));
                }
            }
        }
        // GitHub: .../pull/<N>
        if parts.len() >= 4 && parts[parts.len() - 2] == "pull" {
            let n: u32 = parts[parts.len() - 1].parse().map_err(|_| {
                format!("Invalid PR number: {}", parts[parts.len() - 1])
            })?;
            if n > 0 {
                return Ok((Forge::Github, n));
            }
        }
        // Gitea: .../pulls/<N>
        if parts.len() >= 4 && parts[parts.len() - 2] == "pulls" {
            let n: u32 = parts[parts.len() - 1].parse().map_err(|_| {
                format!("Invalid PR number: {}", parts[parts.len() - 1])
            })?;
            if n > 0 {
                return Ok((Forge::Gitea, n));
            }
        }
        Err("URL does not match a known merge/pull request pattern".into())
    }

    /// The label for display: "!95" on GitLab, "#95" everywhere else.
    pub fn label(&self) -> String {
        match self.forge {
            Forge::Gitlab => format!("!{}", self.number),
            _ => format!("#{}", self.number),
        }
    }

    /// The title for the helper thread.
    pub fn helper_title(&self) -> String {
        format!("Merge {}", self.label())
    }

    /// The prompt text sent to the LLM to land this request.
    pub fn prompt(&self) -> String {
        let land = match self.forge {
            Forge::Gitlab => format!(
                "Use glab from this directory: `glab mr merge {} --yes`. \
                If GitLab answers that the request is still being checked (a 405), \
                wait a few seconds and try again; if it reports conflicts, stop and \
                say so instead of resolving them.",
                self.number
            ),
            Forge::Github => format!(
                "Use gh from this directory: `gh pr merge {} --merge`. \
                If GitHub reports the pull request is not mergeable, stop and say so \
                instead of resolving it.",
                self.number
            ),
            Forge::Gitea => format!(
                "Use tea from this directory: `tea pulls merge {}`. \
                If tea is not installed or signed in to this host, or the pull request \
                is not mergeable, stop and say so instead of working around it.",
                self.number
            ),
        };
        format!(
            "Merge {} now: {}\n\n{}\n\n\
            Once it is merged, sync the checkout: if this directory is on main with \
            a clean working tree, run `git pull --ff-only`; otherwise leave the working \
            tree alone and say so. Do not rebuild, install or relaunch anything. \
            Reply in a few lines with the merged commit and the request's link.",
            self.label(),
            self.url,
            land
        )
    }
}

// ---------------------------------------------------------------------------
// MergeRequestStatus
// ---------------------------------------------------------------------------

/// The lifecycle state of a merge/pull request.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MergeRequestStatus {
    Open,
    Draft,
    Merged,
    Closed,
    Unknown,
}

impl MergeRequestStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            MergeRequestStatus::Open => "open",
            MergeRequestStatus::Draft => "draft",
            MergeRequestStatus::Merged => "merged",
            MergeRequestStatus::Closed => "closed",
            MergeRequestStatus::Unknown => "unknown",
        }
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_gitlab_url() {
        let url = "https://gitlab.com/group/project/-/merge_requests/95";
        let link = MergeRequestLink::from_url(url).unwrap();
        assert_eq!(link.forge, Forge::Gitlab);
        assert_eq!(link.number, 95);
        assert_eq!(link.label(), "!95");
    }

    #[test]
    fn test_github_url() {
        let url = "https://github.com/owner/repo/pull/42";
        let link = MergeRequestLink::from_url(url).unwrap();
        assert_eq!(link.forge, Forge::Github);
        assert_eq!(link.number, 42);
        assert_eq!(link.label(), "#42");
    }

    #[test]
    fn test_gitea_url() {
        let url = "https://gitea.example.com/owner/repo/pulls/7";
        let link = MergeRequestLink::from_url(url).unwrap();
        assert_eq!(link.forge, Forge::Gitea);
        assert_eq!(link.number, 7);
        assert_eq!(link.label(), "#7");
    }

    #[test]
    fn test_invalid_url() {
        let url = "https://example.com/something/else";
        let result = MergeRequestLink::from_url(url);
        assert!(result.is_err());
    }

    #[test]
    fn test_prompt_contains_url() {
        let link = MergeRequestLink::from_url("https://github.com/o/r/pull/1").unwrap();
        let prompt = link.prompt();
        assert!(prompt.contains("https://github.com/o/r/pull/1"));
        assert!(prompt.contains("gh pr merge 1"));
    }

    #[test]
    fn test_serialisation() {
        let link = MergeRequestLink::from_url("https://gitlab.com/g/p/-/merge_requests/3").unwrap();
        let json = serde_json::to_string(&link).unwrap();
        let parsed: MergeRequestLink = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.number, 3);
        assert_eq!(parsed.forge, Forge::Gitlab);
    }
}
