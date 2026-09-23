import type { SVGProps } from "react";

export type IconProps = SVGProps<SVGSVGElement>;

// Sentry icon
export function SentryIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" {...props}>
      <path d="M13.11 2.37a2.53 2.53 0 0 0-2.22 0L2.83 6.94a2.54 2.54 0 0 0-1.33 2.24v9.64a2.54 2.54 0 0 0 1.33 2.24l8.06 4.56a2.53 2.53 0 0 0 2.22 0l8.06-4.56a2.54 2.54 0 0 0 1.33-2.24V9.18a2.54 2.54 0 0 0-1.33-2.24L13.11 2.37zm-1.11 2.45a.5.5 0 0 1 .44 0l7.26 4.1a.5.5 0 0 1 .26.44v3.83l-3.92-2.22a3.03 3.03 0 0 0-3.04 0l-3.92 2.22V9.36a.5.5 0 0 1 .26-.44l2.66-1.5zm-5.74 5.34 2.94 1.66a5.04 5.04 0 0 1 5.04 0l2.94-1.66 2.8 1.58-2.94 1.66a5.04 5.04 0 0 1-5.04 0l-2.94-1.66-2.8-1.58zm-2.26 2.37 3.92 2.22a3.03 3.03 0 0 0 3.04 0l3.92-2.22v3.83a.5.5 0 0 1-.26.44l-7.26 4.1a.5.5 0 0 1-.44 0l-2.66-1.5a.5.5 0 0 1-.26-.44v-6.43z" />
    </svg>
  );
}

// Playwright masks icon
export function PlaywrightIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" {...props}>
      <path d="M4 6a4 4 0 0 1 7-2.3 4 4 0 0 1 7 2.3v3a8 8 0 0 1-16 0V6z" fill="#2EAD33" stroke="#2EAD33" />
      <circle cx="9" cy="8" r="1" fill="#fff" />
      <circle cx="15" cy="8" r="1" fill="#fff" />
      <path d="M9 12c1.5 1 4.5 1 6 0" stroke="#fff" />
    </svg>
  );
}

// Chrome DevTools pinwheel logo
export function ChromeDevToolsIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" {...props}>
      <circle cx="12" cy="12" r="10" fill="#4285F4" />
      <circle cx="12" cy="12" r="4.5" fill="#FFFFFF" />
      <circle cx="12" cy="12" r="3.5" fill="#1A73E8" />
      <path d="M12 2a10 10 0 0 1 8.66 5H12V2Z" fill="#EA4335" />
      <path d="M20.66 7A10 10 0 0 1 12 22l4.33-7.5 4.33-7.5Z" fill="#34A853" />
      <path d="M12 22A10 10 0 0 1 3.34 7L12 12l-4.33 7.5L12 22Z" fill="#FBBC05" />
      <circle cx="12" cy="12" r="4" fill="#FFFFFF" />
      <circle cx="12" cy="12" r="3" fill="#1A73E8" />
    </svg>
  );
}

// Fetch icon
export function FetchIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" {...props}>
      <circle cx="12" cy="12" r="9" fill="#0A84FF" stroke="#0A84FF" />
      <path d="M12 7v7" stroke="#fff" />
      <path d="m8.5 10.5 3.5 3.5 3.5-3.5" stroke="#fff" />
      <path d="M8 17h8" stroke="#fff" />
    </svg>
  );
}

// Firecrawl flame icon
export function FirecrawlIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" {...props}>
      <path
        d="M12 2c-.6 2.3-2 4.2-3.8 5.6C6.4 9 5 11.4 5 14.2 5 18.5 8.1 22 12 22s7-3.5 7-7.8c0-2.8-1.4-5.2-3.2-6.6-1.8-1.4-3.2-3.3-3.8-5.6zm1 9.5c1.8 1.4 2.5 3.2 2.5 4.7 0 2.1-1.6 3.8-3.5 3.8s-3.5-1.7-3.5-3.8c0-1.5.7-3.3 2.5-4.7.4-.3.9-.3 1.3 0l.7.5z"
        fill="#FF6B1A"
      />
    </svg>
  );
}

// Brave Search lion head icon
export function BraveIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" {...props}>
      <path
        d="M12 2 4 6v6c0 5.5 3.5 10 8 10s8-4.5 8-10V6l-8-4zm0 2.5 5.5 2.8V12c0 3.8-2.4 7.2-5.5 7.8-3.1-.6-5.5-4-5.5-7.8V7.3L12 4.5z"
        fill="#FB542B"
      />
      <path d="M9 10h6v1.5H9zM10.5 13.5h3V15h-3z" fill="#FB542B" />
    </svg>
  );
}

