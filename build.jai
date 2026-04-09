#run {	
	set_build_options_dc(.{do_output=false});
	// Builds Engine DLL.
	{
		w := compiler_create_workspace();
		options := get_build_options(w);
		copy_commonly_propagated_fields(get_build_options(), *options);
		options.output_executable_name = "engine";
		options.output_type = .DYNAMIC_LIBRARY;
		set_optimization(*options, .OPTIMIZED); // @Debug ??
		set_build_options(options, w);

		compiler_begin_intercept(w);

		add_build_file("core/module.jai", w);

		while true {
			message := compiler_wait_for_message();
			if message.kind == .COMPLETE {
                mc := cast(*Message_Complete) message;
                if mc.error_code != .NONE {
                    print("DLL compilation failed; exiting without compiling the main program.\n");
                    return;
                }

                break;
            }
		}

		compiler_end_intercept(w);
	}

	// Build Game Executable.
	{
		w := compiler_create_workspace();
		options := get_build_options(w);
		copy_commonly_propagated_fields(get_build_options(), *options);
		options.output_executable_name = "editor_program";
		options.output_type = .EXECUTABLE;
		set_build_options(options, w);

		add_build_file("main.jai", w);
	}	

};

#import "Basic";
#import "Compiler";