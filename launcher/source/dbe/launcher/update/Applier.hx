package dbe.launcher.update;

import dbe.launcher.update.Journal;
import dbe.launcher.util.PathUtil;
import dbe.launcher.util.Platform;
import sys.FileSystem;
import sys.io.File;

/**
 * Applies / reverts a {@link Journal} against the install root.
 * Every operation is idempotent so an interrupted run can simply be repeated.
 */
class Applier {
	/**
	 * Returns relative paths that cannot be written right now (e.g. the game is
	 * running and Windows locks `DBE.exe` / `.dll` files).
	 */
	public static function findLockedFiles(root:String, ops:Array<JournalOp>):Array<String> {
		var locked = [];
		for (op in ops) {
			var abs = PathUtil.join(root, op.path);
			if (!FileSystem.exists(abs) || FileSystem.isDirectory(abs)) continue;
			try {
				var h = File.append(abs, true);
				h.close();
			} catch (_:Dynamic) {
				locked.push(op.path);
			}
		}
		return locked;
	}

	public static function apply(root:String, j:Journal, ?onProgress:(done:Int, total:Int, path:String) -> Void) {
		var total = j.ops.length;
		for (i in 0...total) {
			var op = j.ops[i];
			if (onProgress != null) onProgress(i, total, op.path);
			var target = PathUtil.join(root, op.path);
			var backup = j.backupPath(op);

			switch (op.kind) {
				case Write:
					var staged = j.stagedPath(op);
					if (!FileSystem.exists(staged)) {
						// Resume case: a previous attempt already moved the staged file.
						var tmp = target + ".dbe-tmp";
						if (FileSystem.exists(tmp)) {
							if (FileSystem.exists(target)) FileSystem.deleteFile(target);
							FileSystem.rename(tmp, target);
						}
						if (FileSystem.exists(target)) continue;
						throw 'Staged file missing: ${op.path}';
					}
					if (op.existed && FileSystem.exists(target) && !FileSystem.exists(backup)) copy(target, backup);
					replace(staged, target);
					if (op.exec == true) Platform.makeExecutable(target);
				case Delete:
					if (FileSystem.exists(target)) {
						if (!FileSystem.exists(backup)) copy(target, backup);
						FileSystem.deleteFile(target);
						PathUtil.pruneEmptyParents(root, op.path);
					}
			}
		}
		if (onProgress != null) onProgress(total, total, "");
	}

	/** Restores the install to the state recorded before `j` was applied. */
	public static function rollback(root:String, j:Journal, ?onProgress:(done:Int, total:Int, path:String) -> Void) {
		var total = j.ops.length;
		var i = total;
		while (i-- > 0) {
			var op = j.ops[i];
			if (onProgress != null) onProgress(total - 1 - i, total, op.path);
			var target = PathUtil.join(root, op.path);
			var backup = j.backupPath(op);
			if (op.existed) {
				if (FileSystem.exists(backup)) {
					copy(backup, target);
					if (op.exec == true) Platform.makeExecutable(target);
				}
				// else: never modified (crash before backup) → nothing to do
			} else if (FileSystem.exists(target)) {
				FileSystem.deleteFile(target);
				PathUtil.pruneEmptyParents(root, op.path);
			}
		}
		if (onProgress != null) onProgress(total, total, "");
	}

	/** Copies via a temp file + rename so the destination is never half-written. */
	public static function copy(src:String, dst:String) {
		PathUtil.ensureDirFor(dst);
		var tmp = dst + ".dbe-tmp";
		File.copy(src, tmp);
		if (FileSystem.exists(dst)) FileSystem.deleteFile(dst);
		FileSystem.rename(tmp, dst);
	}

	/** Moves `src` over `dst` (rename when possible, copy+delete across volumes). */
	static function replace(src:String, dst:String) {
		PathUtil.ensureDirFor(dst);
		var tmp = dst + ".dbe-tmp";
		if (FileSystem.exists(tmp)) FileSystem.deleteFile(tmp);
		try {
			FileSystem.rename(src, tmp);
		} catch (_:Dynamic) {
			File.copy(src, tmp);
			FileSystem.deleteFile(src);
		}
		if (FileSystem.exists(dst)) FileSystem.deleteFile(dst);
		FileSystem.rename(tmp, dst);
	}
}
