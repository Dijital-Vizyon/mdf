const std = @import("std");

pub const PngError = error{
    BadSignature,
    Truncated,
    BadIHDR,
    Unsupported,
    BadChunk,
    BadZlib,
    BadImageData,
};

fn readU32BE(bytes: []const u8, off: usize) !u32 {
    if (off + 4 > bytes.len) return PngError.Truncated;
    return (@as(u32, bytes[off]) << 24) |
        (@as(u32, bytes[off + 1]) << 16) |
        (@as(u32, bytes[off + 2]) << 8) |
        (@as(u32, bytes[off + 3]));
}

pub const Decoded = struct {
    width: u32,
    height: u32,
    rgba: []u8, // length = width * height * 4
};

// Minimal PNG decoder for the PNGs produced by this repo:
// - non-interlaced
// - color type 6 (RGBA)
// - bit depth 8
// - supports filter 0 (None)
pub fn decode(allocator: std.mem.Allocator, png: []const u8) !Decoded {
    const sig = [_]u8{ 137, 80, 78, 71, 13, 10, 26, 10 };
    if (png.len < sig.len) return PngError.BadSignature;
    if (!std.mem.eql(u8, png[0..sig.len], &sig)) return PngError.BadSignature;

    var off: usize = 8;
    var width: u32 = 0;
    var height: u32 = 0;
    var seen_ihdr = false;

    var idat = std.ArrayList(u8).init(allocator);
    defer idat.deinit();

    while (true) {
        if (off + 8 > png.len) return PngError.Truncated;
        const len = try readU32BE(png, off);
        off += 4;
        const typ = png[off .. off + 4];
        off += 4;
        if (off + len + 4 > png.len) return PngError.Truncated;
        const data = png[off .. off + len];
        off += len;
        _ = png[off .. off + 4]; // crc (ignored here; MDF chunk CRC already protects payload)
        off += 4;

        if (std.mem.eql(u8, typ, "IHDR")) {
            if (len != 13) return PngError.BadIHDR;
            width = try readU32BE(data, 0);
            height = try readU32BE(data, 4);
            const bit_depth = data[8];
            const color_type = data[9];
            const compression = data[10];
            const filter = data[11];
            const interlace = data[12];
            if (!(bit_depth == 8 and color_type == 6 and compression == 0 and filter == 0 and interlace == 0)) {
                return PngError.Unsupported;
            }
            seen_ihdr = true;
        } else if (std.mem.eql(u8, typ, "IDAT")) {
            try idat.appendSlice(data);
        } else if (std.mem.eql(u8, typ, "IEND")) {
            break;
        } else {
            // ignore other chunks
        }
    }

    if (!seen_ihdr) return PngError.BadIHDR;
    if (width == 0 or height == 0) return PngError.BadIHDR;

    // Decompress zlib stream in IDAT
    var zlib_stream = std.io.fixedBufferStream(idat.items);
    var z = std.compress.zlib.decompressor(zlib_stream.reader());

    const row_bytes: usize = 1 + @as(usize, width) * 4;
    const expected_raw: usize = @as(usize, height) * row_bytes;

    var raw = try allocator.alloc(u8, expected_raw);
    errdefer allocator.free(raw);
    const n = try z.reader().readAll(raw);
    if (n != expected_raw) return PngError.BadImageData;

    // Unfilter: only filter 0 supported
    var rgba = try allocator.alloc(u8, @as(usize, width) * @as(usize, height) * 4);
    errdefer allocator.free(rgba);

    var y: usize = 0;
    while (y < height) : (y += 1) {
        const roff = y * row_bytes;
        const filter_type = raw[roff];
        if (filter_type != 0) return PngError.Unsupported;
        const src = raw[roff + 1 .. roff + row_bytes];
        const dst_off = y * @as(usize, width) * 4;
        std.mem.copyForwards(u8, rgba[dst_off .. dst_off + src.len], src);
    }

    allocator.free(raw);
    return .{ .width = width, .height = height, .rgba = rgba };
}

