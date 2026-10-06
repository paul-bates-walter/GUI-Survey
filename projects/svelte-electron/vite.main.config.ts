import { defineConfig } from "vite";

export default defineConfig({
  build: {
    sourcemap: true,
    outDir: ".vite/build",
    emptyOutDir: false,
    target: "node20",
    lib: {
      entry: "src/main.ts",
      formats: ["es"],
      fileName: () => "main.js",
    },
    rollupOptions: {
      external: ["electron", /^node:/],
    },
  },
});
