package dbe.launcher.update;

import dbe.launcher.util.PathUtil;

/** Locations of the launcher's private state inside the install root (`.dbe/`). */
class Layout {
	public static inline var DIR = ".dbe";

	public var root(default, null):String;

	public function new(root:String)
		this.root = root;

	public var dbeDir(get, never):String;
	public var installedFile(get, never):String;
	public var journalFile(get, never):String;
	public var hashCacheFile(get, never):String;
	public var settingsFile(get, never):String;
	public var stagingRoot(get, never):String;
	public var backupsRoot(get, never):String;
	public var downloadsDir(get, never):String;
	public var logFile(get, never):String;

	inline function get_dbeDir() return PathUtil.join(root, DIR);
	inline function get_installedFile() return PathUtil.join(dbeDir, "installed.json");
	inline function get_journalFile() return PathUtil.join(dbeDir, "journal.json");
	inline function get_hashCacheFile() return PathUtil.join(dbeDir, "hashcache.json");
	inline function get_settingsFile() return PathUtil.join(dbeDir, "settings.json");
	inline function get_stagingRoot() return PathUtil.join(dbeDir, "staging");
	inline function get_backupsRoot() return PathUtil.join(dbeDir, "backups");
	inline function get_downloadsDir() return PathUtil.join(dbeDir, "downloads");
	inline function get_logFile() return PathUtil.join(dbeDir, "launcher.log");

	public function stagingFor(tag:String):String
		return PathUtil.join(stagingRoot, safeName(tag));

	/** Backup folder names sort chronologically: `20261022-190812-345_v1.1.0_to_v1.2.0`. Always unique. */
	public function newBackupDir(fromTag:Null<String>, toTag:String):String {
		var suffix = '_${safeName(fromTag == null ? "unknown" : fromTag)}_to_${safeName(toTag)}';
		var t = Sys.time();
		while (true) {
			var ms = Std.int((t - Math.ffloor(t)) * 1000);
			var stamp = DateTools.format(Date.fromTime(Math.ffloor(t) * 1000), "%Y%m%d-%H%M%S") + "-" + StringTools.lpad(Std.string(ms), "0", 3);
			var dir = PathUtil.join(backupsRoot, stamp + suffix);
			if (!sys.FileSystem.exists(dir) && !existsWithStamp(stamp)) return dir;
			t += 0.001;
		}
	}

	function existsWithStamp(stamp:String):Bool {
		if (!sys.FileSystem.exists(backupsRoot)) return false;
		for (n in sys.FileSystem.readDirectory(backupsRoot)) if (StringTools.startsWith(n, stamp)) return true;
		return false;
	}

	public static function safeName(s:String):String
		return ~/[^0-9A-Za-z._\-]/g.replace(s, "_");
}
