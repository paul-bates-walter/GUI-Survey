using System;
using System.Buffers.Binary;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace AvaloniaPngEditor.Services;

/// Reads and writes PNG 'tEXt' metadata chunks (spec Feature: Forms / Text
/// Editing). Avalonia/Skia encode pixels but do not emit tEXt chunks, so we
/// splice them into the encoded byte stream ourselves.
///
/// PNG layout: 8-byte signature, then chunks of
///   length (uint32 BE) | type (4 ASCII) | data (length bytes) | CRC32 (uint32 BE)
/// A tEXt chunk's data is: keyword (Latin-1, 1..79) | 0x00 | text (Latin-1).
public static class PngText
{
    private static readonly byte[] Signature = { 137, 80, 78, 71, 13, 10, 26, 10 };

    /// Parse all tEXt chunks into a keyword→text map. Returns empty for non-PNG.
    public static Dictionary<string, string> Read(byte[] png)
    {
        var result = new Dictionary<string, string>();
        if (!HasSignature(png))
            return result;

        int pos = 8;
        while (pos + 8 <= png.Length)
        {
            int len = (int)BinaryPrimitives.ReadUInt32BigEndian(png.AsSpan(pos, 4));
            string type = Encoding.ASCII.GetString(png, pos + 4, 4);
            int dataStart = pos + 8;
            if (len < 0 || dataStart + len + 4 > png.Length)
                break;

            if (type == "tEXt")
            {
                int sep = Array.IndexOf(png, (byte)0, dataStart, len);
                if (sep >= 0)
                {
                    string key = Latin1(png, dataStart, sep - dataStart);
                    string val = Latin1(png, sep + 1, dataStart + len - (sep + 1));
                    result[key] = val;
                }
            }

            if (type == "IEND")
                break;
            pos = dataStart + len + 4; // advance past data + CRC
        }
        return result;
    }

    /// Return a copy of `png` with all existing tEXt chunks replaced by `entries`
    /// (inserted immediately before IEND). Empty keys are skipped.
    public static byte[] Write(byte[] png, IReadOnlyDictionary<string, string> entries)
    {
        if (!HasSignature(png))
            throw new ArgumentException("Input is not a PNG.", nameof(png));

        using var ms = new MemoryStream(png.Length + 128);
        ms.Write(Signature, 0, Signature.Length);

        int pos = 8;
        bool inserted = false;
        while (pos + 8 <= png.Length)
        {
            int len = (int)BinaryPrimitives.ReadUInt32BigEndian(png.AsSpan(pos, 4));
            string type = Encoding.ASCII.GetString(png, pos + 4, 4);
            int chunkEnd = pos + 8 + len + 4;
            if (len < 0 || chunkEnd > png.Length)
                break;

            if (type == "tEXt")
            {
                // Drop old text chunks; they are re-emitted from `entries`.
            }
            else if (type == "IEND")
            {
                if (!inserted) { WriteTextChunks(ms, entries); inserted = true; }
                ms.Write(png, pos, chunkEnd - pos);
            }
            else
            {
                ms.Write(png, pos, chunkEnd - pos);
            }
            pos = chunkEnd;
        }

        if (!inserted) // malformed input without IEND; append anyway
            WriteTextChunks(ms, entries);

        return ms.ToArray();
    }

    private static void WriteTextChunks(Stream s, IReadOnlyDictionary<string, string> entries)
    {
        foreach (var kv in entries)
        {
            if (string.IsNullOrEmpty(kv.Key))
                continue;

            byte[] keyword = Encoding.Latin1.GetBytes(Clamp(kv.Key, 79));
            byte[] text = Encoding.Latin1.GetBytes(kv.Value ?? "");
            byte[] type = { (byte)'t', (byte)'E', (byte)'X', (byte)'t' };

            byte[] data = new byte[keyword.Length + 1 + text.Length];
            Buffer.BlockCopy(keyword, 0, data, 0, keyword.Length);
            data[keyword.Length] = 0; // null separator
            Buffer.BlockCopy(text, 0, data, keyword.Length + 1, text.Length);

            WriteUInt32BE(s, (uint)data.Length);
            s.Write(type, 0, type.Length);
            s.Write(data, 0, data.Length);
            WriteUInt32BE(s, Crc32(type, data));
        }
    }

    private static bool HasSignature(byte[] png)
    {
        if (png is null || png.Length < 8)
            return false;
        for (int i = 0; i < 8; i++)
            if (png[i] != Signature[i])
                return false;
        return true;
    }

    private static string Latin1(byte[] buf, int offset, int count) =>
        count <= 0 ? "" : Encoding.Latin1.GetString(buf, offset, count);

    private static string Clamp(string s, int maxBytes) =>
        s.Length <= maxBytes ? s : s.Substring(0, maxBytes);

    private static void WriteUInt32BE(Stream s, uint value)
    {
        Span<byte> b = stackalloc byte[4];
        BinaryPrimitives.WriteUInt32BigEndian(b, value);
        s.Write(b);
    }

    // Standard PNG CRC-32 (reflected, polynomial 0xEDB88320) over the given buffers.
    private static readonly uint[] CrcTable = BuildCrcTable();

    private static uint[] BuildCrcTable()
    {
        var table = new uint[256];
        for (uint n = 0; n < 256; n++)
        {
            uint c = n;
            for (int k = 0; k < 8; k++)
                c = (c & 1) != 0 ? 0xEDB88320u ^ (c >> 1) : c >> 1;
            table[n] = c;
        }
        return table;
    }

    private static uint Crc32(params byte[][] buffers)
    {
        uint crc = 0xFFFFFFFFu;
        foreach (byte[] buf in buffers)
            foreach (byte b in buf)
                crc = CrcTable[(crc ^ b) & 0xFF] ^ (crc >> 8);
        return crc ^ 0xFFFFFFFFu;
    }
}
