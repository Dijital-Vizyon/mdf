const std = @import("std");
const mdf = @import("mdf");
const png = @import("png.zig");

const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

const AppError = error{
    SdlInitFailed,
    WindowFailed,
    RendererFailed,
    TextureFailed,
    NoPagedDoc,
};

fn sdlErr() []const u8 {
    return std.mem.span(c.SDL_GetError());
}

const Loaded = struct {
    path: []u8,
    bytes: []u8,
    doc: mdf.ParsedDocument,
    arena: std.heap.ArenaAllocator,

    pages: []mdf.paged.Page,
    images: []mdf.paged.Image,
};

fn freeLoaded(gpa: std.mem.Allocator, loaded: *Loaded) void {
    gpa.free(loaded.path);
    gpa.free(loaded.bytes);
    loaded.arena.deinit();
    // pages/images live in arena slices
}

fn loadPaged(gpa: std.mem.Allocator, path: []const u8) !Loaded {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const bytes = try file.readToEndAlloc(gpa, 1 << 32);
    errdefer gpa.free(bytes);

    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const alloc = arena.allocator();

    const doc = try mdf.parseDocument(alloc, bytes);
    const paged = try mdf.paged.parseDocument02(alloc, bytes);

    // Copy pages/images slices into stable arena-owned slices for convenience.
    const pages = try alloc.alloc(mdf.paged.Page, paged.pages.len);
    std.mem.copyForwards(mdf.paged.Page, pages, paged.pages);
    const images = try alloc.alloc(mdf.paged.Image, paged.images.len);
    std.mem.copyForwards(mdf.paged.Image, images, paged.images);

    return .{
        .path = try gpa.dupe(u8, path),
        .bytes = bytes,
        .doc = doc,
        .arena = arena,
        .pages = pages,
        .images = images,
    };
}

fn findImageBytes(loaded: *const Loaded, image_id: u32) ?[]const u8 {
    for (loaded.images) |img| {
        if (img.image_id == image_id) return img.png_bytes;
    }
    return null;
}

fn setWindowTitle(window: *c.SDL_Window, loaded: *const Loaded, page_idx: usize) void {
    const title = std.fmt.allocPrint(std.heap.page_allocator, "MDF Reader — {s} (page {d}/{d})", .{
        std.fs.path.basename(loaded.path),
        page_idx + 1,
        loaded.pages.len,
    }) catch return;
    defer std.heap.page_allocator.free(title);
    _ = c.SDL_SetWindowTitle(window, title.ptr);
}

fn makeTextureFromPng(
    renderer: *c.SDL_Renderer,
    decoded: png.Decoded,
) !*c.SDL_Texture {
    const tex = c.SDL_CreateTexture(renderer, c.SDL_PIXELFORMAT_RGBA32, c.SDL_TEXTUREACCESS_STATIC, @intCast(decoded.width), @intCast(decoded.height)) orelse {
        return AppError.TextureFailed;
    };
    if (c.SDL_UpdateTexture(tex, null, decoded.rgba.ptr, @intCast(decoded.width * 4)) != 0) {
        c.SDL_DestroyTexture(tex);
        return AppError.TextureFailed;
    }
    return tex;
}

