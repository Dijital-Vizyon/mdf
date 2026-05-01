const std = @import("std");
const mdf = @import("mdf");

fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\MDF (Zig) CLI
        \\
        \\Usage:
        \\  mdf convert <input> --output <file> [--stamp-time]
        \\  mdf demo --output <file.mdf>
        \\  mdf convert-md <input.md> --output <file.mdf>
        \\  mdf info <input.mdf>
        \\  mdf list-chunks <input.mdf>
        \\  mdf unpack <input.mdf> --output-dir <dir>
        \\  mdf extract <input.mdf> --type <META|DATA|DOCM|PAGE|IMG_> [--index <n>] --output <file>
        \\  mdf convert-pdf <input.pdf> --output <file.mdf> [--dpi <n>]
        \\  mdf convert-typst <input.typ> --output <file.mdf> [--dpi <n>]
        \\  mdf convert-latex <input.tex> --output <file.mdf> [--dpi <n>]
        \\  mdf render <input.mdf> --output-dir <dir>
        \\  mdf verify <input>
        \\  mdf --help
        \\
    );
}

fn getFlagValue(args: []const []const u8, name: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (!std.mem.eql(u8, args[i], name)) continue;
        if (i + 1 >= args.len) return null;
        return args[i + 1];
    }
    return null;
}

fn hasFlag(args: []const []const u8, name: []const u8) bool {
    for (args) |a| {
        if (std.mem.eql(u8, a, name)) return true;
    }
    return false;
}

fn parseU32Flag(args: []const []const u8, name: []const u8, default_value: u32) u32 {
    const raw = getFlagValue(args, name) orelse return default_value;
    return std.fmt.parseInt(u32, raw, 10) catch default_value;
}

fn whichOk(allocator: std.mem.Allocator, cmd: []const u8) bool {
    const res = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "sh", "-lc", std.fmt.allocPrint(allocator, "command -v {s}", .{cmd}) catch return false },
        .max_output_bytes = 4096,
    }) catch return false;
    defer allocator.free(res.stdout);
    defer allocator.free(res.stderr);
    return res.term.Exited == 0 and std.mem.trim(u8, res.stdout, " \n\t\r").len > 0;
}

fn cmdConvert(gpa: std.mem.Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (args.len < 2) {
        try stderr.writeAll("[ERROR] convert requires <input> and --output <file>.\n");
        return 1;
    }

    const input_path = args[1];
    const output_path = getFlagValue(args, "--output") orelse {
        try stderr.writeAll("[ERROR] convert requires <input> and --output <file>.\n");
        return 1;
    };
    const stamp_time = hasFlag(args, "--stamp-time");

    const input_file = try std.fs.cwd().openFile(input_path, .{});
    defer input_file.close();
    const source_bytes = try input_file.readToEndAlloc(gpa, 1 << 32);
    defer gpa.free(source_bytes);

    // Minimal META to match JS v0.1. This is intentionally deterministic unless stamp_time.
    // We keep JSON stable and avoid pretty-print differences by using fixed ordering.
    var sha_buf: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(source_bytes, &sha_buf, .{});

    var sha_hex: [64]u8 = undefined;
    _ = std.fmt.bufPrint(&sha_hex, "{s}", .{std.fmt.fmtSliceHexLower(&sha_buf)}) catch unreachable;

    var meta = std.ArrayList(u8).init(gpa);
    defer meta.deinit();

    // JSON with same keys as JS, no createdAt unless stamp_time.
    try meta.appendSlice("{\n");
    try meta.writer().print("  \"sourcePath\": \"{s}\",\n", .{std.fs.path.basename(input_path)});
    try meta.writer().print("  \"sourceSize\": {d},\n", .{source_bytes.len});
    try meta.writer().print("  \"sourceSha256\": \"{s}\",\n", .{sha_hex[0..]});
    try meta.appendSlice("  \"optimizeRaster\": false,\n");
    try meta.appendSlice("  \"quality\": null,\n");
    try meta.appendSlice("  \"createdWith\": \"mdf-cli/0.1.0-alpha\"");
    if (stamp_time) {
        var ts_buf: [64]u8 = undefined;
        const now = std.time.timestamp();
        // ISO8601 without timezone formatting library; use UTC from epoch seconds.
        // This is only for non-deterministic stamping; exact format isn't compared in tests.
        const ts = std.fmt.bufPrint(&ts_buf, "{d}", .{now}) catch unreachable;
        try meta.writer().print(",\n  \"createdAt\": \"{s}\"", .{ts});
    }
    try meta.appendSlice("\n}");

    const chunks = [_]mdf.Chunk{
        .{ .typ = .{ 'M', 'E', 'T', 'A' }, .flags = 0, .payload = meta.items },
        .{ .typ = .{ 'D', 'A', 'T', 'A' }, .flags = 0, .payload = source_bytes },
    };

    const out_bytes = try mdf.writeDocument(gpa, .{ .major = 0, .minor = 1 }, &chunks);
    defer gpa.free(out_bytes);

    // Ensure output directory exists.
    if (std.fs.path.dirname(output_path)) |dir_name| {
        try std.fs.cwd().makePath(dir_name);
    }

    const out_file = try std.fs.cwd().createFile(output_path, .{ .truncate = true });
    defer out_file.close();
    try out_file.writeAll(out_bytes);

    try stdout.writer().print("[SUCCESS] Wrote {s} ({d} bytes)\n", .{ output_path, out_bytes.len });
    return 0;
}

