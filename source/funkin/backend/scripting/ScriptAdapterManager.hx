package funkin.backend.scripting;

import cne.compat.ScriptAdapterRegistry;
import cne.compat.ScriptCapabilities;

/**
	Engine-level registry that binds script extensions to concrete runtimes.
	Language implementations register here instead of adding another hard-coded
	branch to Script.create().
**/
class ScriptAdapterManager
{
	private static var adapters:ScriptAdapterRegistry<Script>;

	private static function getRegistry():ScriptAdapterRegistry<Script>
	{
		if (adapters == null)
		{
			adapters = new ScriptAdapterRegistry<Script>();
			adapters.register(
				"hscript",
				"hscript-improved",
				["hx", "hscript", "hsc", "hxs", "hxc"],
				(path:String) -> new HScript(path),
				(code:String, path:String) -> new HScript(path).loadFromString(code)
			);
			#if LUA_ALLOWED
			if (adapters.register(
				"lua",
				"luajit",
				["lua"],
				(path:String) -> new LuaScript(path),
				(code:String, path:String) -> new LuaScript(path, code)
			))
				ScriptCapabilities.registerAdapter("lua", "luajit", ["lua"]);
			#end
		}
		return adapters;
	}

	/** Registers a runtime adapter for additional source extensions. */
	public static function register(language:String, runtime:String, extensions:Array<String>, createFile:String->Script, createFromString:(String, String)->Script):Bool
	{
		var registered = getRegistry().register(language, runtime, extensions, createFile, createFromString);
		if (registered) ScriptCapabilities.registerAdapter(language, runtime, extensions);
		return registered;
	}

	public static function supportsLanguage(language:String):Bool
	{
		return getRegistry().supportsLanguage(language);
	}

	public static function supportsExtension(pathOrExtension:String):Bool
	{
		return getRegistry().supportsExtension(pathOrExtension);
	}

	public static function create(path:String):Null<Script>
	{
		return getRegistry().create(path);
	}

	public static function createFromString(code:String, path:String):Null<Script>
	{
		return getRegistry().createFromString(code, path);
	}

	public static function getLanguages():Array<String>
	{
		return getRegistry().getLanguages();
	}

	public static function getRuntimes():Array<String>
	{
		return getRegistry().getRuntimes();
	}

	public static function getSupportedExtensions():Array<String>
	{
		return getRegistry().getSupportedExtensions();
	}
}
