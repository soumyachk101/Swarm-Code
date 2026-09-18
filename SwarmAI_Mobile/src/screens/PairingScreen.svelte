<script lang="ts">
import { pairWithCode, getConnectionStatus } from '../api/commands';
import { connectionStatus, view, currentHost, currentPort } from '../stores/appStore';

let code = ['', '', '', '', '', ''];
let inputRefs: HTMLInputElement[] = [];
let error = '';
let isSubmitting = false;

$: if ($connectionStatus === 'paired') {
    view.set('threads');
}

const handleInput = (index: number, value: string) => {
    if (!/^\d*$/.test(value)) return;
    code[index] = value.slice(-1);
    error = '';

    if (code[index] && index < 5) {
        inputRefs[index + 1]?.focus();
    }

    if (code.every(c => c !== '')) {
        submitCode();
    }
};

const handleKeyDown = (index: number, e: KeyboardEvent) => {
    if (e.key === 'Backspace' && !code[index] && index > 0) {
        inputRefs[index - 1]?.focus();
    }
};

const submitCode = async () => {
    const fullCode = code.join('');
    if (fullCode.length !== 6) return;

    isSubmitting = true;
    error = '';
    try {
        await pairWithCode(fullCode);
        // Wait for the paired event to fire
        await new Promise(resolve => setTimeout(resolve, 1000));
    } catch (err) {
        error = err instanceof Error ? err.message : 'Pairing failed';
        code = ['', '', '', '', '', ''];
        inputRefs[0]?.focus();
    } finally {
        isSubmitting = false;
    }
};

const goBack = () => view.set('connect');
</script>

<div class="screen" style="align-items: center; justify-content: center; padding: 24px;">
    <button class="header-back" style="position: absolute; top: 12px; left: 16px;" on:click={goBack}>
        <svg width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" viewBox="0 0 24 24"><polyline points="15 18 9 12 15 6"/></svg>
    </button>

    <div style="text-align: center; margin-bottom: 40px;">
        <div style="font-size: 48px; margin-bottom: 12px;">🔗</div>
        <h1 style="font-size: 22px; margin-bottom: 6px;">Pair with Mac</h1>
        <p style="font-size: 14px;">Enter the 6-digit code shown on your Mac</p>
    </div>

    <div class="pairing-code-grid">
        {#each code as digit, i}
            <input
                class="pairing-digit"
                type="text"
                inputmode="numeric"
                maxlength="1"
                value={digit}
                bind:this={inputRefs[i]}
                on:input={(e) => handleInput(i, (e.target as HTMLInputElement).value)}
                on:keydown={(e) => handleKeyDown(i, e)}
                disabled={isSubmitting}
            />
        {/each}
    </div>

    {#if error}
        <p style="color: var(--danger); font-size: 13px; margin-top: 20px; text-align: center;">{error}</p>
    {/if}

    {#if isSubmitting}
        <p class="text-muted" style="margin-top: 20px; font-size: 14px;">Pairing...</p>
    {/if}
</div>