pub fn main() !void {
    var gpa_impl = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_impl.deinit();
    const gpa = gpa_impl.allocator();

    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        std.debug.print("SDL_Init failed: {s}\n", .{sdlErr()});
        return AppError.SdlInitFailed;
    }
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow(
        "MDF Reader",
        c.SDL_WINDOWPOS_CENTERED,
        c.SDL_WINDOWPOS_CENTERED,
        1100,
        800,
        c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_ALLOW_HIGHDPI,
    ) orelse {
        std.debug.print("SDL_CreateWindow failed: {s}\n", .{sdlErr()});
        return AppError.WindowFailed;
    };
    defer c.SDL_DestroyWindow(window);

    const renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC) orelse {
        std.debug.print("SDL_CreateRenderer failed: {s}\n", .{sdlErr()});
        return AppError.RendererFailed;
    };
    defer c.SDL_DestroyRenderer(renderer);

    // Load initial file if provided
    var loaded_opt: ?Loaded = null;
    defer if (loaded_opt) |*l| freeLoaded(gpa, l);

    var page_idx: usize = 0;
    var tex: ?*c.SDL_Texture = null;
    defer if (tex) |t| c.SDL_DestroyTexture(t);
    var tex_w: i32 = 0;
    var tex_h: i32 = 0;

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);
    if (args.len >= 2) {
        loaded_opt = loadPaged(gpa, args[1]) catch |err| blk: {
            std.debug.print("Failed to open {s}: {s}\n", .{ args[1], @errorName(err) });
            break :blk null;
        };
    }

    const reloadPageTexture = struct {
        fn run(gpa_: std.mem.Allocator, renderer_: *c.SDL_Renderer, window_: *c.SDL_Window, l: *Loaded, idx: usize, tex_ptr: *?*c.SDL_Texture, tw: *i32, th: *i32) void {
            if (tex_ptr.*) |t| c.SDL_DestroyTexture(t);
            tex_ptr.* = null;
            tw.* = 0;
            th.* = 0;

            const p = if (idx < l.pages.len) l.pages[idx] else return;
            const img_bytes = findImageBytes(l, p.image_id) orelse return;
            const decoded = png.decode(gpa_, img_bytes) catch return;
            defer gpa_.free(decoded.rgba);

            const t = makeTextureFromPng(renderer_, decoded) catch return;
            tex_ptr.* = t;
            tw.* = @intCast(decoded.width);
            th.* = @intCast(decoded.height);
            setWindowTitle(window_, l, idx);
        }
    }.run;

    if (loaded_opt) |*l| {
        reloadPageTexture(gpa, renderer, window, l, page_idx, &tex, &tex_w, &tex_h);
    }

    var running = true;
    while (running) {
        var ev: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&ev) != 0) {
            switch (ev.type) {
                c.SDL_QUIT => running = false,
                c.SDL_KEYDOWN => {
                    const key = ev.key.keysym.sym;
                    if (key == c.SDLK_ESCAPE) running = false;
                    if (loaded_opt) |*l| {
                        if (key == c.SDLK_RIGHT and page_idx + 1 < l.pages.len) {
                            page_idx += 1;
                            reloadPageTexture(gpa, renderer, window, l, page_idx, &tex, &tex_w, &tex_h);
                        } else if (key == c.SDLK_LEFT and page_idx > 0) {
                            page_idx -= 1;
                            reloadPageTexture(gpa, renderer, window, l, page_idx, &tex, &tex_w, &tex_h);
                        }
                    }
                },
                c.SDL_DROPFILE => {
                    const dropped = ev.drop.file;
                    if (dropped != null) {
                        const dropped_path = std.mem.span(dropped);
                        defer c.SDL_free(dropped);

                        if (loaded_opt) |*old| freeLoaded(gpa, old);
                        loaded_opt = loadPaged(gpa, dropped_path) catch |err| blk: {
                            std.debug.print("Failed to open {s}: {s}\n", .{ dropped_path, @errorName(err) });
                            break :blk null;
                        };
                        page_idx = 0;
                        if (loaded_opt) |*l| reloadPageTexture(gpa, renderer, window, l, page_idx, &tex, &tex_w, &tex_h);
                    }
                },
                else => {},
            }
        }

        _ = c.SDL_SetRenderDrawColor(renderer, 18, 18, 20, 255);
        _ = c.SDL_RenderClear(renderer);

        if (tex) |t| {
            var ww: i32 = 0;
            var wh: i32 = 0;
            _ = c.SDL_GetRendererOutputSize(renderer, &ww, &wh);

            // Fit image into window while preserving aspect ratio.
            const iw: f32 = @floatFromInt(tex_w);
            const ih: f32 = @floatFromInt(tex_h);
            const rw: f32 = @floatFromInt(ww);
            const rh: f32 = @floatFromInt(wh);
            const scale = @min(rw / iw, rh / ih);
            const dw: i32 = @intFromFloat(iw * scale);
            const dh: i32 = @intFromFloat(ih * scale);
            const dx: i32 = @divTrunc(ww - dw, 2);
            const dy: i32 = @divTrunc(wh - dh, 2);

            var dst = c.SDL_Rect{ .x = dx, .y = dy, .w = dw, .h = dh };
            _ = c.SDL_RenderCopy(renderer, t, null, &dst);
        }

        c.SDL_RenderPresent(renderer);
    }
}

