import cne.compat.ScriptCapabilities;

class ScriptCapabilitiesTest
{
	static function assertTrue(value:Bool, message:String):Void
	{
		if (!value) throw message;
	}

	static function assertFalse(value:Bool, message:String):Void
	{
		if (value) throw message;
	}

	static function main():Void
	{
		assertTrue(ScriptCapabilities.supportsLanguage("hscript"), "HScript must be reported as supported");
		assertTrue(ScriptCapabilities.supportsLanguage("HSCRIPT-IMPROVED"), "HScript Improved alias must be case-insensitive");
		#if LUA_ALLOWED
		assertTrue(ScriptCapabilities.supportsLanguage("lua"), "Lua must be reported when the native LuaJIT adapter is compiled in");
		assertTrue(ScriptCapabilities.supportsLanguage("luajit"), "The LuaJIT runtime must be reported separately");
		#else
		assertFalse(ScriptCapabilities.supportsLanguage("lua"), "Lua must not be reported without its native adapter");
		#end
		assertFalse(ScriptCapabilities.supportsLanguage("javascript"), "JavaScript must not be reported as executable");
		assertFalse(ScriptCapabilities.supportsLanguage("typescript"), "TypeScript must not be reported as executable");

		assertTrue(ScriptCapabilities.supportsScriptFile("mods/example.HX"), "Haxe-style HScript extension must be supported");
		assertTrue(ScriptCapabilities.supportsScriptFile("example.hscript"), "HScript extension must be supported");
		assertTrue(ScriptCapabilities.supportsScriptFile("mods/stage.hxc"), "V-Slice scripted-class files must be recognized as HScript source");
		assertTrue(ScriptCapabilities.supportsScriptFile("example.hsc"), "HSC extension must be supported");
		assertTrue(ScriptCapabilities.supportsScriptFile("example.hxs"), "HXS extension must be supported");
		assertFalse(ScriptCapabilities.supportsScriptFile("bundle.pack"), "Pack containers must not be classified as executable source files");
		#if LUA_ALLOWED
		assertTrue(ScriptCapabilities.supportsScriptFile("example.lua"), "Lua files must be reported as executable when the adapter is enabled");
		#else
		assertFalse(ScriptCapabilities.supportsScriptFile("example.lua"), "Lua files must not be reported as executable without the adapter");
		#end
		assertFalse(ScriptCapabilities.supportsScriptFile("example.js"), "JavaScript files must not be reported as executable");
		assertFalse(ScriptCapabilities.supportsScriptFile("example.ts"), "TypeScript files must not be reported as executable");

		assertTrue(ScriptCapabilities.isContainerFile("bundle.pack"), "Pack files must be identified as containers");
		assertFalse(ScriptCapabilities.isContainerFile("example.hx"), "Source scripts must not be identified as containers");
		assertFalse(ScriptCapabilities.isContainerFile("bundle.lua"), "Unsupported files must not be identified as containers");

		var info = ScriptCapabilities.getCompatibilityInfo();
		assertTrue(info.apiVersion == ScriptCapabilities.API_VERSION, "Compatibility info must report its API version");
		assertTrue(info.languages.contains("hscript"), "Compatibility info must list HScript");
		assertTrue(info.runtimes != null && info.runtimes.contains("hscript-improved"), "Compatibility info must identify the HScript runtime separately from the language");
		#if LUA_ALLOWED
		assertTrue(info.languages.contains("lua") && info.runtimes.contains("luajit"), "Lua-enabled builds must advertise Lua and LuaJIT");
		#else
		assertFalse(info.languages.contains("lua") || info.runtimes.contains("luajit"), "Builds without Lua must not advertise its runtime");
		#end
		assertTrue(info.scriptExtensions.contains("hx"), "Compatibility info must list runnable script extensions");
		assertTrue(info.scriptExtensions.contains("hxc"), "Compatibility info must list V-Slice scripted-class source files");
		assertTrue(info.containerExtensions.contains("pack"), "Compatibility info must list container extensions separately");
		assertTrue(Std.isOfType(info.platform, String), "Compatibility info must report a target platform");
		assertTrue(Std.isOfType(info.globalScripts, Bool), "Compatibility info must report whether global scripts are compiled in");
		assertTrue(Std.isOfType(info.modSupport, Bool), "Compatibility info must report whether mod support is compiled in");
		#if windows
		assertTrue(info.platform == "windows", "Windows builds must report their target platform");
		#elseif linux
		assertTrue(info.platform == "linux", "Linux builds must report their target platform");
		#elseif mac
		assertTrue(info.platform == "macOS", "macOS builds must report their target platform");
		#end
		#if GLOBAL_SCRIPT
		assertTrue(info.globalScripts, "Builds with GLOBAL_SCRIPT must report global script support");
		#else
		assertFalse(info.globalScripts, "Builds without GLOBAL_SCRIPT must report global scripts as unavailable");
		#end
		#if MOD_SUPPORT
		assertTrue(info.modSupport, "Builds with MOD_SUPPORT must report mod support");
		#else
		assertFalse(info.modSupport, "Builds without MOD_SUPPORT must report mod support as unavailable");
		#end

		var interp = new hscript.Interp();
		var parser = new hscript.Parser();
		interp.variables.set("engine", {compatibility: info});
		interp.execute(parser.parseString('var canRunHScript = engine.compatibility.supportsLanguage("hscript"); var canRunLua = engine.compatibility.supportsLanguage("lua"); var canReadPack = engine.compatibility.isContainerFile("bundle.pack");'));
		assertTrue(interp.variables.get("canRunHScript") == true, "HScript scripts must be able to query supported runtimes");
		#if LUA_ALLOWED
		assertTrue(interp.variables.get("canRunLua") == true, "HScript scripts must see the compiled Lua runtime as available");
		#else
		assertTrue(interp.variables.get("canRunLua") == false, "HScript scripts must see unsupported runtimes as false");
		#end
		assertTrue(interp.variables.get("canReadPack") == true, "HScript scripts must be able to identify containers");

		Sys.println("ScriptCapabilitiesTest: PASS");
	}
}
