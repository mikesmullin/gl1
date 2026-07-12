# Draw commands (Phase 8)

Widgets should **emit commands** into `draw.List` rather than calling Sokol
directly. The app flushes lists after `ui.endFrame()`.

## Command set (`src/draw.zig`)

| Command | Purpose |
|---------|---------|
| `rect` | Filled axis-aligned rectangle |
| `text` | Bitmap font run (interned into list scratch) |
| `icon` | Icon atlas sprite by `IconId` ordinal |
| `scissor_push` / `scissor_pop` | Nested clip stacks |

## Layers

- `Ui.cmds` — main UI layer  
- `Ui.front` — tooltips, context menus, soft cursor host, overlays  

`flushDraw` runs `cmds` then `front`, then the soft pointer.

## Backend

Today: **sokol_gl** (`List.flushSgl`).  

Future TUI: implement a second consumer that maps rect/text to a cell buffer
without changing widget code. Keep new primitives backend-agnostic.

## Rules of thumb

1. Prefer `ui.drawRect` / `drawText` / `drawIcon` (they push commands).  
2. Scenes that need raw 3D (canvas cubes) may use `sgl` directly **before** UI.  
3. Scene transition diamond overlay draws after UI flush (app frame).  
4. Do not grow ad-hoc GPU state inside widgets.