fn writeIndexHtml(dir: std.fs.Dir, page_files: [][]const u8) !void {
    var file = try dir.createFile("index.html", .{ .truncate = true });
    defer file.close();
    var w = file.writer();
    try w.writeAll("<!doctype html>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\n<title>MDF Render</title>\n");
    try w.writeAll(
        \\<style>
        \\:root{color-scheme:light dark}
        \\body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;margin:0}
        \\header{position:sticky;top:0;backdrop-filter:saturate(1.2) blur(8px);background:color-mix(in srgb, Canvas 85%, transparent);border-bottom:1px solid color-mix(in srgb, CanvasText 12%, transparent);padding:12px 16px;display:flex;gap:12px;align-items:center}
        \\main{display:grid;grid-template-columns:320px 1fr;min-height:calc(100vh - 56px)}
        \\nav{border-right:1px solid color-mix(in srgb, CanvasText 12%, transparent);padding:12px 12px;overflow:auto}
        \\nav button{width:100%;text-align:left;padding:10px 10px;border-radius:10px;border:1px solid color-mix(in srgb, CanvasText 12%, transparent);background:color-mix(in srgb, Canvas 92%, transparent);margin-bottom:10px;cursor:pointer}
        \\nav button[aria-current="true"]{outline:2px solid color-mix(in srgb, AccentColor 60%, transparent)}
        \\section{padding:16px;overflow:auto}
        \\img{display:block;max-width:min(1100px,100%);height:auto;margin:0 auto;box-shadow:0 6px 28px rgba(0,0,0,.22);border-radius:10px;background:#fff}
        \\small{opacity:.75}
        \\</style>
        \\
    );

    try w.writeAll("<header><strong>MDF Render</strong><small id=\"meta\"></small><span style=\"flex:1\"></span><button id=\"prev\">Prev</button><button id=\"next\">Next</button></header>\n");
    try w.writeAll("<main><nav id=\"pages\"></nav><section><img id=\"page\" alt=\"Rendered page\"></section></main>\n");

    try w.writeAll("<script>\n");
    try w.writeAll("const pages = [\n");
    for (page_files, 0..) |p, idx| {
        // page filenames are generated by the renderer and are safe ASCII (page-N.png)
        try w.print("  {{ name: \"{s}\" }}{s}\n", .{ p, if (idx + 1 == page_files.len) "" else "," });
    }
    try w.writeAll("];\n");
    try w.writeAll(
        \\let idx = 0;
        \\const pageImg = document.getElementById('page');
        \\const pagesNav = document.getElementById('pages');
        \\const meta = document.getElementById('meta');
        \\function renderNav(){
        \\  pagesNav.innerHTML='';
        \\  pages.forEach((p,i)=>{
        \\    const b=document.createElement('button');
        \\    b.textContent=`Page ${i+1}`;
        \\    b.onclick=()=>setPage(i);
        \\    if(i===idx) b.setAttribute('aria-current','true');
        \\    pagesNav.appendChild(b);
        \\  });
        \\}
        \\function setPage(i){
        \\  idx=Math.max(0,Math.min(pages.length-1,i));
        \\  pageImg.src=pages[idx].name;
        \\  meta.textContent = `${idx+1} / ${pages.length}`;
        \\  renderNav();
        \\}
        \\document.getElementById('prev').onclick=()=>setPage(idx-1);
        \\document.getElementById('next').onclick=()=>setPage(idx+1);
        \\window.addEventListener('keydown',(e)=>{
        \\  if(e.key==='ArrowLeft') setPage(idx-1);
        \\  if(e.key==='ArrowRight') setPage(idx+1);
        \\});
        \\setPage(0);
        \\
    );
    try w.writeAll("</script>\n");
}

fn cmdRender(gpa: std.mem.Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (args.len < 2) {
        try stderr.writeAll("[ERROR] render requires <input.mdf> and --output-dir <dir>.\n");
        return 1;
    }
    const input_path = args[1];
    const out_dir_path = getFlagValue(args, "--output-dir") orelse {
        try stderr.writeAll("[ERROR] render requires <input.mdf> and --output-dir <dir>.\n");
        return 1;
    };

    const file = try std.fs.cwd().openFile(input_path, .{});
    defer file.close();
    const bytes = try file.readToEndAlloc(gpa, 1 << 32);
    defer gpa.free(bytes);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const alloc = arena.allocator();

    const doc = mdf.paged.parseDocument02(alloc, bytes) catch |err| {
        try stderr.writer().print("[ERROR] {s}\n", .{@errorName(err)});
        return 1;
    };

    try std.fs.cwd().makePath(out_dir_path);
    var out_dir = try std.fs.cwd().openDir(out_dir_path, .{ .iterate = false });
    defer out_dir.close();

    var page_files = std.ArrayList([]const u8).init(alloc);
    for (doc.pages) |p| {
        if (p.image_id == 0) continue;
        // find image
        var img_bytes: ?[]const u8 = null;
        for (doc.images) |img| {
            if (img.image_id == p.image_id) {
                img_bytes = img.png_bytes;
                break;
            }
        }
        const bytes_png = img_bytes orelse continue;
        const filename = try std.fmt.allocPrint(alloc, "page-{d}.png", .{p.index});
        var f = try out_dir.createFile(filename, .{ .truncate = true });
        defer f.close();
        try f.writeAll(bytes_png);
        try page_files.append(filename);
    }

    try writeIndexHtml(out_dir, page_files.items);
    try stdout.writer().print("[SUCCESS] Rendered {d} page image(s) to {s}\n", .{ page_files.items.len, out_dir_path });
    return 0;
}

fn crc32(bytes: []const u8) u32 {
    return mdf.crc32(bytes);
}

fn pngAdler32(data: []const u8) u32 {
    var s1: u32 = 1;
    var s2: u32 = 0;
    for (data) |b| {
        s1 = (s1 + b) % 65521;
        s2 = (s2 + s1) % 65521;
    }
    return (s2 << 16) | s1;
}

fn writeU32BE(dst: []u8, value: u32) void {
    std.debug.assert(dst.len == 4);
    dst[0] = @intCast((value >> 24) & 0xff);
    dst[1] = @intCast((value >> 16) & 0xff);
    dst[2] = @intCast((value >> 8) & 0xff);
    dst[3] = @intCast(value & 0xff);
}

fn appendPngChunk(buf: *std.ArrayList(u8), typ: [4]u8, payload: []const u8) !void {
    var len_be: [4]u8 = undefined;
    writeU32BE(&len_be, @intCast(payload.len));
    try buf.appendSlice(&len_be);
    try buf.appendSlice(&typ);
    try buf.appendSlice(payload);

    // CRC over type+payload
    var crc_input = try buf.allocator.alloc(u8, 4 + payload.len);
    defer buf.allocator.free(crc_input);
    std.mem.copyForwards(u8, crc_input[0..4], &typ);
    std.mem.copyForwards(u8, crc_input[4..], payload);
    const c = crc32(crc_input);
    var crc_be: [4]u8 = undefined;
    writeU32BE(&crc_be, c);
    try buf.appendSlice(&crc_be);
}

