import { useState, useMemo, useCallback } from "react";
import {
  SearchIcon,
  XIcon,
  CheckIcon,
  ShieldCheckIcon,
  InfoIcon,
  FolderIcon,
} from "lucide-react";
import { SettingsPageContainer } from "./settingsLayout";
import { GitHubIcon, GitIcon, GitLabIcon } from "../Icons";
import {
  SentryIcon,
  PlaywrightIcon,
  ChromeDevToolsIcon,
  FetchIcon,
  FirecrawlIcon,
  BraveIcon,
  TavilyIcon,
  ExaIcon,
  PerplexityIcon,
  SlackIcon,
  NotionIcon,
  LinearIcon,
  AtlassianIcon,
  FigmaIcon,
  StripeIcon,
  ResendIcon,
  SupabaseIcon,
  PostgresIcon,
  SQLiteIcon,
  MongoDBIcon,
  VercelIcon,
  CloudflareIcon,
  NetlifyIcon,
  AWSDocsIcon,
  Context7Icon,
  MemoryIcon,
  SequentialThinkingIcon,
  HuggingFaceIcon,
  DeepWikiIcon,
} from "./MCPIcons";

export interface MCPServerItem {
  id: string;
  name: string;
  vendor: string;
  summary: string;
  category: "Developer" | "Browser" | "Search" | "Work" | "Data" | "Cloud" | "Knowledge";
  action: "Connect" | "Sign in";
  sampleTools: string;
  docsUrl?: string;
  isCustom?: boolean;
}

