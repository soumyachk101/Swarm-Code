<script lang="ts">
	import { onMount } from 'svelte';
	import { appStore, updateSettings } from '$lib/stores/appStore';

	let settings = $derived($appStore.settings);

	let shell = $state('');
	let copyOnSelect = $state(false);
	let cursorShape = $state('block');
	let scrollbackLines = $state(10000);
	let fontSize = $state(14);
	let lineHeight = $state(1.2);
	let debugLogging = $state(false);
	let macosOptionIsMeta = $state(false);

	const ALLOWED_SHELLS = ['bash', 'zsh', 'fish', 'nu', 'pwsh', 'sh'];

	onMount(() => {
		if (settings) {
			shell = settings.terminal_shell ?? '/bin/zsh';
			copyOnSelect = settings.terminal_copyOnSelect ?? false;
			cursorShape = settings.terminal_cursorShape ?? 'block';
			scrollbackLines = settings.terminal_scrollback ?? 10000;
			fontSize = settings.terminal_fontSize ?? 14;
			lineHeight = settings.terminal_lineHeight ?? 1.2;
			debugLogging = settings.terminal_debugLogging ?? false;
			macosOptionIsMeta = settings.terminal_macosOptionIsMeta ?? false;
		}
	});

	function handleSave() {
		if (!settings) return;
		updateSettings({
			terminal_shell: shell,
			terminal_copyOnSelect: copyOnSelect,
			terminal_cursorShape: cursorShape,
			terminal_scrollback: scrollbackLines,
			terminal_fontSize: fontSize,
			terminal_lineHeight: lineHeight,
			terminal_debugLogging: debugLogging,
			terminal_macosOptionIsMeta: macosOptionIsMeta
		});
	}
</script>

