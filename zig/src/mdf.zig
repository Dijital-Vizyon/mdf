const std = @import("std");

pub const MAGIC: [4]u8 = .{ 'M', 'D', 'F', '1' };
pub const header_size: usize = 16;
pub const chunk_header_size: usize = 16;

pub const Version = struct {
    major: u8 = 0,
    minor: u8 = 1,
};

pub const Chunk = struct {
    typ: [4]u8,
    flags: u32 = 0,
    payload: []const u8,
};

pub const ParsedChunk = struct {
    typ: [4]u8,
    flags: u32,
    length: u32,
    crc32: u32,
    payload: []const u8,
};

pub const ParsedDocument = struct {
    version: Version,
    chunks: []ParsedChunk,
};

pub const ForbiddenChunkTypes = struct {
    pub fn isForbidden(typ: [4]u8) bool {
        return std.mem.eql(u8, &typ, "EXEC") or
            std.mem.eql(u8, &typ, "JS__") or
            std.mem.eql(u8, &typ, "CODE") or
            std.mem.eql(u8, &typ, "XCMD");
    }
};

fn writeU32LE(dst: []u8, value: u32) void {
    std.debug.assert(dst.len == 4);
    const ptr: *[4]u8 = @alignCast(@ptrCast(dst.ptr));
    std.mem.writeInt(u32, ptr, value, .little);
}

fn readU32LE(src: []const u8) u32 {
    std.debug.assert(src.len == 4);
    const ptr: *const [4]u8 = @alignCast(@ptrCast(src.ptr));
    return std.mem.readInt(u32, ptr, .little);
}

fn crc32Table() [256]u32 {
    var table: [256]u32 = undefined;
    var i: u32 = 0;
    while (i < 256) : (i += 1) {
        var value: u32 = i;
        var bit: u32 = 0;
        while (bit < 8) : (bit += 1) {
            if ((value & 1) == 1) {
                value = 0xEDB88320 ^ (value >> 1);
            } else {
                value = value >> 1;
            }
        }
        table[i] = value;
    }
    return table;
}

const CRC_TABLE: [256]u32 = blk: {
    @setEvalBranchQuota(10_000);
    break :blk crc32Table();
};

pub fn crc32(bytes: []const u8) u32 {
    var crc: u32 = 0xFFFF_FFFF;
    for (bytes) |b| {
        const idx: u32 = (crc ^ @as(u32, b)) & 0xFF;
        crc = CRC_TABLE[idx] ^ (crc >> 8);
    }
    return (crc ^ 0xFFFF_FFFF);
}

pub fn writeDocument(
    allocator: std.mem.Allocator,
    version: Version,
    chunks: []const Chunk,
) ![]u8 {
    var total: usize = header_size;
    for (chunks) |c| {
        total += chunk_header_size + c.payload.len;
    }

    var out = try allocator.alloc(u8, total);
    errdefer allocator.free(out);

    // header
    std.mem.copyForwards(u8, out[0..4], MAGIC[0..]);
    out[4] = version.major;
    out[5] = version.minor;
    out[6] = 0;
    out[7] = 0;
    writeU32LE(out[8..12], @intCast(chunks.len));
    writeU32LE(out[12..16], 0);

    var offset: usize = header_size;
    for (chunks) |c| {
        std.mem.copyForwards(u8, out[offset .. offset + 4], c.typ[0..]);
        writeU32LE(out[offset + 4 .. offset + 8], c.flags);
        writeU32LE(out[offset + 8 .. offset + 12], @intCast(c.payload.len));
        const c_crc = crc32(c.payload);
        writeU32LE(out[offset + 12 .. offset + 16], c_crc);
        std.mem.copyForwards(u8, out[offset + chunk_header_size .. offset + chunk_header_size + c.payload.len], c.payload);
        offset += chunk_header_size + c.payload.len;
    }

    return out;
}

pub const ParseError = error{
    TooSmall,
    BadMagic,
    ChunkHeaderPastEnd,
    ChunkPayloadPastEnd,
    CrcMismatch,
    TrailingBytes,
};

