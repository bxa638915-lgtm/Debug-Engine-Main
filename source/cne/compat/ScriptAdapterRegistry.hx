package cne.compat;

import haxe.io.Path;

/**
	A small, runtime-neutral registry for script adapters.
	The registry owns extension dispatch while each adapter owns parsing,
	execution, errors, and its runtime lifecycle.
**/
class ScriptAdapterRegistry<T>
{
	private var adapters:Array<ScriptAdapter<T>> = [];

	public function new()
	{
	}

	/**
		Registers one adapter. Extensions may be supplied as bare extensions or
		file paths. Registration is rejected without changing state when any
		extension is invalid, duplicated, or already claimed.
	**/
	public function register(language:String, runtime:String, extensions:Array<String>, createFile:String->T, createFromString:(String, String)->T):Bool
	{
		var normalizedLanguage = normalizeName(language);
		var normalizedRuntime = normalizeName(runtime);
		if (normalizedLanguage.length == 0 || normalizedRuntime.length == 0 || extensions == null || extensions.length == 0 || createFile == null || createFromString == null)
			return false;

		for (adapter in adapters)
			if (adapter.language == normalizedLanguage)
				return false;

		var normalizedExtensions:Array<String> = [];
		for (extension in extensions)
		{
			var normalized = getExtension(extension);
			if (normalized.length == 0 || normalizedExtensions.contains(normalized) || supportsExtension(normalized))
				return false;
			normalizedExtensions.push(normalized);
		}

		adapters.push({
			language: normalizedLanguage,
			runtime: normalizedRuntime,
			extensions: normalizedExtensions,
			createFile: createFile,
			createFromString: createFromString
		});
		return true;
	}

	/** Returns whether a language or runtime name has a registered adapter. */
	public function supportsLanguage(language:String):Bool
	{
		var name = normalizeName(language);
		if (name.length == 0) return false;

		for (adapter in adapters)
			if (adapter.language == name || adapter.runtime == name)
				return true;
		return false;
	}

	/** Returns whether an extension or path has a registered adapter. */
	public function supportsExtension(pathOrExtension:String):Bool
	{
		var extension = getExtension(pathOrExtension);
		if (extension.length == 0) return false;

		for (adapter in adapters)
			if (adapter.extensions.contains(extension))
				return true;
		return false;
	}

	/** Creates an adapter instance for a file path, or returns null if unsupported. */
	public function create(path:String):Null<T>
	{
		var adapter = findAdapter(path);
		return adapter == null ? null : adapter.createFile(path);
	}

	/** Creates an adapter instance for in-memory source, or returns null if unsupported. */
	public function createFromString(code:String, path:String):Null<T>
	{
		var adapter = findAdapter(path);
		return adapter == null ? null : adapter.createFromString(code, path);
	}

	/** Returns a copy of the registered canonical language names. */
	public function getLanguages():Array<String>
	{
		var result:Array<String> = [];
		for (adapter in adapters)
			result.push(adapter.language);
		return result;
	}

	/** Returns a copy of the registered runtime names. */
	public function getRuntimes():Array<String>
	{
		var result:Array<String> = [];
		for (adapter in adapters)
			if (!result.contains(adapter.runtime)) result.push(adapter.runtime);
		return result;
	}

	/** Returns a copy of the registered source extensions. */
	public function getSupportedExtensions():Array<String>
	{
		var result:Array<String> = [];
		for (adapter in adapters)
			for (extension in adapter.extensions)
				result.push(extension);
		return result;
	}

	private function findAdapter(pathOrExtension:String):Null<ScriptAdapter<T>>
	{
		var extension = getExtension(pathOrExtension);
		if (extension.length == 0) return null;

		for (adapter in adapters)
			if (adapter.extensions.contains(extension))
				return adapter;
		return null;
	}

	private static function normalizeName(value:String):String
	{
		return value == null ? "" : StringTools.trim(value).toLowerCase();
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

private typedef ScriptAdapter<T> =
{
	final language:String;
	final runtime:String;
	final extensions:Array<String>;
	final createFile:String->T;
	final createFromString:(String, String)->T;
}
