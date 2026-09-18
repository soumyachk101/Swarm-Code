<script lang="ts">
import { view } from '$stores/appStore';
import ConnectScreen from '$screens/ConnectScreen.svelte';
import ThreadListScreen from '$screens/ThreadListScreen.svelte';
import ChatScreen from '$screens/ChatScreen.svelte';
import PairingScreen from '$screens/PairingScreen.svelte';
</script>

{#if $view === 'connect'}
    <ConnectScreen />
{:else if $view === 'threads'}
    <ThreadListScreen />
{:else if $view === 'chat'}
    <ChatScreen />
{:else if $view === 'pair'}
    <PairingScreen />
{/if}
