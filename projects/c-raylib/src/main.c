#include "native_dialog.h"
#include "png_text.h"

#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

#include "raylib.h"

#define CANVAS_W 1024
#define CANVAS_H 720
#define TOOLBAR_H 64
#define STATUS_H 28
#define PANEL_W 320
#define PANEL_MARGIN 8
#define WINDOW_W (CANVAS_W + PANEL_W + PANEL_MARGIN * 2)
#define WINDOW_H 860
#define MAX_META 16

typedef enum {
    TOOL_PATH,
    TOOL_RECTANGLE,
    TOOL_CIRCLE,
} Tool;

typedef struct {
    Rectangle bounds;
    const char *label;
} Button;

typedef struct {
    Rectangle bounds;
    Color color;
    const char *label;
} ColorSwatch;

static Vector2 canvas_mouse(Vector2 mouse) {
    return (Vector2){mouse.x, mouse.y - TOOLBAR_H};
}

static bool in_canvas(Vector2 mouse, Image canvas) {
    return mouse.x >= 0 && mouse.x < canvas.width &&
           mouse.y >= TOOLBAR_H && mouse.y < TOOLBAR_H + canvas.height;
}

static Rectangle normalized_rect(Vector2 a, Vector2 b) {
    return (Rectangle){
        fminf(a.x, b.x),
        fminf(a.y, b.y),
        fabsf(b.x - a.x),
        fabsf(b.y - a.y),
    };
}

static bool same_color(Color a, Color b) {
    return a.r == b.r && a.g == b.g && a.b == b.b && a.a == b.a;
}

static Button make_button(float x, float width, const char *label) {
    return (Button){.bounds = {x, 14, width, 36}, .label = label};
}

static bool draw_button(Button button, bool active) {
    bool hover = CheckCollisionPointRec(GetMousePosition(), button.bounds);
    Color fill = active ? (Color){31, 111, 235, 255} : hover ? (Color){224, 231, 241, 255}
                                                           : (Color){245, 247, 250, 255};
    Color text = active ? WHITE : (Color){22, 27, 34, 255};
    DrawRectangleRec(button.bounds, fill);
    DrawRectangleLinesEx(button.bounds, 1, (Color){190, 198, 210, 255});
    DrawText(button.label, (int)button.bounds.x + 14, (int)button.bounds.y + 10, 16, text);
    return hover;
}

static bool clicked(Button button) {
    return CheckCollisionPointRec(GetMousePosition(), button.bounds) &&
           IsMouseButtonPressed(MOUSE_BUTTON_LEFT);
}

static bool clicked_rect(Rectangle bounds) {
    return CheckCollisionPointRec(GetMousePosition(), bounds) &&
           IsMouseButtonPressed(MOUSE_BUTTON_LEFT);
}

static void draw_color_swatch(ColorSwatch swatch, Color active_color) {
    bool active = same_color(swatch.color, active_color);
    bool hover = CheckCollisionPointRec(GetMousePosition(), swatch.bounds);
    DrawRectangleRec(swatch.bounds, swatch.color);
    DrawRectangleLinesEx(swatch.bounds, active ? 3 : hover ? 2 : 1,
                         active ? (Color){31, 111, 235, 255}
                                : (Color){100, 111, 126, 255});
    DrawText(swatch.label, (int)swatch.bounds.x + 7, (int)swatch.bounds.y + 5, 12,
             swatch.color.r + swatch.color.g + swatch.color.b < 180 ? WHITE : BLACK);
}

static void prepare_canvas(Image *canvas) {
    ImageFormat(canvas, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8);
}

static void sync_texture(Texture2D *texture, Image canvas) {
    if (texture->id != 0 && texture->width == canvas.width && texture->height == canvas.height) {
        UpdateTexture(*texture, canvas.data);
        return;
    }

    if (texture->id != 0) {
        UnloadTexture(*texture);
    }
    *texture = LoadTextureFromImage(canvas);
}

static void new_canvas(Image *canvas, Texture2D *texture, int width, int height) {
    UnloadImage(*canvas);
    *canvas = GenImageColor(width, height, WHITE);
    prepare_canvas(canvas);
    sync_texture(texture, *canvas);
}

static bool has_png_extension(const char *path) {
    size_t length = strlen(path);
    if (length < 4) {
        return false;
    }

    const char *extension = path + length - 4;
    return extension[0] == '.' &&
           tolower((unsigned char)extension[1]) == 'p' &&
           tolower((unsigned char)extension[2]) == 'n' &&
           tolower((unsigned char)extension[3]) == 'g';
}

