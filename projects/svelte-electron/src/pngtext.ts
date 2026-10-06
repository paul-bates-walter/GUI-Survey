const PNG_SIGNATURE = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

export type TextEntry = [string, string];

type Chunk = { start: number; total: number; kind: string };

function crc32(data: Buffer): number {
  let crc = 0xffffffff;
  for (let i = 0; i < data.length; i += 1) {
    crc ^= data[i];
    for (let bit = 0; bit < 8; bit += 1) {
      const mask = -(crc & 1);
      crc = (crc >>> 1) ^ (0xedb88320 & mask);
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function parseChunks(png: Buffer): Chunk[] | null {
  if (png.length < 8 || !png.subarray(0, 8).equals(PNG_SIGNATURE)) {
    return null;
  }
  const chunks: Chunk[] = [];
  let offset = 8;
  while (offset + 12 <= png.length) {
    const dataLen = png.readUInt32BE(offset);
    const total = 12 + dataLen;
    if (offset + total > png.length) {
      return null;
    }
    const kind = png.subarray(offset + 4, offset + 8).toString("latin1");
    chunks.push({ start: offset, total, kind });
    offset += total;
    if (kind === "IEND") {
      return chunks;
    }
  }
  return null;
}

export function readTextEntries(png: Buffer): TextEntry[] {
  const chunks = parseChunks(png);
  if (chunks === null) {
    return [];
  }
  const entries: TextEntry[] = [];
  for (const chunk of chunks) {
    if (chunk.kind !== "tEXt") {
      continue;
    }
    const data = png.subarray(chunk.start + 8, chunk.start + chunk.total - 4);
    const split = data.indexOf(0);
    if (split < 0) {
      continue;
    }
    entries.push([
      data.subarray(0, split).toString("latin1"),
      data.subarray(split + 1).toString("latin1"),
    ]);
  }
  return entries;
}

function makeTextChunk(key: string, value: string): Buffer {
  const keyword = Buffer.from(key.trim(), "latin1").subarray(0, 79);
  const text = Buffer.from(value, "latin1");
  const body = Buffer.concat([
    Buffer.from("tEXt", "latin1"),
    keyword,
    Buffer.from([0]),
    text,
  ]);
  const length = Buffer.alloc(4);
  length.writeUInt32BE(body.length - 4);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([length, body, crc]);
}

export function writeTextEntries(
  png: Buffer,
  entries: TextEntry[],
): Buffer | null {
  const chunks = parseChunks(png);
  if (chunks === null) {
    return null;
  }
  const parts: Buffer[] = [PNG_SIGNATURE];
  for (const chunk of chunks) {
    if (chunk.kind === "tEXt") {
      continue;
    }
    if (chunk.kind === "IEND") {
      for (const [key, value] of entries) {
        if (key.trim().length === 0) {
          continue;
        }
        parts.push(makeTextChunk(key, value));
      }
    }
    parts.push(png.subarray(chunk.start, chunk.start + chunk.total));
  }
  return Buffer.concat(parts);
}