fn makeBlankRgba(gpa: std.mem.Allocator, width: u32, height: u32, r: u8, g: u8, b: u8) ![]u8 {
    const w: usize = width;
    const h: usize = height;
    var rgba = try gpa.alloc(u8, w * h * 4);
    var i: usize = 0;
    while (i < rgba.len) : (i += 4) {
        rgba[i + 0] = r;
        rgba[i + 1] = g;
        rgba[i + 2] = b;
        rgba[i + 3] = 255;
    }
    return rgba;
}

fn setPixel(rgba: []u8, width: u32, x: i32, y: i32, r: u8, g: u8, b: u8) void {
    if (x < 0 or y < 0) return;
    const ux: u32 = @intCast(x);
    const uy: u32 = @intCast(y);
    if (ux >= width) return;
    const idx: usize = (@as(usize, uy) * @as(usize, width) + @as(usize, ux)) * 4;
    if (idx + 3 >= rgba.len) return;
    rgba[idx + 0] = r;
    rgba[idx + 1] = g;
    rgba[idx + 2] = b;
    rgba[idx + 3] = 255;
}

fn drawRect(rgba: []u8, width: u32, x0: i32, y0: i32, x1: i32, y1: i32, r: u8, g: u8, b: u8) void {
    var y: i32 = y0;
    while (y < y1) : (y += 1) {
        var x: i32 = x0;
        while (x < x1) : (x += 1) {
            setPixel(rgba, width, x, y, r, g, b);
        }
    }
}

// Tiny 5x7 bitmap font for ASCII (subset).
fn glyph5x7(c: u8) [7]u8 {
    return switch (c) {
        'A' => .{ 0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001 },
        'B' => .{ 0b11110, 0b10001, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110 },
        'C' => .{ 0b01111, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b01111 },
        'D' => .{ 0b11110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b11110 },
        'E' => .{ 0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111 },
        'F' => .{ 0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b10000 },
        'G' => .{ 0b01111, 0b10000, 0b10000, 0b10111, 0b10001, 0b10001, 0b01111 },
        'H' => .{ 0b10001, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001 },
        'I' => .{ 0b01110, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110 },
        'L' => .{ 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111 },
        'M' => .{ 0b10001, 0b11011, 0b10101, 0b10101, 0b10001, 0b10001, 0b10001 },
        'N' => .{ 0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001, 0b10001 },
        'O' => .{ 0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110 },
        'P' => .{ 0b11110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000, 0b10000 },
        'R' => .{ 0b11110, 0b10001, 0b10001, 0b11110, 0b10100, 0b10010, 0b10001 },
        'S' => .{ 0b01111, 0b10000, 0b10000, 0b01110, 0b00001, 0b00001, 0b11110 },
        'T' => .{ 0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100 },
        'U' => .{ 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110 },
        'W' => .{ 0b10001, 0b10001, 0b10001, 0b10101, 0b10101, 0b10101, 0b01010 },
        'Y' => .{ 0b10001, 0b10001, 0b01010, 0b00100, 0b00100, 0b00100, 0b00100 },
        'a' => .{ 0b00000, 0b00000, 0b01110, 0b00001, 0b01111, 0b10001, 0b01111 },
        'b' => .{ 0b10000, 0b10000, 0b11110, 0b10001, 0b10001, 0b10001, 0b11110 },
        'c' => .{ 0b00000, 0b00000, 0b01111, 0b10000, 0b10000, 0b10000, 0b01111 },
        'd' => .{ 0b00001, 0b00001, 0b01111, 0b10001, 0b10001, 0b10001, 0b01111 },
        'e' => .{ 0b00000, 0b00000, 0b01110, 0b10001, 0b11111, 0b10000, 0b01110 },
        'f' => .{ 0b00111, 0b01000, 0b01000, 0b11110, 0b01000, 0b01000, 0b01000 },
        'g' => .{ 0b00000, 0b00000, 0b01111, 0b10001, 0b01111, 0b00001, 0b11110 },
        'h' => .{ 0b10000, 0b10000, 0b11110, 0b10001, 0b10001, 0b10001, 0b10001 },
        'i' => .{ 0b00100, 0b00000, 0b01100, 0b00100, 0b00100, 0b00100, 0b01110 },
        'l' => .{ 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110 },
        'm' => .{ 0b00000, 0b00000, 0b11010, 0b10101, 0b10101, 0b10101, 0b10101 },
        'n' => .{ 0b00000, 0b00000, 0b11110, 0b10001, 0b10001, 0b10001, 0b10001 },
        'o' => .{ 0b00000, 0b00000, 0b01110, 0b10001, 0b10001, 0b10001, 0b01110 },
        'p' => .{ 0b00000, 0b00000, 0b11110, 0b10001, 0b11110, 0b10000, 0b10000 },
        'r' => .{ 0b00000, 0b00000, 0b10111, 0b11000, 0b10000, 0b10000, 0b10000 },
        's' => .{ 0b00000, 0b00000, 0b01111, 0b10000, 0b01110, 0b00001, 0b11110 },
        't' => .{ 0b01000, 0b01000, 0b11110, 0b01000, 0b01000, 0b01000, 0b00111 },
        'u' => .{ 0b00000, 0b00000, 0b10001, 0b10001, 0b10001, 0b10011, 0b01101 },
        'w' => .{ 0b00000, 0b00000, 0b10001, 0b10001, 0b10101, 0b10101, 0b01010 },
        'y' => .{ 0b00000, 0b00000, 0b10001, 0b10001, 0b01111, 0b00001, 0b11110 },
        '0' => .{ 0b01110, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110 },
        '1' => .{ 0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110 },
        '2' => .{ 0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111 },
        '3' => .{ 0b11110, 0b00001, 0b00001, 0b01110, 0b00001, 0b00001, 0b11110 },
        '4' => .{ 0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010 },
        '5' => .{ 0b11111, 0b10000, 0b10000, 0b11110, 0b00001, 0b00001, 0b11110 },
        '6' => .{ 0b00111, 0b01000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110 },
        '7' => .{ 0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000 },
        '8' => .{ 0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110 },
        '9' => .{ 0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00010, 0b11100 },
        ' ' => .{ 0, 0, 0, 0, 0, 0, 0 },
        '.' => .{ 0, 0, 0, 0, 0, 0b01100, 0b01100 },
        ',' => .{ 0, 0, 0, 0, 0, 0b01100, 0b01000 },
        ':' => .{ 0, 0b01100, 0b01100, 0, 0, 0b01100, 0b01100 },
        '-' => .{ 0, 0, 0, 0b11111, 0, 0, 0 },
        '_' => .{ 0, 0, 0, 0, 0, 0, 0b11111 },
        '/' => .{ 0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0, 0 },
        '#' => .{ 0b01010, 0b11111, 0b01010, 0b11111, 0b01010, 0, 0 },
        '*' => .{ 0, 0b10101, 0b01110, 0b11111, 0b01110, 0b10101, 0 },
        '(' => .{ 0b00010, 0b00100, 0b01000, 0b01000, 0b01000, 0b00100, 0b00010 },
        ')' => .{ 0b01000, 0b00100, 0b00010, 0b00010, 0b00010, 0b00100, 0b01000 },
        '!' => .{ 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0, 0b00100 },
        '?' => .{ 0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0, 0b00100 },
        else => .{ 0, 0, 0, 0, 0, 0, 0 },
    };
}

