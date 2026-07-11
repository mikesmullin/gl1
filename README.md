# gl1

Portable **Zig + Sokol** graphics prototype with a custom **immediate-mode UI**
(Style A: `begin` / `end` + `defer`). Built as a greenfield stack for tools,
editors, and eventually TUI backends—without shipping Dear ImGui or Clay as the
product UI.

| | |
|--|--|
| Language | Zig **master** ([zvm](https://github.com/tristanisham/zvm)) |
| Window / GPU | [sokol-zig](https://github.com/floooh/sokol-zig) (`sokol_app` + `sokol_gfx` + `sokol_gl`) |
| UI | In-repo immediate mode (`src/ui/`) + `RenderCommand` list |
| Font | Bitmap atlas (`assets/fonts/glyphs-outline.bmp`) |
| Default scene | `storybook` |

![gl1 storybook](docs/screenshots/storybook.png)

## Requirements

- Zig **master** via [`zvm`](https://github.com/tristanisham/zvm)  
  (tested: `0.17.0-dev.1252+e4b325c19`)
- Linux with OpenGL + X11 (macOS / Windows via Sokol backends later)

```bash
zvm use master
zig build
./zig-out/bin/gl1                    # default: storybook
./zig-out/bin/gl1 --scene inspector
./zig-out/bin/gl1 help
```

## Global hotkeys

| Input | Action |
|-------|--------|
| **Ctrl+P** | Toggle command palette (filter with e.g. `scene`, arrows / Enter / click) |
| **Esc** | Close palette/modal → clear text focus → quit app |
| **Ctrl+C / X / V** | Copy / cut / paste in focused text fields |
| **Ctrl+Z** / **Ctrl+Shift+Z** | Undo / redo in text fields |

Scene switching is via the palette (type `scene`). Digits stay free for typing.

### Command palette

| Input | Action |
|-------|--------|
| **↑ / ↓** | Move selection (scroll keeps selection in view) |
| **Mouse wheel** | Scroll list only (does not change selection) |
| **Mouse move over row** | Select that row (only while the mouse is moving) |
| **Enter** / click | Run command |
| **Esc** | Close palette |

---

## Scenes overview

Favorite demos first:

| Scene | CLI | Description |
|-------|-----|-------------|
| [`inspector`](#inspector) | `--scene inspector` | App chrome: menubar, split, tree, form, notes, console |
| [`canvas`](#canvas) | `--scene canvas` | Blender-like 3D orbit viewport + entity cubes |
| [`storybook`](#storybook) | `--scene storybook` | Living widget gallery (**default**) |
| [`text`](#text) | `--scene text` | Bitmap font sample |
| [`triangle`](#triangle) | `--scene triangle` | Hello triangle + mouse readout |
| [`panels`](#panels) | `--scene panels` | Desktop windows + dock (drag / resize / toggle) |

---

## Scene gallery

### inspector

Composite “app shell”: menubar, left tree + filter, splitter, property form
(Blender-style sliders), viewport preview, multi-line **Notes** textarea, console.

![inspector](docs/screenshots/inspector.png)

| Input | Action |
|-------|--------|
| Drag vertical splitter | Resize left/right panes |
| Right-click entity list | Context menu |
| Menubar items | File / edit actions, open palette |
| **Notes** textarea | Full multi-line editor (see [Text editing](#text-editing-hotkeys)) |
| Layer / HP sliders | Blender-style number sliders |

---

### canvas

Mini Blender-like **3D** viewport: orbit camera, solid cubes as ECS-style
entities, selection outlines, orientation compass, fly mode.

![canvas](docs/screenshots/canvas.png)

| Input | Action |
|-------|--------|
| **MMB drag** | Orbit (yaw / pitch only; no snap on click) |
| **Shift+MMB drag** | Strafe (pan in camera plane) |
| **Space+LMB drag** | Pan look-target |
| **Wheel** | Dolly (distance) |
| **WASD** | Fly forward / left / back / right |
| **Q** / **E** | Fly down / up |
| **Space** | Fly up (when not Space+LMB panning) |
| **Shift** | Faster fly |
| **LMB** | Select entity (mesh only) |
| **Ctrl/Shift+LMB** | Multi-select toggle |
| **Ctrl+A** | Toggle select all / none |
| **F** or **Numpad `.`** | Frame selection (center + zoom ~80%, 250 ms tween) |
| **1** / **3** / **7** | Front / Right / Top view (numpad or top-row) |
| Top-right RGB gizmo | World-axis orientation (always on) |

---

### storybook

Widget gallery with a sidebar index. Default launch scene.

![storybook](docs/screenshots/storybook.png)

| Input | Action |
|-------|--------|
| Click sidebar row | Open that widget’s playground |
| Scroll sidebar / detail | Wheel when hovered (scissor-clipped) |
| **Ctrl+P** | Command palette |

---

### text

Bitmap font atlas demo (magenta chroma key → transparency).

![text](docs/screenshots/text.png)

| Input | Action |
|-------|--------|
| — | View only |

---

### triangle

Minimal Sokol GL triangle and mouse position HUD.

![triangle](docs/screenshots/triangle.png)

| Input | Action |
|-------|--------|
| Move mouse | Updates on-screen position readout |

---

### panels

Lightweight **desktop**: floating windows, title-bar drag, bottom-right resize
triangle, and a macOS-style dock that opens/closes windows while **remembering
position and size**.

![panels](docs/screenshots/panels.png)

| Input | Action |
|-------|--------|
| Drag window title bar | Move window |
| Drag bottom-right triangle | Resize window |
| Click dock icon | Toggle window open/closed (geometry preserved) |
| Wheel over window body | Scroll clipped content |

---

## Text editing hotkeys

Focused single-line (`textInput`) and multi-line (`textArea`) fields:

| Input | Action |
|-------|--------|
| Arrows / Home / End | Move caret (Ctrl+arrow = word) |
| Shift+arrows | Extend selection |
| Double-click | Select word |
| Triple-click | Select line (multi-line) |
| **Ctrl+D** | Add next occurrence (first press: select word if empty) |
| **Ctrl+Shift+L** | Select all occurrences |
| **Alt+Shift+↑/↓** or **Ctrl+Alt+↑/↓** | Add caret above/below |
| **Esc** | End multi-caret / Ctrl+D session (restore origin caret) |
| **Enter** | Newline (multi-line) |
| Soft wrap | Display-only; buffer keeps real newlines only |

Textarea: bottom-right **solid triangle** grip resizes the field (ghost preview while dragging).

---

## Project layout

```
src/
  main.zig              CLI entry
  app.zig               sokol_app / gfx / gl shell
  input.zig             normalized input + key repeat
  anim.zig              Timer / Tween / Easing (Game9-inspired)
  bmp.zig               BMP loader
  font.zig              bitmap atlas font
  draw.zig              RenderCommand list + sgl backend
  ui/
    ui.zig              immediate UI core + high-level widgets
    theme.zig           dark theme tokens
    text_edit.zig       shared text model (multi-caret, soft wrap, undo)
    components/         modular widgets (slider, textArea, …)
  scenes/
    scenes.zig          runner + palette wiring
    inspector.zig canvas.zig storybook.zig text.zig triangle.zig panels.zig
assets/fonts/
  glyphs-outline.bmp    bitmap font atlas (magenta = transparent)
docs/screenshots/       committed scene screenshots (for this README)
```

## Design notes

- **UI:** immediate mode with stable IDs and previous-frame geometry for hits  
- **Font:** fixed-cell bitmap atlas (`5×8` glyphs, `32×4` grid); pink/magenta chroma key → alpha  
- **Layout:** simple vstack/hstack (flex-inspired; no external layout library)  
- **Draw:** widgets emit a `RenderCommand` list; Sokol/GL backend executes it  
- **Panels:** body always scissor-clipped; desktop scene adds drag/resize/dock  
- **Scroll capture:** overlays (palette) own the wheel via `wheelY` / `eatScroll`  
- **Anim:** `src/anim.zig` for camera framing tweens  
- **Sokol:** official [`sokol-zig`](https://github.com/floooh/sokol-zig) package  

## Regenerating screenshots

```bash
zig build
mkdir -p docs/screenshots
for s in inspector canvas storybook text triangle panels; do
  ./zig-out/bin/gl1 --scene "$s" &
  pid=$!
  sleep 1.5
  scrot -u "docs/screenshots/${s}.png"
  kill $pid
  wait $pid 2>/dev/null
done
```

## License

MIT — see [LICENSE](./LICENSE).
