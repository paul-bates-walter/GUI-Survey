const std = @import("std");
const png_text = @import("png_text.zig");

const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3_image/SDL_image.h");
});

const PanelW = 320;
const PanelMargin = 8;
const WindowH = 860;
const ToolbarH = 64;
const StatusH = 28;
const CanvasW = 1024;
const CanvasH = 720;
const PanelX = CanvasW + PanelMargin;
const WindowW = CanvasW + PanelW + PanelMargin * 2;
const MaxMeta = 16;

const Tool = enum { path, rectangle, circle };
const Point = struct { x: f32, y: f32 };
const Button = struct {
    rect: c.SDL_FRect,
    label: [:0]const u8,
};
const PendingDialog = enum { none, open, save };
const png_filters = [_]c.SDL_DialogFileFilter{
    .{ .name = "PNG images", .pattern = "png" },
};

const State = struct {
    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    canvas: *c.SDL_Texture,
    tool: Tool = .path,
    color: c.SDL_Color = .{ .r = 31, .g = 111, .b = 235, .a = 255 },
    radius: f32 = 8,
    drawing_path: bool = false,
    has_anchor: bool = false,
    anchor: Point = .{ .x = 0, .y = 0 },
    previous: Point = .{ .x = 0, .y = 0 },
    dialog_mutex: std.Thread.Mutex = .{},
    pending_dialog: PendingDialog = .none,
    dialog_complete: bool = false,
    pending_path: [4096]u8 = undefined,
    pending_path_len: usize = 0,
    status: [512]u8 = undefined,
    status_len: usize = 0,
    meta: [MaxMeta]png_text.Entry = undefined,
    meta_count: usize = 0,
    meta_focus: i32 = -1,
    meta_focus_col: u1 = 0,

    fn setStatus(self: *State, comptime fmt: []const u8, args: anytype) void {
        const text = std.fmt.bufPrintZ(&self.status, fmt, args) catch "Status message too long";
        self.status_len = text.len;
    }

    fn editing(self: *const State) bool {
        return self.meta_focus >= 0;
    }
};

fn metaAddRect() c.SDL_FRect {
    return .{ .x = PanelX + PanelW - 72, .y = ToolbarH + 8, .w = 60, .h = 30 };
}

fn metaRowY(index: usize) f32 {
    return ToolbarH + 48 + @as(f32, @floatFromInt(index)) * 36;
}

fn metaKeyRect(index: usize) c.SDL_FRect {
    return .{ .x = PanelX + 8, .y = metaRowY(index), .w = 92, .h = 30 };
}

fn metaValueRect(index: usize) c.SDL_FRect {
    return .{ .x = PanelX + 104, .y = metaRowY(index), .w = 164, .h = 30 };
}

fn metaDelRect(index: usize) c.SDL_FRect {
    return .{ .x = PanelX + 274, .y = metaRowY(index), .w = 32, .h = 30 };
}

fn setTextInput(state: *State, enabled: bool) void {
    if (enabled) {
        _ = c.SDL_StartTextInput(state.window);
    } else {
        _ = c.SDL_StopTextInput(state.window);
    }
}

fn handlePanelClick(state: *State, x: f32, y: f32) void {
    const prev_focus = state.meta_focus;
    state.meta_focus = -1;

    if (pointInRect(x, y, metaAddRect())) {
        if (state.meta_count < state.meta.len) {
            state.meta[state.meta_count] = .{};
            state.meta_focus = @intCast(state.meta_count);
            state.meta_focus_col = 0;
            state.meta_count += 1;
        }
    } else {
        var index: usize = 0;
        while (index < state.meta_count) : (index += 1) {
            if (pointInRect(x, y, metaKeyRect(index))) {
                state.meta_focus = @intCast(index);
                state.meta_focus_col = 0;
            } else if (pointInRect(x, y, metaValueRect(index))) {
                state.meta_focus = @intCast(index);
                state.meta_focus_col = 1;
            } else if (pointInRect(x, y, metaDelRect(index))) {
                var move = index;
                while (move + 1 < state.meta_count) : (move += 1) {
                    state.meta[move] = state.meta[move + 1];
                }
                state.meta_count -= 1;
                state.meta_focus = -1;
                break;
            }
        }
    }

    if (state.meta_focus >= 0 and prev_focus < 0) setTextInput(state, true);
    if (state.meta_focus < 0 and prev_focus >= 0) setTextInput(state, false);
}

