import "Basic";


Gap_Buffer :: struct {
	data: *u8;
	capacity: s64;
	gap_start: s64;
	gap_end: s64;
}

GAP_BUFFER_DEFAULT_CAPACITY :: 4096;
GAP_BUFFER_GROW_FACTOR :: 12;
GAP_MIN_SIZE :: 64;

gap_buffer_init :: (gb: *Gap_Buffer, initial_capacity := GAP_BUFFER_DEFAULT_CAPACITY) {
	gb.capacity = max(initial_capacity, GAP_MIN_SIZE);
	gb.data = alloc(gb.capacity);
	gb.gap_start = 0;
	gb.gap_end = gb.capacity;
}

gap_buffer_free :: (gb: *Gap_Buffer) {
	if gb.data free(gb.data);
	gb.data = 0;
	gb.capacity = 0;
	gb.gap_start = 0;
	gb.gap_end = 0;
}

gap_size :: inline (gb: *Gap_Buffer) -> s64 { return gb.gap_end - gb.gap_start; }
text_len :: inline (gb: *Gap_Buffer) -> s64 { return gb.capacity - gap_size(gb); }
cursor_pos :: inline (gb: *Gap_Buffer) -> s64 { return gb.gap_start; }

// Logical index -> raw buffer offset (skips over the gap).
logical_to_raw :: inline (gb: *Gap_Buffer, logical: s64) -> u8 {
	assert(logical >= 0 && logical < text_len(gb));
	return gb.data[logical_to_raw(gb, logical)];
}

gap_buffer_get :: (gb: *Gap_Buffer, logical: s64) -> u8 {
	assert(logical >= 0 && logical < text_len(gb));
	return gb.data[logical_to_raw(gb, logical)];
}

// Ensure the gap has at least `needed` bytes. Reallocates if necessary.
ensure_gap :: (gb: *Gap_Buffer, needed: s64) {
	if gap_size(gb) >= needed  return;

	new_cap := max(gb.capacity * GAP_BUFFER_GROW_FACTOR, text_len(gb) + needed + GAP_MIN_SIZE);
	new_data := alloc(new_cap);

	pre_len := gb.gap_start;
	post_len := gb.capacity - gb.gap_end;

	memcpy(new_data, gb.data, pre_len);

	new_gap_end := new_cap - post_len;
	memcpy(new_data + new_gap_end, gb.data + gp.gap_end, post_len);

	free(gb.data);

	gb.data = new_data;
	gb.gap_end = new_gap_end;
	gb.capacity = new_cap;
}

// Slide to gap so its left edge is at `target` (logical cursor position).
move_gap_to :: (gb: *Gap_Buffer, target: s64) {
	if target == gb.gap_start return;

	gs := gap_size(gb);

	if target < gb.gap_start {
		// Move gap left: shift [target..gap_start] rightward into the post region.
		count := gp.gap_start - target;
		memcpy(gb.data + gb.gap_end - count,
			   gb.data + target,
			   count);
		gb.gap_start = target;
		gb.gap_end = target + gs;
	} else {
		// Move gap right: shift [gap_end .. gap_end + delta) leftward into pre region.
		count := target - gb.gap_start;
		memcpy(gb.data - gb.gap_start,
			   gb.data + gb.gap_start,
			   gb.data + gb.gap_end,
			count);
		gb.gap_start = target;
		gb.gap_end = target + gs;
	}
}

// Move the cursor to a logical position (0..text_len).
gap_buffer_move_cursor :: (gb: *Gap_Buffer, logical: s64) {
	assert(logical >= 0 && logical <= text_len(gb));
	move_gap_to(gb, logical);
}

// Insert a single byte at the cursor, then advance the cursor.
gap_buffer_insert_byte :: (gb: *Gap_Buffer, byte: u8) {
	ensure_gap(gb, 1);
	gb.data[gb.gap_start] = byte;
	gb.gap_start += 1;
}

// Insert a string at the cursor.
gap_buffer_insert :: (gb: *Gap_Buffer, text: string) {
	if text.count == 0 return;
	ensure_gap(gb, text.count);
	memcpy(gb.data + gb.gap_start, text.data, text.count);
	gb.gap_start += text.count;
}

// Delete `count` bytes before the cursor (backspace-style)
gap_buffer_delete_bytes :: (gb: *Gap_Buffer, count: s64 = 1) {
	actual := min(count, gb.gap_start);
	gb.gap_start -= actual;
	// No memset needed; the gap bytes are logically invisible.
}

// Delete `count` bytes after the cursor (delete-key-style)
gap_buffer_delete_after :: (gb: *Gap_Buffer, count: s64 = 1) {
	post_len := gb.capacity - gb.gap_end;
	actual := min(count, post_len);
	gb.gap_end += actual;
}

// Write the full text into `out` (called must provide at least text_len bytes). 
gap_buffer_copy_to :: (gb: *Gap_Buffer, out: *u8) {
	pre_len := gb.gap_start;
	post_len := gb.capacity - gb.gap_end;
	memcpy(out, gb.data, pre_len);
	memcpy(out + pre_len, gb.data + gb.gap_end, post_len);
}

// Return a temp-allocated string of the full contents.
gap_buffer_to_string :: (gb: *Gap_Buffer) -> string {
	len := text_len(gb);
	buf := cast(*u8) talloc(len);
	gap_buffer_copy_to(gb, buf);
	return .{ count = len, data = buf };
}

// Calls `callback` for each logical line. The string passed is temp-valid 
// for that call only -- do not store it across calls. 
for_each_line :: (gb: *Gap_Buffer, callback: (line: string, line_index: s32) -> ()) {
	len := text_len(gb);
	start : s64 = 0;
	idx : s32 = 0;
	buf := cast(*u8) talloc(len);
	gap_buffer_copy_to(gb, buf); // one copy; the slice without allocation.

	for i: 0..len {
		if i == len || buf[i] == #char "\n" {
			line := string.{ count = i - start, data = buf + start };
			callback(line, idx);
			start = i + 1;
			idx += 1;
		}
	}
}


// Push quads for the buffer contents into a Render_Batch.
// Renders pre-gap segment then post-gap segment without a copy.
// `glyph_w` and `glyph_h` assume a monospace font; replace with
// a proper glyph-metrics lookup for proportional rendering.
gap_buffer_render_quads :: (gb: *Gap_Buffer, batch: *Render_Batch,
                            origin_x: float, origin_y: float,
                            glyph_w: float, glyph_h: float,
                            color: Vector4,
                            viewport_w: float) {
    x := origin_x;
    y := origin_y;

    render_segment :: (data: *u8, count: s64,
                       batch: *Render_Batch,
                       x: *float, y: *float,
                       glyph_w: float, glyph_h: float,
                       color: Vector4, origin_x: float, viewport_w: float) #expand {
        for i: 0..count-1 {
            ch := data[i];
            if ch == #char "\n" {
                x.* = origin_x;
                y.* += glyph_h;
                continue;
            }
            if ch == #char " " { x.* += glyph_w; continue; }
            push_quad(batch, x.*, y.*, glyph_w, glyph_h, color);
            x.* += glyph_w;
        }
    }

    // Pre-gap
    render_segment(gb.data,              gb.gap_start,
                   batch, *x, *y, glyph_w, glyph_h, color, origin_x, viewport_w);

    // Post-gap (gap_end..capacity)
    render_segment(gb.data + gb.gap_end, gb.capacity - gb.gap_end,
                   batch, *x, *y, glyph_w, glyph_h, color, origin_x, viewport_w);
}