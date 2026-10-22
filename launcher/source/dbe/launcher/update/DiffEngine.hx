package dbe.launcher.update;

import dbe.launcher.update.Manifest.ManifestFile;
import dbe.launcher.util.Hasher;
import dbe.launcher.util.PathUtil;
import dbe.launcher.util.Platform;
import dbe.launcher.util.ProtectedPaths;
import sys.FileSystem;

enum DiffReason {
	Missing;
	SizeMismatch;
	HashMismatch;
}

enum DeleteReason {
	/** Listed in `manifest.removed`. */
	Removed;
	/** Not in the manifest but inside a managed dir (migration only). */
	Orphan;
}

typedef DownloadItem = {
	var file:ManifestFile;
	var reason:DiffReason;
}

typedef DeleteItem = {
	var path:String;
	var reason:DeleteReason;
}

typedef DiffResult = {
	var downloads:Array<DownloadItem>;
	var deletes:Array<DeleteItem>;
	var unchanged:Int;
	/** Manifest entries skipped because they fall under a protected path. */
	var skippedProtected:Array<String>;
	var downloadBytes:Float;
}

typedef DiffOptions = {
	var root:String;
	var manifest:Manifest;
	@:optional var protectedPaths:ProtectedPaths;
	@:optional var cache:HashCache;
	/** Ignore the hash cache and re-hash every file. */
	@:optional var fullVerify:Bool;
	/** Asset epoch changed: also remove orphans in `manifest.managedDirs`. */
	@:optional var migration:Bool;
	@:optional var caseInsensitive:Bool;
	/** Extra relative paths never treated as orphans (e.g. the launcher itself). */
	@:optional var keep:Array<String>;
	@:optional var onProgress:(done:Int, total:Int, path:String) -> Void;
	/** Polled between files; return true to abort (throws DiffCancelled). */
	@:optional var isCancelled:() -> Bool;
}

class DiffCancelled extends haxe.Exception {}

/** Compares the local install against a manifest. Read-only: never touches disk content. */
class DiffEngine {
	public static function compute(o:DiffOptions):DiffResult {
		var ci = o.caseInsensitive == null ? Platform.caseInsensitive() : o.caseInsensitive;
		var prot = o.protectedPaths == null ? new ProtectedPaths(null, ci) : o.protectedPaths;
		var m = o.manifest;

		var res:DiffResult = {
			downloads: [],
			deletes: [],
			unchanged: 0,
			skippedProtected: [],
			downloadBytes: 0
		};

		var total = m.files.length;
		var done = 0;
		for (f in m.files) {
			if (o.isCancelled != null && o.isCancelled()) throw new DiffCancelled("cancelled");
			if (o.onProgress != null) o.onProgress(done, total, f.path);
			done++;

			if (prot.isProtected(f.path)) {
				res.skippedProtected.push(f.path);
				continue;
			}
			var reason = check(o.root, f, o.cache, o.fullVerify == true);
			if (reason == null) res.unchanged++;
			else {
				res.downloads.push({file: f, reason: reason});
				res.downloadBytes += f.size;
			}
		}
		if (o.onProgress != null) o.onProgress(total, total, "");

		var inManifest = m.fileMap(ci);
		var keep = new Map<String, Bool>();
		if (o.keep != null) for (k in o.keep) keep.set(PathUtil.key(k, ci), true);
		var queued = new Map<String, Bool>();

		inline function canDelete(rel:String):Bool {
			var k = PathUtil.key(rel, ci);
			return !inManifest.exists(k) && !keep.exists(k) && !queued.exists(k) && !prot.isProtected(rel);
		}

		for (r in m.removed) {
			if (canDelete(r) && FileSystem.exists(PathUtil.join(o.root, r)) && !FileSystem.isDirectory(PathUtil.join(o.root, r))) {
				res.deletes.push({path: r, reason: Removed});
				queued.set(PathUtil.key(r, ci), true);
			}
		}

		if (o.migration == true) {
			for (dir in m.managedDirs) {
				if (dir == "" || prot.isProtected(dir)) continue;
				for (rel in PathUtil.listFilesRecursive(o.root, dir)) {
					if (canDelete(rel)) {
						res.deletes.push({path: rel, reason: Orphan});
						queued.set(PathUtil.key(rel, ci), true);
					}
				}
			}
		}

		if (o.cache != null) o.cache.save();
		return res;
	}

	/** Returns null when the local file matches the manifest entry. */
	public static function check(root:String, f:ManifestFile, ?cache:HashCache, fullVerify = false):Null<DiffReason> {
		var abs = PathUtil.join(root, f.path);
		if (!FileSystem.exists(abs) || FileSystem.isDirectory(abs)) return Missing;
		var st = FileSystem.stat(abs);
		if (st.size != f.size) return SizeMismatch;

		var mtime = st.mtime.getTime();
		var sha:String = (cache != null && !fullVerify) ? cache.lookup(f.path, st.size, mtime) : null;
		if (sha == null) {
			sha = Hasher.sha256File(abs);
			if (cache != null) cache.store(f.path, st.size, mtime, sha);
		}
		return sha == f.sha256 ? null : HashMismatch;
	}
}
