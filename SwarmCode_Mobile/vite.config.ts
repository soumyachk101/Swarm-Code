import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';
import { resolve } from 'path';

export default defineConfig({
	plugins: [svelte()],
	resolve: {
		alias: {
			$lib: resolve(__dirname, './src'),
			$stores: resolve(__dirname, './src/stores'),
			$screens: resolve(__dirname, './src/screens'),
			$api: resolve(__dirname, './src/api'),
			$styles: resolve(__dirname, './src/styles'),
		},
	},
	server: {
		host: '0.0.0.0',
		port: 5174,
	},
});
