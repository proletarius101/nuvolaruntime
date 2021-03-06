/*
 * Copyright 2014-2019 Jiří Janoušek <janousek.jiri@gmail.com>
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

#if HAVE_CEF
namespace Nuvola {

public class CefOptions : WebOptions {
    public override VersionTuple engine_version {get; protected set;}
    public CefGtk.WebContext default_context {get; private set; default = null;}
    public bool widevine_required {get; set; default = false;}
    public bool flash_required {get; private set; default = false;}
    public File widevine_dir {get; private set;}
    public File flash_dir {get; private set;}
    public CefGtk.InitFlags flags {get; private set;}
    public bool widevine_found {get; private set; default = false;}
    public bool flash_found {get; private set; default = false;}

    public CefOptions(WebAppStorage storage, Connection? connection) {
        base(storage, connection);
    }

    construct {
        engine_version = VersionTuple.parse(Cef.get_chromium_version());
        widevine_dir = storage.data_dir.get_child("widevine");
        flash_dir = storage.data_dir.get_child("flash");
        flags = new CefGtk.InitFlags();
        flags.auto_play_policy = CefGtk.AutoPlayPolicy.NO_USER_GESTURE_REQUIRED;
    }

    public override string get_name_version() {
        return "Chromium %s, ValaCEF %s".printf(Cef.get_chromium_version(), Cef.get_valacef_version());
    }

    public override string get_name() {
        return "Chromium/ValaCEF";
    }

    public override async void gather_format_support_info(WebApp web_app) {
        if (widevine_required && connection != null) {
            var wd = new CefWidevineDownloader(connection, widevine_dir);
            widevine_found = wd.exists() && !wd.needs_update();
            if (!widevine_found) {
                var dialog = new CefWidevineDownloaderDialog(wd, web_app.name);
                yield dialog.wait_for_result();
                dialog.destroy();
                widevine_found = wd.exists() && !wd.needs_update();
            }
        } else {
            widevine_found = true;
        }
        if (flash_required && connection != null) {
            var fd = new CefFlashDownloader(connection, flash_dir);
            try {
                if (fd.exists()) {
                    yield fd.check_latest();
                }
            } catch (CefFlashDownloaderError e) {
                Drt.warn_error(e, "Failed to get Flash info.");
            }
            flash_found = fd.exists() && !fd.needs_update();
            if (!flash_found) {
                var dialog = new CefFlashDownloaderDialog(fd, web_app.name);
                yield dialog.wait_for_result();
                dialog.destroy();
                flash_found = fd.exists() && !fd.needs_update();
            }
        } else {
            flash_found = true;
        }
        init(web_app);
        CefGtk.InitializationResult result = CefGtk.get_init_result();
        CefGtk.WidevinePlugin widevine = result.widevine_plugin;
        if (widevine != null && !widevine.registration_complete) {
            SourceFunc cb = gather_format_support_info.callback;
            ulong handler_id = widevine.notify["registration-complete"].connect_after(() => Idle.add((owned) cb));
            yield;
            widevine.disconnect(handler_id);
        }
    }

    public void init(WebApp web_app) {
        if (default_context == null) {
            string? user_agent = WebOptions.make_user_agent(web_app.user_agent);
            string product = "Chrome/%s".printf(Cef.get_chromium_version());

            CefGtk.ProxyType proxy_type = CefGtk.ProxyType.SYSTEM;
            string? proxy_server = null;
            int proxy_port = 0;
            if (connection != null) {
                switch(connection.get_network_proxy(out proxy_server, out proxy_port)) {
                case NetworkProxyType.DIRECT:
                    proxy_type = CefGtk.ProxyType.NONE;
                    break;
                case NetworkProxyType.SOCKS:
                    proxy_type = CefGtk.ProxyType.SOCKS;
                    break;
                case NetworkProxyType.HTTP:
                    proxy_type = CefGtk.ProxyType.HTTP;
                    break;
                default:
                    proxy_type = CefGtk.ProxyType.SYSTEM;
                    break;
                }
            }

            CefGtk.init(
                flags,
                web_app.scale_factor,
                widevine_required && widevine_found ? widevine_dir.get_path() : null,
                flash_required && flash_found ? flash_dir.get_path() : null,
                user_agent, product,
                proxy_type, proxy_server, (uint) proxy_port);
            default_context = new CefGtk.WebContext(storage.create_data_subdir("cef").get_path());
        }
    }

    public override WebEngine create_web_engine(WebApp web_app) {
        init(web_app);
        return new CefEngine(this, web_app);
    }

    public override void shutdown() {
        CefGtk.shutdown();
    }

    public override Drt.RequirementState supports_requirement(string type, string? parameter, out string? error) {
        error = null;
        switch (type) {
        case "chromium":
        case "chrome":
            if (parameter == null) {
                return Drt.RequirementState.SUPPORTED;
            }
            string param = parameter.strip().down();
            if (param[0] == 0) {
                return Drt.RequirementState.SUPPORTED;
            }
            string[] versions = param.split(".");
            if (versions.length > 4) {
                error = "%s[] received invalid version parameter '%s'.".printf(type, param);
                return Drt.RequirementState.ERROR;
            }
            uint[] uint_versions = {0, 0, 0, 0};
            for (var i = 0; i < versions.length; i++) {
                int version = int.parse(versions[i]);
                if (i < 0) {
                    error = "%s[] received invalid version parameter '%s'.".printf(type, param);
                    return Drt.RequirementState.ERROR;
                }
                uint_versions[i] = (uint) version;
            }
            return (engine_version.is_greater_or_equal_to(VersionTuple.uintv(uint_versions))
                ? Drt.RequirementState.SUPPORTED : Drt.RequirementState.UNSUPPORTED);
        default:
            return Drt.RequirementState.UNSUPPORTED;
        }
    }

    public override Drt.RequirementState supports_feature(string name, out string? error) {
        error = null;
        switch (name) {
        case "mse":
            return Drt.RequirementState.SUPPORTED;
        case "widevine":
            widevine_required = true;
            CefGtk.InitializationResult? result = CefGtk.get_init_result();
            if (result == null) {
                return Drt.RequirementState.UNKNOWN;
            }
            CefGtk.WidevinePlugin widevine = result.widevine_plugin;
            return (widevine != null && widevine.available ?
                Drt.RequirementState.SUPPORTED : Drt.RequirementState.UNSUPPORTED);
        case "flash":
            flash_required = true;
            CefGtk.InitializationResult? result = CefGtk.get_init_result();
            if (result == null) {
                return Drt.RequirementState.UNKNOWN;
            }
            CefGtk.FlashPlugin flash = result.flash_plugin;
            return (flash != null && flash.available
                ? Drt.RequirementState.SUPPORTED : Drt.RequirementState.UNSUPPORTED);
        default:
            return Drt.RequirementState.UNSUPPORTED;
        }
    }

    public override Drt.RequirementState supports_codec(string name, out string? error) {
        error = null;
        switch (name) {
        case "mp3":
        case "h264":
            return Drt.RequirementState.SUPPORTED;
        default:
            return Drt.RequirementState.UNSUPPORTED;
        }
    }

    public override string[] get_format_support_warnings() {
        string[] warnings = {};
        CefGtk.InitializationResult? result = CefGtk.get_init_result();
        if (result != null) {
            if (result.flash_plugin != null && result.flash_plugin.registration_error != null) {
                warnings += Markup.printf_escaped("Failed to load Flash plugin: %s",
                    result.flash_plugin.registration_error);
            }
            if (result.widevine_plugin != null && result.widevine_plugin.registration_error != null) {
                warnings += Markup.printf_escaped("Failed to load Widevine plugin: %s",
                    result.widevine_plugin.registration_error);
            }
        }
        return warnings;
    }
}

} // namespace Nuvola
#endif
