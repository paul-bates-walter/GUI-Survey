<script lang="ts">
  import { onMount } from "svelte";

  type DrawMode = "circle" | "rectangle" | "path";
  type Point = { x: number; y: number };
  type MetadataRow = { key: string; value: string };

  const modes: DrawMode[] = ["circle", "rectangle", "path"];

  let canvas: HTMLCanvasElement;
  let context: CanvasRenderingContext2D;
  let mode: DrawMode = "path";
  let color = "#1f6feb";
  let radius = 8;
  let pendingPoint: Point | null = null;
  let isDrawingPath = false;
  let status = "Ready";
  let metadata: MetadataRow[] = [];

  function addMetadataRow() {
    metadata = [...metadata, { key: "", value: "" }];
  }

  function removeMetadataRow(index: number) {
    metadata = metadata.filter((_, i) => i !== index);
  }

  function collectEntries(): [string, string][] {
    return metadata
      .filter((row) => row.key.trim().length > 0)
      .map((row) => [row.key.trim(), row.value] as [string, string]);
  }

  function canvasPoint(event: MouseEvent): Point {
    const rect = canvas.getBoundingClientRect();
    return {
      x: ((event.clientX - rect.left) / rect.width) * canvas.width,
      y: ((event.clientY - rect.top) / rect.height) * canvas.height,
    };
  }

  function setupCanvas() {
    const parent = canvas.parentElement;
    const width = parent ? parent.clientWidth : 960;
    const height = parent ? parent.clientHeight : 560;
    canvas.width = Math.max(width, 640);
    canvas.height = Math.max(height, 420);

    context = canvas.getContext("2d") as CanvasRenderingContext2D;
    context.fillStyle = "#ffffff";
    context.fillRect(0, 0, canvas.width, canvas.height);
    context.lineCap = "round";
    context.lineJoin = "round";
  }

  function setMode(nextMode: DrawMode) {
    mode = nextMode;
    pendingPoint = null;
    isDrawingPath = false;
    status = `${labelForMode(nextMode)} mode`;
  }

  function labelForMode(value: DrawMode) {
    return value[0].toUpperCase() + value.slice(1);
  }

  function drawCircle(center: Point, edge: Point) {
    const circleRadius = Math.hypot(edge.x - center.x, edge.y - center.y);
    context.beginPath();
    context.arc(center.x, center.y, circleRadius, 0, Math.PI * 2);
    context.strokeStyle = color;
    context.lineWidth = radius;
    context.stroke();
  }

  function drawRectangle(corner: Point, opposite: Point) {
    context.beginPath();
    context.rect(
      corner.x,
      corner.y,
      opposite.x - corner.x,
      opposite.y - corner.y,
    );
    context.strokeStyle = color;
    context.lineWidth = radius;
    context.stroke();
  }

  function drawPathPoint(point: Point) {
    context.fillStyle = color;
    context.beginPath();
    context.arc(point.x, point.y, radius, 0, Math.PI * 2);
    context.fill();
  }

  function handleCanvasDown(event: MouseEvent) {
    const point = canvasPoint(event);

    if (mode === "path") {
      isDrawingPath = true;
      context.beginPath();
      context.moveTo(point.x, point.y);
      drawPathPoint(point);
      return;
    }

    if (!pendingPoint) {
      pendingPoint = point;
      status = "Pick the second point";
      return;
    }

    if (mode === "circle") {
      drawCircle(pendingPoint, point);
    } else {
      drawRectangle(pendingPoint, point);
    }

    pendingPoint = null;
    status = "Ready";
  }

  function handleCanvasMove(event: MouseEvent) {
    if (!isDrawingPath || mode !== "path") {
      return;
    }

    const point = canvasPoint(event);
    context.strokeStyle = color;
    context.lineWidth = radius * 2;
    context.lineTo(point.x, point.y);
    context.stroke();
  }

  function stopPath() {
    isDrawingPath = false;
  }

  function clearCanvas() {
    pendingPoint = null;
    context.fillStyle = "#ffffff";
    context.fillRect(0, 0, canvas.width, canvas.height);
    status = "Cleared";
  }

  async function savePng() {
    const result = await window.guiSurvey.savePng(
      canvas.toDataURL("image/png"),
      collectEntries(),
    );
    status = result.canceled ? "Save canceled" : `Saved ${result.filePath}`;
  }

  async function loadPng() {
    const result = await window.guiSurvey.loadPng();
    if (result.canceled) {
      status = "Open canceled";
      return;
    }

    const image = new Image();
    image.onload = () => {
      context.fillStyle = "#ffffff";
      context.fillRect(0, 0, canvas.width, canvas.height);

      const scale = Math.min(
        canvas.width / image.width,
        canvas.height / image.height,
      );
      const width = image.width * scale;
      const height = image.height * scale;
      const x = (canvas.width - width) / 2;
      const y = (canvas.height - height) / 2;

      context.drawImage(image, x, y, width, height);
      status = `Opened ${result.filePath}`;
    };
    image.src = result.dataUrl;
    metadata = result.entries.map(([key, value]) => ({ key, value }));
  }

  onMount(() => {
    setupCanvas();
  });
</script>

<main class="app-shell">
  <header class="toolbar">
    <div class="brand">
      <span class="title">PNG Editor</span>
      <span class="runtime">Electron + Vite + Svelte</span>
    </div>

    <div class="control-group" aria-label="Drawing mode">
      {#each modes as item}
        <button
          class:active={mode === item}
          type="button"
          on:click={() => setMode(item)}
        >
          {labelForMode(item)}
        </button>
      {/each}
    </div>

    <label class="color-field">
      <span>Color</span>
      <input bind:value={color} type="color" />
    </label>

    <label class="range-field">
      <span>Radius</span>
      <input bind:value={radius} min="1" max="40" type="range" />
      <output>{radius}</output>
    </label>

    <div class="actions">
      <button type="button" on:click={loadPng}>Open</button>
      <button type="button" on:click={savePng}>Save</button>
      <button type="button" on:click={clearCanvas}>Clear</button>
    </div>
  </header>

  <section class="work-area">
    <div class="canvas-host" aria-label="Drawing canvas">
      <canvas
        bind:this={canvas}
        on:mousedown={handleCanvasDown}
        on:mousemove={handleCanvasMove}
        on:mouseleave={stopPath}
        on:mouseup={stopPath}
      ></canvas>
    </div>

    <aside class="metadata-panel" aria-label="PNG text metadata">
      <div class="metadata-head">
        <span>tEXt metadata</span>
        <button type="button" on:click={addMetadataRow}>Add</button>
      </div>
      <table>
        <thead>
          <tr><th>Key</th><th>Value</th><th></th></tr>
        </thead>
        <tbody>
          {#each metadata as row, index}
            <tr>
              <td><input bind:value={row.key} placeholder="key" /></td>
              <td><input bind:value={row.value} placeholder="value" /></td>
              <td>
                <button type="button" on:click={() => removeMetadataRow(index)}>
                  ✕
                </button>
              </td>
            </tr>
          {/each}
        </tbody>
      </table>
    </aside>
  </section>

  <footer class="status-bar">
    <span>{status}</span>
  </footer>
</main>
