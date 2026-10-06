import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { Path, rootDir } from "./paths.ts";

// just calls vite?
// produces .map, .js, .css, .html
if (!existsSync(Path("node_modules/electron/dist/electron"))) {
  run(process.execPath, [Path("node_modules/electron/install.js")]);
}
run(Path("node_modules/.bin/vite"), ["build", "--config", Path("vite.main.config.ts")]);
run(Path("node_modules/.bin/vite"), ["build", "--config", Path("vite.preload.config.ts")]);
run(Path("node_modules/.bin/vite"), ["build", "--config", Path("vite.renderer.config.ts")]);

function run(command: string, args: string[]): void {
  const result = spawnSync(command, args, { cwd: rootDir, stdio: "inherit" });
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}
