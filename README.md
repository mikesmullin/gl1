# gl1

Portable **Zig + Sokol** graphics prototype with a custom **immediate-mode UI**
(Style A: `begin` / `end` + `defer`).

Copyright © 2026 [Mike Smullin](mailto:mike@smullindesign.com) — MIT License.

## Requirements

- Zig **master** via [`zvm`](https://github.com/tristanisham/zvm)  
  (tested: `0.17.0-dev.1252+e4b325c19`)
- Linux with OpenGL + X11 (macOS / Windows via Sokol backends later)

```bash
zvm use master
zig build
./zig-out/bin/gl1                    # default: storybook
./zig-out/bin/gl1 --scene triangle
./zig-out/bin/gl1 help
```

## Scenes

| Scene | Description |
|-------|-------------|
| `storybook` | Widget gallery (**default**) |
| `triangle` | Hello triangle + mouse readout |
| `rects` | Colored rects |
| `text` | Bitmap font sample |
| `widgets_basic` | Label, button, slider, text field, … |
| `panels` | `beginPanel` / `endPanel` |
| `layout` | vstack / hstack |
| `inspector` | Menubar + entity list + form + modal (composite) |

**Keys**

| Input | Action |
|-------|--------|
| **Ctrl+0…7** | Switch scene |
| **Esc** | Close modal → clear text focus → quit |

Digits and Shift+digit (e.g. `!`) are free for typing. Scene shortcuts require **Ctrl**.

## Project layout

```
src/
  main.zig           CLI entry
  app.zig            sokol_app / gfx / gl shell
  input.zig          normalized input
  bmp.zig            BMP loader
  font.zig           bitmap atlas font
  draw.zig           RenderCommand list + sgl backend
  ui/
    ui.zig           immediate UI core + widgets
    theme.zig        dark theme tokens
  scenes/
    scenes.zig       scene runner + demos
assets/fonts/
  glyphs-outline.bmp bitmap font atlas (magenta = transparent)
```

## Design notes

- **UI:** immediate mode with stable IDs and previous-frame geometry for hits  
- **Font:** fixed-cell bitmap atlas (`5×8` glyphs, `32×4` grid); pink/magenta chroma key → alpha  
- **Layout:** simple vstack/hstack (flex-inspired; no external layout library)  
- **Draw:** widgets emit a `RenderCommand` list; Sokol/GL backend executes it  
- **Sokol:** official [`sokol-zig`](https://github.com/floooh/sokol-zig) package  

## License

MIT — see [LICENSE](./LICENSE).