static bool ensure_png_extension(char *path, size_t path_size) {
    if (has_png_extension(path)) {
        return true;
    }

    size_t length = strlen(path);
    if (length + 4 >= path_size) {
        return false;
    }

    memcpy(path + length, ".png", 5);
    return true;
}

static void set_path_status(char *status, size_t status_size, const char *prefix, const char *path) {
    if (status_size == 0) {
        return;
    }

    status[0] = '\0';
    size_t prefix_length = strlen(prefix);
    if (prefix_length >= status_size) {
        memcpy(status, prefix, status_size - 1);
        status[status_size - 1] = '\0';
        return;
    }

    memcpy(status, prefix, prefix_length);
    size_t used = prefix_length;
    size_t available = status_size - used - 1;
    size_t path_length = strlen(path);

    if (path_length > available && available > 3) {
        memcpy(status + used, "...", 3);
        used += 3;
        available -= 3;
        path += path_length - available;
        path_length = available;
    } else if (path_length > available) {
        path_length = available;
    }

    memcpy(status + used, path, path_length);
    status[used + path_length] = '\0';
}

static void load_png(Image *canvas, Texture2D *texture, PngTextEntry *meta, int *meta_count,
                     char *status, size_t status_size) {
    char path[4096];
    if (!dialog_open_png(path, sizeof(path))) {
        snprintf(status, status_size, "Open canceled or no file dialog helper is available.");
        return;
    }

    Image loaded = LoadImage(path);
    if (loaded.data == NULL) {
        set_path_status(status, status_size, "Could not load PNG: ", path);
        return;
    }

    prepare_canvas(&loaded);
    UnloadImage(*canvas);
    *canvas = loaded;
    sync_texture(texture, *canvas);
    *meta_count = png_text_read(path, meta, MAX_META);
    set_path_status(status, status_size, "Opened ", path);
}

static void save_png(Image canvas, const PngTextEntry *meta, int meta_count,
                     char *status, size_t status_size) {
    char path[4096];
    if (!dialog_save_png(path, sizeof(path))) {
        snprintf(status, status_size, "Save canceled or no file dialog helper is available.");
        return;
    }

    if (!ensure_png_extension(path, sizeof(path))) {
        snprintf(status, status_size, "Could not save PNG: file path is too long.");
        return;
    }

    if (!ExportImage(canvas, path)) {
        set_path_status(status, status_size, "Could not save PNG: ", path);
        return;
    }

    if (png_text_write(path, meta, meta_count)) {
        set_path_status(status, status_size, "Saved ", path);
    } else {
        set_path_status(status, status_size, "Saved pixels, but not metadata: ", path);
    }
}

static Rectangle meta_key_box(int panel_x, int index) {
    return (Rectangle){(float)panel_x + 8, TOOLBAR_H + 48 + (float)index * 36, 92, 30};
}

static Rectangle meta_value_box(int panel_x, int index) {
    return (Rectangle){(float)panel_x + 104, TOOLBAR_H + 48 + (float)index * 36, 164, 30};
}

static Rectangle meta_del_box(int panel_x, int index) {
    return (Rectangle){(float)panel_x + 274, TOOLBAR_H + 48 + (float)index * 36, 32, 30};
}

static void draw_meta_field(Rectangle box, const char *text, bool focused) {
    DrawRectangleRec(box, WHITE);
    DrawRectangleLinesEx(box, focused ? 2 : 1,
                         focused ? (Color){31, 111, 235, 255} : (Color){160, 168, 180, 255});
    const char *shown = text;
    while (*shown != '\0' && MeasureText(shown, 14) > (int)box.width - 14) {
        shown++;
    }
    DrawText(shown, (int)box.x + 6, (int)box.y + 8, 14, (Color){22, 27, 34, 255});
    if (focused) {
        DrawText("_", (int)box.x + 7 + MeasureText(shown, 14), (int)box.y + 8, 14,
                 (Color){31, 111, 235, 255});
    }
}

static void clear_canvas(Image *canvas, Texture2D *texture, char *status, size_t status_size) {
    ImageDrawRectangle(canvas, 0, 0, canvas->width, canvas->height, WHITE);
    sync_texture(texture, *canvas);
    snprintf(status, status_size, "Cleared canvas.");
}

