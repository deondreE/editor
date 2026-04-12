# TODO FROM AI :)

Input & cursor

Keyboard event handling (SDL gives you SDL_KEYDOWN + SDL_TEXTINPUT events — TEXTINPUT handles Unicode composition for free)
Cursor blink timer
Selection range (just two cursor positions, sel_start and sel_end)
Basic shortcuts: Ctrl+A, Ctrl+C/X/V (SDL clipboard via SDL_GetClipboardText / SDL_SetClipboardText)

Text rendering

A real glyph metrics source — the fixed glyph_w placeholder won't survive proportional fonts or Unicode. The standard path is stb_truetype (single-header, easy Jai FFI) or freetype if you need hinting. You need at minimum: advance width per codepoint, ascender/descender for line height, and kerning pairs if you care.
A glyph atlas — pack rasterized glyphs into a texture, render each quad with the right UV. Your push_quad already takes uv_min/uv_max, so the batcher is ready for this.
UTF-8 decoding — a small utf8_next_codepoint iterator so gap_buffer_render_quads and cursor movement step by codepoint rather than byte.

Editor state

Undo/redo stack — simplest approach is a fixed ring of (operation, payload) snapshots; coalesce consecutive inserts into one entry
Logical ↔ visual line mapping — you need to know which logical line the cursor is on, the byte offset of each line start, and (for soft-wrap) where visual breaks fall. A line_cache: []s64 of gap-relative offsets, invalidated on any edit, is enough to start.
Hit-testing — converting a mouse (x, y) back to a logical cursor position, needed for click-to-place and drag selection

The rough build order that avoids blocking yourself:

SDL TEXTINPUT + KEYDOWN → gap buffer ops (you can test this with your fixed-width placeholder)
stb_truetype atlas → real glyph quads with correct UVs
UTF-8 iteration + cursor movement by codepoint
Line cache + cursor-to-screen and screen-to-cursor
Selection highlight (push a colored quad behind the text range)
Clipboard + undo