fn appendFocusedText(state: *State, text: []const u8) void {
    if (state.meta_focus < 0) return;
    const index: usize = @intCast(state.meta_focus);
    const entry = &state.meta[index];
    for (text) |byte| {
        if (byte < 32) continue;
        if (state.meta_focus_col == 0) {
            if (entry.key_len + 1 < png_text.KeyMax) {
                entry.key[entry.key_len] = byte;
                entry.key_len += 1;
            }
        } else {
            if (entry.value_len + 1 < png_text.ValueMax) {
                entry.value[entry.value_len] = byte;
                entry.value_len += 1;
            }
        }
    }
}

fn backspaceFocusedText(state: *State) void {
    if (state.meta_focus < 0) return;
    const index: usize = @intCast(state.meta_focus);
    const entry = &state.meta[index];
    if (state.meta_focus_col == 0) {
        if (entry.key_len > 0) entry.key_len -= 1;
    } else {
        if (entry.value_len > 0) entry.value_len -= 1;
    }
}

fn drawMetaField(renderer: *c.SDL_Renderer, rect: c.SDL_FRect, text: []const u8, focused: bool) void {
    setDrawColor(renderer, .{ .r = 255, .g = 255, .b = 255, .a = 255 });
    var fill = rect;
    _ = c.SDL_RenderFillRect(renderer, &fill);
    if (focused) {
        setDrawColor(renderer, .{ .r = 31, .g = 111, .b = 235, .a = 255 });
    } else {
        setDrawColor(renderer, .{ .r = 160, .g = 168, .b = 180, .a = 255 });
    }
    _ = c.SDL_RenderRect(renderer, &fill);

    const max_chars: usize = @intFromFloat((rect.w - 14) / 8);
    const shown = if (text.len > max_chars) text[text.len - max_chars ..] else text;
    var buffer: [64]u8 = undefined;
    const label = std.fmt.bufPrintZ(&buffer, "{s}", .{shown}) catch return;
    setDrawColor(renderer, .{ .r = 22, .g = 27, .b = 34, .a = 255 });
    _ = c.SDL_RenderDebugText(renderer, rect.x + 6, rect.y + 11, label.ptr);
    if (focused) {
        setDrawColor(renderer, .{ .r = 31, .g = 111, .b = 235, .a = 255 });
        _ = c.SDL_RenderDebugText(renderer, rect.x + 6 + @as(f32, @floatFromInt(shown.len * 8)), rect.y + 11, "_");
    }
}

fn sdlFail(comptime label: []const u8) !void {
    std.debug.print("{s}: {s}\n", .{ label, c.SDL_GetError() });
    return error.SdlFailure;
}

fn setDrawColor(renderer: *c.SDL_Renderer, color: c.SDL_Color) void {
    _ = c.SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);
}

fn withCanvasTarget(state: *State) void {
    _ = c.SDL_SetRenderTarget(state.renderer, state.canvas);
}

fn withWindowTarget(state: *State) void {
    _ = c.SDL_SetRenderTarget(state.renderer, null);
}

fn clearCanvas(state: *State) void {
    withCanvasTarget(state);
    setDrawColor(state.renderer, .{ .r = 255, .g = 255, .b = 255, .a = 255 });
    _ = c.SDL_RenderClear(state.renderer);
    withWindowTarget(state);
}

fn recreateCanvas(state: *State, width: i32, height: i32) !void {
    c.SDL_DestroyTexture(state.canvas);
    const texture = c.SDL_CreateTexture(
        state.renderer,
        c.SDL_PIXELFORMAT_RGBA32,
        c.SDL_TEXTUREACCESS_TARGET,
        width,
        height,
    ) orelse return sdlFail("SDL_CreateTexture");
    state.canvas = texture;
    clearCanvas(state);
}

fn fillCircle(renderer: *c.SDL_Renderer, center: Point, radius: f32) void {
    const min_x = @as(i32, @intFromFloat(center.x - radius));
    const max_x = @as(i32, @intFromFloat(center.x + radius));
    const min_y = @as(i32, @intFromFloat(center.y - radius));
    const max_y = @as(i32, @intFromFloat(center.y + radius));
    const r2 = radius * radius;
    var y = min_y;
    while (y <= max_y) : (y += 1) {
        var x = min_x;
        while (x <= max_x) : (x += 1) {
            const dx = @as(f32, @floatFromInt(x)) - center.x;
            const dy = @as(f32, @floatFromInt(y)) - center.y;
            if (dx * dx + dy * dy <= r2) {
                _ = c.SDL_RenderPoint(renderer, @floatFromInt(x), @floatFromInt(y));
            }
        }
    }
}

