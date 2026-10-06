const std = @import("std");

pub const KeyMax = 80;
pub const ValueMax = 256;
pub const MaxFileSize = 256 * 1024 * 1024;

pub const Entry = struct {
    key: [KeyMax]u8 = undefined,
    key_len: usize = 0,
    value: [ValueMax]u8 = undefined,
    value_len: usize = 0,

    pub fn keySlice(self: *const Entry) []const u8 {
        return self.key[0..self.key_len];
    }

    pub fn valueSlice(self: *const Entry) []const u8 {
        return self.value[0..self.value_len];
    }
};

const png_signature = [8]u8{ 137, 80, 78, 71, 13, 10, 26, 10 };

fn crc32(data: []const u8) u32 {
    var crc: u32 = 0xffffffff;
    for (data) |byte| {
        crc ^= byte;
        var bit: u8 = 0;
        while (bit < 8) : (bit += 1) {
            const mask: u32 = if (crc & 1 != 0) 0xedb88320 else 0;
            crc = (crc >> 1) ^ mask;
        }
    }
    return crc ^ 0xffffffff;
}

fn readU32(bytes: []const u8, offset: usize) u32 {
    return (@as(u32, bytes[offset]) << 24) |
        (@as(u32, bytes[offset + 1]) << 16) |
        (@as(u32, bytes[offset + 2]) << 8) |
        @as(u32, bytes[offset + 3]);
}

fn isPng(bytes: []const u8) bool {
    return bytes.len >= 8 and std.mem.eql(u8, bytes[0..8], &png_signature);
}

pub fn readFile(path: []const u8, entries: []Entry) usize {
    const allocator = std.heap.page_allocator;
    const data = std.fs.cwd().readFileAlloc(allocator, path, MaxFileSize) catch return 0;
    defer allocator.free(data);
    if (!isPng(data)) return 0;

    var count: usize = 0;
    var offset: usize = 8;
    while (offset + 12 <= data.len and count < entries.len) {
        const data_len: usize = readU32(data, offset);
        if (offset + 12 + data_len > data.len) break;
        const kind = data[offset + 4 .. offset + 8];
        const body = data[offset + 8 .. offset + 8 + data_len];
        if (std.mem.eql(u8, kind, "tEXt")) {
            if (std.mem.indexOfScalar(u8, body, 0)) |split| {
                const key = body[0..split];
                const value = body[split + 1 ..];
                const key_len = @min(key.len, KeyMax - 1);
                const value_len = @min(value.len, ValueMax - 1);
                @memcpy(entries[count].key[0..key_len], key[0..key_len]);
                entries[count].key_len = key_len;
                @memcpy(entries[count].value[0..value_len], value[0..value_len]);
                entries[count].value_len = value_len;
                count += 1;
            }
        }
        if (std.mem.eql(u8, kind, "IEND")) break;
        offset += 12 + data_len;
    }
    return count;
}

fn appendTextChunk(out: *std.ArrayList(u8), entry: *const Entry) !void {
    const key = entry.keySlice();
    const key_len = @min(key.len, 79);
    const value = entry.valueSlice();
    const body_len: usize = 4 + key_len + 1 + value.len;

    var length_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &length_bytes, @intCast(body_len - 4), .big);
    try out.appendSlice(&length_bytes);

    const body_start = out.items.len;
    try out.appendSlice("tEXt");
    try out.appendSlice(key[0..key_len]);
    try out.append(0);
    try out.appendSlice(value);

    var crc_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &crc_bytes, crc32(out.items[body_start..]), .big);
    try out.appendSlice(&crc_bytes);
}

pub fn writeFile(path: []const u8, entries: []const Entry) bool {
    const allocator = std.heap.page_allocator;
    const data = std.fs.cwd().readFileAlloc(allocator, path, MaxFileSize) catch return false;
    defer allocator.free(data);
    if (!isPng(data)) return false;

    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();
    out.appendSlice(&png_signature) catch return false;

    var offset: usize = 8;
    var wrote_end = false;
    while (offset + 12 <= data.len) {
        const data_len: usize = readU32(data, offset);
        const total = 12 + data_len;
        if (offset + total > data.len) break;
        const kind = data[offset + 4 .. offset + 8];
        if (std.mem.eql(u8, kind, "tEXt")) {
            offset += total;
            continue;
        }
        if (std.mem.eql(u8, kind, "IEND")) {
            for (entries) |*entry| {
                const trimmed = std.mem.trim(u8, entry.keySlice(), " \t");
                if (trimmed.len == 0) continue;
                appendTextChunk(&out, entry) catch return false;
            }
        }
        out.appendSlice(data[offset .. offset + total]) catch return false;
        if (std.mem.eql(u8, kind, "IEND")) {
            wrote_end = true;
            break;
        }
        offset += total;
    }
    if (!wrote_end) return false;

    std.fs.cwd().writeFile(.{ .sub_path = path, .data = out.items }) catch return false;
    return true;
}