// Tavily icon
export function TavilyIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" {...props}>
      <path
        d="M12 2c.5 4.5 4.5 8.5 9 9-4.5.5-8.5 4.5-9 9-.5-4.5-4.5-8.5-9-9 4.5-.5 8.5-4.5 9-9z"
        fill="#0D9488"
      />
    </svg>
  );
}

// Exa search icon
export function ExaIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" {...props}>
      <circle cx="11" cy="11" r="7" stroke="#1F4FFF" />
      <path d="m16 16 5 5" stroke="#1F4FFF" />
      <circle cx="11" cy="11" r="2.5" fill="#1F4FFF" stroke="none" />
    </svg>
  );
}

// Perplexity woven asterisk icon
export function PerplexityIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="#20808D" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" {...props}>
      <path d="M12 2v20M4 7l16 10M20 7 4 17" />
      <circle cx="12" cy="12" r="3" fill="#20808D" stroke="none" />
    </svg>
  );
}

// Slack logo
export function SlackIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" {...props}>
      <path d="M6 15a2 2 0 0 1-2-2 2 2 0 0 1 2-2h2v2a2 2 0 0 1-2 2zm1-2a2 2 0 0 1 2-2 2 2 0 0 1 2 2v5a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-5z" fill="#E01E5A" />
      <path d="M9 6a2 2 0 0 1 2-2 2 2 0 0 1 2 2v2H11a2 2 0 0 1-2-2zm2 1a2 2 0 0 1 2 2 2 2 0 0 1-2 2H6a2 2 0 0 1-2-2 2 2 0 0 1 2-2h5z" fill="#36C5F0" />
      <path d="M18 9a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-2V11a2 2 0 0 1 2-2zm-1 2a2 2 0 0 1-2 2 2 2 0 0 1-2-2V6a2 2 0 0 1 2-2 2 2 0 0 1 2 2v5z" fill="#2EB67D" />
      <path d="M15 18a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-2h2a2 2 0 0 1 2 2zm-2-1a2 2 0 0 1-2-2 2 2 0 0 1 2-2h5a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-5z" fill="#ECB22E" />
    </svg>
  );
}

// Notion logo
export function NotionIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" {...props}>
      <rect x="3" y="3" width="18" height="18" rx="3.5" fill="#FFFFFF" />
      <path
        d="M6.8 5.8l9.5-.7c.8-.1 1.2.3 1.2 1.1v10.5c0 .7-.3 1.1-.9 1.1l-2.4.2c-.6 0-.8-.3-.8-.8v-6.2l-5 6.7c-.4.5-.8.7-1.3.7l-1.3.1c-.5 0-.8-.4-.8-1.1V7c0-.7.3-1.1.9-1.2h.9v-.0z"
        fill="#000000"
      />
    </svg>
  );
}

// Linear logo
export function LinearIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" {...props}>
      <circle cx="12" cy="12" r="10" fill="#5E6AD2" />
      <path
        d="M6 14.5A7.5 7.5 0 0 0 17.5 6l-1.8 1.8a5 5 0 0 1-7.9 7.9L6 14.5z"
        fill="#FFFFFF"
      />
    </svg>
  );
}

// Atlassian sails logo
export function AtlassianIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" {...props}>
      <path
        d="M11.6 3.2a1 1 0 0 0-1.4.3L4.3 15.6a1 1 0 0 0 .9 1.4h6.7c.6 0 1-.4 1-1V3.9a1 1 0 0 0-1.3-.7z"
        fill="#0052CC"
      />
      <path
        d="M12.4 9.2a1 1 0 0 1 1.4.3l5.9 12.1a1 1 0 0 1-.9 1.4h-6.7c-.6 0-1-.4-1-1v-12c0-.4.2-.7.3-.8z"
        fill="#2684FF"
      />
    </svg>
  );
}

// Figma logo
export function FigmaIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" {...props}>
      <path d="M8.5 2A3.5 3.5 0 0 0 5 5.5 3.5 3.5 0 0 0 8.5 9H12V2H8.5z" fill="#F24E1E" />
      <path d="M12 2h3.5a3.5 3.5 0 0 1 0 7H12V2z" fill="#FF7262" />
      <path d="M12 9h3.5a3.5 3.5 0 0 1 0 7H12V9z" fill="#1ABCFE" />
      <path d="M8.5 9A3.5 3.5 0 0 0 5 12.5 3.5 3.5 0 0 0 8.5 16H12V9H8.5z" fill="#A259FF" />
      <path d="M8.5 16A3.5 3.5 0 0 0 5 19.5 3.5 3.5 0 0 0 8.5 23 3.5 3.5 0 0 0 12 19.5V16H8.5z" fill="#0ACF83" />
    </svg>
  );
}

