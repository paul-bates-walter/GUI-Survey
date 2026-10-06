import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.Button
import androidx.compose.material.MaterialTheme
import androidx.compose.material.OutlinedButton
import androidx.compose.material.Slider
import androidx.compose.material.Surface
import androidx.compose.material.Text
import androidx.compose.material.TextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.FrameWindowScope
import androidx.compose.ui.window.MenuBar
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application
import androidx.compose.ui.window.rememberWindowState
import java.awt.FileDialog
import java.io.File

fun main() = application {
    Window(
        onCloseRequest = ::exitApplication,
        state = rememberWindowState(width = 1100.dp, height = 720.dp),
        title = "PNG Editor (Compose)",
    ) {
        MaterialTheme {
            Surface { EditorApp(onExit = ::exitApplication) }
        }
    }
}

private val PALETTE = listOf(
    Color.Black, Color.White, Color.Red, Color(0xFFFF8800), Color.Yellow,
    Color(0xFF2E7D32), Color.Blue, Color(0xFF6A1B9A),
)

@Composable
fun FrameWindowScope.EditorApp(onExit: () -> Unit) {
    var backing by remember { mutableStateOf(newBitmap(800, 600)) }
    var version by remember { mutableStateOf(0) }
    var mode by remember { mutableStateOf(Mode.PATH) }
    var penColor by remember { mutableStateOf(Color.Black) }
    var penRadius by remember { mutableStateOf(4f) }
    var currentPath by remember { mutableStateOf<File?>(null) }

    // PNG tEXt metadata as two parallel editable lists (no row objects).
    val keys = remember { mutableStateListOf<String>() }
    val values = remember { mutableStateListOf<String>() }

    fun setMetadata(entries: List<Pair<String, String>>) {
        keys.clear(); values.clear()
        entries.forEach { keys.add(it.first); values.add(it.second) }
    }

    fun newImage() {
        backing = newBitmap(800, 600)
        version++
        setMetadata(emptyList())
        currentPath = null
    }

    fun openImage() {
        val dialog = FileDialog(window, "Open PNG", FileDialog.LOAD).apply {
            file = "*.png"
            isVisible = true
        }
        val name = dialog.file ?: return
        val file = File(dialog.directory, name)
        val bytes = file.readBytes()
        backing = decodePng(bytes)
        version++
        setMetadata(readTextChunks(bytes))
        currentPath = file
    }

    fun writeTo(file: File) {
        val entries = keys.indices.mapNotNull { i ->
            val k = keys[i].trim()
            if (k.isEmpty()) null else k to values[i]
        }
        file.writeBytes(withTextChunks(encodePng(backing), entries))
        currentPath = file
    }

    fun saveAs() {
        val dialog = FileDialog(window, "Save PNG", FileDialog.SAVE).apply {
            file = currentPath?.name ?: "untitled.png"
            isVisible = true
        }
        val name = dialog.file ?: return
        val fixed = if (name.lowercase().endsWith(".png")) name else "$name.png"
        writeTo(File(dialog.directory, fixed))
    }

    fun save() {
        val path = currentPath
        if (path == null) saveAs() else writeTo(path)
    }

    MenuBar {
        Menu("File") {
            Item("New", onClick = ::newImage)
            Item("Open…", onClick = ::openImage)
            Item("Save", onClick = ::save)
            Item("Save As…", onClick = ::saveAs)
            Separator()
            Item("Quit", onClick = onExit)
        }
    }

    Column(Modifier.fillMaxSize()) {
        Toolbar(
            mode = mode, onMode = { mode = it },
            penColor = penColor, onColor = { penColor = it },
            penRadius = penRadius, onRadius = { penRadius = it },
        )
        Row(Modifier.fillMaxSize()) {
            // Scrollable canvas viewport.
            Box(
                Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .verticalScroll(rememberScrollState())
                    .horizontalScroll(rememberScrollState())
                    .padding(8.dp),
            ) {
                EditorCanvas(backing, version, mode, penColor, penRadius) { version++ }
            }
            MetadataPanel(keys, values, Modifier.width(320.dp).fillMaxHeight())
        }
    }
}

@Composable
private fun Toolbar(
    mode: Mode, onMode: (Mode) -> Unit,
    penColor: Color, onColor: (Color) -> Unit,
    penRadius: Float, onRadius: (Float) -> Unit,
) {
    Row(
        Modifier.padding(8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text("Mode:")
        Mode.values().forEach { m ->
            val label = m.name.lowercase().replaceFirstChar { it.uppercase() }
            if (m == mode) Button(onClick = { onMode(m) }) { Text(label) }
            else OutlinedButton(onClick = { onMode(m) }) { Text(label) }
        }

        Spacer(Modifier.width(12.dp))
        Text("Colour:")
        PALETTE.forEach { c ->
            Box(
                Modifier
                    .size(22.dp)
                    .background(c)
                    .border(if (c == penColor) 3.dp else 1.dp, Color.Gray)
                    .clickable { onColor(c) },
            )
        }

        Spacer(Modifier.width(12.dp))
        Text("Radius: ${penRadius.toInt()}")
        Slider(
            value = penRadius,
            onValueChange = onRadius,
            valueRange = 1f..64f,
            modifier = Modifier.width(160.dp),
        )
    }
}

@Composable
private fun MetadataPanel(
    keys: MutableList<String>,
    values: MutableList<String>,
    modifier: Modifier = Modifier,
) {
    Column(modifier.padding(8.dp)) {
        Text("PNG text metadata", modifier = Modifier.padding(bottom = 6.dp))
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            for (i in keys.indices) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    TextField(
                        value = keys[i],
                        onValueChange = { keys[i] = it },
                        placeholder = { Text("key") },
                        singleLine = true,
                        modifier = Modifier.width(120.dp),
                    )
                    TextField(
                        value = values[i],
                        onValueChange = { values[i] = it },
                        placeholder = { Text("value") },
                        singleLine = true,
                        modifier = Modifier.weight(1f),
                    )
                    OutlinedButton(onClick = { keys.removeAt(i); values.removeAt(i) }) { Text("–") }
                }
            }
        }
        Spacer(Modifier.size(6.dp))
        Button(onClick = { keys.add(""); values.add("") }) { Text("Add row") }
    }
}
