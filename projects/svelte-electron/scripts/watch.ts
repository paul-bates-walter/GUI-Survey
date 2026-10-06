import { spawn, spawnSync, type ChildProcess } from "node:child_process";
import { statSync } from "node:fs";
import { Path, rootDir } from "./paths.ts";

const devPort = process.env.DEV_PORT ?? "5173";

await main();

async function main(): Promise<void> {
  runSync(process.execPath, [Path("scripts/build.ts")]);

  const watchers: ChildProcess[] = [
    spawn(
      Path("node_modules/.bin/vite"),
      [
        "dev",
        "--config",
        Path("vite.renderer.config.ts"),
        "--port",
        devPort,
        "--strictPort",
      ],
      { cwd: rootDir, stdio: "inherit" },
    ),
    spawn(
      Path("node_modules/.bin/vite"),
      ["build", "--watch", "--config", Path("vite.main.config.ts")],
      { cwd: rootDir, stdio: "inherit" },
    ),
    spawn(
      Path("node_modules/.bin/vite"),
      ["build", "--watch", "--config", Path("vite.preload.config.ts")],
      { cwd: rootDir, stdio: "inherit" },
    ),
  ];
  let currentElectron: ChildProcess | undefined;
  const stopWatchers = (): void => {
    for (const watcher of watchers) {
      watcher.kill();
    }
  };
  const stopAll = (signal: NodeJS.Signals): void => {
    stopWatchers();
    if (currentElectron !== undefined) {
      currentElectron.kill();
    }
    process.exit(signal === "SIGINT" ? 130 : 143);
  };
  process.on("SIGINT", () => stopAll("SIGINT"));
  process.on("SIGTERM", () => stopAll("SIGTERM"));

  while (true) {
    const electron = spawn(Path("node_modules/.bin/electron"), ["."], {
      cwd: rootDir,
      stdio: "inherit",
      env: { ...process.env, VITE_DEV_SERVER_URL: `http://localhost:${devPort}` },
    });
    currentElectron = electron;
    let exited = false;
    electron.on("exit", () => {
      exited = true;
    });
    const before = stamp();
    let restart = false;
    while (!exited) {
      await sleep(1000);
      if (!restart && stamp() !== before) {
        restart = true;
        electron.kill();
      }
    }
    if (!restart) {
      break;
    }
  }
  stopWatchers();
}

function runSync(command: string, args: string[]): void {
  const result = spawnSync(command, args, { cwd: rootDir, stdio: "inherit" });
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

function stamp(): string {
  return [Path(".vite/build/main.js"), Path(".vite/build/preload.cjs")]
    .map((file) => {
      try {
        return String(statSync(file).mtimeMs);
      } catch {
        return "missing";
      }
    })
    .join(" ");
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
