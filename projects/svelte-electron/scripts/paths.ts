import path from "node:path";

export type Segment =
  | "package.json"
  | "vite.main.config.ts"
  | "vite.preload.config.ts"
  | "vite.renderer.config.ts"
  | "node_modules/.bin/vite"
  | "node_modules/.bin/electron"
  | "node_modules/electron/dist"
  | "node_modules/electron/dist/electron"
  | "node_modules/electron/install.js"
  | "scripts/build.ts"
  | ".vite"
  | ".vite/build"
  | ".vite/build/main.js"
  | ".vite/build/preload.cjs"
  | ".vite/renderer"
  | "build";

export const rootDir = path.resolve(import.meta.dirname, "..");

export function Path(segment: Segment): string {
  return path.join(rootDir, ...segment.split("/"));
}