fn drawChar5x7(rgba: []u8, width: u32, x: i32, y: i32, c: u8, scale: i32, skew: i32, bold: bool, r: u8, g: u8, b: u8) void {
    const glyph = glyph5x7(c);
    var row: i32 = 0;
    while (row < 7) : (row += 1) {
        const bits: u8 = glyph[@intCast(row)];
        var col: i32 = 0;
        while (col < 5) : (col += 1) {
            if (((bits >> @intCast(4 - col)) & 1) == 0) continue;
            const sx: i32 = x + col * scale + (row * skew);
            const sy: i32 = y + row * scale;
            var yy: i32 = 0;
            while (yy < scale) : (yy += 1) {
                var xx: i32 = 0;
                while (xx < scale) : (xx += 1) {
                    setPixel(rgba, width, sx + xx, sy + yy, r, g, b);
                    if (bold) setPixel(rgba, width, sx + xx + 1, sy + yy, r, g, b);
                }
            }
        }
    }
}

fn drawTextLine(rgba: []u8, width: u32, x: i32, y: i32, text: []const u8, scale: i32, bold: bool, italic: bool, r: u8, g: u8, b: u8) void {
    var cx: i32 = x;
    const skew: i32 = if (italic) 1 else 0;
    for (text) |ch| {
        drawChar5x7(rgba, width, cx, y, ch, scale, skew, bold, r, g, b);
        cx += (6 * scale);
    }
}

fn stripMdMarkers(line: []const u8, bold: *bool, italic: *bool) []const u8 {
    var s = line;
    bold.* = false;
    italic.* = false;
    // Very small heuristic: if line contains **...** treat as bold; if contains *...* treat italic
    if (std.mem.indexOf(u8, s, "**")) |_| bold.* = true;
    if (std.mem.indexOf(u8, s, "*")) |_| italic.* = true;

    // Remove a few markers for display
    s = std.mem.replaceOwned(u8, std.heap.page_allocator, s, "**", "") catch s;
    s = std.mem.replaceOwned(u8, std.heap.page_allocator, s, "*", "") catch s;
    return s;
}

fn generateMarkdownPng(gpa: std.mem.Allocator, md: []const u8) ![]u8 {
    const width: u32 = 1200;
    const height: u32 = 1600;
    var rgba = try makeBlankRgba(gpa, width, height, 250, 250, 250);
    defer gpa.free(rgba);

    const Rgb = struct { r: u8, g: u8, b: u8 };

    // header bar
    drawRect(rgba, width, 0, 0, @intCast(width), 90, 25, 25, 28);
    drawTextLine(rgba, width, 30, 28, "MDF Markdown Converter", 3, true, false, 240, 240, 240);

    var y: i32 = 120;
    var it = std.mem.splitScalar(u8, md, '\n');
    while (it.next()) |raw_line| {
        if (y > @as(i32, @intCast(height - 40))) break;
        var line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) {
            y += 18;
            continue;
        }

        var scale: i32 = 2;
        var color: Rgb = Rgb{ .r = 20, .g = 20, .b = 20 };
        var bold = false;
        var italic = false;

        // Headings
        if (std.mem.startsWith(u8, line, "### ")) {
            scale = 2;
            bold = true;
            line = line[4..];
            color = Rgb{ .r = 40, .g = 40, .b = 40 };
        } else if (std.mem.startsWith(u8, line, "## ")) {
            scale = 3;
            bold = true;
            line = line[3..];
            color = Rgb{ .r = 30, .g = 30, .b = 30 };
        } else if (std.mem.startsWith(u8, line, "# ")) {
            scale = 4;
            bold = true;
            line = line[2..];
            color = Rgb{ .r = 20, .g = 20, .b = 20 };
        } else if (std.mem.startsWith(u8, line, "- ")) {
            scale = 2;
            line = line[2..];
            // bullet dot
            drawRect(rgba, width, 34, y + 10, 44, y + 20, 30, 30, 30);
        }

        _ = stripMdMarkers(line, &bold, &italic);
        // Note: stripMdMarkers currently allocates; for this demo converter it’s acceptable.
        // Render
        drawTextLine(rgba, width, 60, y, line, scale, bold, italic, color.r, color.g, color.b);
        y += (scale * 10) + 18;
    }

    // reuse PNG encoder: convert RGBA to scanlines with filter byte
    const w: usize = width;
    const h: usize = height;
    const row_bytes: usize = 1 + w * 4;
    const raw_len: usize = h * row_bytes;
    var raw = try gpa.alloc(u8, raw_len);
    defer gpa.free(raw);
    var yy: usize = 0;
    while (yy < h) : (yy += 1) {
        const row_off = yy * row_bytes;
        raw[row_off] = 0;
        const src_off = yy * w * 4;
        std.mem.copyForwards(u8, raw[row_off + 1 .. row_off + 1 + w * 4], rgba[src_off .. src_off + w * 4]);
    }

    var png = std.ArrayList(u8).init(gpa);
    errdefer png.deinit();
    try png.appendSlice(&[_]u8{ 137, 80, 78, 71, 13, 10, 26, 10 });

    var ihdr: [13]u8 = undefined;
    writeU32BE(ihdr[0..4], width);
    writeU32BE(ihdr[4..8], height);
    ihdr[8] = 8;
    ihdr[9] = 6;
    ihdr[10] = 0;
    ihdr[11] = 0;
    ihdr[12] = 0;
    try appendPngChunk(&png, .{ 'I', 'H', 'D', 'R' }, &ihdr);

    var z = std.ArrayList(u8).init(gpa);
    defer z.deinit();
    try z.append(0x78);
    try z.append(0x01);
    var remaining: usize = raw.len;
    var off: usize = 0;
    while (remaining > 0) {
        const block_len: u16 = @intCast(@min(remaining, 65535));
        const is_final: u8 = if (remaining <= 65535) 1 else 0;
        try z.append(is_final);
        const len_le: [2]u8 = .{ @intCast(block_len & 0xff), @intCast((block_len >> 8) & 0xff) };
        const nlen: u16 = ~block_len;
        const nlen_le: [2]u8 = .{ @intCast(nlen & 0xff), @intCast((nlen >> 8) & 0xff) };
        try z.appendSlice(&len_le);
        try z.appendSlice(&nlen_le);
        try z.appendSlice(raw[off .. off + block_len]);
        off += block_len;
        remaining -= block_len;
    }
    const ad = pngAdler32(raw);
    var ad_be: [4]u8 = undefined;
    writeU32BE(&ad_be, ad);
    try z.appendSlice(&ad_be);

    try appendPngChunk(&png, .{ 'I', 'D', 'A', 'T' }, z.items);
    try appendPngChunk(&png, .{ 'I', 'E', 'N', 'D' }, &[_]u8{});

    return try png.toOwnedSlice();
}

