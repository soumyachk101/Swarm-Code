import swamlLogo from '../../assets/icons/swarmai-logo.svg';
import hydraMark from '../../assets/icons/hydra-mark.svg';
import providerClaude from '../../assets/icons/provider-claude.svg';
import providerAntigravity from '../../assets/icons/provider-antigravity.svg';
import providerCodex from '../../assets/icons/provider-codex.svg';
import providerCopilot from '../../assets/icons/provider-copilot.svg';
import providerCursor from '../../assets/icons/provider-cursor.svg';
import providerDeepSeek from '../../assets/icons/provider-deepseek.svg';
import providerDevin from '../../assets/icons/provider-devin.svg';
import providerGrok from '../../assets/icons/provider-grok.svg';
import providerMeta from '../../assets/icons/provider-meta.svg';
import providerOllama from '../../assets/icons/provider-opencode.svg';

export const ICONS = {
	swarmai_logo: swamlLogo,
	hydra_mark: hydraMark,
	provider_openai: providerClaude,
	provider_anthropic: providerAntigravity,
	provider_claude: providerClaude,
	provider_codex: providerCodex,
	provider_copilot: providerCopilot,
	provider_cursor: providerCursor,
	provider_deepseek: providerDeepSeek,
	provider_devin: providerDevin,
	provider_grok: providerGrok,
	provider_meta: providerMeta,
	provider_ollama: providerOllama,
};

export function providerIcon(providerId: string): string {
	const map: Record<string, string> = {
		openai: 'provider_openai',
		claude: 'provider_claude',
		anthropic: 'provider_anthropic',
		copilot: 'provider_copilot',
		cursor: 'provider_cursor',
		codex: 'provider_codex',
		devin: 'provider_devin',
		deepseek: 'provider_deepseek',
		grok: 'provider_grok',
		meta: 'provider_meta',
		ollama: 'provider_ollama',
	};
	return ICONS[map[providerId] ?? 'provider_openai'];
}

export function providerShortName(providerId: string): string {
	const map: Record<string, string> = {
		openai: 'OA',
		claude: 'CL',
		anthropic: 'AN',
		copilot: 'GH',
		cursor: 'CU',
		codex: 'CD',
		devin: 'DV',
		deepseek: 'DS',
		grok: 'GR',
		meta: 'ME',
		ollama: 'OL',
		gemini: 'GE',
		azure: 'AZ',
		local: 'LO',
		custom: 'CU',
	};
	return map[providerId] ?? '?';
}
