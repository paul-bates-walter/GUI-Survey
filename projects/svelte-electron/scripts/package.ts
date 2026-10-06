import { spawnSync } from "node:child_process";
import {
  chmodSync,
  cpSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  renameSync,
  statSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import os from "node:os";
import path from "node:path";
import { Path, rootDir } from "./paths.ts";

const appName = "png-editor-electron";

const archByNodeArch: Record<string, { arch: string; debArch: string }> = {
  x64: { arch: "x86_64", debArch: "amd64" },
  arm64: { arch: "arm64", debArch: "arm64" },
};

main();

function run(command: string, args: string[]): void {
  const result = spawnSync(command, args, { cwd: rootDir, stdio: "inherit" });
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

function normalizeModes(dir: string): void {
  chmodSync(dir, 0o755);
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      normalizeModes(full);
    } else if (entry.isFile()) {
      const executable = (statSync(full).mode & 0o100) !== 0;
      chmodSync(full, executable ? 0o755 : 0o644);
    }
  }
}

function main(): void {
  if (process.platform !== "linux") {
    console.error("❌ Error: packaging implemented for Linux only");
    process.exit(1);
  }
  const archInfo = archByNodeArch[process.arch];
  if (archInfo === undefined) {
    console.error(`❌ Error: unsupported cpu arch ${process.arch}`);
    process.exit(1);
  }

  run(process.execPath, [Path("scripts/build.ts")]);

  const version = JSON.parse(readFileSync(Path("package.json"), "utf8"))
    .version as string;

  const stage = mkdtempSync(path.join(os.tmpdir(), `${appName}-`));
  try {
    const appDir = path.join(stage, "usr", "lib", appName);
    const binDir = path.join(stage, "usr", "bin");
    const applicationsDir = path.join(stage, "usr", "share", "applications");
    const debianDir = path.join(stage, "DEBIAN");
    for (const dir of [appDir, binDir, applicationsDir, debianDir]) {
      mkdirSync(dir, { recursive: true });
    }

    cpSync(Path("node_modules/electron/dist"), appDir, { recursive: true });
    rmSync(path.join(appDir, "resources", "default_app.asar"));
    renameSync(path.join(appDir, "electron"), path.join(appDir, appName));

    const resourcesApp = path.join(appDir, "resources", "app");
    mkdirSync(path.join(resourcesApp, ".vite"), { recursive: true });
    cpSync(Path(".vite/build"), path.join(resourcesApp, ".vite", "build"), {
      recursive: true,
    });
    cpSync(Path(".vite/renderer"), path.join(resourcesApp, ".vite", "renderer"), {
      recursive: true,
    });
    writeFileSync(
      path.join(resourcesApp, "package.json"),
      JSON.stringify(
        { name: appName, version, type: "module", main: ".vite/build/main.js" },
        null,
        2,
      ) + "\n",
    );

    symlinkSync(`/usr/lib/${appName}/${appName}`, path.join(binDir, appName));
    writeFileSync(
      path.join(applicationsDir, `${appName}.desktop`),
      [
        "[Desktop Entry]",
        "Type=Application",
        "Name=PNG Editor (Electron)",
        `Exec=${appName}`,
        "Categories=Graphics;",
        "Terminal=false",
        "",
      ].join("\n"),
    );
    writeFileSync(
      path.join(debianDir, "control"),
      [
        `Package: ${appName}`,
        `Version: ${version}`,
        "Section: graphics",
        "Priority: optional",
        `Architecture: ${archInfo.debArch}`,
        "Maintainer: gui_survey <noreply@local>",
        "Depends: libgtk-3-0, libnotify4, libnss3, libxss1, libxtst6, xdg-utils, libatspi2.0-0, libuuid1, libsecret-1-0, libasound2",
        "Description: Desktop PNG editor built with Electron, Vite, and Svelte.",
        "",
      ].join("\n"),
    );

    normalizeModes(stage);
    chmodSync(path.join(appDir, "chrome-sandbox"), 0o4755);

    mkdirSync(Path("build"), { recursive: true });
    const dest = path.join(Path("build"), `linux-${appName}-${archInfo.arch}.deb`);
    run("dpkg-deb", ["--build", "--root-owner-group", stage, dest]);
    console.log(dest);
  } finally {
    rmSync(stage, { recursive: true, force: true });
  }
}
