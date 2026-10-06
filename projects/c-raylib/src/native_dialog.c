#define _POSIX_C_SOURCE 200809L

#include "native_dialog.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <commdlg.h>

static bool run_dialog(char *buffer, size_t buffer_size, bool save) {
    OPENFILENAMEA dialog = {0};
    buffer[0] = '\0';
    dialog.lStructSize = sizeof(dialog);
    dialog.lpstrFile = buffer;
    dialog.nMaxFile = (DWORD)buffer_size;
    dialog.lpstrFilter = "PNG images\0*.png\0All files\0*.*\0";
    dialog.nFilterIndex = 1;
    dialog.lpstrDefExt = "png";
    dialog.Flags = OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR;

    if (save) {
        dialog.Flags |= OFN_OVERWRITEPROMPT;
        return GetSaveFileNameA(&dialog) == TRUE;
    }

    dialog.Flags |= OFN_FILEMUSTEXIST;
    return GetOpenFileNameA(&dialog) == TRUE;
}

bool dialog_open_png(char *buffer, size_t buffer_size) {
    return run_dialog(buffer, buffer_size, false);
}

bool dialog_save_png(char *buffer, size_t buffer_size) {
    return run_dialog(buffer, buffer_size, true);
}

#else
static void trim_newline(char *value) {
    size_t length = strlen(value);
    while (length > 0 && (value[length - 1] == '\n' || value[length - 1] == '\r')) {
        value[--length] = '\0';
    }
}

static bool command_exists(const char *name) {
    char command[128];
    snprintf(command, sizeof(command), "command -v %s >/dev/null 2>&1", name);
    return system(command) == 0;
}

static bool read_command(const char *command, char *buffer, size_t buffer_size) {
    FILE *pipe = popen(command, "r");
    if (pipe == NULL) {
        return false;
    }

    bool ok = fgets(buffer, (int)buffer_size, pipe) != NULL;
    int status = pclose(pipe);
    if (!ok || status != 0) {
        buffer[0] = '\0';
        return false;
    }

    trim_newline(buffer);
    return buffer[0] != '\0';
}

static bool run_dialog(char *buffer, size_t buffer_size, bool save) {
    buffer[0] = '\0';

#if defined(__APPLE__)
    const char *open_script =
        "osascript -e 'POSIX path of (choose file of type {\"png\", \"public.png\"})'";
    const char *save_script =
        "osascript -e 'POSIX path of (choose file name with prompt \"Save PNG\" default name \"output.png\")'";
    return read_command(save ? save_script : open_script, buffer, buffer_size);
#else
    if (command_exists("zenity")) {
        const char *open_command =
            "zenity --file-selection --title='Open PNG' --file-filter='PNG images | *.png'";
        const char *save_command =
            "zenity --file-selection --save --confirm-overwrite --title='Save PNG' "
            "--filename='output.png' --file-filter='PNG images | *.png'";
        return read_command(save ? save_command : open_command, buffer, buffer_size);
    }

    if (command_exists("kdialog")) {
        const char *open_command =
            "kdialog --getopenfilename . 'image/png application/octet-stream'";
        const char *save_command =
            "kdialog --getsavefilename output.png 'image/png application/octet-stream'";
        return read_command(save ? save_command : open_command, buffer, buffer_size);
    }

    return false;
#endif
}

bool dialog_open_png(char *buffer, size_t buffer_size) {
    return run_dialog(buffer, buffer_size, false);
}

bool dialog_save_png(char *buffer, size_t buffer_size) {
    return run_dialog(buffer, buffer_size, true);
}
#endif