export const MCP_CATALOG: MCPServerItem[] = [
  // Developer
  {
    id: "github",
    name: "GitHub",
    vendor: "GitHub",
    summary: "Issues, pull requests and code across your repositories",
    category: "Developer",
    action: "Connect",
    sampleTools: "list_issues · create_pull_requ...",
    docsUrl: "https://github.com/github/github-mcp-server",
  },
  {
    id: "gitlab",
    name: "GitLab",
    vendor: "GitLab",
    summary: "Issues, merge requests, pipelines and code across your projects",
    category: "Developer",
    action: "Sign in",
    sampleTools: "list_merge_requests · get_merg...",
    docsUrl: "https://docs.gitlab.com/user/model_context_protocol/mcp_server/",
  },
  {
    id: "filesystem",
    name: "Filesystem",
    vendor: "Anthropic",
    summary: "Reads, writes and searches files in one folder",
    category: "Developer",
    action: "Connect",
    sampleTools: "read_text_file · write_file ·...",
    docsUrl: "https://github.com/modelcontextprotocol/servers",
  },
  {
    id: "git",
    name: "Git",
    vendor: "Anthropic",
    summary: "Status, diffs, history and commits for a repo",
    category: "Developer",
    action: "Connect",
    sampleTools: "git_status · git_diff · git_lo...",
    docsUrl: "https://github.com/modelcontextprotocol/servers",
  },
  {
    id: "sentry",
    name: "Sentry",
    vendor: "Sentry",
    summary: "Error reports and which projects they hit",
    category: "Developer",
    action: "Sign in",
    sampleTools: "search_issues · get_issue_deta...",
    docsUrl: "https://mcp.sentry.dev",
  },

  // Browser
  {
    id: "playwright",
    name: "Playwright",
    vendor: "Microsoft",
    summary: "Drives a real browser: open pages, click, fill forms, screenshot",
    category: "Browser",
    action: "Connect",
    sampleTools: "browser_navigate · browser_cli...",
    docsUrl: "https://github.com/microsoft/playwright-mcp",
  },
  {
    id: "chrome-devtools",
    name: "Chrome DevTools",
    vendor: "Google",
    summary: "Inspects pages, console messages and performance traces",
    category: "Browser",
    action: "Connect",
    sampleTools: "navigate_page · take_screensho...",
    docsUrl: "https://github.com/ChromeDevTools/chrome-devtools-mcp",
  },
  {
    id: "fetch",
    name: "Fetch",
    vendor: "Anthropic",
    summary: "Downloads web pages as plain text to read",
    category: "Browser",
    action: "Connect",
    sampleTools: "fetch",
    docsUrl: "https://github.com/modelcontextprotocol/servers",
  },
  {
    id: "firecrawl",
    name: "Firecrawl",
    vendor: "Firecrawl",
    summary: "Scrapes, searches and maps whole websites",
    category: "Browser",
    action: "Connect",
    sampleTools: "firecrawl_scrape · firecrawl_s...",
    docsUrl: "https://github.com/firecrawl/firecrawl-mcp-server",
  },

  // Search
  {
    id: "brave-search",
    name: "Brave Search",
    vendor: "Brave",
    summary: "Searches the web, local places and news",
    category: "Search",
    action: "Connect",
    sampleTools: "brave_web_search · brave_loca...",
    docsUrl: "https://github.com/brave/brave-search-mcp-server",
  },
  {
    id: "tavily",
    name: "Tavily",
    vendor: "Tavily",
    summary: "Searches the web and pulls out page content",
    category: "Search",
    action: "Sign in",
    sampleTools: "tavily-search · tavily-extra...",
    docsUrl: "https://github.com/tavily-ai/tavily-mcp",
  },
  {
    id: "exa",
    name: "Exa",
    vendor: "Exa",
    summary: "Searches the web and reads pages, with code-focused answers",
    category: "Search",
    action: "Sign in",
    sampleTools: "web_search_exa · web_fetch_exa...",
    docsUrl: "https://github.com/exa-labs/exa-mcp-server",
  },
  {
    id: "perplexity",
    name: "Perplexity",
    vendor: "Perplexity",
    summary: "Asks the web and answers with sources",
    category: "Search",
    action: "Connect",
    sampleTools: "perplexity_search · perplexity...",
    docsUrl: "https://github.com/perplexityai/modelcontextprotocol",
  },

  // Work
  {
    id: "slack",
    name: "Slack",
    vendor: "Slack",
    summary: "Lists channels, reads and posts messages",
    category: "Work",
    action: "Connect",
    sampleTools: "channels_list · conversations_...",
    docsUrl: "https://github.com/korotovsky/slack-mcp-server",
  },
  {
    id: "notion",
    name: "Notion",
    vendor: "Notion",
    summary: "Finds and edits pages in your workspace",
    category: "Work",
    action: "Sign in",
    sampleTools: "API-post-search · API-retrieve...",
    docsUrl: "https://developers.notion.com/docs/mcp",
  },
  {
    id: "linear",
    name: "Linear",
    vendor: "Linear",
    summary: "Issues and projects in your Linear teams",
    category: "Work",
    action: "Sign in",
    sampleTools: "list_issues · create_issue · u...",
    docsUrl: "https://linear.app/docs/mcp",
  },
  {
    id: "atlassian",
    name: "Atlassian",
    vendor: "Atlassian",
    summary: "Jira issues and Confluence pages",
    category: "Work",
    action: "Sign in",
    sampleTools: "searchJiraIssuesUsingJql · cre...",
    docsUrl: "https://developer.atlassian.com/cloud/rovo-mcp/",
  },
  {
    id: "figma",
    name: "Figma",
    vendor: "Figma",
    summary: "Design details and screenshots from files",
    category: "Work",
    action: "Sign in",
    sampleTools: "get_design_context · get_scree...",
    docsUrl: "https://help.figma.com",
  },
  {
    id: "stripe",
    name: "Stripe",
    vendor: "Stripe",
    summary: "Customers, payment links and balances",
    category: "Work",
    action: "Sign in",
    sampleTools: "create_customer · list_custome...",
    docsUrl: "https://docs.stripe.com/mcp",
  },
  {
    id: "resend",
    name: "Resend",
    vendor: "Resend",
    summary: "Sends email and manages contacts, broadcasts and domains",
    category: "Work",
    action: "Sign in",
    sampleTools: "send-email · list-contacts · c...",
    docsUrl: "https://github.com/resend/resend-mcp",
  },

  // Data
  {
    id: "supabase",
    name: "Supabase",
    vendor: "Supabase",
    summary: "Projects, SQL queries and database changes",
    category: "Data",
    action: "Sign in",
    sampleTools: "list_projects · execute_sql ·...",
    docsUrl: "https://supabase.com/docs/guides/ai-tools/mcp",
  },
  {
    id: "postgres",
    name: "PostgreSQL",
    vendor: "PostgreSQL",
    summary: "Runs SQL and explores the schema of a Postgres database",
    category: "Data",
    action: "Connect",
    sampleTools: "execute_sql · search_objects",
    docsUrl: "https://github.com/bytebase/dbhub",
  },
  {
    id: "sqlite",
    name: "SQLite",
    vendor: "SQLite",
    summary: "Reads and writes a local database file",
    category: "Data",
    action: "Connect",
    sampleTools: "read_query · write_query · lis...",
    docsUrl: "https://github.com/modelcontextprotocol/servers",
  },
  {
    id: "mongodb",
    name: "MongoDB",
    vendor: "MongoDB",
    summary: "Finds and changes documents in your collections",
    category: "Data",
    action: "Connect",
    sampleTools: "find · aggregate · list-collec...",
    docsUrl: "https://github.com/mongodb-js/mongodb-mcp-server",
  },

  // Cloud
  {
    id: "vercel",
    name: "Vercel",
    vendor: "Vercel",
    summary: "Projects, deployments and their build logs",
    category: "Cloud",
    action: "Sign in",
    sampleTools: "list_projects · list_deploymen...",
    docsUrl: "https://vercel.com/docs/agent-resources/vercel-mcp",
  },
  {
    id: "cloudflare",
    name: "Cloudflare",
    vendor: "Cloudflare",
    summary: "Workers, storage buckets and databases",
    category: "Cloud",
    action: "Sign in",
    sampleTools: "workers_list · kv_namespaces_l...",
    docsUrl: "https://github.com/cloudflare/mcp-server-cloudflare",
  },
  {
    id: "netlify",
    name: "Netlify",
    vendor: "Netlify",
    summary: "Sites, deploys, forms and environment variables",
    category: "Cloud",
    action: "Sign in",
    sampleTools: "get-projects · deploy-site · m...",
    docsUrl: "https://docs.netlify.com",
  },
  {
    id: "aws-docs",
    name: "AWS Docs",
    vendor: "Amazon Web Services",
    summary: "Searches and reads the AWS documentation",
    category: "Cloud",
    action: "Connect",
    sampleTools: "read_documentation · search_do...",
    docsUrl: "https://awslabs.github.io/mcp",
  },

  // Knowledge
  {
    id: "context7",
    name: "Context7",
    vendor: "Upstash",
    summary: "Fresh docs and examples for the libraries you use",
    category: "Knowledge",
    action: "Connect",
    sampleTools: "resolve-library-id · query-docs",
    docsUrl: "https://github.com/upstash/context7",
  },
  {
    id: "memory",
    name: "Memory",
    vendor: "Anthropic",
    summary: "Remembers people, facts and how they connect",
    category: "Knowledge",
    action: "Connect",
    sampleTools: "create_entities · create_relat...",
    docsUrl: "https://github.com/modelcontextprotocol/servers",
  },
  {
    id: "sequential-thinking",
    name: "Sequential Thinking",
    vendor: "Anthropic",
    summary: "Thinks hard problems through step by step",
    category: "Knowledge",
    action: "Connect",
    sampleTools: "sequentialthinking",
    docsUrl: "https://github.com/modelcontextprotocol/servers",
  },
  {
    id: "huggingface",
    name: "Hugging Face",
    vendor: "Hugging Face",
    summary: "Searches models, datasets and papers",
    category: "Knowledge",
    action: "Connect",
    sampleTools: "hub_repo_search · hub_repo_det...",
    docsUrl: "https://github.com/huggingface/hf-mcp-server",
  },
  {
    id: "deepwiki",
    name: "DeepWiki",
    vendor: "Cognition",
    summary: "Reads docs and answers questions about repos",
    category: "Knowledge",
    action: "Connect",
    sampleTools: "read_wiki_structure · read_wik...",
    docsUrl: "https://docs.devin.ai",
  },
];

