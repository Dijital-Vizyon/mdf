import { createHash } from "node:crypto";
import { crc32 } from "./crc32.js";

const MAGIC = Buffer.from("MDF1", "ascii");
const HEADER_SIZE = 16;
const CHUNK_HEADER_SIZE = 16;
const FORBIDDEN_CHUNK_TYPES = new Set(["EXEC", "JS__", "CODE", "XCMD"]);

function assertChunkType(type) {
  if (!/^[A-Z0-9_]{4}$/.test(type)) {
    throw new Error(`Invalid chunk type "${type}". Expected 4 ASCII uppercase characters.`);
  }
}

function toUInt32(value, label) {
  if (!Number.isInteger(value) || value < 0 || value > 0xffffffff) {
    throw new Error(`${label} must fit in an unsigned 32-bit integer.`);
  }
  return value;
}

function makeChunk(type, payload, flags = 0) {
  assertChunkType(type);
  const data = Buffer.isBuffer(payload) ? payload : Buffer.from(payload);
  return {
    type,
    flags: toUInt32(flags, "Chunk flags"),
    length: toUInt32(data.length, "Chunk length"),
    crc32: crc32(data),
    payload: data
  };
}

export function buildMdfDocument({
  sourcePath,
  sourceBytes,
  optimizeRaster = false,
  quality = null,
  stampTime = false
}) {
  const sha256 = createHash("sha256").update(sourceBytes).digest("hex");
  const metaObject = {
    sourcePath,
    sourceSize: sourceBytes.length,
    sourceSha256: sha256,
    optimizeRaster,
    quality,
    createdWith: "mdf-cli/0.1.0-alpha"
  };

  if (stampTime) {
    metaObject.createdAt = new Date().toISOString();
  }

  const metadata = Buffer.from(JSON.stringify(metaObject, null, 2));

  const chunks = [
    makeChunk("META", metadata),
    makeChunk("DATA", sourceBytes)
  ];

  const totalSize = HEADER_SIZE + chunks.reduce((sum, chunk) => sum + CHUNK_HEADER_SIZE + chunk.length, 0);
  const output = Buffer.allocUnsafe(totalSize);

  MAGIC.copy(output, 0);
  output[4] = 0;
  output[5] = 1;
  output[6] = 0;
  output[7] = 0;
  output.writeUInt32LE(chunks.length, 8);
  output.writeUInt32LE(0, 12);

  let offset = HEADER_SIZE;
  for (const chunk of chunks) {
    output.write(chunk.type, offset, 4, "ascii");
    output.writeUInt32LE(chunk.flags, offset + 4);
    output.writeUInt32LE(chunk.length, offset + 8);
    output.writeUInt32LE(chunk.crc32, offset + 12);
    chunk.payload.copy(output, offset + CHUNK_HEADER_SIZE);
    offset += CHUNK_HEADER_SIZE + chunk.length;
  }

  return output;
}

export function parseMdfDocument(buffer) {
  if (buffer.length < HEADER_SIZE) {
    throw new Error("Input is too small to be a valid MDF document.");
  }

  if (!buffer.subarray(0, 4).equals(MAGIC)) {
    throw new Error("Invalid MDF signature.");
  }

  const versionMajor = buffer[4];
  const versionMinor = buffer[5];
  const chunkCount = buffer.readUInt32LE(8);
  const chunks = [];
  let offset = HEADER_SIZE;

  for (let index = 0; index < chunkCount; index += 1) {
    if (offset + CHUNK_HEADER_SIZE > buffer.length) {
      throw new Error(`Chunk header ${index} exceeds file length.`);
    }

    const type = buffer.toString("ascii", offset, offset + 4);
    const flags = buffer.readUInt32LE(offset + 4);
    const length = buffer.readUInt32LE(offset + 8);
    const expectedCrc32 = buffer.readUInt32LE(offset + 12);
    const payloadOffset = offset + CHUNK_HEADER_SIZE;
    const payloadEnd = payloadOffset + length;

    if (payloadEnd > buffer.length) {
      throw new Error(`Chunk payload ${index} exceeds file length.`);
    }

    const payload = buffer.subarray(payloadOffset, payloadEnd);
    const actualCrc32 = crc32(payload);

    if (actualCrc32 !== expectedCrc32) {
      throw new Error(`CRC mismatch in chunk ${type} at index ${index}.`);
    }

    chunks.push({
      type,
      flags,
      length,
      crc32: expectedCrc32,
      payload
    });

    offset = payloadEnd;
  }

  if (offset !== buffer.length) {
    throw new Error("Trailing bytes detected after the final MDF chunk.");
  }

  return {
    version: `${versionMajor}.${versionMinor}`,
    chunkCount,
    chunks
  };
}

export function summarizeMdfDocument(buffer) {
  const parsed = parseMdfDocument(buffer);
  const forbiddenTypes = parsed.chunks.filter((chunk) => FORBIDDEN_CHUNK_TYPES.has(chunk.type));

  if (forbiddenTypes.length > 0) {
    throw new Error(`Executable chunk types detected: ${forbiddenTypes.map((chunk) => chunk.type).join(", ")}.`);
  }

  return {
    version: parsed.version,
    chunkCount: parsed.chunkCount,
    types: parsed.chunks.map((chunk) => chunk.type),
    payloadBytes: parsed.chunks.reduce((sum, chunk) => sum + chunk.length, 0)
  };
}