int main(void) {
    SetConfigFlags(FLAG_WINDOW_RESIZABLE | FLAG_VSYNC_HINT);
    InitWindow(WINDOW_W, WINDOW_H, "PNG Editor - raylib + C");
    SetTargetFPS(60);

    SetExitKey(KEY_NULL);

    Image canvas = GenImageColor(CANVAS_W, CANVAS_H, WHITE);
    prepare_canvas(&canvas);
    Texture2D texture = LoadTextureFromImage(canvas);
    Tool tool = TOOL_PATH;
    Color color = (Color){31, 111, 235, 255};
    int radius = 8;
    bool drawing_path = false;
    bool has_anchor = false;
    Vector2 anchor = {0};
    Vector2 previous = {0};
    char status[512] = "Ready.";
    PngTextEntry meta[MAX_META] = {0};
    int meta_count = 0;
    int meta_focus = -1;
    int meta_focus_col = 0;
    int panel_x = CANVAS_W + PANEL_MARGIN;

    while (!WindowShouldClose()) {
        Button path_button = make_button(16, 82, "Path");
        Button rect_button = make_button(106, 104, "Rectangle");
        Button circle_button = make_button(218, 82, "Circle");
        ColorSwatch red_swatch = {{326, 20, 24, 24}, RED, "R"};
        ColorSwatch green_swatch = {{358, 20, 24, 24}, (Color){0, 128, 96, 255}, "G"};
        ColorSwatch blue_swatch = {{390, 20, 24, 24}, (Color){31, 111, 235, 255}, "B"};
        ColorSwatch black_swatch = {{422, 20, 24, 24}, BLACK, "K"};
        Button radius_down_button = make_button(486, 36, "-");
        Button radius_up_button = make_button(568, 36, "+");
        Button open_button = make_button(640, 82, "Open");
        Button save_button = make_button(730, 82, "Save");
        Button clear_button = make_button(820, 82, "Clear");
        Button new_button = make_button(910, 82, "New");
        Button meta_add_button = {{(float)panel_x + PANEL_W - 72, TOOLBAR_H + 8, 60, 30}, "Add"};

        if (clicked(path_button)) {
            tool = TOOL_PATH;
            has_anchor = false;
            snprintf(status, sizeof(status), "Path mode.");
        }
        if (clicked(rect_button)) {
            tool = TOOL_RECTANGLE;
            has_anchor = false;
            snprintf(status, sizeof(status), "Rectangle mode.");
        }
        if (clicked(circle_button)) {
            tool = TOOL_CIRCLE;
            has_anchor = false;
            snprintf(status, sizeof(status), "Circle mode.");
        }
        if (clicked_rect(red_swatch.bounds)) color = red_swatch.color;
        if (clicked_rect(green_swatch.bounds)) color = green_swatch.color;
        if (clicked_rect(blue_swatch.bounds)) color = blue_swatch.color;
        if (clicked_rect(black_swatch.bounds)) color = black_swatch.color;
        if (clicked(radius_down_button) && radius > 1) radius--;
        if (clicked(radius_up_button) && radius < 40) radius++;

        if (IsMouseButtonPressed(MOUSE_BUTTON_LEFT)) {
            meta_focus = -1;
        }
        if (clicked(meta_add_button) && meta_count < MAX_META) {
            meta[meta_count].key[0] = '\0';
            meta[meta_count].value[0] = '\0';
            meta_focus = meta_count;
            meta_focus_col = 0;
            meta_count++;
        }
        for (int i = 0; i < meta_count; i++) {
            if (clicked_rect(meta_key_box(panel_x, i))) {
                meta_focus = i;
                meta_focus_col = 0;
            }
            if (clicked_rect(meta_value_box(panel_x, i))) {
                meta_focus = i;
                meta_focus_col = 1;
            }
        }
        int meta_remove = -1;
        for (int i = 0; i < meta_count; i++) {
            if (clicked_rect(meta_del_box(panel_x, i))) {
                meta_remove = i;
            }
        }
        if (meta_remove >= 0) {
            for (int i = meta_remove; i < meta_count - 1; i++) {
                meta[i] = meta[i + 1];
            }
            meta_count--;
            meta_focus = -1;
        }

        if (clicked(open_button)) {
            load_png(&canvas, &texture, meta, &meta_count, status, sizeof(status));
            has_anchor = false;
            meta_focus = -1;
        }
        if (clicked(save_button)) {
            save_png(canvas, meta, meta_count, status, sizeof(status));
        }
        if (clicked(clear_button)) {
            clear_canvas(&canvas, &texture, status, sizeof(status));
            has_anchor = false;
        }
        if (clicked(new_button)) {
            new_canvas(&canvas, &texture, CANVAS_W, CANVAS_H);
            has_anchor = false;
            snprintf(status, sizeof(status), "Created a blank canvas.");
        }

        bool editing = meta_focus >= 0;
        bool modifier = IsKeyDown(KEY_LEFT_CONTROL) || IsKeyDown(KEY_RIGHT_CONTROL) ||
                        IsKeyDown(KEY_LEFT_SUPER) || IsKeyDown(KEY_RIGHT_SUPER);
        if (modifier && IsKeyPressed(KEY_O)) {
            load_png(&canvas, &texture, meta, &meta_count, status, sizeof(status));
            has_anchor = false;
            meta_focus = -1;
        }
        if (modifier && IsKeyPressed(KEY_S)) {
            save_png(canvas, meta, meta_count, status, sizeof(status));
        }
        if (modifier && IsKeyPressed(KEY_N)) {
            new_canvas(&canvas, &texture, CANVAS_W, CANVAS_H);
            has_anchor = false;
            snprintf(status, sizeof(status), "Created a blank canvas.");
        }
        if (!editing && (IsKeyPressed(KEY_DELETE) || IsKeyPressed(KEY_BACKSPACE)) && !modifier) {
            clear_canvas(&canvas, &texture, status, sizeof(status));
            has_anchor = false;
        }
        if (IsKeyPressed(KEY_ESCAPE)) {
            if (editing) {
                meta_focus = -1;
            } else {
                has_anchor = false;
                drawing_path = false;
                snprintf(status, sizeof(status), "Canceled pending shape.");
            }
        }
        if (!editing && IsKeyPressed(KEY_ONE)) {
            tool = TOOL_PATH;
            has_anchor = false;
            snprintf(status, sizeof(status), "Path mode.");
        }
        if (!editing && IsKeyPressed(KEY_TWO)) {
            tool = TOOL_RECTANGLE;
            has_anchor = false;
            snprintf(status, sizeof(status), "Rectangle mode.");
        }
        if (!editing && IsKeyPressed(KEY_THREE)) {
            tool = TOOL_CIRCLE;
            has_anchor = false;
            snprintf(status, sizeof(status), "Circle mode.");
        }
        if (!editing && IsKeyPressed(KEY_LEFT_BRACKET) && radius > 1) radius--;
        if (!editing && IsKeyPressed(KEY_RIGHT_BRACKET) && radius < 40) radius++;
        if (!editing && IsKeyPressed(KEY_R)) color = RED;
        if (!editing && IsKeyPressed(KEY_G)) color = (Color){0, 128, 96, 255};
        if (!editing && IsKeyPressed(KEY_B)) color = (Color){31, 111, 235, 255};
        if (!editing && IsKeyPressed(KEY_K)) color = BLACK;

        if (meta_focus >= 0) {
            char *field = meta_focus_col == 0 ? meta[meta_focus].key : meta[meta_focus].value;
            size_t field_cap = meta_focus_col == 0 ? PNG_TEXT_KEY_MAX : PNG_TEXT_VALUE_MAX;
            int pressed;
            while ((pressed = GetCharPressed()) > 0) {
                size_t length = strlen(field);
                if (pressed >= 32 && pressed < 256 && length + 1 < field_cap) {
                    field[length] = (char)pressed;
                    field[length + 1] = '\0';
                }
            }
            if (IsKeyPressed(KEY_BACKSPACE) || IsKeyPressedRepeat(KEY_BACKSPACE)) {
                size_t length = strlen(field);
                if (length > 0) {
                    field[length - 1] = '\0';
                }
            }
            if (IsKeyPressed(KEY_TAB) || IsKeyPressed(KEY_ENTER)) {
                if (meta_focus_col == 0) {
                    meta_focus_col = 1;
                } else {
                    meta_focus = -1;
                }
            }
        }

        Vector2 mouse = GetMousePosition();
        if (!editing && in_canvas(mouse, canvas)) {
            Vector2 point = canvas_mouse(mouse);
            if (tool == TOOL_PATH) {
                if (IsMouseButtonPressed(MOUSE_BUTTON_LEFT)) {
                    drawing_path = true;
                    previous = point;
                    ImageDrawCircleV(&canvas, point, radius, color);
                    sync_texture(&texture, canvas);
                } else if (drawing_path && IsMouseButtonDown(MOUSE_BUTTON_LEFT)) {
                    ImageDrawLineEx(&canvas, previous, point, radius * 2, color);
                    previous = point;
                    sync_texture(&texture, canvas);
                }
            } else if (IsMouseButtonPressed(MOUSE_BUTTON_LEFT)) {
                if (!has_anchor) {
                    anchor = point;
                    has_anchor = true;
                    snprintf(status, sizeof(status), "Pick the second point.");
                } else {
                    if (tool == TOOL_CIRCLE) {
                        float distance = hypotf(point.x - anchor.x, point.y - anchor.y);
                        ImageDrawCircleLines(&canvas, (int)anchor.x, (int)anchor.y,
                                             (int)distance, color);
                    } else {
                        Rectangle rect = normalized_rect(anchor, point);
                        ImageDrawRectangleLines(&canvas, rect, radius, color);
                    }
                    sync_texture(&texture, canvas);
                    has_anchor = false;
                    snprintf(status, sizeof(status), "Ready.");
                }
            }
        }

        if (IsMouseButtonReleased(MOUSE_BUTTON_LEFT)) {
            drawing_path = false;
        }

        BeginDrawing();
        ClearBackground((Color){236, 240, 245, 255});
        DrawRectangle(0, 0, GetScreenWidth(), TOOLBAR_H, (Color){255, 255, 255, 255});
        draw_button(path_button, tool == TOOL_PATH);
        draw_button(rect_button, tool == TOOL_RECTANGLE);
        draw_button(circle_button, tool == TOOL_CIRCLE);
        draw_color_swatch(red_swatch, color);
        draw_color_swatch(green_swatch, color);
        draw_color_swatch(blue_swatch, color);
        draw_color_swatch(black_swatch, color);
        draw_button(radius_down_button, false);
        DrawText(TextFormat("%2d px", radius), 526, 24, 16, (Color){31, 35, 40, 255});
        draw_button(radius_up_button, false);
        draw_button(open_button, false);
        draw_button(save_button, false);
        draw_button(clear_button, false);
        draw_button(new_button, false);

        DrawTexture(texture, 0, TOOLBAR_H, WHITE);
        DrawRectangleLines(0, TOOLBAR_H, canvas.width, canvas.height, (Color){145, 152, 161, 255});

        if (has_anchor && in_canvas(mouse, canvas)) {
            Vector2 point = canvas_mouse(mouse);
            if (tool == TOOL_CIRCLE) {
                DrawCircleLines((int)anchor.x, (int)anchor.y + TOOLBAR_H,
                                hypotf(point.x - anchor.x, point.y - anchor.y), color);
            } else if (tool == TOOL_RECTANGLE) {
                Rectangle preview = normalized_rect((Vector2){anchor.x, anchor.y + TOOLBAR_H},
                                                    (Vector2){point.x, point.y + TOOLBAR_H});
                DrawRectangleLinesEx(preview, 2, color);
            }
        }

        DrawRectangle(panel_x, TOOLBAR_H, PANEL_W,
                      GetScreenHeight() - TOOLBAR_H - STATUS_H, WHITE);
        DrawRectangleLines(panel_x, TOOLBAR_H, PANEL_W,
                           GetScreenHeight() - TOOLBAR_H - STATUS_H,
                           (Color){190, 198, 210, 255});
        DrawText("tEXt metadata", panel_x + 10, TOOLBAR_H + 16, 16, (Color){22, 27, 34, 255});
        draw_button(meta_add_button, false);
        for (int i = 0; i < meta_count; i++) {
            draw_meta_field(meta_key_box(panel_x, i), meta[i].key,
                            meta_focus == i && meta_focus_col == 0);
            draw_meta_field(meta_value_box(panel_x, i), meta[i].value,
                            meta_focus == i && meta_focus_col == 1);
            Button del_button = {meta_del_box(panel_x, i), "x"};
            draw_button(del_button, false);
        }

        DrawRectangle(0, GetScreenHeight() - STATUS_H, GetScreenWidth(), STATUS_H,
                      (Color){255, 255, 255, 255});
        DrawText(status, 12, GetScreenHeight() - 20, 14, (Color){31, 35, 40, 255});
        EndDrawing();
    }

    UnloadTexture(texture);
    UnloadImage(canvas);
    CloseWindow();
    return 0;
}
