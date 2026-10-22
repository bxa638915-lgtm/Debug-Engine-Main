package dbe.launcher.util;

/** Platform identification used to pick manifests / release assets. */
class Platform {
	public static inline var WINDOWS = "windows";
	public static inline var LINUX = "linux";
	public static inline var MACOS = "macos";

	public static function id():String {
		return switch (Sys.systemName()) {
			case "Windows": WINDOWS;
			case "Mac": MACOS;
			default: LINUX;
		}
	}

	/** Windows (NTFS) and macOS (APFS default) are case-insensitive. */
	public static function caseInsensitive(?platform:String):Bool
		return (platform == null ? id() : platform) != LINUX;

	public static function isWindows():Bool
		return id() == WINDOWS;

	/** Marks a file as executable on POSIX systems (no-op on Windows). */
	public static function makeExecutable(path:String) {
		if (isWindows()) return;
		try Sys.command("chmod", ["+x", path]) catch (_:Dynamic) {}
	}
}
