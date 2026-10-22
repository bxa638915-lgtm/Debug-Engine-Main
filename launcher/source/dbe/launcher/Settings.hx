package dbe.launcher;

import dbe.launcher.update.Channel;
import dbe.launcher.util.PathUtil;
import haxe.Json;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/** User preferences, stored next to the launcher executable (`launcher-settings.json`). */
class Settings {
	public var channel:Channel = Stable;
	public var autoCheck:Bool = true;
	public var keepBackups:Int = 3;
	/** Engine root. Empty = parent of the launcher folder. */
	public var enginePath:String = "";
	/** Extra protected rules (saves, configs...) on top of mods/ .dbe/ launcher/. */
	public var protectedExtra:Array<String> = [];
	public var owner:String = LauncherInfo.DEFAULT_OWNER;
	public var repo:String = LauncherInfo.DEFAULT_REPO;
	/** Close the launcher after pressing Play. */
	public var closeOnPlay:Bool = true;

	public var file(default, null):String;

	public function new(file:String)
		this.file = file;

	public static function launcherDir():String
		return Path.directory(Sys.programPath());

	public static function defaultFile():String
		return Path.join([launcherDir(), "launcher-settings.json"]);

	public static function load(?file:String):Settings {
		var s = new Settings(file == null ? defaultFile() : file);
		if (!FileSystem.exists(s.file)) return s;
		try {
			var d:Dynamic = Json.parse(File.getContent(s.file));
			if (d.channel != null) s.channel = Channel.fromString(d.channel);
			if (d.autoCheck != null) s.autoCheck = d.autoCheck == true;
			if (d.keepBackups != null) s.keepBackups = Std.int(Math.max(1, d.keepBackups));
			if (d.enginePath != null) s.enginePath = d.enginePath;
			if (d.protectedExtra != null) s.protectedExtra = [for (x in (d.protectedExtra : Array<Dynamic>)) Std.string(x)];
			if (d.owner != null && d.owner != "") s.owner = d.owner;
			if (d.repo != null && d.repo != "") s.repo = d.repo;
			if (d.closeOnPlay != null) s.closeOnPlay = d.closeOnPlay == true;
		} catch (_:Dynamic) {}
		return s;
	}

	public function save() {
		PathUtil.ensureDirFor(file);
		File.saveContent(file, Json.stringify({
			channel: (channel : String),
			autoCheck: autoCheck,
			keepBackups: keepBackups,
			enginePath: enginePath,
			protectedExtra: protectedExtra,
			owner: owner,
			repo: repo,
			closeOnPlay: closeOnPlay
		}, null, "\t"));
	}

	/**
	 * Resolved engine root: explicit setting, else the parent folder when the
	 * launcher runs from `<engine>/launcher/`, else the launcher folder itself.
	 */
	public function resolveEngineRoot():String {
		if (enginePath != null && enginePath != "") return Path.normalize(enginePath);
		var dir = Path.normalize(launcherDir());
		if (Path.withoutDirectory(dir).toLowerCase() == LauncherInfo.INSTALL_DIR) return Path.directory(dir);
		return dir;
	}
}