fn drawThickLine(renderer: *c.SDL_Renderer, a: Point, b: Point, radius: f32) void {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const distance = @sqrt(dx * dx + dy * dy);
    if (distance < 0.001) {
        fillCircle(renderer, a, radius);
        return;
    }

    const steps = @max(1, @as(i32, @intFromFloat(distance / @max(1.0, radius * 0.5))));
    var i: i32 = 0;
    while (i <= steps) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps));
        fillCircle(renderer, .{ .x = a.x + dx * t, .y = a.y + dy * t }, radius);
    }
}

fn strokeCircle(renderer: *c.SDL_Renderer, center: Point, edge: Point, radius: f32) void {
    const circle_radius = @sqrt((edge.x - center.x) * (edge.x - center.x) + (edge.y - center.y) * (edge.y - center.y));
    var previous = Point{ .x = center.x + circle_radius, .y = center.y };
    var i: i32 = 1;
    while (i <= 96) : (i += 1) {
        const angle = (@as(f32, @floatFromInt(i)) / 96.0) * std.math.tau;
        const next = Point{
            .x = center.x + @cos(angle) * circle_radius,
            .y = center.y + @sin(angle) * circle_radius,
        };
        drawThickLine(renderer, previous, next, radius);
        previous = next;
    }
}

fn strokeRectangle(renderer: *c.SDL_Renderer, a: Point, b: Point, radius: f32) void {
    const p1 = Point{ .x = a.x, .y = a.y };
    const p2 = Point{ .x = b.x, .y = a.y };
    const p3 = Point{ .x = b.x, .y = b.y };
    const p4 = Point{ .x = a.x, .y = b.y };
    drawThickLine(renderer, p1, p2, radius);
    drawThickLine(renderer, p2, p3, radius);
    drawThickLine(renderer, p3, p4, radius);
    drawThickLine(renderer, p4, p1, radius);
}

fn canvasPoint(x: f32, y: f32) Point {
    return .{ .x = x, .y = y - ToolbarH };
}

fn insideCanvas(x: f32, y: f32) bool {
    return x >= 0 and y >= ToolbarH and x < CanvasW and y < ToolbarH + CanvasH;
}

fn button(x: f32, label: [:0]const u8) Button {
    return .{ .rect = .{ .x = x, .y = 14, .w = 92, .h = 36 }, .label = label };
}

fn pointInRect(x: f32, y: f32, rect: c.SDL_FRect) bool {
    return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h;
}

fn drawButton(renderer: *c.SDL_Renderer, b: Button, active: bool) void {
    const fill = if (active)
        c.SDL_Color{ .r = 31, .g = 111, .b = 235, .a = 255 }
    else
        c.SDL_Color{ .r = 245, .g = 247, .b = 250, .a = 255 };
    setDrawColor(renderer, fill);
    _ = c.SDL_RenderFillRect(renderer, &b.rect);
    setDrawColor(renderer, .{ .r = 180, .g = 188, .b = 200, .a = 255 });
    _ = c.SDL_RenderRect(renderer, &b.rect);
    const text = if (active)
        c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 }
    else
        c.SDL_Color{ .r = 22, .g = 27, .b = 34, .a = 255 };
    setDrawColor(renderer, text);
    _ = c.SDL_RenderDebugText(renderer, b.rect.x + 12, b.rect.y + 11, b.label.ptr);
}

fn dialogCallback(userdata: ?*anyopaque, filelist: [*c]const [*c]const u8, _: c_int) callconv(.C) void {
    if (userdata == null) return;
    const state: *State = @ptrCast(@alignCast(userdata.?));
    state.dialog_mutex.lock();
    defer state.dialog_mutex.unlock();

    if (filelist == null or filelist[0] == null) {
        state.pending_path_len = 0;
        state.dialog_complete = true;
        return;
    }

    const selected = std.mem.span(filelist[0]);
    const len = @min(selected.len, state.pending_path.len - 1);
    @memcpy(state.pending_path[0..len], selected[0..len]);
    state.pending_path[len] = 0;
    state.pending_path_len = len;
    state.dialog_complete = true;
}