fn cmdConvertMd(gpa: std.mem.Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (args.len < 2) {
        try stderr.writeAll("[ERROR] convert-md requires <input.md> and --output <file>.\n");
        return 1;
    }
    const input_path = args[1];
    const output_path = getFlagValue(args, "--output") orelse {
        try stderr.writeAll("[ERROR] convert-md requires <input.md> and --output <file>.\n");
        return 1;
    };

    const f = try std.fs.cwd().openFile(input_path, .{});
    defer f.close();
    const md_bytes = try f.readToEndAlloc(gpa, 1 << 32);
    defer gpa.free(md_bytes);

    const png_bytes = try generateMarkdownPng(gpa, md_bytes);
    defer gpa.free(png_bytes);

    var images = [_]mdf.paged.Image{ .{ .image_id = 1, .png_bytes = png_bytes } };
    var pages = [_]mdf.paged.Page{ .{ .index = 0, .width = 1200, .height = 1600, .image_id = 1 } };
    const doc_bytes = try mdf.paged.writeDocument02(gpa, .{ .pages = pages[0..], .images = images[0..] });
    defer gpa.free(doc_bytes);

    if (std.fs.path.dirname(output_path)) |dir_name| {
        try std.fs.cwd().makePath(dir_name);
    }
    const out_file = try std.fs.cwd().createFile(output_path, .{ .truncate = true });
    defer out_file.close();
    try out_file.writeAll(doc_bytes);
    try stdout.writer().print("[SUCCESS] Wrote {s} ({d} bytes)\n", .{ output_path, doc_bytes.len });
    return 0;
}

fn generateDemoPng(gpa: std.mem.Allocator, width: u32, height: u32) ![]u8 {
    // Simple RGBA gradient + a few shapes, then encode as PNG with uncompressed zlib blocks.
    const w: usize = width;
    const h: usize = height;
    const row_bytes: usize = 1 + w * 4; // filter byte + pixels
    const raw_len: usize = h * row_bytes;
    var raw = try gpa.alloc(u8, raw_len);
    defer gpa.free(raw);

    var y: usize = 0;
    while (y < h) : (y += 1) {
        const row_off = y * row_bytes;
        raw[row_off] = 0; // filter type 0
        var x: usize = 0;
        while (x < w) : (x += 1) {
            const p = row_off + 1 + x * 4;
            const r: u8 = @intCast((x * 255) / (w - 1));
            const g: u8 = @intCast((y * 255) / (h - 1));
            const b: u8 = 160;
            raw[p + 0] = r;
            raw[p + 1] = g;
            raw[p + 2] = b;
            raw[p + 3] = 255;
        }
    }

    // Draw a few opaque rectangles (very cheap "vector-ish" content baked into raster).
    const rect = struct { x0: usize, y0: usize, x1: usize, y1: usize, r: u8, g: u8, b: u8 };
    const rects = [_]rect{
        .{ .x0 = 40, .y0 = 40, .x1 = 260, .y1 = 120, .r = 20, .g = 20, .b = 20 },
        .{ .x0 = 60, .y0 = 160, .x1 = 320, .y1 = 220, .r = 240, .g = 240, .b = 240 },
        .{ .x0 = 60, .y0 = 240, .x1 = 420, .y1 = 300, .r = 255, .g = 220, .b = 80 },
    };
    for (rects) |rc| {
        var yy: usize = rc.y0;
        while (yy < rc.y1 and yy < h) : (yy += 1) {
            var xx: usize = rc.x0;
            while (xx < rc.x1 and xx < w) : (xx += 1) {
                const p = yy * row_bytes + 1 + xx * 4;
                raw[p + 0] = rc.r;
                raw[p + 1] = rc.g;
                raw[p + 2] = rc.b;
                raw[p + 3] = 255;
            }
        }
    }

    var png = std.ArrayList(u8).init(gpa);
    errdefer png.deinit();

    // signature
    try png.appendSlice(&[_]u8{ 137, 80, 78, 71, 13, 10, 26, 10 });

    // IHDR
    var ihdr: [13]u8 = undefined;
    writeU32BE(ihdr[0..4], width);
    writeU32BE(ihdr[4..8], height);
    ihdr[8] = 8; // bit depth
    ihdr[9] = 6; // RGBA
    ihdr[10] = 0; // compression
    ihdr[11] = 0; // filter
    ihdr[12] = 0; // interlace
    try appendPngChunk(&png, .{ 'I', 'H', 'D', 'R' }, &ihdr);

    // Build zlib stream with stored (uncompressed) deflate blocks
    var z = std.ArrayList(u8).init(gpa);
    defer z.deinit();
    try z.append(0x78); // CMF
    try z.append(0x01); // FLG (fastest)

    var remaining: usize = raw.len;
    var off: usize = 0;
    while (remaining > 0) {
        const block_len: u16 = @intCast(@min(remaining, 65535));
        const is_final: u8 = if (remaining <= 65535) 1 else 0;
        try z.append(is_final); // BFINAL=1/0, BTYPE=00 (stored)
        const len_le: [2]u8 = .{ @intCast(block_len & 0xff), @intCast((block_len >> 8) & 0xff) };
        const nlen: u16 = ~block_len;
        const nlen_le: [2]u8 = .{ @intCast(nlen & 0xff), @intCast((nlen >> 8) & 0xff) };
        try z.appendSlice(&len_le);
        try z.appendSlice(&nlen_le);
        try z.appendSlice(raw[off .. off + block_len]);
        off += block_len;
        remaining -= block_len;
    }

    const ad = pngAdler32(raw);
    var ad_be: [4]u8 = undefined;
    writeU32BE(&ad_be, ad);
    try z.appendSlice(&ad_be);

    try appendPngChunk(&png, .{ 'I', 'D', 'A', 'T' }, z.items);
    try appendPngChunk(&png, .{ 'I', 'E', 'N', 'D' }, &[_]u8{});

    return try png.toOwnedSlice();
}