pub fn parseDocument(allocator: std.mem.Allocator, bytes: []const u8) !ParsedDocument {
    if (bytes.len < header_size) return ParseError.TooSmall;
    if (!std.mem.eql(u8, bytes[0..4], MAGIC[0..])) return ParseError.BadMagic;

    const version = Version{ .major = bytes[4], .minor = bytes[5] };
    const chunk_count = readU32LE(bytes[8..12]);

    var chunks = try allocator.alloc(ParsedChunk, chunk_count);
    errdefer allocator.free(chunks);

    var offset: usize = header_size;
    var i: usize = 0;
    while (i < chunk_count) : (i += 1) {
        if (offset + chunk_header_size > bytes.len) return ParseError.ChunkHeaderPastEnd;

        var typ: [4]u8 = undefined;
        std.mem.copyForwards(u8, &typ, bytes[offset .. offset + 4]);
        const flags = readU32LE(bytes[offset + 4 .. offset + 8]);
        const length = readU32LE(bytes[offset + 8 .. offset + 12]);
        const expected_crc = readU32LE(bytes[offset + 12 .. offset + 16]);

        const payload_off = offset + chunk_header_size;
        const payload_end = payload_off + @as(usize, length);
        if (payload_end > bytes.len) return ParseError.ChunkPayloadPastEnd;

        const payload = bytes[payload_off..payload_end];
        const actual_crc = crc32(payload);
        if (actual_crc != expected_crc) return ParseError.CrcMismatch;

        chunks[i] = .{
            .typ = typ,
            .flags = flags,
            .length = length,
            .crc32 = expected_crc,
            .payload = payload,
        };

        offset = payload_end;
    }

    if (offset != bytes.len) return ParseError.TrailingBytes;

    return .{ .version = version, .chunks = chunks };
}

pub const VerifyError = error{
    ExecutableChunkType,
} || ParseError;

pub fn verify(bytes: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const doc = try parseDocument(alloc, bytes);
    for (doc.chunks) |c| {
        if (ForbiddenChunkTypes.isForbidden(c.typ)) return VerifyError.ExecutableChunkType;
    }
}

