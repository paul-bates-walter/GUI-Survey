import { contextBridge, ipcRenderer } from "electron";

export type TextEntry = [string, string];

export type LoadPngResult =
  | { canceled: true }
  | {
      canceled: false;
      dataUrl: string;
      filePath: string;
      entries: TextEntry[];
    };

export type SavePngResult =
  | { canceled: true }
  | { canceled: false; filePath: string };

const api = {
  loadPng: () => ipcRenderer.invoke("png:load") as Promise<LoadPngResult>,
  savePng: (dataUrl: string, entries: TextEntry[]) =>
    ipcRenderer.invoke("png:save", dataUrl, entries) as Promise<SavePngResult>,
};

contextBridge.exposeInMainWorld("guiSurvey", api);

export type GuiSurveyApi = typeof api;
