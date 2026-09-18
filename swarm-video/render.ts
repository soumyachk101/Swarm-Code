import { bundle } from "@remotion/bundler";
import { renderMedia, selectComposition } from "@remotion/renderer";
import path from "path";

async function renderVideo() {
  console.log("📦 Bundling Remotion project...");
  const bundleLocation = await bundle({
    entryPoint: path.resolve("./src/Root.tsx"),
  });

  console.log("✅ Bundle complete:", bundleLocation);
  console.log("\n🎬 Launching Remotion Studio...");
  console.log("   Run: npx remotion studio");
  console.log("\n   Or render directly:");
  console.log('   npx remotion render SwarmCodeCinematic SwarmCodeCinematic output/swarm-code-cinematic.mp4');
}

renderVideo().catch((err) => {
  console.error("❌ Error:", err);
  process.exit(1);
});
