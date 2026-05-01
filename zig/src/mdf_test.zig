const std = @import("std");
const mdf = @import("mdf");

test "crc32 matches known value" {
    const bytes = "hello world";
    // Same polynomial/table as common CRC32 (IEEE).
    try std.testing.expectEqual(@as(u32, 0x0D4A1185), mdf.crc32(bytes));
}

test "writeDocument + parseDocument roundtrip" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const meta = "{\n  \"k\": \"v\"\n}";
    const data = "payload";

    const chunks = [_]mdf.Chunk{
        .{ .typ = .{ 'M', 'E', 'T', 'A' }, .flags = 0, .payload = meta },
        .{ .typ = .{ 'D', 'A', 'T', 'A' }, .flags = 0, .payload = data },
    };

    const doc_bytes = try mdf.writeDocument(alloc, .{ .major = 0, .minor = 1 }, &chunks);

    const parsed = try mdf.parseDocument(alloc, doc_bytes);
    try std.testing.expectEqual(@as(u8, 0), parsed.version.major);
    try std.testing.expectEqual(@as(u8, 1), parsed.version.minor);
    try std.testing.expectEqual(@as(usize, 2), parsed.chunks.len);
    try std.testing.expect(std.mem.eql(u8, &parsed.chunks[0].typ, "META"));
    try std.testing.expect(std.mem.eql(u8, parsed.chunks[0].payload, meta));
    try std.testing.expect(std.mem.eql(u8, &parsed.chunks[1].typ, "DATA"));
    try std.testing.expect(std.mem.eql(u8, parsed.chunks[1].payload, data));
}

test "verify rejects forbidden chunk types" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const chunks = [_]mdf.Chunk{
        .{ .typ = .{ 'E', 'X', 'E', 'C' }, .flags = 0, .payload = "nope" },
    };
    const doc_bytes = try mdf.writeDocument(alloc, .{ .major = 0, .minor = 1 }, &chunks);

    try std.testing.expectError(mdf.VerifyError.ExecutableChunkType, mdf.verify(doc_bytes));
}

