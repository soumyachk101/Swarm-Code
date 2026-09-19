<script lang="ts">
	interface Props {
		content: string;
		class?: string;
	}

	let { content, class: className = '' }: Props = $props();

	function escapeHtml(text: string): string {
		const div = document.createElement('div');
		div.textContent = text;
		return div.innerHTML;
	}

	let htmlContent = $derived(() => {
		let text = content;

		// Escape first to prevent XSS
		text = escapeHtml(text);

		// Code blocks (must be before other inline processing)
		text = text.replace(/&lt;code&gt;([\s\S]*?)&lt;\/code&gt;/g, (match, code) => {
			return `<code class="inline-code">${code}</code>`;
		});

		// Code blocks with optional language
		text = text.replace(/```(\w+)?\n?([\s\S]*?)```/g, (match, lang, code) => {
			const langLabel = lang ? `<span class="code-lang">${escapeHtml(lang)}</span>` : '';
			const escaped = escapeHtml(code.trim());
			return `<div class="code-block-wrapper"><pre class="code-block">${langLabel}<code>${escaped}</code></pre><button class="code-copy-btn" data-code="${escapeHtml(escaped).slice(0, 50)}" title="Copy code" aria-label="Copy code to clipboard"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg></button></div>`;
		});

		// Bold
		text = text.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
		text = text.replace(/__([^_]+)__/g, '<strong>$1</strong>');

		// Italic
		text = text.replace(/\*([^*]+)\*/g, '<em>$1</em>');
		text = text.replace(/_([^_]+)_/g, '<em>$1</em>');

		// Strikethrough
		text = text.replace(/~~([^~]+)~~/g, '<del>$1</del>');

		// Headers
		text = text.replace(/^### (.+)$/gm, '<h4>$1</h4>');
		text = text.replace(/^## (.+)$/gm, '<h3>$1</h3>');
		text = text.replace(/^# (.+)$/gm, '<h2>$1</h2>');

		// Links
		text = text.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" class="md-link" target="_blank" rel="noopener noreferrer">$1</a>');

		// Blockquotes
		text = text.replace(/^&gt;\s?(.+)$/gm, '<blockquote>$1</blockquote>');

		// Lists (simple unordered)
		const lines = text.split('\n');
		const processed = lines.map(line => {
			const ulMatch = line.match(/^(\s*)[-*]\s(.+)$/);
			if (ulMatch) {
				return `<li>${ulMatch[2]}</li>`;
			}
			const olMatch = line.match(/^(\s*)\d+\.\s(.+)$/);
			if (olMatch) {
				return `<li>${olMatch[2]}</li>`;
			}
			return line;
		});
		text = processed.join('\n');

		// Wrap consecutive <li> in <ul>
		text = text.replace(/(<li>.*?<\/li>\n?)+/g, (match) => `<ul>${match}</ul>`);

		// Paragraphs — split by double newlines
		const blocks = text.split(/\n\n+/);
		text = blocks.map(block => {
			const trimmed = block.trim();
			if (!trimmed) return '';
			if (
				trimmed.startsWith('<pre') ||
				trimmed.startsWith('<ul') ||
				trimmed.startsWith('<h') ||
				trimmed.startsWith('<blockquote') ||
				trimmed.startsWith('<div') ||
				trimmed.startsWith('<table') ||
				trimmed.startsWith('<ol')
			) {
				return trimmed;
			}
			return `<p>${trimmed.replace(/\n/g, '<br/>')}</p>`;
		}).join('\n');

		// Collapse multiple consecutive blockquotes
		text = text.replace(/(<blockquote>.*?<\/blockquote>\n?)+/g, (match) => `<blockquote>${match.replace(/<\/?blockquote>/g, '')}</blockquote>`);

		return text;
	});

	let containerRef: HTMLDivElement | undefined = $state();

	function handleClick(e: MouseEvent) {
		const target = e.target as HTMLElement;
		const copyBtn = target.closest('.code-copy-btn') as HTMLButtonElement | null;
		if (!copyBtn) return;

		const pre = copyBtn.closest('.code-block-wrapper');
		if (!pre) return;

		const codeEl = pre.querySelector('code');
		if (!codeEl) return;

		const text = codeEl.textContent ?? '';
		navigator.clipboard.writeText(text).then(() => {
			const original = copyBtn.innerHTML;
			copyBtn.innerHTML = '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="20 6 9 17 4 12"/></svg>';
			copyBtn.classList.add('copied');
			setTimeout(() => {
				copyBtn.innerHTML = original;
				copyBtn.classList.remove('copied');
			}, 1500);
		}).catch(() => {
			console.error('Failed to copy');
		});
	}

	function handleCodeBlockKeydown(e: KeyboardEvent) {
		const target = e.target as HTMLElement;
		if (target.classList.contains('code-copy-btn') && (e.key === 'Enter' || e.key === ' ')) {
			e.preventDefault();
			target.click();
		}
	}
</script>

<div
	bind:this={containerRef}
	class="markdown-renderer {className}"
	onclick={handleClick}
	onkeydown={handleCodeBlockKeydown}
>
	{@html htmlContent()}
</div>

<style>
	.markdown-renderer {
		font-size: var(--font-size-md);
		line-height: var(--line-height-relaxed);
		color: var(--text-primary);
		word-wrap: break-word;
	}

	.markdown-renderer :global(p) {
		margin-bottom: 0.6em;
	}

	.markdown-renderer :global(p:last-child) {
		margin-bottom: 0;
	}

	.markdown-renderer :global(h2),
	.markdown-renderer :global(h3),
	.markdown-renderer :global(h4) {
		font-weight: 600;
		margin-top: 0.8em;
		margin-bottom: 0.4em;
		color: var(--text-primary);
	}

	.markdown-renderer :global(h2) {
		font-size: 1.3em;
		border-bottom: 1px solid var(--border-color-1);
		padding-bottom: 0.2em;
	}

	.markdown-renderer :global(h3) {
		font-size: 1.15em;
	}

	.markdown-renderer :global(h4) {
		font-size: 1em;
	}

	.markdown-renderer :global(ul),
	.markdown-renderer :global(ol) {
		margin: 0.4em 0;
		padding-left: 1.5em;
	}

	.markdown-renderer :global(li) {
		margin-bottom: 0.15em;
	}

	.markdown-renderer :global(blockquote) {
		border-left: 3px solid var(--accent-1);
		padding-left: var(--space-3);
		margin: 0.5em 0;
		color: var(--text-secondary);
	}

	.markdown-renderer :global(code) {
		font-family: var(--font-mono);
		font-size: 0.88em;
		background: var(--surface-3);
		padding: 0.1em 0.35em;
		border-radius: 3px;
		color: var(--accent-1);
	}

	.markdown-renderer :global(.inline-code) {
		font-size: 0.85em;
	}

	.markdown-renderer :global(.code-block-wrapper) {
		position: relative;
		margin: 0.6em 0;
	}

	.markdown-renderer :global(pre) {
		background: var(--surface-2);
		border: var(--border-1) var(--border-color-1);
		border-radius: var(--radius-md);
		padding: var(--space-4);
		padding-top: var(--space-3);
		overflow-x: auto;
	}

	.markdown-renderer :global(pre code) {
		background: none;
		padding: 0;
		border-radius: 0;
		font-size: var(--font-size-sm);
		color: var(--text-primary);
		line-height: 1.5;
	}

	.markdown-renderer :global(.code-lang) {
		display: block;
		font-size: 10px;
		font-family: var(--font-mono);
		text-transform: uppercase;
		letter-spacing: 0.5px;
		color: var(--text-tertiary);
		margin-bottom: var(--space-2);
	}

	.markdown-renderer :global(.code-copy-btn) {
		position: absolute;
		top: var(--space-2);
		right: var(--space-2);
		width: 28px;
		height: 28px;
		display: flex;
		align-items: center;
		justify-content: center;
		border: var(--border-1) var(--border-color-1);
		background: var(--surface-1);
		border-radius: var(--radius-sm);
		color: var(--text-tertiary);
		cursor: pointer;
		opacity: 0;
		transition: all var(--transition-fast);
		padding: 0;
	}

	.markdown-renderer :global(.code-block-wrapper:hover .code-copy-btn) {
		opacity: 1;
	}

	.markdown-renderer :global(.code-copy-btn:hover) {
		background: var(--surface-3);
		color: var(--text-primary);
	}

	.markdown-renderer :global(.code-copy-btn.copied) {
		opacity: 1;
		color: var(--success);
		background: var(--surface-1);
	}

	.markdown-renderer :global(.md-link) {
		color: var(--accent-1);
		text-decoration: none;
	}

	.markdown-renderer :global(.md-link:hover) {
		text-decoration: underline;
	}

	.markdown-renderer :global(strong) {
		font-weight: 600;
	}

	.markdown-renderer :global(em) {
		font-style: italic;
	}

	.markdown-renderer :global(del) {
		opacity: 0.6;
	}

	.markdown-renderer :global(table) {
		border-collapse: collapse;
		width: 100%;
		margin: var(--space-3) 0;
		font-size: var(--font-size-sm);
	}

	.markdown-renderer :global(th) {
		text-align: left;
		font-weight: 600;
		padding: var(--space-2) var(--space-3);
		border: var(--border-1) var(--border-color-1);
		background: var(--surface-2);
	}

	.markdown-renderer :global(td) {
		padding: var(--space-2) var(--space-3);
		border: var(--border-1) var(--border-color-1);
	}
</style>