fn openDialog(state: *State) void {
    state.dialog_mutex.lock();
    state.pending_dialog = .open;
    state.dialog_complete = false;
    state.pending_path_len = 0;
    state.dialog_mutex.unlock();

    c.SDL_ShowOpenFileDialog(dialogCallback, state, state.window, &png_filters[0], @intCast(png_filters.len), null, false);
}

fn saveDialog(state: *State) void {
    state.dialog_mutex.lock();
    state.pending_dialog = .save;
    state.dialog_complete = false;
    state.pending_path_len = 0;
    state.dialog_mutex.unlock();

    c.SDL_ShowSaveFileDialog(dialogCallback, state, state.window, &png_filters[0], @intCast(png_filters.len), null);
}

fn loadPng(state: *State, path: [:0]const u8) !void {
    const surface = c.IMG_Load(path.ptr) orelse return sdlFail("IMG_Load");
    defer c.SDL_DestroySurface(surface);

    try recreateCanvas(state, surface.*.w, surface.*.h);
    const texture = c.SDL_CreateTextureFromSurface(state.renderer, surface) orelse return sdlFail("SDL_CreateTextureFromSurface");
    defer c.SDL_DestroyTexture(texture);

    withCanvasTarget(state);
    _ = c.SDL_RenderTexture(state.renderer, texture, null, null);
    withWindowTarget(state);
    state.meta_count = png_text.readFile(path, &state.meta);
    state.meta_focus = -1;
    state.setStatus("Opened {s}", .{path});
}

fn savePng(state: *State, path: [:0]const u8) !void {
    withCanvasTarget(state);
    const read = c.SDL_RenderReadPixels(state.renderer, null) orelse return sdlFail("SDL_RenderReadPixels");
    withWindowTarget(state);
    defer c.SDL_DestroySurface(read);

    if (!c.IMG_SavePNG(read, path.ptr)) return sdlFail("IMG_SavePNG");
    if (png_text.writeFile(path, state.meta[0..state.meta_count])) {
        state.setStatus("Saved {s}", .{path});
    } else {
        state.setStatus("Saved pixels, but not metadata: {s}", .{path});
    }
}

fn handleDialogResult(state: *State) void {
    var dialog: PendingDialog = .none;
    var path_buffer: [4096]u8 = undefined;
    var path_len: usize = 0;

    state.dialog_mutex.lock();
    if (state.pending_dialog != .none and state.dialog_complete) {
        dialog = state.pending_dialog;
        path_len = state.pending_path_len;
        if (path_len > 0) {
            @memcpy(path_buffer[0..path_len], state.pending_path[0..path_len]);
            path_buffer[path_len] = 0;
        }
        state.pending_dialog = .none;
        state.dialog_complete = false;
        state.pending_path_len = 0;
    }
    state.dialog_mutex.unlock();

    if (dialog == .none) return;
    if (path_len == 0) {
        state.setStatus("Dialog canceled.", .{});
        return;
    }

    const raw = path_buffer[0..path_len :0];
    switch (dialog) {
        .open => loadPng(state, raw) catch state.setStatus("Open failed: {s}", .{c.SDL_GetError()}),
        .save => savePng(state, raw) catch state.setStatus("Save failed: {s}", .{c.SDL_GetError()}),
        .none => {},
    }
}

