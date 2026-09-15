import { defineConfig } from "vite";
import { svelte } from "@sveltejs/vite-plugin-svelte";

export default defineConfig({
 plugins: [svelte()],
 base: "./",
 resolve: {
 alias: {
 $lib: "/src/lib",
 },
 },
 build: {
 outDir: "dist",
 emptyOutDir: true,
 },
 server: {
 port: 5173,
 strictPort: true,
 },
});
