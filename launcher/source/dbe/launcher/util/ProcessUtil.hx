package dbe.launcher.util;

import haxe.io.Path;
import sys.FileSystem;

/** Starts external programs detached from the launcher process. */
class ProcessUtil {
	/**
	 * Launches the game. `exe` is relative to `root`.
	 * macOS `.app` bundles are opened with `open`.
	 */
	public static function launch(root:String, exe:String, ?args:Array<String>):Void {
		var full = PathUtil.join(root, exe);
		if (!FileSystem.exists(full)) throw 'Executable not found: $exe';
		var argStr = args == null ? "" : " " + [for (a in args) quote(a)].join(" ");
		switch (Platform.id()) {
			case Platform.WINDOWS:
				var win = StringTools.replace(full, "/", "\\");
				var dir = StringTools.replace(root, "/", "\\");
				Sys.command("start \"\" /D " + quote(dir) + " " + quote(win) + argStr);
			case Platform.MACOS if (StringTools.endsWith(full.toLowerCase(), ".app")):
				Sys.command("open " + quote(full) + (args == null ? "" : " --args" + argStr));
			default:
				Platform.makeExecutable(full);
				Sys.command("cd " + quote(root) + " && nohup " + quote(full) + argStr + " >/dev/null 2>&1 &");
		}
	}

	/** Restarts the launcher (after self-update). */
	public static function relaunchSelf() {
		var exe = Sys.programPath();
		launch(Path.directory(exe), Path.withoutDirectory(exe));
	}

	/** Opens a folder or URL with the OS default handler. */
	public static function open(target:String) {
		switch (Platform.id()) {
			case Platform.WINDOWS:
				var win = StringTools.replace(target, "/", "\\");
				Sys.command("start \"\" " + quote(win));
			case Platform.MACOS:
				Sys.command("open " + quote(target));
			default:
				Sys.command("xdg-open " + quote(target) + " >/dev/null 2>&1 &");
		}
	}

	static function quote(s:String):String
		return '"' + StringTools.replace(s, '"', '\\"') + '"';
}
