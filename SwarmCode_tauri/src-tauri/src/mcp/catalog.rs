use std::sync::LazyLock;

use super::MCPCatalogEntry;
use super::MCPCategory;
use super::MCPField;
use super::MCPFieldKind;
use super::MCPTransport;
use super::MCPTransportConfig;

pub struct MCPCatalog;

impl MCPCatalog {
    pub fn global() -> &'static Self {
        static INSTANCE: MCPCatalog = MCPCatalog;
        &INSTANCE
    }

    pub fn entries() -> &'static [MCPCatalogEntry] {
        CATALOG.as_slice()
    }

    pub fn list_all(&self) -> Vec<MCPCatalogEntry> {
        CATALOG.iter().cloned().collect()
    }

    pub fn entry(id: &str) -> Option<&'static MCPCatalogEntry> {
        CATALOG.iter().find(|e| e.id == id)
    }

    pub fn by_category(&self) -> Vec<MCPCatalogEntry> {
        CATALOG.iter().cloned().collect()
    }

    pub fn is_known(id: &str) -> bool {
        CATALOG.iter().any(|e| e.id == id)
    }
}

// ---------------------------------------------------------------------------
// Catalog entries
// ---------------------------------------------------------------------------

fn field(key: &str, label: &str, placeholder: &str, kind: MCPFieldKind) -> MCPField {
    MCPField {
        key: key.to_string(),
        label: label.to_string(),
        placeholder: placeholder.to_string(),
        kind,
        help: String::new(),
        is_required: false,
        default_value: None,
    }
}

fn req_field(key: &str, label: &str, placeholder: &str, kind: MCPFieldKind) -> MCPField {
    MCPField {
        key: key.to_string(),
        label: label.to_string(),
        placeholder: placeholder.to_string(),
        kind,
        help: String::new(),
        is_required: true,
        default_value: None,
    }
}

fn http_transport(url: &str, headers: &[(&str, &str)]) -> MCPTransportConfig {
    MCPTransportConfig {
        transport: MCPTransport::Http,
        command: None,
        args: Vec::new(),
        url: Some(url.to_string()),
        headers: headers.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect(),
    }
}

fn stdio_transport(command: &str, args: &[&str]) -> MCPTransportConfig {
    MCPTransportConfig {
        transport: MCPTransport::Stdio,
        command: Some(command.to_string()),
        args: args.iter().map(|s| s.to_string()).collect(),
        url: None,
        headers: Vec::new(),
    }
}