const CATEGORIES: MCPServerItem["category"][] = [
  "Developer",
  "Browser",
  "Search",
  "Work",
  "Data",
  "Cloud",
  "Knowledge",
];

export function MCPSettingsPanel() {
  const navigate = useNavigate();
  const [searchQuery, setSearchQuery] = useState("");
  const [connectedIds, setConnectedIds] = useState<Set<string>>(new Set());
  const [isAddServerOpen, setIsAddServerOpen] = useState(false);
  const [configuringServer, setConfiguringServer] = useState<MCPServerItem | null>(null);
  const [configValue, setConfigValue] = useState("");
  const [customServers, setCustomServers] = useState<MCPServerItem[]>([]);
  const [newServerName, setNewServerName] = useState("");
  const [newServerCommand, setNewServerCommand] = useState("");

  const allServers = useMemo(() => [...customServers, ...MCP_CATALOG], [customServers]);

  const filteredServers = useMemo(() => {
    const q = searchQuery.trim().toLowerCase();
    if (!q) return allServers;
    return allServers.filter(
      (s) =>
        s.name.toLowerCase().includes(q) ||
        s.vendor.toLowerCase().includes(q) ||
        s.summary.toLowerCase().includes(q) ||
        s.sampleTools.toLowerCase().includes(q),
    );
  }, [allServers, searchQuery]);

  const connectedServers = useMemo(
    () => allServers.filter((s) => connectedIds.has(s.id)),
    [allServers, connectedIds],
  );

  const toggleConnect = useCallback((server: MCPServerItem) => {
    setConnectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(server.id)) {
        next.delete(server.id);
      } else {
        next.add(server.id);
      }
      return next;
    });
  }, []);

  const handleOpenConfig = (server: MCPServerItem) => {
    if (connectedIds.has(server.id)) {
      toggleConnect(server);
      return;
    }
    setConfiguringServer(server);
    setConfigValue("");
  };

  const handleSaveConfig = () => {
    if (configuringServer) {
      toggleConnect(configuringServer);
      setConfiguringServer(null);
    }
  };

  const handleAddCustomServer = () => {
    if (!newServerName.trim()) return;
    const newServer: MCPServerItem = {
      id: `custom-${Date.now()}`,
      name: newServerName.trim(),
      vendor: "Custom",
      summary: newServerCommand.trim() || "Local custom command runner",
      category: "Developer",
      action: "Connect",
      sampleTools: "run_command",
      isCustom: true,
    };
    setCustomServers((prev) => [newServer, ...prev]);
    setConnectedIds((prev) => new Set(prev).add(newServer.id));
    setIsAddServerOpen(false);
    setNewServerName("");
    setNewServerCommand("");
  };

  return (
    <SettingsPageContainer className="pb-24 max-w-4xl">
      <div className="space-y-6">
        {/* Top Header Row with MCP Title and Search Servers Capsule */}
        <div className="flex items-center justify-between gap-4 pt-1">
          <h2 className="text-2xl font-bold tracking-tight text-foreground">MCP</h2>
          <div className="relative w-56 sm:w-64">
            <SearchIcon className="absolute left-3 top-1/2 -translate-y-1/2 size-3.5 text-muted-foreground/70" />
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="Search servers"
              className="w-full rounded-full bg-white/[0.06] hover:bg-white/[0.09] focus:bg-white/[0.09] border border-white/10 pl-8.5 pr-3 py-1.5 text-xs text-foreground placeholder:text-muted-foreground/60 focus:outline-none focus:ring-1 focus:ring-[#af52de] transition-all shadow-xs"
            />
            {searchQuery ? (
              <button
                type="button"
                onClick={() => setSearchQuery("")}
                className="absolute right-2.5 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
              >
                <XIcon className="size-3" />
              </button>
            ) : null}
          </div>
        </div>

        {/* Connected servers lead banner */}
        <div className="rounded-2xl border border-white/[0.08] bg-[#1c1c1e]/60 p-4 sm:p-5 flex items-start gap-3.5 shadow-xs/5">
          <div className="size-8 rounded-xl bg-[#af52de] flex items-center justify-center shrink-0 mt-0.5 shadow-xs">
            <ShieldCheckIcon className="size-5 text-white" />
          </div>
          <div className="min-w-0 flex-1 space-y-1">
            <div className="flex items-center gap-1.5">
              <h3 className="text-[13px] font-semibold text-foreground">Connected servers lead</h3>
              <InfoIcon className="size-3.5 text-muted-foreground/60" />
            </div>
            <p className="text-xs text-muted-foreground leading-relaxed">
              Connect a server here and every thread can use it. Anything set up in a terminal or
              another app stays just as it is.
            </p>
          </div>
        </div>

        {/* Connected Section (Active when servers are connected) */}
        {connectedServers.length > 0 ? (
          <div className="space-y-2">
            <h3 className="text-sm font-semibold tracking-tight text-foreground px-0.5">Connected</h3>
            <div className="rounded-2xl border border-white/[0.08] bg-[#1c1c1e]/60 divide-y divide-white/[0.06] shadow-xs/5 overflow-hidden">
              {connectedServers.map((server) => (
                <div
                  key={server.id}
                  className="flex items-center justify-between gap-4 px-4 py-3 sm:px-5"
                >
                  <div className="flex items-center gap-3 min-w-0">
                    <ServerBrandIcon server={server} size="sm" />
                    <div className="min-w-0">
                      <div className="text-[13px] font-semibold text-foreground flex items-center gap-2">
                        <span>{server.name}</span>
                        <span className="inline-flex items-center gap-1 text-[11px] text-emerald-400 font-normal">
                          <CheckIcon className="size-3" />
                          <span>Connected</span>
                        </span>
                      </div>
                      <div className="text-xs text-muted-foreground truncate">{server.summary}</div>
                    </div>
                  </div>
                  <button
                    type="button"
                    onClick={() => toggleConnect(server)}
                    className="rounded-full bg-white/[0.08] hover:bg-red-500/20 hover:text-red-400 text-xs font-semibold px-3 py-1 transition-colors text-muted-foreground cursor-pointer"
                  >
                    Disconnect
                  </button>
                </div>
              ))}
            </div>
          </div>
        ) : null}

        {/* Custom Section */}
        <div className="space-y-2">
          <h3 className="text-sm font-semibold tracking-tight text-foreground px-0.5">Custom</h3>
          <div className="rounded-2xl border border-white/[0.08] bg-[#1c1c1e]/60 divide-y divide-white/[0.06] shadow-xs/5 overflow-hidden">
            <div className="px-4 py-3.5 sm:px-5 sm:py-4">
              <p className="text-xs text-muted-foreground leading-relaxed">
                Servers of your own: a command that runs on this Mac, or a remote address, with the
                variables they need.
              </p>
            </div>
            <div className="px-4 py-3 sm:px-5 sm:py-3.5">
              <button
                type="button"
                onClick={() => setIsAddServerOpen(true)}
                className="flex items-center gap-2 text-xs font-semibold text-foreground hover:text-[#af52de] transition-colors cursor-pointer"
              >
                <span className="size-4.5 rounded-full border border-white/40 flex items-center justify-center text-xs font-bold leading-none">
                  +
                </span>
                <span>Add server</span>
              </button>
            </div>
          </div>
        </div>

        {/* Categorized Sections */}
        {CATEGORIES.map((cat) => {
          const servers = filteredServers.filter((s) => s.category === cat);
          if (servers.length === 0) return null;

          return (
            <div key={cat} className="space-y-2.5">
              <h3 className="text-sm font-semibold tracking-tight text-foreground px-0.5">{cat}</h3>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-2.5">
                {servers.map((server) => {
                  const isConnected = connectedIds.has(server.id);
                  return (
                    <div
                      key={server.id}
                      className="rounded-2xl border border-white/[0.08] bg-[#1c1c1e]/60 hover:border-white/[0.16] p-4 flex flex-col justify-between min-h-[142px] transition-colors shadow-xs/5"
                    >
                      {/* Top Row: Icon + Names + Action Button */}
                      <div className="flex items-start justify-between gap-3">
                        <div className="flex items-center gap-3 min-w-0">
                          <ServerBrandIcon server={server} size="md" />
                          <div className="min-w-0">
                            <h4 className="text-[14px] font-semibold text-foreground leading-tight truncate">
                              {server.name}
                            </h4>
                            <p className="text-[12px] text-muted-foreground mt-0.5 truncate">
                              {server.vendor}
                            </p>
                          </div>
                        </div>

                        <button
                          type="button"
                          onClick={() => handleOpenConfig(server)}
                          className={`rounded-full px-3.5 py-1 text-xs font-semibold transition-colors shadow-xs shrink-0 cursor-pointer ${
                            isConnected
                              ? "bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 hover:bg-emerald-500/30"
                              : "bg-[#af52de] hover:bg-[#9d3ed0] active:bg-[#8b2ec0] text-white"
                          }`}
                        >
                          {isConnected ? (
                            <span className="inline-flex items-center gap-1">
                              <CheckIcon className="size-3" />
                              <span>Connected</span>
                            </span>
                          ) : (
                            server.action
                          )}
                        </button>
                      </div>

                      {/* Middle: Summary */}
                      <p className="text-xs text-muted-foreground line-clamp-2 leading-relaxed my-2 min-h-[32px]">
                        {server.summary}
                      </p>

                      {/* Bottom Row: Sample tools and info button */}
                      <div className="flex items-center justify-between gap-2 pt-2 border-t border-white/[0.05] text-[11px] font-mono text-muted-foreground/60">
                        <span className="truncate">{server.sampleTools}</span>
                        <a
                          href={server.docsUrl ?? "#"}
                          target="_blank"
                          rel="noreferrer noopener"
                          aria-label="View documentation"
                          className="shrink-0 text-muted-foreground/60 hover:text-foreground transition-colors"
                        >
                          <InfoIcon className="size-3.5" />
                        </a>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          );
        })}

        {/* Footer Note */}
        <p className="text-xs text-muted-foreground leading-relaxed pt-2">
          Connected servers reach every provider when a thread starts: the CLIs at launch, the API
          models through Swarm Code itself.
        </p>
      </div>

      {/* Add Custom Server Modal */}
      {isAddServerOpen ? (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4 animate-in fade-in duration-150">
          <div className="w-full max-w-md rounded-2xl border border-border/80 bg-card p-6 shadow-xl space-y-4">
            <div className="flex items-center justify-between">
              <h3 className="text-base font-semibold text-foreground">Add Custom MCP Server</h3>
              <button
                type="button"
                onClick={() => setIsAddServerOpen(false)}
                className="rounded-lg p-1.5 text-muted-foreground hover:text-foreground hover:bg-muted/60"
              >
                <XIcon className="size-4" />
              </button>
            </div>

            <div className="space-y-3 text-xs">
              <div>
                <label className="block font-medium text-foreground mb-1">Server Name</label>
                <input
                  type="text"
                  value={newServerName}
                  onChange={(e) => setNewServerName(e.target.value)}
                  placeholder="e.g. My Database Server"
                  className="w-full rounded-xl border border-border/70 bg-muted/20 px-3 py-2 text-foreground focus:outline-none focus:ring-1 focus:ring-[#af52de]"
                />
              </div>

              <div>
                <label className="block font-medium text-foreground mb-1">
                  Command or URL (stdio / SSE)
                </label>
                <input
                  type="text"
                  value={newServerCommand}
                  onChange={(e) => setNewServerCommand(e.target.value)}
                  placeholder="npx -y @modelcontextprotocol/server-postgres postgresql://..."
                  className="w-full rounded-xl border border-border/70 bg-muted/20 px-3 py-2 font-mono text-foreground focus:outline-none focus:ring-1 focus:ring-[#af52de]"
                />
              </div>
            </div>

            <div className="flex justify-end gap-2 pt-2">
              <button
                type="button"
                onClick={() => setIsAddServerOpen(false)}
                className="px-4 py-1.5 text-xs text-muted-foreground hover:text-foreground"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleAddCustomServer}
                disabled={!newServerName.trim()}
                className="rounded-full bg-[#af52de] hover:bg-[#9d3ed0] disabled:opacity-50 text-white px-5 py-1.5 text-xs font-semibold shadow-sm transition-colors cursor-pointer"
              >
                Add & Connect
              </button>
            </div>
          </div>
        </div>
      ) : null}

      {/* Configure Server Key / Auth Modal */}
      {configuringServer ? (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4 animate-in fade-in duration-150">
          <div className="w-full max-w-md rounded-2xl border border-border/80 bg-card p-6 shadow-xl space-y-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2.5">
                <ServerBrandIcon server={configuringServer} size="sm" />
                <div>
                  <h3 className="text-base font-semibold text-foreground">
                    Connect {configuringServer.name}
                  </h3>
                  <p className="text-xs text-muted-foreground">{configuringServer.vendor}</p>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setConfiguringServer(null)}
                className="rounded-lg p-1.5 text-muted-foreground hover:text-foreground hover:bg-muted/60"
              >
                <XIcon className="size-4" />
              </button>
            </div>

            <p className="text-xs text-muted-foreground leading-relaxed">
              {configuringServer.summary}
            </p>

            <div className="space-y-2 text-xs">
              <label className="block font-medium text-foreground">
                {configuringServer.action === "Sign in"
                  ? "Access Token / API Key"
                  : "Connection String or Token"}
              </label>
              <input
                type="password"
                value={configValue}
                onChange={(e) => setConfigValue(e.target.value)}
                placeholder="Paste token or leave blank to test default connection..."
                className="w-full rounded-xl border border-border/70 bg-muted/20 px-3 py-2 font-mono text-foreground focus:outline-none focus:ring-1 focus:ring-[#af52de]"
              />
            </div>

            <div className="flex justify-end gap-2 pt-2">
              <button
                type="button"
                onClick={() => setConfiguringServer(null)}
                className="px-4 py-1.5 text-xs text-muted-foreground hover:text-foreground"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleSaveConfig}
                className="rounded-full bg-[#af52de] hover:bg-[#9d3ed0] text-white px-5 py-1.5 text-xs font-semibold shadow-sm transition-colors cursor-pointer"
              >
                Connect Server
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </SettingsPageContainer>
  );
}

function ServerBrandIcon({ server, size = "md" }: { server: MCPServerItem; size?: "sm" | "md" }) {
  const sizeClasses = size === "sm" ? "size-7" : "size-10";
  const iconClasses = size === "sm" ? "size-4" : "size-5.5";

  switch (server.id) {
    case "github":
      return (
        <div className={`${sizeClasses} rounded-xl bg-[#24292F] flex items-center justify-center shrink-0 text-white shadow-xs`}>
          <GitHubIcon className={iconClasses} />
        </div>
      );
    case "gitlab":
      return (
        <div className={`${sizeClasses} rounded-xl bg-[#FC6D26]/20 border border-[#FC6D26]/30 flex items-center justify-center shrink-0 text-white shadow-xs`}>
          <GitLabIcon className={iconClasses} />
        </div>
      );
    case "filesystem":
      return (
        <div className={`${sizeClasses} rounded-xl bg-white/[0.08] flex items-center justify-center shrink-0 text-[#8E8E93] shadow-xs`}>
          <FolderIcon className={iconClasses} />
        </div>
      );
    case "git":
      return (
        <div className={`${sizeClasses} rounded-xl bg-[#F05032]/20 border border-[#F05032]/30 flex items-center justify-center shrink-0 text-white shadow-xs`}>
          <GitIcon className={iconClasses} />
        </div>
      );
    case "sentry":
      return (
        <div className={`${sizeClasses} rounded-xl bg-[#362D59] flex items-center justify-center shrink-0 text-[#7B61FF] shadow-xs`}>
          <SentryIcon className={iconClasses} />
        </div>
      );
    case "playwright":
      return (
        <div className={`${sizeClasses} rounded-xl bg-[#2EAD33]/15 flex items-center justify-center shrink-0 shadow-xs`}>
          <PlaywrightIcon className={iconClasses} />
        </div>
      );
    case "chrome-devtools":
      return (
        <div className={`${sizeClasses} rounded-xl bg-white/[0.06] flex items-center justify-center shrink-0 shadow-xs`}>
          <ChromeDevToolsIcon className={iconClasses} />
        </div>
      );
    case "fetch":
      return (
        <div className={`${sizeClasses} rounded-xl bg-[#0A84FF]/15 flex items-center justify-center shrink-0 shadow-xs`}>
          <FetchIcon className={iconClasses} />
        </div>
      );
    case "firecrawl":
      return (
        <div className={`${sizeClasses} rounded-xl bg-[#FF6B1A]/15 flex items-center justify-center shrink-0 shadow-xs`}>
          <FirecrawlIcon className={iconClasses} />
        </div>
      );
    case "brave-search":
      return (
        <div className={`${sizeClasses} rounded-xl bg-[#FB542B]/15 flex items-center justify-center shrink-0 shadow-xs`}>
          <BraveIcon className={iconClasses} />
        </div>
      );
    case "tavily":
      return (
        <div className={`${sizeClasses} rounded-xl bg-[#0D9488]/15 flex items-center justify-center shrink-0 shadow-xs`}>
          <TavilyIcon className={iconClasses} />
        </div>
      );
    case "exa":
      return (
        <div className={`${sizeClasses} rounded-xl bg-[#1F4FFF]/15 flex items-center justify-center shrink-0 shadow-xs`}>
          <ExaIcon className={iconClasses} />
        </div>
      );
    case "perplexity":
      return (
        <div className={`${sizeClasses} rounded-xl bg-[#20808D]/15 flex items-center justify-center shrink-0 shadow-xs`}>
          <PerplexityIcon className={iconClasses} />
        </div>
      );
    case "slack":
      return (
        <div className={`${sizeClasses} rounded-xl bg-white/[0.06] flex items-center justify-center shrink-0 shadow-xs`}>
          <SlackIcon className={iconClasses} />
        </div>
      );
    case "notion":
      return (
        <div className={`${sizeClasses} rounded-xl bg-white/[0.06] flex items-center justify-center shrink-0 shadow-xs`}>
          <NotionIcon className={iconClasses} />
        </div>
      );
    case "linear":
      return (
        <div className={`${sizeClasses} rounded-xl bg-[#5E6AD2]/15 flex items-center justify-center shrink-0 shadow-xs`}>
          <LinearIcon className={iconClasses} />
        </div>
      );
    case "atlassian":
      return (
        <div className={`${sizeClasses} rounded-xl bg-[#0052CC]/15 flex items-center justify-center shrink-0 shadow-xs`}>
          <AtlassianIcon className={iconClasses} />
        </div>
      );
    case "figma":
      return (
        <div className={`${sizeClasses} rounded-xl bg-white/[0.06] flex items-center justify-center shrink-0 shadow-xs`}>
          <FigmaIcon className={iconClasses} />
        </div>
      );
    case "stripe":
      return (
        <div className={`${sizeClasses} rounded-xl bg-[#635BFF]/15 flex items-center justify-center shrink-0 shadow-xs`}>
          <StripeIcon className={iconClasses} />
        </div>
      );
    case "resend":
      return (
        <div className={`${sizeClasses} rounded-xl bg-black flex items-center justify-center shrink-0 shadow-xs`}>
          <ResendIcon className={iconClasses} />
        </div>
      );
    case "supabase":
      return (
        <div className={`${sizeClasses} rounded-xl bg-[#3ECF8E]/15 flex items-center justify-center shrink-0 shadow-xs`}>
          <SupabaseIcon className={iconClasses} />
        </div>
      );
    case "postgres":
      return (
        <div className={`${sizeClasses} rounded-xl bg-[#336791]/15 flex items-center justify-center shrink-0 shadow-xs`}>
          <PostgresIcon className={iconClasses} />
        </div>
      );
    case "sqlite":
      return (
        <div className={`${sizeClasses} rounded-xl bg-[#0F80CC]/15 flex items-center justify-center shrink-0 shadow-xs`}>
          <SQLiteIcon className={iconClasses} />
        </div>
      );
    case "mongodb":
      return (
        <div className={`${sizeClasses} rounded-xl bg-[#47A248]/15 flex items-center justify-center shrink-0 shadow-xs`}>
          <MongoDBIcon className={iconClasses} />
        </div>
      );
    case "vercel":
      return (
        <div className={`${sizeClasses} rounded-xl bg-black border border-white/10 flex items-center justify-center shrink-0 shadow-xs`}>
          <VercelIcon className={iconClasses} />
        </div>
      );
    case "cloudflare":
      return (
        <div className={`${sizeClasses} rounded-xl bg-[#F38020]/15 flex items-center justify-center shrink-0 shadow-xs`}>
          <CloudflareIcon className={iconClasses} />
        </div>
      );
    case "netlify":
      return (
        <div className={`${sizeClasses} rounded-xl bg-[#00C7B7]/15 flex items-center justify-center shrink-0 shadow-xs`}>
          <NetlifyIcon className={iconClasses} />
        </div>
      );
    case "aws-docs":
      return (
        <div className={`${sizeClasses} rounded-xl bg-[#FF9900]/15 flex items-center justify-center shrink-0 shadow-xs`}>
          <AWSDocsIcon className={iconClasses} />
        </div>
      );
    case "context7":
      return (
        <div className={`${sizeClasses} rounded-xl bg-[#5B8DEF]/15 flex items-center justify-center shrink-0 shadow-xs`}>
          <Context7Icon className={iconClasses} />
        </div>
      );
    case "memory":
      return (
        <div className={`${sizeClasses} rounded-xl bg-[#AF52DE]/15 flex items-center justify-center shrink-0 shadow-xs`}>
          <MemoryIcon className={iconClasses} />
        </div>
      );
    case "sequential-thinking":
      return (
        <div className={`${sizeClasses} rounded-xl bg-[#30B0C7]/15 flex items-center justify-center shrink-0 shadow-xs`}>
          <SequentialThinkingIcon className={iconClasses} />
        </div>
      );
    case "huggingface":
      return (
        <div className={`${sizeClasses} rounded-xl bg-[#FFD21E]/15 flex items-center justify-center shrink-0 shadow-xs`}>
          <HuggingFaceIcon className={iconClasses} />
        </div>
      );
    case "deepwiki":
      return (
        <div className={`${sizeClasses} rounded-xl bg-white/[0.08] flex items-center justify-center shrink-0 shadow-xs`}>
          <DeepWikiIcon className={iconClasses} />
        </div>
      );
    default:
      return (
        <div
          className={`${sizeClasses} rounded-xl bg-white/[0.08] flex items-center justify-center font-bold text-white shrink-0 shadow-xs`}
        >
          {server.name.charAt(0)}
        </div>
      );
  }
}
