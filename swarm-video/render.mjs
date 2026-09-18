import { bundle } from "@remotion/bundler";
import { renderMedia, selectComposition } from "@remotion/renderer";
import path from "path";

async function main() {
  const bundlePath = await bundle(path.resolve("./src/Root.tsx"), {
    ignoreRegisterRootWarning: true,
  });
  console.log("Bundled:", bundlePath);

  try {
    const composition = await selectComposition({
      serveUrl: bundlePath,
      id: "SwarmCodeCinematic",
      inputProps: {},
    });
    console.log("Composition:", composition.id, composition.width, "x", composition.height);

    console.log("Rendering...");
    await renderMedia({
      serveUrl: bundlePath,
      composition,
      outputLocation: "out/swarm-code-cinematic.mp4",
      inputProps: {},
      onProgress: ({ progress }) => {
        process.stdout.write(`\rProgress: ${(progress * 100).toFixed(1)}%`);
      },
      concurrency: 4,
    });
    console.log("\nDone!");
  } catch (err) {
    console.error("Error:", err.message);
  }
}

main();
