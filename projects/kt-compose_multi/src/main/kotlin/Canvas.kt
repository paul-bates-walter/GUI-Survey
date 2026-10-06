import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Canvas as GraphicsCanvas
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.PaintingStyle
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

enum class Mode { PATH, CIRCLE, RECTANGLE }

fun newBitmap(width: Int, height: Int): ImageBitmap {
    val bitmap = ImageBitmap(width, height)
    val canvas = GraphicsCanvas(bitmap)
    canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), Paint().apply { color = Color.White })
    return bitmap
}

private fun clamp(p: Offset, bitmap: ImageBitmap): Offset =
    Offset(p.x.coerceIn(0f, (bitmap.width - 1).toFloat()), p.y.coerceIn(0f, (bitmap.height - 1).toFloat()))

/** Commit a circle or rectangle stroke between [a] and [b] into [bitmap]. */
private fun stampShape(bitmap: ImageBitmap, mode: Mode, color: Color, radius: Float, a: Offset, b: Offset) {
    val canvas = GraphicsCanvas(bitmap)
    val paint = Paint().apply {
        this.color = color
        isAntiAlias = true
        style = PaintingStyle.Stroke
        strokeWidth = radius
    }
    when (mode) {
        Mode.CIRCLE -> canvas.drawCircle(a, (b - a).getDistance(), paint)
        Mode.RECTANGLE -> canvas.drawRect(min(a.x, b.x), min(a.y, b.y), max(a.x, b.x), max(a.y, b.y), paint)
        Mode.PATH -> {}
    }
}

/** Freehand: a filled dab at [from], then a round-capped line to [to]. */
private fun stampPath(bitmap: ImageBitmap, color: Color, radius: Float, from: Offset, to: Offset) {
    val canvas = GraphicsCanvas(bitmap)
    val paint = Paint().apply {
        this.color = color
        isAntiAlias = true
        strokeWidth = radius * 2
        strokeCap = StrokeCap.Round
    }
    canvas.drawCircle(from, radius, paint.apply { style = PaintingStyle.Fill })
    paint.style = PaintingStyle.Stroke
    canvas.drawLine(from, to, paint)
}

/**
 * Renders [backing] 1:1 and handles all pointer input. Committed pixels are
 * drawn into [backing] in place; [version] is bumped through [onMutated] to
 * force a redraw. For circle/rectangle a live "rubber-band" preview follows the
 * cursor between the two clicks.
 *
 * The canvas is pinned to Density(1f) so one Compose dp equals one bitmap pixel,
 * keeping pointer coordinates aligned with the backing store on any display.
 */
@Composable
fun EditorCanvas(
    backing: ImageBitmap,
    version: Int,
    mode: Mode,
    penColor: Color,
    penRadius: Float,
    onMutated: () -> Unit,
) {
    // First click (circle/rect) and current cursor, read by the preview below.
    var pending by remember { mutableStateOf<Offset?>(null) }
    var cursor by remember { mutableStateOf(Offset.Zero) }

    // Switching modes cancels any half-drawn shape.
    LaunchedEffect(mode) { pending = null }

    CompositionLocalProvider(LocalDensity provides Density(1f, 1f)) {
        Box(
            Modifier
                .size(backing.width.dp, backing.height.dp)
                .pointerInput(mode, penColor, penRadius) {
                    var last = Offset.Zero
                    awaitPointerEventScope {
                        while (true) {
                            val change = awaitPointerEvent().changes.first()
                            val pos = clamp(change.position, backing)
                            val pressed = change.pressed
                            val wasPressed = change.previousPressed

                            if (mode == Mode.PATH) {
                                if (pressed && !wasPressed) {              // pen down
                                    last = pos
                                    stampPath(backing, penColor, penRadius, pos, pos)
                                    onMutated()
                                } else if (pressed && wasPressed) {        // drag
                                    stampPath(backing, penColor, penRadius, last, pos)
                                    last = pos
                                    onMutated()
                                }
                            } else {
                                cursor = pos
                                if (pressed && !wasPressed) {              // a click
                                    val start = pending
                                    if (start == null) {
                                        pending = pos
                                    } else {
                                        stampShape(backing, mode, penColor, penRadius, start, pos)
                                        pending = null
                                        onMutated()
                                    }
                                }
                            }
                            change.consume()
                        }
                    }
                }
        ) {
            Canvas(Modifier.size(backing.width.dp, backing.height.dp)) {
                version // read so a mutation triggers redraw
                drawImage(backing)

                val start = pending
                if (start != null) {
                    when (mode) {
                        Mode.CIRCLE -> drawCircle(
                            color = penColor,
                            radius = (cursor - start).getDistance(),
                            center = start,
                            style = Stroke(penRadius),
                        )
                        Mode.RECTANGLE -> drawRect(
                            color = penColor,
                            topLeft = Offset(min(start.x, cursor.x), min(start.y, cursor.y)),
                            size = Size(abs(cursor.x - start.x), abs(cursor.y - start.y)),
                            style = Stroke(penRadius),
                        )
                        Mode.PATH -> {}
                    }
                }
            }
        }
    }
}