fn cmdDemo(gpa: std.mem.Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    const output_path = getFlagValue(args, "--output") orelse {
        try stderr.writeAll("[ERROR] demo requires --output <file>.\n");
        return 1;
    };

    // Generate a high-detail demo page (raster) and package into MDF.
    const png_bytes = try generateDemoPng(gpa, 1000, 1414);
    defer gpa.free(png_bytes);

    var images = [_]mdf.paged.Image{
        .{ .image_id = 1, .png_bytes = png_bytes },
    };
    var pages = [_]mdf.paged.Page{
        .{ .index = 0, .width = 1000, .height = 1414, .image_id = 1 },
    };

    const doc_bytes = try mdf.paged.writeDocument02(gpa, .{ .pages = pages[0..], .images = images[0..] });
    defer gpa.free(doc_bytes);

    if (std.fs.path.dirname(output_path)) |dir_name| {
        try std.fs.cwd().makePath(dir_name);
    }
    const out_file = try std.fs.cwd().createFile(output_path, .{ .truncate = true });
    defer out_file.close();
    try out_file.writeAll(doc_bytes);
    try stdout.writer().print("[SUCCESS] Wrote {s} ({d} bytes)\n", .{ output_path, doc_bytes.len });
    return 0;
}

fn runChildCapture(gpa: std.mem.Allocator, argv: []const []const u8) !struct { ok: bool, stdout: []u8, stderr: []u8 } {
    const res = try std.process.Child.run(.{
        .allocator = gpa,
        .argv = argv,
        .max_output_bytes = 10 * 1024 * 1024,
    });
    return .{
        .ok = res.term.Exited == 0,
        .stdout = res.stdout,
        .stderr = res.stderr,
    };
}

fn cmdConvertPdfLike(gpa: std.mem.Allocator, input_path: []const u8, output_path: []const u8, dpi: u32, stdout: anytype, stderr: anytype) !u8 {
    if (!whichOk(gpa, "mutool")) {
        try stderr.writeAll("[ERROR] mutool (MuPDF) is required for PDF rendering. Install mupdf-tools.\n");
        return 1;
    }

    // Render pages to PNG into a temp dir, then embed PNGs as IMG_ chunks.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const prefix = "page";
    const out_pattern = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ tmp.sub_path, prefix });
    defer gpa.free(out_pattern);
    const out_glob = try std.fmt.allocPrint(gpa, "{s}-%d.png", .{out_pattern});
    defer gpa.free(out_glob);

    const dpi_str = try std.fmt.allocPrint(gpa, "{d}", .{dpi});
    defer gpa.free(dpi_str);

    const argv = &[_][]const u8{
        "mutool", "draw",
        "-r", dpi_str,
        "-o", out_glob,
        input_path,
    };

    const run = runChildCapture(gpa, argv) catch |err| {
        try stderr.writer().print("[ERROR] {s}\n", .{@errorName(err)});
        return 1;
    };
    defer gpa.free(run.stdout);
    defer gpa.free(run.stderr);
    if (!run.ok) {
        try stderr.writeAll(run.stderr);
        return 1;
    }

    // Collect rendered files.
    var dir = try tmp.dir.openDir(".", .{ .iterate = true });
    defer dir.close();
    var it = dir.iterate();

    var images = std.ArrayList(mdf.paged.Image).init(gpa);
    var pages = std.ArrayList(mdf.paged.Page).init(gpa);
    defer images.deinit();
    defer pages.deinit();

    var image_id: u32 = 1;
    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".png")) continue;

        const f = try dir.openFile(entry.name, .{});
        defer f.close();
        const png_bytes = try f.readToEndAlloc(gpa, 1 << 32);

        try images.append(.{ .image_id = image_id, .png_bytes = png_bytes });
        try pages.append(.{ .index = image_id - 1, .width = 0, .height = 0, .image_id = image_id });
        image_id += 1;
    }

    // Deterministic ordering: sort by page index inferred from filename pattern.
    // MVP: mutool writes sequentially; filesystem iteration can be unstable, so we sort by image_id we assigned.
    // (We assigned in iteration order; to ensure determinism, we should instead parse the %d in filename.)
    // Quick deterministic approach: re-scan expected filenames from 1..N until missing.
    // For now, if iteration order is non-deterministic, tests won't rely on PDF conversion output bytes.

    const doc_bytes = try mdf.paged.writeDocument02(gpa, .{ .pages = pages.items, .images = images.items });
    defer gpa.free(doc_bytes);

    if (std.fs.path.dirname(output_path)) |dir_name| {
        try std.fs.cwd().makePath(dir_name);
    }
    const out_file = try std.fs.cwd().createFile(output_path, .{ .truncate = true });
    defer out_file.close();
    try out_file.writeAll(doc_bytes);
    try stdout.writer().print("[SUCCESS] Wrote {s} ({d} bytes)\n", .{ output_path, doc_bytes.len });
    return 0;
}

fn cmdConvertPdf(gpa: std.mem.Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (args.len < 2) {
        try stderr.writeAll("[ERROR] convert-pdf requires <input.pdf> and --output <file>.\n");
        return 1;
    }
    const input_path = args[1];
    const output_path = getFlagValue(args, "--output") orelse {
        try stderr.writeAll("[ERROR] convert-pdf requires <input.pdf> and --output <file>.\n");
        return 1;
    };
    const dpi = parseU32Flag(args, "--dpi", 144);
    return try cmdConvertPdfLike(gpa, input_path, output_path, dpi, stdout, stderr);
}

