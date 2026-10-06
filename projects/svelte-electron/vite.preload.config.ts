import { defineConfig } from "vite";

export default defineConfig({
  build: {
    sourcemap: true,
    outDir: ".vite/build",
    emptyOutDir: false,
    target: "node20",
    lib: {
      entry: "src/preload.ts",
      formats: ["cjs"],
      fileName: () => "preload.cjs",
    },
    rollupOptions: {
      external: ["electron", /^node:/],
    },
  },
});
