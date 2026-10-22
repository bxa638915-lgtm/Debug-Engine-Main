package dbe.launcher.util;

import haxe.io.Path;
import sys.FileSystem;

/**
 * Path helpers. All paths stored in manifests / caches / journals are
 * *relative*, use forward slashes and never contain `..`.
 */
class PathUtil {
	static final MULTI_SLASH = ~/\/+/g;
	static final DRIVE = ~/^[a-zA-Z]:/;

	/** Converts `\` to `/`, strips leading `./` and `/`, collapses `//`. */
	public static function normalize(p:String):String {
		var s = StringTools.replace(p, "\\", "/");
		s = MULTI_SLASH.replace(s, "/");
		while (StringTools.startsWith(s, "./")) s = s.substr(2);
		while (StringTools.startsWith(s, "/")) s = s.substr(1);
		return s;
	}

	/** Key used for map lookups (case-folded on case-insensitive file systems). */
	public static inline function key(p:String, caseInsensitive:Bool):String {
		var n = normalize(p);
		return caseInsensitive ? n.toLowerCase() : n;
	}

	/** True when `p` is a relative path that can't escape the install root. */
	public static function isSafeRelative(p:String):Bool {
		if (p == null || p.length == 0) return false;
		if (StringTools.startsWith(p, "/") || StringTools.startsWith(p, "\\")) return false;
		if (DRIVE.match(p)) return false;
		var n = normalize(p);
		if (n.length == 0 || StringTools.endsWith(n, "/")) return false;
		for (seg in n.split("/")) if (seg == ".." || seg == "." || seg == "") return false;
		return true;
	}

	public static function join(root:String, rel:String):String
		return Path.join([root, normalize(rel)]);

	public static function ensureDirFor(file:String) {
		var d = Path.directory(file);
		if (d != "" && !FileSystem.exists(d)) FileSystem.createDirectory(d);
	}

	/** Lists every file below `root/sub`, returned relative to `root`. */
	public static function listFilesRecursive(root:String, sub:String = ""):Array<String> {
		var out:Array<String> = [];
		var base = normalize(sub);
		while (StringTools.endsWith(base, "/")) base = base.substr(0, base.length - 1);
		var start = base == "" ? root : join(root, base);
		if (!FileSystem.exists(start) || !FileSystem.isDirectory(start)) return out;
		var stack = [base];
		while (stack.length > 0) {
			var rel = stack.pop();
			var abs = rel == "" ? root : join(root, rel);
			for (name in FileSystem.readDirectory(abs)) {
				var childRel = rel == "" ? name : rel + "/" + name;
				if (FileSystem.isDirectory(join(root, childRel))) stack.push(childRel);
				else out.push(childRel);
			}
		}
		out.sort(Reflect.compare);
		return out;
	}

	/** Recursively deletes a directory (no-op if missing). */
	public static function deleteRecursive(path:String) {
		if (!FileSystem.exists(path)) return;
		if (!FileSystem.isDirectory(path)) {
			FileSystem.deleteFile(path);
			return;
		}
		for (name in FileSystem.readDirectory(path)) deleteRecursive(Path.join([path, name]));
		FileSystem.deleteDirectory(path);
	}

	/** Removes now-empty parent directories of `rel` up to (not including) `root`. */
	public static function pruneEmptyParents(root:String, rel:String) {
		var parts = normalize(rel).split("/");
		parts.pop();
		while (parts.length > 0) {
			var dir = join(root, parts.join("/"));
			if (FileSystem.exists(dir) && FileSystem.isDirectory(dir) && FileSystem.readDirectory(dir).length == 0)
				FileSystem.deleteDirectory(dir);
			else
				break;
			parts.pop();
		}
	}
}