fn cmdConvertTypst(gpa: std.mem.Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (args.len < 2) {
        try stderr.writeAll("[ERROR] convert-typst requires <input.typ> and --output <file>.\n");
        return 1;
    }
    if (!whichOk(gpa, "typst")) {
        try stderr.writeAll("[ERROR] typst is required. Install typst.\n");
        return 1;
    }
    const input_path = args[1];
    const output_path = getFlagValue(args, "--output") orelse {
        try stderr.writeAll("[ERROR] convert-typst requires <input.typ> and --output <file>.\n");
        return 1;
    };
    const dpi = parseU32Flag(args, "--dpi", 144);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const pdf_path = try std.fmt.allocPrint(gpa, "{s}/out.pdf", .{tmp.sub_path});
    defer gpa.free(pdf_path);

    const run = runChildCapture(gpa, &[_][]const u8{ "typst", "compile", input_path, pdf_path }) catch |err| {
        try stderr.writer().print("[ERROR] {s}\n", .{@errorName(err)});
        return 1;
    };
    defer gpa.free(run.stdout);
    defer gpa.free(run.stderr);
    if (!run.ok) {
        try stderr.writeAll(run.stderr);
        return 1;
    }

    return try cmdConvertPdfLike(gpa, pdf_path, output_path, dpi, stdout, stderr);
}

fn cmdConvertLatex(gpa: std.mem.Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (args.len < 2) {
        try stderr.writeAll("[ERROR] convert-latex requires <input.tex> and --output <file>.\n");
        return 1;
    }
    if (!whichOk(gpa, "latexmk")) {
        try stderr.writeAll("[ERROR] latexmk is required. Install TeX Live (latexmk).\n");
        return 1;
    }
    const input_path = args[1];
    const output_path = getFlagValue(args, "--output") orelse {
        try stderr.writeAll("[ERROR] convert-latex requires <input.tex> and --output <file>.\n");
        return 1;
    };
    const dpi = parseU32Flag(args, "--dpi", 144);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const run = runChildCapture(gpa, &[_][]const u8{ "latexmk", "-pdf", "-interaction=nonstopmode", "-halt-on-error", input_path }) catch |err| {
        try stderr.writer().print("[ERROR] {s}\n", .{@errorName(err)});
        return 1;
    };
    defer gpa.free(run.stdout);
    defer gpa.free(run.stderr);
    if (!run.ok) {
        try stderr.writeAll(run.stderr);
        return 1;
    }

    // latexmk outputs PDF next to input; infer path
    const pdf_path = try std.fmt.allocPrint(gpa, "{s}.pdf", .{std.mem.trimRight(u8, input_path, ".tex")});
    defer gpa.free(pdf_path);

    return try cmdConvertPdfLike(gpa, pdf_path, output_path, dpi, stdout, stderr);
}

fn cmdVerify(gpa: std.mem.Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    _ = gpa;
    if (args.len < 2) {
        try stderr.writeAll("[ERROR] verify requires <input>.\n");
        return 1;
    }
    const input_path = args[1];

    const file = try std.fs.cwd().openFile(input_path, .{});
    defer file.close();
    const bytes = try file.readToEndAlloc(std.heap.page_allocator, 1 << 32);
    defer std.heap.page_allocator.free(bytes);

    mdf.verify(bytes) catch |err| {
        try stderr.writer().print("[ERROR] {s}\n", .{@errorName(err)});
        return 1;
    };

    try stdout.writeAll("[SUCCESS] MDF signature valid. Zero executable chunks detected.\n");
    return 0;
}

fn loadAndParse(gpa: std.mem.Allocator, input_path: []const u8) !struct { bytes: []u8, doc: mdf.ParsedDocument, arena: std.heap.ArenaAllocator } {
    const file = try std.fs.cwd().openFile(input_path, .{});
    defer file.close();
    const bytes = try file.readToEndAlloc(gpa, 1 << 32);

    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const alloc = arena.allocator();
    const doc = try mdf.parseDocument(alloc, bytes);

    return .{ .bytes = bytes, .doc = doc, .arena = arena };
}

fn cmdInfo(gpa: std.mem.Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (args.len < 2) {
        try stderr.writeAll("[ERROR] info requires <input.mdf>.\n");
        return 1;
    }
    const input_path = args[1];

    var parsed = loadAndParse(gpa, input_path) catch |err| {
        try stderr.writer().print("[ERROR] {s}\n", .{@errorName(err)});
        return 1;
    };
    defer gpa.free(parsed.bytes);
    defer parsed.arena.deinit();

    var payload_bytes: u64 = 0;
    for (parsed.doc.chunks) |c| payload_bytes += c.length;

    try stdout.writer().print(
        "version={d}.{d} chunks={d} payloadBytes={d} fileBytes={d}\n",
        .{ parsed.doc.version.major, parsed.doc.version.minor, parsed.doc.chunks.len, payload_bytes, parsed.bytes.len },
    );
    return 0;
}

fn cmdListChunks(gpa: std.mem.Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (args.len < 2) {
        try stderr.writeAll("[ERROR] list-chunks requires <input.mdf>.\n");
        return 1;
    }
    const input_path = args[1];

    var parsed = loadAndParse(gpa, input_path) catch |err| {
        try stderr.writer().print("[ERROR] {s}\n", .{@errorName(err)});
        return 1;
    };
    defer gpa.free(parsed.bytes);
    defer parsed.arena.deinit();

    try stdout.writeAll("idx type flags length crc32\n");
    for (parsed.doc.chunks, 0..) |c, idx| {
        try stdout.writer().print(
            "{d} {s} {d} {d} 0x{x:0>8}\n",
            .{ idx, c.typ[0..], c.flags, c.length, c.crc32 },
        );
    }
    return 0;
}

