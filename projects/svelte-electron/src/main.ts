import path from "node:path";
import { app, BrowserWindow, dialog, ipcMain } from "electron";
import { readFile, writeFile } from "node:fs/promises";
import { readTextEntries, writeTextEntries, type TextEntry } from "./pngtext";

const devServerUrl = process.env.VITE_DEV_SERVER_URL;

function createWindow() {
  const mainWindow = new BrowserWindow({
    width: 1120,
    height: 760,
    minWidth: 820,
    minHeight: 560,
    title: "GUI Survey",
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      preload: path.join(import.meta.dirname, "preload.cjs"),
    },
  });

  if (devServerUrl) {
    void mainWindow.loadURL(devServerUrl);
  } else {
    void mainWindow.loadFile(
      path.join(import.meta.dirname, "../renderer/index.html"),
    );
  }
}

ipcMain.handle(
  "png:save",
  async (_event, dataUrl: string, entries: TextEntry[]) => {
    const result = await dialog.showSaveDialog({
      title: "Save PNG",
      defaultPath: "drawing.png",
      filters: [{ name: "PNG images", extensions: ["png"] }],
    });

    if (result.canceled || !result.filePath) {
      return { canceled: true };
    }

    const payload = dataUrl.replace(/^data:image\/png;base64,/, "");
    const plain = Buffer.from(payload, "base64");
    const combined = writeTextEntries(plain, entries);
    if (combined === null) {
      throw new Error("canvas produced invalid png data");
    }
    await writeFile(result.filePath, combined);

    return { canceled: false, filePath: result.filePath };
  },
);

ipcMain.handle("png:load", async () => {
  const result = await dialog.showOpenDialog({
    title: "Open PNG",
    properties: ["openFile"],
    filters: [{ name: "PNG images", extensions: ["png"] }],
  });

  if (result.canceled || result.filePaths.length === 0) {
    return { canceled: true };
  }

  const [filePath] = result.filePaths;
  const image = await readFile(filePath);

  return {
    canceled: false,
    dataUrl: `data:image/png;base64,${image.toString("base64")}`,
    filePath,
    entries: readTextEntries(image),
  };
});

app.whenReady().then(createWindow);

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});

app.on("activate", () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    createWindow();
  }
});
