package dbe.launcher.update;

import dbe.launcher.util.PathUtil;
import haxe.io.Path;
import sys.FileSystem;

typedef BackupEntry = {
	var dir:String;
	var name:String;
	var journal:Journal;
}

/** Lists, prunes and restores update backups stored in `.dbe/backups/`. */
class BackupManager {
	public static inline var RECORD = "backup.json";

	/** Newest first. Folders without a valid `backup.json` are ignored. */
	public static function list(layout:Layout):Array<BackupEntry> {
		var out:Array<BackupEntry> = [];
		if (!FileSystem.exists(layout.backupsRoot)) return out;
		for (name in FileSystem.readDirectory(layout.backupsRoot)) {
			var dir = Path.join([layout.backupsRoot, name]);
			if (!FileSystem.isDirectory(dir)) continue;
			var j = try Journal.load(Path.join([dir, RECORD])) catch (_:Dynamic) null;
			if (j != null) out.push({dir: dir, name: name, journal: j});
		}
		out.sort((a, b) -> Reflect.compare(b.name, a.name));
		return out;
	}

	/** Keeps the `keep` newest backups; deletes the rest (and any orphan folders). */
	public static function prune(layout:Layout, keep:Int) {
		if (!FileSystem.exists(layout.backupsRoot)) return;
		var valid = list(layout);
		var keepDirs = new Map<String, Bool>();
		for (i in 0...valid.length) if (i < keep) keepDirs.set(valid[i].name, true);
		for (name in FileSystem.readDirectory(layout.backupsRoot)) {
			if (!keepDirs.exists(name)) PathUtil.deleteRecursive(Path.join([layout.backupsRoot, name]));
		}
	}

	/**
	 * Reverts the install to the state before backup `b` was taken.
	 * Only the most recent backup can be restored safely without restoring the
	 * newer ones first, so `restoreChain` walks newest → target.
	 */
	public static function restoreChain(layout:Layout, target:BackupEntry, ?onProgress:(done:Int, total:Int, path:String) -> Void):InstalledState {
		var all = list(layout);
		var state:InstalledState = null;
		for (b in all) {
			Applier.rollback(layout.root, b.journal, onProgress);
			state = new InstalledState(b.journal.fromTag == null ? "unknown" : b.journal.fromTag, b.journal.fromEpoch, b.journal.platform,
				b.journal.channel);
			PathUtil.deleteRecursive(b.dir);
			if (b.name == target.name) break;
		}
		if (state != null) state.save(layout.installedFile);
		return state;
	}
}