// Stripe logo
export function StripeIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" {...props}>
      <rect x="2" y="2" width="20" height="20" rx="5" fill="#635BFF" />
      <path
        d="M11.5 8.2c0-.9.8-1.3 1.9-1.3 1.7 0 3.2.5 4.3 1.1V5.2c-1.3-.5-2.9-.8-4.4-.8-3.7 0-6.1 1.9-6.1 5 0 4.9 6.7 4.1 6.7 6.3 0 1-.9 1.4-2.2 1.4-1.9 0-3.7-.7-5-1.5v2.9c1.5.7 3.3 1 5.1 1 3.8 0 6.4-1.8 6.4-5.1 0-5.3-6.7-4.4-6.7-6.2z"
        fill="#FFFFFF"
      />
    </svg>
  );
}

// Resend logo
export function ResendIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" {...props}>
      <rect x="2" y="2" width="20" height="20" rx="5" fill="#000000" stroke="#333" strokeWidth="1" />
      <path
        d="M8 6h5c2.5 0 4 1.3 4 3.3 0 1.6-1 2.7-2.4 3.1l2.9 5.6h-2.8l-2.6-5.2H10.5v5.2H8V6zm2.5 4.8h2.3c1.2 0 1.9-.6 1.9-1.5s-.7-1.5-1.9-1.5h-2.3v3z"
        fill="#FFFFFF"
      />
    </svg>
  );
}

// Supabase logo
export function SupabaseIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" {...props}>
      <path
        d="M13.4 2.2a1 1 0 0 0-1.7.7v8.5H4.2a1 1 0 0 0-.8 1.6l7.2 9.8a1 1 0 0 0 1.7-.7v-8.5h7.5a1 1 0 0 0 .8-1.6l-7.2-9.8z"
        fill="#3ECF8E"
      />
    </svg>
  );
}

// PostgreSQL elephant logo
export function PostgresIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" {...props}>
      <path
        d="M12 2C6.5 2 2 6.5 2 12c0 4.1 2.5 7.6 6.1 9.1-.1-.7-.2-1.6-.2-2.5 0-3.6 2.5-6.6 6.1-6.6 1.2 0 2.3.3 3.3.9V12c0-5.5-4.5-10-10-10zm2.5 13.5c-2.2 0-4 1.8-4 4 0 1 .4 1.9 1 2.6 1.1-.3 2.1-.8 3-1.5v-5.1z"
        fill="#336791"
      />
    </svg>
  );
}

// SQLite feather / cylinder logo
export function SQLiteIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" {...props}>
      <path
        d="M12 2C6.5 2 4 4 4 6v12c0 2 2.5 4 8 4s8-2 8-4V6c0-2-2.5-4-8-4zm0 2c4.7 0 6 1.3 6 2s-1.3 2-6 2-6-1.3-6-2 1.3-2 6-2zm0 6c4.7 0 6 1.3 6 2s-1.3 2-6 2-6-1.3-6-2 1.3-2 6-2zm0 6c4.7 0 6 1.3 6 2s-1.3 2-6 2-6-1.3-6-2 1.3-2 6-2z"
        fill="#0F80CC"
      />
    </svg>
  );
}

// MongoDB leaf logo
export function MongoDBIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" {...props}>
      <path
        d="M12 2C11.5 3.5 8 8 8 13.5c0 3.6 2 6.5 4 8.5 2-2 4-4.9 4-8.5C16 8 12.5 3.5 12 2zm.2 18.2c-.3.3-.4.3-.7 0C9.8 18.5 8.8 16 8.8 13.5c0-4 2.4-7.5 3.4-9.3v16z"
        fill="#47A248"
      />
    </svg>
  );
}

// Vercel triangle logo
export function VercelIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" {...props}>
      <path d="M12 3 22 20H2L12 3z" fill="#FFFFFF" />
    </svg>
  );
}

