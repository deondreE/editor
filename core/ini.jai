#import "Basic";
#import "String";
#import "File";

Ini_Value :: struct {
	section : string;
	key : string;
	value : string;
}

Ini_File :: struct {
	entries : [..]Ini_Value;
}

parse_ini :: (content: string) -> Ini_File {
	result: Ini_File;
	current_section: string = "global";

	lines := split(content, "\n");
	for lines {
		line := trim(it);

		// Skip empty lines and comments 
		if line.count == 0 || line[0] == #char ";" || line[0] == #char "#" continue;

		// Section header: [section_name]
		if line[0] == #char "[" {
			end := find_index_from_left(line, #char "]");
			if end > 0 {
				current_section = slice(line, 1, end - 1);
			}
			continue;
		}

		// Key=value pair
		eq := find_index_from_left(line, #char "=");
		if eq >= 0 {
			entry: Ini_Value;
			entry.section = current_section;
			entry.key = trim(slice(line, 0, eq));
			entry.value = trim(slice(line, eq + 1, line.count - eq - 1));
			array_add(*result.entries, entry);
		}
	}

	return result;
}

load_ini_file :: (path: string) -> (Ini_File, bool) {
	content, ok := read_entire_file(path);
	if !ok return .{}, false;
	return parse_ini(content), true;
}

//
// Single Getter values.
// Allows for typelevel control from the inner text file.
//

get_value :: (ini: Ini_File, section: string, key: string) -> (string, bool) {
	for ini.entries {
		if it.section == section && it.key == key {
			return it.value, true;
		}
	}
	return "", false;
}
	
get_int :: (ini: Ini_File, section: string, key: string, default: int = 0) -> (int, bool) {
	raw, found := get_value(ini, section, key);
	if !found return default, false;

	value, ok, _ := string_to_int(raw);
	if !ok return default, false;
	return value, true;
}

get_float :: (ini: Ini_File, section: string, key: string, default: float64 = 0) -> (float64, bool) {
	raw, found := get_value(ini, section, key);
	if !found return default, false;

	value, ok, _ := string_to_float64(raw);
	if !ok return default, false;
	return value, true;
}

// get_bool :: (ini: Ini_File, section: string, key: string, default: bool = false) -> (bool, bool) {
// 	raw, found := get_value(ini, section, key);
// 	if !found return default, false;

// 	lower := to_lower(raw);
// 	if lower == "true" || lower == "1" || lower == "yes" || lower == "on" return true, true;
// 	if lower == "false" || lower == "0" || lower == "no" || lower == "off" return false, false;
// 	return default, false;
// }


// Returns every value that matches section+key (caller owns the array).
get_all_values :: (ini: Ini_File, section: string, key: string) -> [..]string {
	results: [..]string;
	for ini.entries {
		if it.section == section && it.key == key
			array_add(*results, it.value);
	}
	return results;
}

get_all_ints :: (ini: Ini_File, section: string, key: string) -> [..]int {
	results: [..]int;
	for ini.entries {
		if it.section == section && it.key == key {
			value, ok, _ := string_to_int(it.value);
			if ok {
			array_add(*results, value); 	
			} 
		}
	}
	return results;
}

get_all_floats :: (ini: Ini_File, section: string, key: string) -> [..]float64 {
	results: [..]float64;
	for ini.entries {
		if it.section == section && it.key == key {
			value, ok, _ := string_to_float64(it.value);
			if ok array_add(*results, value); 
		}
	}
	return results;
}

serialize_ini :: (ini: Ini_File) -> string
{ 
	section_order: [..]string;
	for entry: ini.entries {
		already := false;
        for section_order {
            if it == entry.section { already = true; break; }
        }
        if !already  array_add(*section_order, entry.section);
	}

	builder: String_Builder;

	for sec: section_order {
		// Write header
		if sec != "global" {
			append(*builder, "[");
			append(*builder, sec);
			append(*builder, "]\n");
		}

		// Write every key=value that belongs to this section.
		for ini.entries {
			if it.section != sec continue;
			append(*builder, it.key);
			append(*builder, " = ");
			append(*builder, it.value);
			append(*builder, "\n");
		}

		append(*builder, "\n");
	}

	return builder_to_string(*builder);
}

write_ini_file :: (path: string, ini: Ini_File) -> bool {
	content := serialize_ini(ini);
	return write_entire_file(path, content);
}