pub fn main() !void {
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) return sdlFail("SDL_Init");
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow("PNG Editor - SDL + Zig", WindowW, WindowH, c.SDL_WINDOW_RESIZABLE) orelse return sdlFail("SDL_CreateWindow");
    defer c.SDL_DestroyWindow(window);

    const renderer = c.SDL_CreateRenderer(window, null) orelse return sdlFail("SDL_CreateRenderer");
    defer c.SDL_DestroyRenderer(renderer);

    const canvas = c.SDL_CreateTexture(renderer, c.SDL_PIXELFORMAT_RGBA32, c.SDL_TEXTUREACCESS_TARGET, CanvasW, CanvasH) orelse return sdlFail("SDL_CreateTexture");

    var state = State{ .window = window, .renderer = renderer, .canvas = canvas };
    state.setStatus("Ready.", .{});
    clearCanvas(&state);

    var running = true;
    while (running) {
        handleDialogResult(&state);

        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => running = false,
                c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                    const x = event.button.x;
                    const y = event.button.y;
                    const buttons = [_]Button{
                        button(16, "Path"), button(114, "Rectangle"), button(212, "Circle"),
                        button(624, "Open"), button(722, "Save"), button(820, "Clear"), button(918, "New"),
                    };

                    handlePanelClick(&state, x, y);

                    if (pointInRect(x, y, buttons[0].rect)) state.tool = .path else
                    if (pointInRect(x, y, buttons[1].rect)) state.tool = .rectangle else
                    if (pointInRect(x, y, buttons[2].rect)) state.tool = .circle else
                    if (pointInRect(x, y, buttons[3].rect)) openDialog(&state) else
                    if (pointInRect(x, y, buttons[4].rect)) saveDialog(&state) else
                    if (pointInRect(x, y, buttons[5].rect)) {
                        clearCanvas(&state);
                        state.setStatus("Cleared canvas.", .{});
                    } else if (pointInRect(x, y, buttons[6].rect)) {
                        try recreateCanvas(&state, CanvasW, CanvasH);
                        state.setStatus("Created a blank canvas.", .{});
                    } else if (insideCanvas(x, y)) {
                        const point = canvasPoint(x, y);
                        withCanvasTarget(&state);
                        setDrawColor(state.renderer, state.color);
                        if (state.tool == .path) {
                            state.drawing_path = true;
                            state.previous = point;
                            fillCircle(state.renderer, point, state.radius);
                        } else if (!state.has_anchor) {
                            state.anchor = point;
                            state.has_anchor = true;
                            state.setStatus("Pick the second point.", .{});
                        } else {
                            if (state.tool == .circle) {
                                strokeCircle(state.renderer, state.anchor, point, state.radius);
                            } else {
                                strokeRectangle(state.renderer, state.anchor, point, state.radius);
                            }
                            state.has_anchor = false;
                            state.setStatus("Ready.", .{});
                        }
                        withWindowTarget(&state);
                    }
                },
                c.SDL_EVENT_MOUSE_BUTTON_UP => state.drawing_path = false,
                c.SDL_EVENT_MOUSE_MOTION => {
                    if (state.drawing_path and state.tool == .path and insideCanvas(event.motion.x, event.motion.y)) {
                        const point = canvasPoint(event.motion.x, event.motion.y);
                        withCanvasTarget(&state);
                        setDrawColor(state.renderer, state.color);
                        drawThickLine(state.renderer, state.previous, point, state.radius);
                        withWindowTarget(&state);
                        state.previous = point;
                    }
                },
                c.SDL_EVENT_KEY_DOWN => if (state.editing()) {
                    switch (event.key.key) {
                        c.SDLK_BACKSPACE => backspaceFocusedText(&state),
                        c.SDLK_TAB, c.SDLK_RETURN => {
                            if (state.meta_focus_col == 0) {
                                state.meta_focus_col = 1;
                            } else {
                                state.meta_focus = -1;
                                setTextInput(&state, false);
                            }
                        },
                        c.SDLK_ESCAPE => {
                            state.meta_focus = -1;
                            setTextInput(&state, false);
                        },
                        else => {},
                    }
                } else switch (event.key.key) {
                    c.SDLK_1 => state.tool = .path,
                    c.SDLK_2 => state.tool = .rectangle,
                    c.SDLK_3 => state.tool = .circle,
                    c.SDLK_LEFTBRACKET => if (state.radius > 1) {
                        state.radius -= 1;
                    },
                    c.SDLK_RIGHTBRACKET => if (state.radius < 40) {
                        state.radius += 1;
                    },
                    c.SDLK_R => state.color = .{ .r = 211, .g = 47, .b = 47, .a = 255 },
                    c.SDLK_G => state.color = .{ .r = 0, .g = 128, .b = 96, .a = 255 },
                    c.SDLK_B => state.color = .{ .r = 31, .g = 111, .b = 235, .a = 255 },
                    c.SDLK_K => state.color = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
                    else => {},
                },
                c.SDL_EVENT_TEXT_INPUT => {
                    if (state.editing()) {
                        appendFocusedText(&state, std.mem.span(event.text.text));
                    }
                },
                else => {},
            }
        }

        withWindowTarget(&state);
        setDrawColor(renderer, .{ .r = 236, .g = 240, .b = 245, .a = 255 });
        _ = c.SDL_RenderClear(renderer);

        setDrawColor(renderer, .{ .r = 255, .g = 255, .b = 255, .a = 255 });
        var toolbar = c.SDL_FRect{ .x = 0, .y = 0, .w = WindowW, .h = ToolbarH };
        _ = c.SDL_RenderFillRect(renderer, &toolbar);

        drawButton(renderer, button(16, "Path"), state.tool == .path);
        drawButton(renderer, button(114, "Rectangle"), state.tool == .rectangle);
        drawButton(renderer, button(212, "Circle"), state.tool == .circle);
        setDrawColor(renderer, .{ .r = 31, .g = 35, .b = 40, .a = 255 });
        _ = c.SDL_RenderDebugText(renderer, 330, 25, "Color: R G B K");
        setDrawColor(renderer, state.color);
        var color_rect = c.SDL_FRect{ .x = 452, .y = 22, .w = 20, .h = 20 };
        _ = c.SDL_RenderFillRect(renderer, &color_rect);
        var radius_text: [32]u8 = undefined;
        const radius_label = std.fmt.bufPrintZ(&radius_text, "Radius: {d:.0}  [ ]", .{state.radius}) catch "Radius";
        setDrawColor(renderer, .{ .r = 31, .g = 35, .b = 40, .a = 255 });
        _ = c.SDL_RenderDebugText(renderer, 486, 25, radius_label.ptr);
        drawButton(renderer, button(624, "Open"), false);
        drawButton(renderer, button(722, "Save"), false);
        drawButton(renderer, button(820, "Clear"), false);
        drawButton(renderer, button(918, "New"), false);

        var dst = c.SDL_FRect{ .x = 0, .y = ToolbarH, .w = CanvasW, .h = CanvasH };
        _ = c.SDL_RenderTexture(renderer, state.canvas, null, &dst);
        setDrawColor(renderer, .{ .r = 145, .g = 152, .b = 161, .a = 255 });
        _ = c.SDL_RenderRect(renderer, &dst);

        var panel = c.SDL_FRect{
            .x = PanelX,
            .y = ToolbarH,
            .w = PanelW,
            .h = WindowH - ToolbarH - StatusH,
        };
        setDrawColor(renderer, .{ .r = 255, .g = 255, .b = 255, .a = 255 });
        _ = c.SDL_RenderFillRect(renderer, &panel);
        setDrawColor(renderer, .{ .r = 190, .g = 198, .b = 210, .a = 255 });
        _ = c.SDL_RenderRect(renderer, &panel);
        setDrawColor(renderer, .{ .r = 22, .g = 27, .b = 34, .a = 255 });
        _ = c.SDL_RenderDebugText(renderer, PanelX + 10, ToolbarH + 18, "tEXt metadata");
        drawButton(renderer, .{ .rect = metaAddRect(), .label = "Add" }, false);
        var meta_index: usize = 0;
        while (meta_index < state.meta_count) : (meta_index += 1) {
            const entry = &state.meta[meta_index];
            const row_focus = state.meta_focus == @as(i32, @intCast(meta_index));
            drawMetaField(renderer, metaKeyRect(meta_index), entry.keySlice(), row_focus and state.meta_focus_col == 0);
            drawMetaField(renderer, metaValueRect(meta_index), entry.valueSlice(), row_focus and state.meta_focus_col == 1);
            drawButton(renderer, .{ .rect = metaDelRect(meta_index), .label = "x" }, false);
        }

        var status = c.SDL_FRect{ .x = 0, .y = WindowH - StatusH, .w = WindowW, .h = StatusH };
        setDrawColor(renderer, .{ .r = 255, .g = 255, .b = 255, .a = 255 });
        _ = c.SDL_RenderFillRect(renderer, &status);
        setDrawColor(renderer, .{ .r = 31, .g = 35, .b = 40, .a = 255 });
        state.status[state.status_len] = 0;
        _ = c.SDL_RenderDebugText(renderer, 12, WindowH - 20, @ptrCast(&state.status[0]));

        _ = c.SDL_RenderPresent(renderer);
    }

    c.SDL_DestroyTexture(state.canvas);
}
