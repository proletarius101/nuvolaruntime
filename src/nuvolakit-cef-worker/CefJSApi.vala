/*
 * Copyright 2011-2017 Jiří Janoušek <janousek.jiri@gmail.com>
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met: 
 * 
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer. 
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution. 
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

namespace Nuvola {

private const string SCRIPT_WRAPPER = """window.__nuvola_func__ = function() {
window.__nuvola_func__ = null;
if (this == window) throw Error("Nuvola object is not bound to 'this'.");
%s
;}
""";
private extern const int VERSION_MAJOR;
private extern const int VERSION_MINOR;
private extern const int VERSION_BUGFIX;
private extern const string VERSION_SUFFIX;

public class CefJSApi : GLib.Object {
	private const string MAIN_JS = "main.js";
	private const string META_JSON = "metadata.json";
	private const string META_PROPERTY = "meta";
	public const string JS_DIR = "js";
	/**
	 * Name of file with integration script.
	 */
	private const string INTEGRATE_JS = "integrate.js";
	/**
	 * Name of file with settings script.
	 */
	private const string SETTINGS_SCRIPT = "settings.js";
	/**
	 * Major version of the JavaScript API
	 */
	public const int API_VERSION_MAJOR = VERSION_MAJOR;
	public const int API_VERSION_MINOR = VERSION_MINOR;
	public const int API_VERSION = API_VERSION_MAJOR * 100 + API_VERSION_MINOR;
	
	private Drt.Storage storage;
	private File data_dir;
	private File config_dir;
	private Drt.KeyValueStorage[] key_value_storages;
	private uint[] webkit_version;
	private uint[] libsoup_version;
	private bool warn_on_sync_func;
	private Cef.V8context? v8_ctx = null;
	private Cef.V8value? main_object = null;
	
	public CefJSApi(Drt.Storage storage, File data_dir, File config_dir, Drt.KeyValueStorage config,
	Drt.KeyValueStorage session, uint[] webkit_version, uint[] libsoup_version, bool warn_on_sync_func) {
		this.storage = storage;
		this.data_dir = data_dir;
		this.config_dir = config_dir;
		this.key_value_storages = {config, session};
		assert(webkit_version.length >= 3);
		this.webkit_version = webkit_version;
		this.libsoup_version = libsoup_version;
		this.warn_on_sync_func = warn_on_sync_func;
	}
	
	public virtual signal void call_ipc_method_void(string name, Variant? data) {
		message("call_ipc_method_void('%s', %s)", name, data == null ? "null" : data.print(false));
	}
	
	public virtual signal void call_ipc_method_async(string name, Variant? data, int id) {
		message("call_ipc_method_async('%s', %s, %d)", name, data == null ? "null" : data.print(false), id);
	}
	
	public bool is_valid() {
		return v8_ctx != null;
	}
	
	public void inject(Cef.V8context v8_ctx) {
		if (this.v8_ctx != null) {
			this.v8_ctx.exit();
			this.v8_ctx = null;
		}
		assert(v8_ctx.is_valid() > 0);
		v8_ctx.enter();
		main_object = Cef.v8value_create_object(null, null);
		main_object.ref();
		Cef.V8.set_int(main_object, "API_VERSION_MAJOR", API_VERSION_MAJOR);
		Cef.V8.set_int(main_object, "API_VERSION_MINOR", API_VERSION_MINOR);
		Cef.V8.set_int(main_object, "API_VERSION", API_VERSION);
		Cef.V8.set_int(main_object, "VERSION_MAJOR", VERSION_MAJOR);
		Cef.V8.set_int(main_object, "VERSION_MINOR", VERSION_MINOR);
		Cef.V8.set_int(main_object, "VERSION_MICRO", VERSION_BUGFIX);
		Cef.V8.set_int(main_object, "VERSION_BUGFIX", VERSION_BUGFIX);
		Cef.V8.set_string(main_object, "VERSION_SUFFIX", VERSION_SUFFIX);
		Cef.V8.set_int(main_object, "VERSION", Nuvola.get_encoded_version());
		Cef.V8.set_uint(main_object, "WEBKITGTK_VERSION", get_webkit_version());
		Cef.V8.set_uint(main_object, "WEBKITGTK_MAJOR", webkit_version[0]);
		Cef.V8.set_uint(main_object, "WEBKITGTK_MINOR", webkit_version[1]);
		Cef.V8.set_uint(main_object, "WEBKITGTK_MICRO", webkit_version[2]);
		Cef.V8.set_uint(main_object, "LIBSOUP_VERSION", get_libsoup_version());
		Cef.V8.set_uint(main_object, "LIBSOUP_MAJOR", libsoup_version[0]);
		Cef.V8.set_uint(main_object, "LIBSOUP_MINOR", libsoup_version[1]);
		Cef.V8.set_uint(main_object, "LIBSOUP_MICRO", libsoup_version[2]);
		Cef.V8.set_value(main_object, "_callIpcMethodVoid",
			CefGtk.Function.create("_callIpcMethodVoid", call_ipc_method_void_func));
		Cef.V8.set_value(main_object, "_callIpcMethodAsync",
			CefGtk.Function.create("_callIpcMethodAsync", call_ipc_method_async_func));

		File? main_js = storage.user_data_dir.get_child(JS_DIR).get_child(MAIN_JS);
		if (!main_js.query_exists()) {
			main_js = null;
			foreach (var dir in storage.data_dirs) {
				main_js = dir.get_child(JS_DIR).get_child(MAIN_JS);
				if (main_js.query_exists()) {
					break;
				}
				main_js = null;
			}
		}
		
		if (main_js == null) {
			error("Failed to find a core component main.js. This probably means the application has not been installed correctly or that component has been accidentally deleted.");
		}
		this.v8_ctx = v8_ctx;
		if (!execute_script_from_file(main_js)) {
			error("Failed to initialize a core component main.js located at '%s'. Initialization exited with error:", main_js.get_path());
		}
		
		var meta_json = data_dir.get_child(META_JSON);
		if (!meta_json.query_exists()) {
			error("Failed to find a web app component %s. This probably means the web app integration has not been installed correctly or that component has been accidentally deleted.", META_JSON);
		}
		string meta_json_data;
		try {
			meta_json_data = Drt.System.read_file(meta_json);
		} catch (GLib.Error e) {
			error("Failed load a web app component %s. This probably means the web app integration has not been installed correctly or that component has been accidentally deleted.\n\n%s", META_JSON, e.message);
		}
		
		string? json_error = null; 
		var meta = Cef.V8.parse_json(v8_ctx, meta_json_data, out json_error);
		if (meta == null) {
			error(json_error);
		}
		Cef.V8.set_value(main_object, "meta", meta);
	}
	
	public void integrate(Cef.V8context v8_ctx) {
		var integrate_js = data_dir.get_child(INTEGRATE_JS);
		if (!integrate_js.query_exists()) {
			error("Failed to find a web app component %s. This probably means the web app integration has not been installed correctly or that component has been accidentally deleted.", INTEGRATE_JS);
		}
		if (!execute_script_from_file(integrate_js)) {
			error("Failed to initialize a web app component %s located at '%s'. Initialization exited with error:\n\n%s", INTEGRATE_JS, integrate_js.get_path(), "e.message");
		}
	}
	
	public void release_context(Cef.V8context v8_ctx) {
		if (v8_ctx == this.v8_ctx) {
			v8_ctx.exit();
			this.v8_ctx = null;
		}
	}
	
	public bool execute_script_from_file(File file) {
		string script;
		try {
			script = Drt.System.read_file(file);
		} catch (GLib.Error e) 	{
			error("Unable to read script %s: %s", file.get_path(), e.message);
		}
		return execute_script(script, file.get_uri(), 1);
	}
	
	public bool execute_script(string script, string path, int line) {
		assert(v8_ctx != null);
        Cef.String _script = {};
        var wrapped_script = SCRIPT_WRAPPER.printf(script).replace("\t", " ");
//~         stderr.puts(wrapped_script);
        Cef.set_string(&_script, wrapped_script);
        Cef.String _path = {};
        Cef.set_string(&_path, path);
        Cef.V8value? retval = null;
        Cef.V8exception? exception = null;
        var result = (bool) v8_ctx.eval(&_script, &_path, line, out retval, out exception);
        if (exception != null) {
			error(Cef.V8.format_exception(exception));
		}
		if (result) {
			var global_object = v8_ctx.get_global();
			var func = Cef.V8.get_function(global_object, "__nuvola_func__");
			assert(func != null);
			main_object.ref();
			var ret_val = func.execute_function(main_object, {});
			if (ret_val == null) {
				result = false;
				error(Cef.V8.format_exception(func.get_exception()));
			} else {
				result = true;
			}
		}
        return result;
	}
	
	public void send_async_response(int id, Variant? response, GLib.Error? error) {
		if (is_valid()) {
			var args = new Variant("(imvmv)", (int32) id, response,
				error == null ? null : new Variant.string(error.message));
			if (response != null) {
				// FIXME: How are we losing a reference here?
				g_variant_ref(response);
			}
			call_function_sync("Nuvola.Async.respond", ref args, false);
		}
	}
	
	public void call_function_sync(string name, ref Variant? arguments, bool propagate_error) throws GLib.Error {	
		GLib.Error? error = null;
		var args = arguments;
		var loop = new MainLoop(MainContext.get_thread_default());
		CefGtk.Task.post(Cef.ThreadId.RENDERER, () => {
			try {
				string[] names = name.split(".");
				Cef.V8value object = main_object;
				if (object == null) {
					throw new JSError.NOT_FOUND("Main object not found.'");
				} 
				for (var i = 1; i < names.length - 1; i++) {
					object = Cef.V8.get_object(object, names[i]);
					if (object == null) {
						throw new JSError.NOT_FOUND("Attribute '%s' not found.'", names[i]);
					}
				}
				var func = Cef.V8.get_function(object, names[names.length - 1]);
				if (func == null) {
					throw new JSError.NOT_FOUND("Attribute '%s' not found.'", names[names.length - 1]);
				}  
				Cef.V8value[] params;
				var size = 0;
				if (args != null) {
					assert(args.is_container()); // FIXME
					size = (int) args.n_children();
					params = new Cef.V8value[size];
					int i = 0;
					foreach (var item in args) {
						string? exception = null;
						var param = Cef.V8.value_from_variant(item, out exception);
						if (param == null) {
							throw new JSError.WRONG_TYPE(exception);
						}
						params[i++] = param;
					}
					foreach (var p in params) {
						p.ref();
					}
				} else {
					params = {};
				}
				object.ref();
				var ret_val = func.execute_function(object, params);
				if (ret_val == null) {
					throw new JSError.FUNC_FAILED("Function '%s' failed. %s",
						name, Cef.V8.format_exception(func.get_exception()));
				}
				if (args != null) {
					Variant[] items = new Variant[size];
					for (var i = 0; i < size; i++) {
						string? exception = null;
						items[i] = Cef.V8.variant_from_value(params[i], out exception);
						if (exception != null) {
							throw new JSError.WRONG_TYPE(exception);
						}
					}
					args = new Variant.tuple(items);
				}
			} catch (GLib.Error e) {
				error = e;
			}
			loop.quit();
		});
		if (error != null) {
			throw error;
		}
		arguments = args;
	}
	
	public uint get_webkit_version() {
		return webkit_version[0] * 10000 + webkit_version[1] * 100 + webkit_version[2];
	}
	
	public uint get_libsoup_version() {
		return libsoup_version[0] * 10000 + libsoup_version[1] * 100 + libsoup_version[2];
	}
	
	private void call_ipc_method_void_func(string? name, Cef.V8value? object, Cef.V8value?[] arguments,
    out Cef.V8value? retval, out string? exception) {
		call_ipc_method_func(name, object, arguments, out retval, out exception, true);
	}
	
	private void call_ipc_method_async_func(string? name, Cef.V8value? object, Cef.V8value?[] arguments,
    out Cef.V8value? retval, out string? exception) {
		call_ipc_method_func(name, object, arguments, out retval, out exception, false);
	}
	
	private void call_ipc_method_func(string? name, Cef.V8value? object, Cef.V8value?[] args,
    out Cef.V8value? retval, out string? exception, bool is_void) {
		retval = null;
		exception = null;
		if (args.length == 0) {
			exception = "At least one argument required.";
			return;
		}
		
		var method = Cef.V8.string_or_null(args[0]);
		if (method == null) {
			exception = "The first argument must be a non-null string.";
			return;
		}
		
		Variant? data = null;
		if (args.length > 1 && args[1].is_null() == 0) {
			data = Cef.V8.variant_from_value(args[1], out exception);
			if (data == null) {
				return;
			}
		}
		/* Void call */
		if (is_void) {
			call_ipc_method_void(method, data);
			retval = Cef.v8value_create_undefined();
			return;
		}
		/* Async call */
		int id = -1;
		if (args.length > 2) {
			id = Cef.V8.any_int(args[2]);
		}
		if (id <= 0) {
			exception = "Argument %d: Integer expected (%d).".printf(2, id);
		} else {
			call_ipc_method_async(method, data, id);
		}
	}
}

} // namespace Nuvola

// FIXME
private extern Variant* g_variant_ref(Variant* variant);