static CATALOG: LazyLock<Vec<MCPCatalogEntry>> = LazyLock::new(|| vec![
    MCPCatalogEntry {
        id: "github",
        name: "GitHub",
        vendor: "GitHub",
        summary: "Issues, pull requests and code across your repositories",
        category: MCPCategory::Developer,
        asset: "mcp-github".to_string(),
        color: 0x24292F,
        is_monochrome: true,
        transport: http_transport(
            "https://api.githubcopilot.com/mcp/",
            &[("Authorization", "Bearer {token}")],
        ),
        fields: vec![req_field(
            "token",
            "Personal access token",
            "ghp_…",
            MCPFieldKind::Secret,
        )],
        docs_url: "https://github.com/github/github-mcp-server",
        sample_tools: vec![
            "list_issues".into(),
            "create_pull_request".into(),
            "search_code".into(),
            "get_file_contents".into(),
        ],
        keys_url: Some("https://github.com/settings/tokens"),
    },
    MCPCatalogEntry {
        id: "gitlab",
        name: "GitLab",
        vendor: "GitLab",
        summary: "Issues, merge requests, pipelines and code across your projects",
        category: MCPCategory::Developer,
        asset: "mcp-gitlab".to_string(),
        color: 0xFC6D26,
        is_monochrome: false,
        transport: MCPTransportConfig {
            transport: MCPTransport::Http,
            command: None,
            args: Vec::new(),
            url: Some("https://{instance}/api/v4/mcp".to_string()),
            headers: Vec::new(),
        },
        fields: vec![MCPField {
            key: "instance".to_string(),
            label: "GitLab address".to_string(),
            placeholder: "gitlab.com".to_string(),
            kind: MCPFieldKind::Text,
            help: "gitlab.com, or your own instance's host".to_string(),
            is_required: false,
            default_value: Some("gitlab.com".to_string()),
        }],
        docs_url: "https://docs.gitlab.com/user/model_context_protocol/mcp_server/",
        sample_tools: vec![
            "list_merge_requests".into(),
            "get_merge_request_diffs".into(),
            "create_issue".into(),
            "get_pipeline_jobs".into(),
        ],
        keys_url: None,
    },
    MCPCatalogEntry {
        id: "playwright",
        name: "Playwright",
        vendor: "Microsoft",
        summary: "Drives a real browser: open pages, click, fill forms, screenshot",
        category: MCPCategory::Browser,
        asset: "mcp-playwright".to_string(),
        color: 0x2EAD33,
        is_monochrome: false,
        transport: stdio_transport("npx", &["-y", "@playwright/mcp@latest"]),
        fields: Vec::new(),
        docs_url: "https://github.com/microsoft/playwright-mcp",
        sample_tools: vec![
            "browser_navigate".into(),
            "browser_click".into(),
            "browser_snapshot".into(),
            "browser_take_screenshot".into(),
        ],
        keys_url: None,
    },
    MCPCatalogEntry {
        id: "chrome-devtools",
        name: "Chrome DevTools",
        vendor: "Google",
        summary: "Inspects pages, console messages and performance traces",
        category: MCPCategory::Browser,
        asset: "mcp-chrome-devtools".to_string(),
        color: 0x4285F4,
        is_monochrome: false,
        transport: stdio_transport("npx", &["-y", "chrome-devtools-mcp@latest"]),
        fields: Vec::new(),
        docs_url: "https://github.com/ChromeDevTools/chrome-devtools-mcp",
        sample_tools: vec![
            "navigate_page".into(),
            "take_screenshot".into(),
            "list_console_messages".into(),
            "performance_start_trace".into(),
        ],
        keys_url: None,
    },
    MCPCatalogEntry {
        id: "context7",
        name: "Context7",
        vendor: "Upstash",
        summary: "Fresh docs and examples for the libraries you use",
        category: MCPCategory::Knowledge,
        asset: "mcp-context7".to_string(),
        color: 0x5B8DEF,
        is_monochrome: false,
        transport: http_transport(
            "https://mcp.context7.com/mcp",
            &[("CONTEXT7_API_KEY", "{key}")],
        ),
        fields: vec![MCPField {
            key: "key".to_string(),
            label: "API key".to_string(),
            placeholder: "ctx7sk-…".to_string(),
            kind: MCPFieldKind::Secret,
            help: "Optional, lifts the rate limit".to_string(),
            is_required: false,
            default_value: None,
        }],
        docs_url: "https://github.com/upstash/context7",
        sample_tools: vec![
            "resolve-library-id".into(),
            "get-library-docs".into(),
        ],
        keys_url: Some("https://context7.com/dashboard"),
    },
    MCPCatalogEntry {
        id: "filesystem",
        name: "Filesystem",
        vendor: "Anthropic",
        summary: "Reads, writes and searches files in one folder",
        category: MCPCategory::Developer,
        asset: "mcp-filesystem".to_string(),
        color: 0x8E8E93,
        is_monochrome: true,
        transport: stdio_transport(
            "npx",
            &["-y", "@modelcontextprotocol/server-filesystem", "{root}"],
        ),
        fields: vec![MCPField {
            key: "root".to_string(),
            label: "Folder".to_string(),
            placeholder: "/Users/you/Projects".to_string(),
            kind: MCPFieldKind::Path,
            help: "The folder the server may use".to_string(),
            is_required: false,
            default_value: None,
        }],
        docs_url: "https://github.com/modelcontextprotocol/servers/tree/main/src/filesystem",
        sample_tools: vec![
            "read_file".into(),
            "write_file".into(),
            "list_directory".into(),
            "search_files".into(),
        ],
        keys_url: None,
    },
    MCPCatalogEntry {
        id: "fetch",
        name: "Fetch",
        vendor: "Anthropic",
        summary: "Downloads web pages as plain text to read",
        category: MCPCategory::Browser,
        asset: "mcp-fetch".to_string(),
        color: 0x0A84FF,
        is_monochrome: false,
        transport: stdio_transport("uvx", &["mcp-server-fetch"]),
        fields: Vec::new(),
        docs_url: "https://github.com/modelcontextprotocol/servers/tree/main/src/fetch",
        sample_tools: vec!["fetch".into(), "fetch_markdown".into()],
        keys_url: None,
    },
    MCPCatalogEntry {
        id: "sqlite",
        name: "SQLite",
        vendor: "Anthropic",
        summary: "Query local SQLite databases with SQL",
        category: MCPCategory::Database,
        asset: "mcp-sqlite".to_string(),
        color: 0x003B57,
        is_monochrome: true,
        transport: stdio_transport(
            "uvx",
            &["mcp-server-sqlite", "--db-path", "{path}"],
        ),
        fields: vec![MCPField {
            key: "path".to_string(),
            label: "Database path".to_string(),
            placeholder: "~/data/app.db".to_string(),
            kind: MCPFieldKind::Path,
            help: "Path to the SQLite database file".to_string(),
            is_required: true,
            default_value: None,
        }],
        docs_url: "https://github.com/modelcontextprotocol/servers/tree/main/src/sqlite",
        sample_tools: vec!["query".into(), "create_table".into(), "list_tables".into()],
        keys_url: None,
    },
    MCPCatalogEntry {
        id: "postgres",
        name: "PostgreSQL",
        vendor: "Anthropic",
        summary: "Query PostgreSQL databases",
        category: MCPCategory::Database,
        asset: "mcp-postgres".to_string(),
        color: 0x336791,
        is_monochrome: true,
        transport: stdio_transport(
            "uvx",
            &[
                "mcp-server-postgres",
                "--connection-string",
                "{connection_string}",
            ],
        ),
        fields: vec![req_field(
            "connection_string",
            "Connection string",
            "postgresql://…",
            MCPFieldKind::Secret,
        )],
        docs_url: "https://github.com/modelcontextprotocol/servers/tree/main/src/postgres",
        sample_tools: vec![
            "query".into(),
            "list_tables".into(),
            "describe_table".into(),
        ],
        keys_url: None,
    },
    MCPCatalogEntry {
        id: "brave-search",
        name: "Brave Search",
        vendor: "Brave",
        summary: "Web and local search with privacy-preserving results",
        category: MCPCategory::Knowledge,
        asset: "mcp-brave-search".to_string(),
        color: 0xFB542B,
        is_monochrome: false,
        transport: http_transport(
            "https://api.search.brave.com/res/v1/web/search",
            &[("X-Subscription-Token", "{api_key}"), ("Accept", "application/json")],
        ),
        fields: vec![req_field(
            "api_key",
            "API key",
            "BSA-…",
            MCPFieldKind::Secret,
        )],
        docs_url: "https://github.com/brave/search-mcp",
        sample_tools: vec![
            "brave_web_search".into(),
            "brave_local_search".into(),
        ],
        keys_url: Some("https://brave.com/search/api/"),
    },
    MCPCatalogEntry {
        id: "deepwiki",
        name: "DeepWiki",
        vendor: "Community",
        summary: "Read and search GitHub repository wikis",
        category: MCPCategory::Knowledge,
        asset: "mcp-deepwiki".to_string(),
        color: 0x6E5494,
        is_monochrome: false,
        transport: stdio_transport("npx", &["-y", "@jpmorganchase/deepwiki@latest"]),
        fields: Vec::new(),
        docs_url: "https://github.com/jpmorganchase/deepwiki",
        sample_tools: vec!["read_wiki".into(), "search_wiki".into()],
        keys_url: None,
    },
    MCPCatalogEntry {
        id: "memory",
        name: "Memory",
        vendor: "Anthropic",
        summary: "Persistent knowledge graph across conversations",
        category: MCPCategory::Knowledge,
        asset: "mcp-memory".to_string(),
        color: 0xD4A574,
        is_monochrome: false,
        transport: stdio_transport("npx", &["-y", "@modelcontextprotocol/server-memory"]),
        fields: Vec::new(),
        docs_url: "https://github.com/modelcontextprotocol/servers/tree/main/src/memory",
        sample_tools: vec!["create_entities".into(), "add_observations".into(), "search_nodes".into()],
        keys_url: None,
    },
    MCPCatalogEntry {
        id: "vercel",
        name: "Vercel",
        vendor: "Vercel",
        summary: "Deployments, domains and project management for Vercel",
        category: MCPCategory::Developer,
        asset: "mcp-vercel".to_string(),
        color: 0x000000,
        is_monochrome: true,
        transport: http_transport(
            "https://mcp.vercel.com/",
            &[("Authorization", "Bearer {api_token}")],
        ),
        fields: vec![req_field(
            "api_token",
            "API token",
            "vercel_…",
            MCPFieldKind::Secret,
        )],
        docs_url: "https://vercel.com/docs/mcp",
        sample_tools: vec![
            "list_deployments".into(),
            "create_deployment".into(),
            "list_projects".into(),
        ],
        keys_url: Some("https://vercel.com/account/tokens"),
    },
    MCPCatalogEntry {
        id: "linear",
        name: "Linear",
        vendor: "Linear",
        summary: "Issues, projects and cycles from Linear",
        category: MCPCategory::Communication,
        asset: "mcp-linear".to_string(),
        color: 0x5E6AD2,
        is_monochrome: false,
        transport: stdio_transport("npx", &["-y", "linear-mcp-server"]),
        fields: vec![req_field(
            "api_key",
            "API key",
            "lin_api_…",
            MCPFieldKind::Secret,
        )],
        docs_url: "https://github.com/linear/linear-mcp-server",
        sample_tools: vec![
            "list_issues".into(),
            "create_issue".into(),
            "list_projects".into(),
        ],
        keys_url: Some("https://linear.app/settings/api"),
    },
    MCPCatalogEntry {
        id: "slack",
        name: "Slack",
        vendor: "Slack",
        summary: "Search messages, channels and users in Slack",
        category: MCPCategory::Communication,
        asset: "mcp-slack".to_string(),
        color: 0x4A154B,
        is_monochrome: true,
        transport: stdio_transport("npx", &["-y", "@modelcontextprotocol/server-slack"]),
        fields: vec![
            req_field(
                "token",
                "Bot token",
                "xoxb-…",
                MCPFieldKind::Secret,
            ),
            MCPField {
                key: "channel".to_string(),
                label: "Default channel".to_string(),
                placeholder: "#general".to_string(),
                kind: MCPFieldKind::Text,
                help: "Channel to search by default".to_string(),
                is_required: false,
                default_value: None,
            },
        ],
        docs_url: "https://github.com/modelcontextprotocol/servers/tree/main/src/slack",
        sample_tools: vec![
            "search_messages".into(),
            "list_channels".into(),
            "post_message".into(),
        ],
        keys_url: Some("https://api.slack.com/apps"),
    },
]);