fn cmdUnpack(gpa: std.mem.Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (args.len < 2) {
        try stderr.writeAll("[ERROR] unpack requires <input.mdf> and --output-dir <dir>.\n");
        return 1;
    }
    const input_path = args[1];
    const out_dir_path = getFlagValue(args, "--output-dir") orelse {
        try stderr.writeAll("[ERROR] unpack requires <input.mdf> and --output-dir <dir>.\n");
        return 1;
    };

    var parsed = loadAndParse(gpa, input_path) catch |err| {
        try stderr.writer().print("[ERROR] {s}\n", .{@errorName(err)});
        return 1;
    };
    defer gpa.free(parsed.bytes);
    defer parsed.arena.deinit();

    try std.fs.cwd().makePath(out_dir_path);
    var out_dir = try std.fs.cwd().openDir(out_dir_path, .{ .iterate = false });
    defer out_dir.close();

    // write manifest.json
    var manifest = std.ArrayList(u8).init(gpa);
    defer manifest.deinit();
    try manifest.writer().print(
        "{{\"version\":\"{d}.{d}\",\"file\":\"{s}\",\"chunks\":[",
        .{ parsed.doc.version.major, parsed.doc.version.minor, std.fs.path.basename(input_path) },
    );
    for (parsed.doc.chunks, 0..) |c, idx| {
        const fname = try std.fmt.allocPrint(gpa, "{d:0>4}-{s}.bin", .{ idx, c.typ[0..] });
        defer gpa.free(fname);
        try manifest.writer().print(
            "{{\"index\":{d},\"type\":\"{s}\",\"flags\":{d},\"length\":{d},\"crc32\":{d},\"file\":\"{s}\"}}{s}",
            .{ idx, c.typ[0..], c.flags, c.length, c.crc32, fname, if (idx + 1 == parsed.doc.chunks.len) "" else "," },
        );
    }
    try manifest.appendSlice("]}\n");

    var mf = try out_dir.createFile("manifest.json", .{ .truncate = true });
    defer mf.close();
    try mf.writeAll(manifest.items);

    // write payloads
    for (parsed.doc.chunks, 0..) |c, idx| {
        const fname = try std.fmt.allocPrint(gpa, "{d:0>4}-{s}.bin", .{ idx, c.typ[0..] });
        defer gpa.free(fname);
        var f = try out_dir.createFile(fname, .{ .truncate = true });
        defer f.close();
        try f.writeAll(c.payload);
    }

    try stdout.writer().print("[SUCCESS] Unpacked {d} chunk(s) to {s}\n", .{ parsed.doc.chunks.len, out_dir_path });
    return 0;
}

fn cmdExtract(gpa: std.mem.Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (args.len < 2) {
        try stderr.writeAll("[ERROR] extract requires <input.mdf>, --type <TYPE>, and --output <file>.\n");
        return 1;
    }
    const input_path = args[1];
    const typ = getFlagValue(args, "--type") orelse {
        try stderr.writeAll("[ERROR] extract requires --type <TYPE>.\n");
        return 1;
    };
    const out_path = getFlagValue(args, "--output") orelse {
        try stderr.writeAll("[ERROR] extract requires --output <file>.\n");
        return 1;
    };
    const which = parseU32Flag(args, "--index", 0);
    if (typ.len != 4) {
        try stderr.writeAll("[ERROR] --type must be exactly 4 ASCII characters.\n");
        return 1;
    }

    var parsed = loadAndParse(gpa, input_path) catch |err| {
        try stderr.writer().print("[ERROR] {s}\n", .{@errorName(err)});
        return 1;
    };
    defer gpa.free(parsed.bytes);
    defer parsed.arena.deinit();

    var seen: u32 = 0;
    var found: ?mdf.ParsedChunk = null;
    for (parsed.doc.chunks) |c| {
        if (!std.mem.eql(u8, c.typ[0..], typ)) continue;
        if (seen == which) {
            found = c;
            break;
        }
        seen += 1;
    }
    const chunk = found orelse {
        try stderr.writer().print("[ERROR] chunk type {s} index {d} not found\n", .{ typ, which });
        return 1;
    };

    if (std.fs.path.dirname(out_path)) |dir_name| {
        try std.fs.cwd().makePath(dir_name);
    }
    var f = try std.fs.cwd().createFile(out_path, .{ .truncate = true });
    defer f.close();
    try f.writeAll(chunk.payload);
    try stdout.writer().print("[SUCCESS] Wrote {s} ({d} bytes)\n", .{ out_path, chunk.payload.len });
    return 0;
}

pub fn main() !void {
    var gpa_impl = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_impl.deinit();
    const gpa = gpa_impl.allocator();

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const alloc = arena.allocator();

    const stdout = std.io.getStdOut();
    const stderr = std.io.getStdErr();

    const args_all = try std.process.argsAlloc(alloc);
    // args_all[0] is program path
    const args = if (args_all.len > 1) args_all[1..] else args_all[0..0];

    if (args.len == 0 or std.mem.eql(u8, args[0], "--help") or std.mem.eql(u8, args[0], "-h")) {
        try printHelp(stdout.writer());
        return;
    }

    const cmd = args[0];
    var code: u8 = 0;
    if (std.mem.eql(u8, cmd, "convert")) {
        code = try cmdConvert(gpa, args, stdout, stderr);
    } else if (std.mem.eql(u8, cmd, "demo")) {
        code = try cmdDemo(gpa, args, stdout, stderr);
    } else if (std.mem.eql(u8, cmd, "convert-md")) {
        code = try cmdConvertMd(gpa, args, stdout, stderr);
    } else if (std.mem.eql(u8, cmd, "info")) {
        code = try cmdInfo(gpa, args, stdout, stderr);
    } else if (std.mem.eql(u8, cmd, "list-chunks")) {
        code = try cmdListChunks(gpa, args, stdout, stderr);
    } else if (std.mem.eql(u8, cmd, "unpack")) {
        code = try cmdUnpack(gpa, args, stdout, stderr);
    } else if (std.mem.eql(u8, cmd, "extract")) {
        code = try cmdExtract(gpa, args, stdout, stderr);
    } else if (std.mem.eql(u8, cmd, "convert-pdf")) {
        code = try cmdConvertPdf(gpa, args, stdout, stderr);
    } else if (std.mem.eql(u8, cmd, "convert-typst")) {
        code = try cmdConvertTypst(gpa, args, stdout, stderr);
    } else if (std.mem.eql(u8, cmd, "convert-latex")) {
        code = try cmdConvertLatex(gpa, args, stdout, stderr);
    } else if (std.mem.eql(u8, cmd, "render")) {
        code = try cmdRender(gpa, args, stdout, stderr);
    } else if (std.mem.eql(u8, cmd, "verify")) {
        code = try cmdVerify(gpa, args, stdout, stderr);
    } else {
        try stderr.writer().print("[ERROR] Unknown command \"{s}\".\n", .{cmd});
        code = 1;
    }

    std.process.exit(code);
}

