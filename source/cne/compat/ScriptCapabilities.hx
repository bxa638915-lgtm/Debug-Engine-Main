package cne.compat;

import haxe.io.Path;
import funkin.backend.assets.ModsFolder;

/**
 * Describes the scripting formats this build can execute.
 * Container formats are reported separately from script languages.
 */
class ScriptCapabilities
{
	/** Version of the compatibility information exposed to scripts. */
	public static inline var API_VERSION:Int = 1;

	private static final SUPPORTED_LANGUAGES:Array<String> = ["hscript" #if LUA_ALLOWED, "lua" #end];
	private static final SUPPORTED_RUNTIMES:Array<String> = ["hscript-improved" #if LUA_ALLOWED, "luajit" #end];
	private static final SUPPORTED_SCRIPT_EXTENSIONS:Array<String> = ["hx", "hscript", "hsc", "hxs", "hxc" #if LUA_ALLOWED, "lua" #end];
	private static final CONTAINER_EXTENSIONS:Array<String> = ["pack"];

	/** Returns whether a scripting language has an executable runtime in this engine. */
	public static function supportsLanguage(language:String):Bool
	{
		if (language == null) return false;

		var value = StringTools.trim(language).toLowerCase();
		return SUPPORTED_LANGUAGES.contains(value) || SUPPORTED_RUNTIMES.contains(value);
	}

	/** Returns whether a file path or extension is executed as a script. */
	public static function supportsScriptFile(pathOrExtension:String):Bool
	{
		return SUPPORTED_SCRIPT_EXTENSIONS.contains(getExtension(pathOrExtension));
	}

	/** Returns whether a file path or extension is a supported script container. */
	public static function isContainerFile(pathOrExtension:String):Bool
	{
		return CONTAINER_EXTENSIONS.contains(getExtension(pathOrExtension));
	}

	/** Returns a copy of the executable script extensions. */
	public static function getSupportedScriptExtensions():Array<String>
	{
		return SUPPORTED_SCRIPT_EXTENSIONS.copy();
	}

	/** Returns a copy of the supported container extensions. */
	public static function getContainerExtensions():Array<String>
	{
		return CONTAINER_EXTENSIONS.copy();
	}

	/**
		Adds metadata for an adapter after its registry accepted registration.
		The adapter registry remains responsible for dispatch and collision checks.
	**/
	public static function registerAdapter(language:String, runtime:String, extensions:Array<String>):Void
	{
		var normalizedLanguage = language == null ? "" : StringTools.trim(language).toLowerCase();
		var normalizedRuntime = runtime == null ? "" : StringTools.trim(runtime).toLowerCase();
		if (normalizedLanguage.length > 0 && !SUPPORTED_LANGUAGES.contains(normalizedLanguage)) SUPPORTED_LANGUAGES.push(normalizedLanguage);
		if (normalizedRuntime.length > 0 && !SUPPORTED_RUNTIMES.contains(normalizedRuntime)) SUPPORTED_RUNTIMES.push(normalizedRuntime);
		if (extensions != null)
			for (extension in extensions)
			{
				var normalizedExtension = getExtension(extension);
				if (normalizedExtension.length > 0 && !SUPPORTED_SCRIPT_EXTENSIONS.contains(normalizedExtension))
					SUPPORTED_SCRIPT_EXTENSIONS.push(normalizedExtension);
			}
	}

	/** Returns a fresh, script-friendly snapshot of this build's scripting support. */
	public static function getCompatibilityInfo():Dynamic
	{
		return {
			apiVersion: API_VERSION,
			platform: getPlatform(),
			globalScripts: #if GLOBAL_SCRIPT true #else false #end,
			modSupport: #if MOD_SUPPORT true #else false #end,
			languages: SUPPORTED_LANGUAGES.copy(),
			runtimes: SUPPORTED_RUNTIMES.copy(),
			scriptExtensions: getSupportedScriptExtensions(),
			containerExtensions: getContainerExtensions(),
			psychLuaProfile: getPsychLuaProfile(),
			psychLuaProfiles: PsychLuaProfile.supportedProfiles(),
			psychLuaProfileConfig: PsychLuaProfile.CONFIG_PATH,
			psychLuaProfileConfigStatus: getPsychLuaProfileConfigStatus(),
			supportsLanguage: supportsLanguage,
			supportsScriptFile: supportsScriptFile,
			isContainerFile: isContainerFile
		};
	}

	/** Returns the script-friendly compatibility fields that Lua can copy into a table. */
	public static function getLuaCompatibilityInfo():Dynamic
	{
		return {
			apiVersion: API_VERSION,
			platform: getPlatform(),
			globalScripts: #if GLOBAL_SCRIPT true #else false #end,
			modSupport: #if MOD_SUPPORT true #else false #end,
			languages: SUPPORTED_LANGUAGES.copy(),
			runtimes: SUPPORTED_RUNTIMES.copy(),
			scriptExtensions: getSupportedScriptExtensions(),
			containerExtensions: getContainerExtensions(),
			psychLuaProfile: getPsychLuaProfile(),
			psychLuaProfiles: PsychLuaProfile.supportedProfiles(),
			psychLuaProfileConfig: PsychLuaProfile.CONFIG_PATH,
			psychLuaProfileConfigStatus: getPsychLuaProfileConfigStatus()
		};
	}

	private static function getPsychLuaProfile():String
	{
		return ModsFolder.currentPsychLuaProfile == null ? PsychLuaProfile.UNSPECIFIED : ModsFolder.currentPsychLuaProfile.profile;
	}

	private static function getPsychLuaProfileConfigStatus():String
	{
		var report = ModsFolder.lastPsychLuaCompatibilityReport;
		var status:Dynamic = report == null ? null : Reflect.field(report, "configStatus");
		return status == null ? "missing" : Std.string(status);
	}

	private static function getPlatform():String
	{
		return #if windows "windows" #elseif linux "linux" #elseif mac "macOS" #elseif web "web" #elseif html5 "web" #elseif mobile "mobile" #else "unknown" #end;
	}

	private static function getExtension(pathOrExtension:String):String
	{
		if (pathOrExtension == null) return "";

		var value = StringTools.trim(pathOrExtension);
		if (value.length == 0) return "";

		var extension = Path.extension(value);
		if (extension.length == 0)
		{
			extension = value;
			if (StringTools.startsWith(extension, ".")) extension = extension.substr(1);
		}

		return extension.toLowerCase();
	}
}
