// SwarmAI Tauri - Main entry point
import './app.css';
import App from './App.svelte';

// Svelte 5: mount the app
import { mount } from 'svelte';

mount(App, {
	target: document.getElementById('app'),
});
