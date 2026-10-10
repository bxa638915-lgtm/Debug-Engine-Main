package dbe.compatibility.assets;

import haxe.io.Path;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

/** Resolves an external Funkin.assets checkout without copying its files into DBE. */
class VSliceAssetsConfig {
	public static inline var CONFIG_PATH:String = "./config/vslice-assets-path.txt";
	public static inline var ENVIRONMENT_VARIABLE:String = "FUNKIN_ASSETS_PATH";

	/** Read the highest-priority path from `-vslice-assets`, the environment, or the config file. */
	public static function configuredPath():Null<String> {
		#if sys
		var args = Sys.args();
		for (index in 0...args.length) {
			var arg = args[index];
			if (StringTools.startsWith(arg, "-vslice-assets="))
				return _clean(arg.substr("-vslice-assets=".length));
			if (arg == "-vslice-assets" && index + 1 < args.length)
				return _clean(args[index + 1]);
		}

		var environmentPath = _clean(Sys.getEnv(ENVIRONMENT_VARIABLE));
		if (environmentPath != null) return environmentPath;
		if (FileSystem.exists(CONFIG_PATH) && !FileSystem.isDirectory(CONFIG_PATH))
			return _clean(File.getContent(CONFIG_PATH));
		#end
		return null;
	}

	/** Accept either the repository root (`.../Funkin.assets`) or its `assets` directory. */
	public static function resolveAssetsRoot(configured:String):Null<String> {
		#if sys
		var path = _clean(configured);
		if (path == null) return null;
		path = Path.normalize(path);
		if (!FileSystem.exists(path) || !FileSystem.isDirectory(path)) return null;

		var nestedAssets = Path.join([path, "assets"]);
		if (FileSystem.exists(nestedAssets) && FileSystem.isDirectory(nestedAssets))
			return Path.normalize(nestedAssets);

		for (directory in ["data", "images", "songs", "music", "fonts"])
			if (FileSystem.exists(Path.join([path, directory])) && FileSystem.isDirectory(Path.join([path, directory])))
				return path;
		#end
		return null;
	}

	#if sys
	static function _clean(value:Null<String>):Null<String> {
		if (value == null) return null;
		var cleaned = StringTools.trim(value);
		if (cleaned.length >= 2 && ((cleaned.charAt(0) == '"' && cleaned.charAt(cleaned.length - 1) == '"')
			|| (cleaned.charAt(0) == "'" && cleaned.charAt(cleaned.length - 1) == "'")))
			cleaned = cleaned.substring(1, cleaned.length - 1);
		return cleaned.length == 0 ? null : cleaned;
	}
	#end
}