// Cloudflare orange cloud
export function CloudflareIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" {...props}>
      <path
        d="M19.4 12.6C19 9.8 16.7 7.7 14 7.7c-1.9 0-3.5 1-4.4 2.5C9.2 10 8.6 9.9 8 9.9c-2.8 0-5.1 2.2-5.1 5 0 .3 0 .6.1.9C1.2 16.5 0 18 0 19.8 0 22.1 1.9 24 4.2 24h15.2c2.5 0 4.6-2.1 4.6-4.6 0-2.3-1.7-4.2-4-4.5-.2-.8-.4-1.6-.6-2.3z"
        fill="#F38020"
      />
    </svg>
  );
}

// Netlify geometric diamond logo
export function NetlifyIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" {...props}>
      <path
        d="M12 2 3 12l9 10 9-10L12 2zm0 3.2 6.1 6.8L12 18.8 5.9 12 12 5.2z"
        fill="#00C7B7"
      />
    </svg>
  );
}

// AWS Docs cloud logo
export function AWSDocsIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" {...props}>
      <path
        d="M18.8 11.2a5.5 5.5 0 0 0-10.4-1.9A4.5 4.5 0 0 0 4.5 13.5a4.5 4.5 0 0 0 4.5 4.5h9.5a4 4 0 0 0 4-4 4 4 0 0 0-3.7-2.8z"
        fill="#FF9900"
      />
      <path d="M7 19.5c3 1.5 7 1.5 10 0" stroke="#FF9900" strokeWidth="1.8" strokeLinecap="round" fill="none" />
    </svg>
  );
}

// Context7 logo
export function Context7Icon(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" {...props}>
      <rect x="3" y="3" width="18" height="18" rx="4.5" fill="#5B8DEF" />
      <path d="M8 8h8l-5 9h-2.5l4.5-7.2H8V8z" fill="#FFFFFF" />
    </svg>
  );
}

// Memory purple brain logo
export function MemoryIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" {...props}>
      <rect x="2" y="2" width="20" height="20" rx="5" fill="#AF52DE" />
      <path
        d="M12 6a3.5 3.5 0 0 0-3.5 3.5c0 .6.2 1.1.4 1.6A3.5 3.5 0 0 0 7 14.5c0 1.9 1.6 3.5 3.5 3.5.5 0 1-.1 1.5-.3.5.2 1 .3 1.5.3 1.9 0 3.5-1.6 3.5-3.5 0-.5-.1-1-.3-1.5.9-.6 1.4-1.6 1.4-2.7C18.1 8.5 16.5 6 14.5 6c-.8 0-1.6.3-2.5.8V6z"
        fill="#FFFFFF"
      />
    </svg>
  );
}

// Sequential Thinking cyan nodes logo
export function SequentialThinkingIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="#30B0C7" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" {...props}>
      <circle cx="5" cy="12" r="3" fill="#30B0C7" />
      <circle cx="12" cy="12" r="3" fill="#30B0C7" />
      <circle cx="19" cy="12" r="3" fill="#30B0C7" />
      <line x1="8" y1="12" x2="9" y2="12" />
      <line x1="15" y1="12" x2="16" y2="12" />
    </svg>
  );
}

// Hugging Face emoji logo
export function HuggingFaceIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" {...props}>
      <circle cx="12" cy="12" r="10" fill="#FFD21E" />
      <path d="M8 10a1.2 1.2 0 1 1 0-2.4 1.2 1.2 0 0 1 0 2.4zm8 0a1.2 1.2 0 1 1 0-2.4 1.2 1.2 0 0 1 0 2.4z" fill="#000" />
      <path d="M8.5 14.5c1 1.5 2.5 2 3.5 2s2.5-.5 3.5-2" stroke="#000" strokeWidth="1.6" strokeLinecap="round" fill="none" />
      <path d="M4 14c1-1 2.5-1 3.5 0M20 14c-1-1-2.5-1-3.5 0" stroke="#D97706" strokeWidth="1.8" strokeLinecap="round" fill="none" />
    </svg>
  );
}

// DeepWiki open book logo
export function DeepWikiIcon(props: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" {...props}>
      <rect x="2" y="2" width="20" height="20" rx="5" fill="#1D1D1F" stroke="#333" strokeWidth="1" />
      <path
        d="M6 7.5A2.5 2.5 0 0 1 8.5 5H12v12.5H8.5A2.5 2.5 0 0 0 6 20V7.5zm12 0A2.5 2.5 0 0 0 15.5 5H12v12.5h3.5a2.5 2.5 0 0 1 2.5 2.5V7.5z"
        fill="#FFFFFF"
      />
    </svg>
  );
}
