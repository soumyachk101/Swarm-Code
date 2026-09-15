import { vitePreprocess } from "@sveltejs/vite-plugin-svelte";

export default {
 preprocess: vitePreprocess({
 typeCheck: false,
 }),
 compilerOptions: {
 runes: true,
 },
};
