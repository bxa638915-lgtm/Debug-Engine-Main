package dbe.launcher.update;

import dbe.launcher.util.PathUtil;
import haxe.Json;
import sys.FileSystem;
import sys.io.File;

typedef HashCacheEntry = {
	var size:Int;
	var mtime:Float;
	var sha256:String;
}

/**
 * Remembers `path -> (size, mtime, sha256)` so that quick checks only re-hash
 * files whose size or modification time changed. "Verify integrity" bypasses it.
 */
class HashCache {
	public var file(default, null):String;

	var entries:Map<String, HashCacheEntry> = new Map();
	var caseInsensitive:Bool;
	var dirty = false;

	public function new(file:String, caseInsensitive:Bool) {
		this.file = file;
		this.caseInsensitive = caseInsensitive;
	}

	public static function load(file:String, caseInsensitive:Bool):HashCache {
		var c = new HashCache(file, caseInsensitive);
		if (file != null && FileSystem.exists(file)) {
			try {
				var d:Dynamic = Json.parse(File.getContent(file));
				for (k in Reflect.fields(d)) c.entries.set(k, Reflect.field(d, k));
			} catch (_:Dynamic) {
				// corrupt cache: start fresh
			}
		}
		return c;
	}

	public function lookup(rel:String, size:Int, mtime:Float):Null<String> {
		var e = entries.get(PathUtil.key(rel, caseInsensitive));
		return (e != null && e.size == size && e.mtime == mtime) ? e.sha256 : null;
	}

	public function store(rel:String, size:Int, mtime:Float, sha:String) {
		entries.set(PathUtil.key(rel, caseInsensitive), {size: size, mtime: mtime, sha256: sha});
		dirty = true;
	}

	public function remove(rel:String) {
		if (entries.remove(PathUtil.key(rel, caseInsensitive))) dirty = true;
	}

	public function save() {
		if (!dirty || file == null) return;
		var o = {};
		for (k => v in entries) Reflect.setField(o, k, v);
		PathUtil.ensureDirFor(file);
		File.saveContent(file, Json.stringify(o));
		dirty = false;
	}
}
