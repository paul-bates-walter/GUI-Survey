import type { GuiSurveyApi } from "./preload";

declare global {
  interface Window {
    guiSurvey: GuiSurveyApi;
  }
}