// Paged document model.
// Packaged as part of the main `mdf` module.
pub const paged = struct {
    pub const DocVersion = Version{ .major = 0, .minor = 2 };

    pub const Page = struct {
        index: u32,
        width: u32,
        height: u32,
        image_id: u32,
    };

    pub const Image = struct {
        image_id: u32,
        png_bytes: []const u8,
    };

    pub const Document = struct {
        pages: []const Page,
        images: []const Image,
    };

    fn writeU32LE_paged(dst: []u8, value: u32) void {
        std.debug.assert(dst.len == 4);
        const ptr: *[4]u8 = @alignCast(@ptrCast(dst.ptr));
        std.mem.writeInt(u32, ptr, value, .little);
    }

    fn readU32LE_paged(src: []const u8) u32 {
        std.debug.assert(src.len == 4);
        const ptr: *const [4]u8 = @alignCast(@ptrCast(src.ptr));
        return std.mem.readInt(u32, ptr, .little);
    }

    pub fn buildDocmJson(allocator: std.mem.Allocator, pages: []const Page) ![]u8 {
        var list = std.ArrayList(u8).init(allocator);
        errdefer list.deinit();

        try list.appendSlice("{\n");
        try list.appendSlice("  \"version\": 2,\n");
        try list.appendSlice("  \"pages\": [\n");
        for (pages, 0..) |p, idx| {
            try list.writer().print(
                "    {{\"index\":{d},\"width\":{d},\"height\":{d},\"imageId\":{d}}}{s}\n",
                .{ p.index, p.width, p.height, p.image_id, if (idx + 1 == pages.len) "" else "," },
            );
        }
        try list.appendSlice("  ]\n");
        try list.appendSlice("}\n");

        return try list.toOwnedSlice();
    }

    pub fn buildPageJson(allocator: std.mem.Allocator, page: Page) ![]u8 {
        return std.fmt.allocPrint(allocator, "{{\"index\":{d},\"width\":{d},\"height\":{d},\"imageId\":{d}}}\n", .{
            page.index,
            page.width,
            page.height,
            page.image_id,
        });
    }

    pub fn buildImgPayload(allocator: std.mem.Allocator, image: Image) ![]u8 {
        var payload = try allocator.alloc(u8, 4 + image.png_bytes.len);
        errdefer allocator.free(payload);
        writeU32LE_paged(payload[0..4], image.image_id);
        std.mem.copyForwards(u8, payload[4..], image.png_bytes);
        return payload;
    }

    pub fn writeDocument02(allocator: std.mem.Allocator, doc: Document) ![]u8 {
        const docm_json = try buildDocmJson(allocator, doc.pages);
        defer allocator.free(docm_json);

        const chunk_count = 1 + doc.pages.len + doc.images.len;
        var chunks = try allocator.alloc(Chunk, chunk_count);
        defer allocator.free(chunks);

        chunks[0] = .{ .typ = .{ 'D', 'O', 'C', 'M' }, .flags = 0, .payload = docm_json };

        var cursor: usize = 1;
        for (doc.pages) |p| {
            const page_json = try buildPageJson(allocator, p);
            chunks[cursor] = .{ .typ = .{ 'P', 'A', 'G', 'E' }, .flags = 0, .payload = page_json };
            cursor += 1;
        }
        for (doc.images) |img| {
            const img_payload = try buildImgPayload(allocator, img);
            chunks[cursor] = .{ .typ = .{ 'I', 'M', 'G', '_' }, .flags = 0, .payload = img_payload };
            cursor += 1;
        }

        return try writeDocument(allocator, DocVersion, chunks);
    }

    pub const Parse02Error = error{
        WrongVersion,
        MissingDocm,
        BadImgPayload,
    } || ParseError;

    pub fn parseDocument02(allocator: std.mem.Allocator, bytes: []const u8) !Document {
        const parsed = try parseDocument(allocator, bytes);
        if (!(parsed.version.major == 0 and parsed.version.minor == 2)) return Parse02Error.WrongVersion;

        var pages = std.ArrayList(Page).init(allocator);
        var images = std.ArrayList(Image).init(allocator);
        errdefer pages.deinit();
        errdefer images.deinit();

        var has_docm = false;
        for (parsed.chunks) |c| {
            if (std.mem.eql(u8, &c.typ, "DOCM")) {
                has_docm = true;
                continue;
            }
            if (std.mem.eql(u8, &c.typ, "PAGE")) {
                const s = c.payload;
                const idx = extractJsonU32(s, "\"index\":") orelse 0;
                const w = extractJsonU32(s, "\"width\":") orelse 0;
                const h = extractJsonU32(s, "\"height\":") orelse 0;
                const id = extractJsonU32(s, "\"imageId\":") orelse 0;
                try pages.append(.{ .index = idx, .width = w, .height = h, .image_id = id });
            } else if (std.mem.eql(u8, &c.typ, "IMG_")) {
                if (c.payload.len < 4) return Parse02Error.BadImgPayload;
                const image_id = readU32LE_paged(c.payload[0..4]);
                const png_bytes = c.payload[4..];
                try images.append(.{ .image_id = image_id, .png_bytes = png_bytes });
            }
        }
        if (!has_docm) return Parse02Error.MissingDocm;

        return .{
            .pages = try pages.toOwnedSlice(),
            .images = try images.toOwnedSlice(),
        };
    }

    fn extractJsonU32(s: []const u8, needle: []const u8) ?u32 {
        const pos = std.mem.indexOf(u8, s, needle) orelse return null;
        var i: usize = pos + needle.len;
        while (i < s.len and (s[i] == ' ' or s[i] == '\t')) : (i += 1) {}
        var value: u32 = 0;
        var any = false;
        while (i < s.len and s[i] >= '0' and s[i] <= '9') : (i += 1) {
            any = true;
            value = value * 10 + @as(u32, s[i] - '0');
        }
        return if (any) value else null;
    }
};

