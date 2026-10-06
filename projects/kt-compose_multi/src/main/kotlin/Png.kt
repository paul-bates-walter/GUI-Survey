import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asSkiaBitmap
import androidx.compose.ui.graphics.toComposeImageBitmap
import org.jetbrains.skia.EncodedImageFormat
import org.jetbrains.skia.Image as SkiaImage
import java.util.zip.CRC32

// PNG load/save with tEXt metadata (spec.md: Filesystem Integration + Forms).
//
// Pixels go through Skia (the renderer Compose Desktop already ships): a
// ComposeImageBitmap <-> encoded-PNG conversion. Skia's PNG encoder does not
// let us attach arbitrary tEXt chunks, so textual metadata is read/written by
// manipulating the encoded byte stream directly. Everything here is plain
// top-level functions over ByteArray, matching the repo's functional style.

private val PNG_SIGNATURE = byteArrayOf(
    0x89.toByte(), 'P'.code.toByte(), 'N'.code.toByte(), 'G'.code.toByte(),
    '\r'.code.toByte(), '\n'.code.toByte(), 0x1A.toByte(), '\n'.code.toByte(),
)

// --- Pixels ------------------------------------------------------------------

/** Encode an ImageBitmap to PNG bytes (no metadata; add it with [withTextChunks]). */
fun encodePng(bitmap: ImageBitmap): ByteArray {
    val image = SkiaImage.makeFromBitmap(bitmap.asSkiaBitmap())
    val data = image.encodeToData(EncodedImageFormat.PNG)
        ?: error("PNG encoding failed")
    return data.bytes
}

/** Decode PNG bytes into an ImageBitmap. */
fun decodePng(bytes: ByteArray): ImageBitmap =
    SkiaImage.makeFromEncoded(bytes).toComposeImageBitmap()

// --- tEXt metadata -----------------------------------------------------------

private fun hasSignature(png: ByteArray): Boolean =
    png.size >= 8 && PNG_SIGNATURE.indices.all { png[it] == PNG_SIGNATURE[it] }

private fun readBE32(b: ByteArray, off: Int): Int =
    ((b[off].toInt() and 0xFF) shl 24) or
        ((b[off + 1].toInt() and 0xFF) shl 16) or
        ((b[off + 2].toInt() and 0xFF) shl 8) or
        (b[off + 3].toInt() and 0xFF)

private fun be32(v: Int): ByteArray =
    byteArrayOf((v ushr 24).toByte(), (v ushr 16).toByte(), (v ushr 8).toByte(), v.toByte())

/** Serialize one chunk: length, type, data, CRC-32 over (type + data). */
private fun chunk(type: String, data: ByteArray): ByteArray {
    val typeBytes = type.toByteArray(Charsets.US_ASCII)
    val crc = CRC32().apply { update(typeBytes); update(data) }.value.toInt()
    return be32(data.size) + typeBytes + data + be32(crc)
}

/** All tEXt entries in a PNG, in file order. Returns empty for a non-PNG. */
fun readTextChunks(png: ByteArray): List<Pair<String, String>> {
    if (!hasSignature(png)) return emptyList()
    val out = mutableListOf<Pair<String, String>>()
    var pos = 8
    while (pos + 8 <= png.size) {
        val len = readBE32(png, pos)
        val type = String(png, pos + 4, 4, Charsets.US_ASCII)
        val dataStart = pos + 8
        if (len < 0 || dataStart + len + 4 > png.size) break // truncated / malformed
        if (type == "tEXt") {
            var sep = 0
            while (sep < len && png[dataStart + sep].toInt() != 0) sep++
            if (sep < len) {
                val key = String(png, dataStart, sep, Charsets.ISO_8859_1)
                val value = String(png, dataStart + sep + 1, len - sep - 1, Charsets.ISO_8859_1)
                out.add(key to value)
            }
        }
        pos = dataStart + len + 4
    }
    return out
}

/**
 * Return a copy of [png] whose tEXt chunks are exactly [entries]. Existing
 * tEXt/zTXt/iTXt chunks are dropped first (so deleted keys do not survive) and
 * the new tEXt chunks are inserted before IEND. Blank keys are skipped and
 * keywords are trimmed to the PNG-mandated 1..79 bytes. Returns [png] unchanged
 * if it is not a valid PNG.
 */
fun withTextChunks(png: ByteArray, entries: List<Pair<String, String>>): ByteArray {
    if (!hasSignature(png)) return png
    val out = java.io.ByteArrayOutputStream()
    out.write(PNG_SIGNATURE)

    var pos = 8
    var wroteText = false
    while (pos + 8 <= png.size) {
        val len = readBE32(png, pos)
        val type = String(png, pos + 4, 4, Charsets.US_ASCII)
        val chunkEnd = pos + 8 + len + 4
        if (len < 0 || chunkEnd > png.size) return png // malformed
        val isText = type == "tEXt" || type == "zTXt" || type == "iTXt"

        if (type == "IEND" && !wroteText) {
            for ((rawKey, value) in entries) {
                var key = rawKey.trim()
                if (key.isEmpty()) continue
                if (key.length > 79) key = key.substring(0, 79)
                val data = key.toByteArray(Charsets.ISO_8859_1) +
                    byteArrayOf(0) +
                    value.toByteArray(Charsets.ISO_8859_1)
                out.write(chunk("tEXt", data))
            }
            wroteText = true
        }

        if (!isText) out.write(png, pos, chunkEnd - pos)
        pos = chunkEnd
    }
    return out.toByteArray()
}