<div class="settings-page">
	<h2 class="page-title">Terminal</h2>
	<p class="page-description">Configure the integrated terminal experience.</p>

	<div class="settings-section">
		<h3 class="section-title">Shell</h3>
		<div class="settings-group">
			<div class="setting-item">
				<div class="setting-info">
					<label class="setting-label">Default Shell</label>
					<p class="setting-description">Shell executable for new terminal sessions</p>
				</div>
				<div class="settings-field-control">
					<input
						type="text"
						class="settings-input mono"
						list="allowed-shells"
						bind:value={shell}
					/>
					<datalist id="allowed-shells">
						{#each ALLOWED_SHELLS as s}
							<option value={s}></option>
						{/each}
					</datalist>
				</div>
			</div>
		</div>
	</div>

	<div class="settings-section">
		<h3 class="section-title">Selection</h3>
		<div class="settings-group">
			<div class="setting-item">
				<div class="setting-info">
					<label class="setting-label">Copy on Select</label>
					<p class="setting-description">Copy text to clipboard when selected</p>
				</div>
				<button
					class="toggle {copyOnSelect ? 'active' : ''}"
					onclick={() => copyOnSelect = !copyOnSelect}
					aria-label="Toggle copy on select"
				>
					<div class="toggle-thumb"></div>
				</button>
			</div>
		</div>
	</div>

	<div class="settings-section">
		<h3 class="section-title">Cursor</h3>
		<div class="settings-group">
			<div class="setting-item">
				<div class="setting-info">
					<label class="setting-label">Cursor Shape</label>
					<p class="setting-description">Terminal cursor style</p>
				</div>
				<select class="settings-select" bind:value={cursorShape}>
					<option value="block">Block</option>
					<option value="beam">Beam</option>
					<option value="underline">Underline</option>
				</select>
			</div>
		</div>
	</div>

	<div class="settings-section">
		<h3 class="section-title">Scrollback</h3>
		<div class="settings-group">
			<div class="setting-item">
				<div class="setting-info">
					<label class="setting-label">Scrollback Lines</label>
					<p class="setting-description">Number of lines to keep in scrollback buffer</p>
				</div>
				<input
					type="number"
					class="settings-input"
					bind:value={scrollbackLines}
					min="100"
					max="100000"
					step="100"
				/>
			</div>
		</div>
	</div>

	<div class="settings-section">
		<h3 class="section-title">Appearance</h3>
		<div class="settings-group">
			<div class="setting-item">
				<div class="setting-info">
					<label class="setting-label">Font Size</label>
					<p class="setting-description">Terminal font size in pixels</p>
				</div>
				<input
					type="number"
					class="settings-input"
					bind:value={fontSize}
					min="8"
					max="32"
					step="1"
				/>
			</div>

			<div class="setting-item">
				<div class="setting-info">
					<label class="setting-label">Line Height</label>
					<p class="setting-description">Line spacing multiplier</p>
				</div>
				<input
					type="number"
					class="settings-input"
					bind:value={lineHeight}
					min="1.0"
					max="2.0"
					step="0.05"
				/>
			</div>
		</div>
	</div>

	<div class="settings-section">
		<h3 class="section-title">Platform</h3>
		<div class="settings-group">
			<div class="setting-item">
				<div class="setting-info">
					<label class="setting-label">macOS Option as Meta</label>
					<p class="setting-description">Treat Option key as Meta in terminal</p>
				</div>
				<button
					class="toggle {macosOptionIsMeta ? 'active' : ''}"
					onclick={() => macosOptionIsMeta = !macosOptionIsMeta}
					aria-label="Toggle macOS option as meta"
				>
					<div class="toggle-thumb"></div>
				</button>
			</div>
		</div>
	</div>

	<div class="settings-section">
		<h3 class="section-title">Debug</h3>
		<div class="settings-group">
			<div class="setting-item">
				<div class="setting-info">
					<label class="setting-label">Debug Logging</label>
					<p class="setting-description">Enable verbose terminal debug output</p>
				</div>
				<button
					class="toggle {debugLogging ? 'active' : ''}"
					onclick={() => debugLogging = !debugLogging}
					aria-label="Toggle debug logging"
				>
					<div class="toggle-thumb"></div>
				</button>
			</div>
		</div>
	</div>
</div>

<style>
	.settings-page {
		display: flex;
		flex-direction: column;
		gap: 1.5rem;
		padding: 2rem;
		max-width: 720px;
	}
	.page-title {
		font-size: 1.5rem;
		font-weight: 600;
		margin: 0;
	}
	.page-description {
		color: var(--text-secondary);
		margin: 0;
		font-size: 0.875rem;
	}
	.settings-section {
		display: flex;
		flex-direction: column;
		gap: 0.75rem;
	}
	.section-title {
		font-size: 0.75rem;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--text-secondary);
		margin: 0;
	}
	.settings-group {
		display: flex;
		flex-direction: column;
		gap: 1px;
		background: var(--border);
		border-radius: 8px;
		overflow: hidden;
		border: 1px solid var(--border);
	}
	.setting-item {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 0.875rem 1rem;
		background: var(--surface-2);
		gap: 1rem;
	}
	.setting-info {
		display: flex;
		flex-direction: column;
		gap: 0.125rem;
	}
	.setting-label {
		font-size: 0.8125rem;
		font-weight: 500;
	}
	.setting-description {
		font-size: 0.75rem;
		color: var(--text-secondary);
		margin: 0;
	}
	.settings-field-control {
		display: flex;
		align-items: center;
	}
	.toggle {
		position: relative;
		width: 36px;
		height: 20px;
		border-radius: 10px;
		border: none;
		cursor: pointer;
		background: var(--border);
		padding: 0;
		flex-shrink: 0;
		transition: background 0.2s;
	}
	.toggle.active {
		background: var(--accent, #007aff);
	}
	.toggle-thumb {
		position: absolute;
		top: 2px;
		left: 2px;
		width: 16px;
		height: 16px;
		border-radius: 50%;
		background: white;
		box-shadow: 0 1px 3px rgba(0,0,0,0.2);
		transition: transform 0.2s;
	}
	.toggle.active .toggle-thumb {
		transform: translateX(16px);
	}
	.settings-select {
		padding: 0.375rem 0.625rem;
		border-radius: 6px;
		border: 1px solid var(--border);
		background: var(--surface-1);
		color: var(--text-primary);
		font-size: 0.8125rem;
		cursor: pointer;
	}
	.settings-input {
		width: 120px;
		padding: 0.375rem 0.625rem;
		border-radius: 6px;
		border: 1px solid var(--border);
		background: var(--surface-1);
		color: var(--text-primary);
		font-size: 0.8125rem;
		text-align: right;
	}
	.mono {
		font-family: ui-monospace, 'SF Mono', Menlo, monospace;
	}
</style>
