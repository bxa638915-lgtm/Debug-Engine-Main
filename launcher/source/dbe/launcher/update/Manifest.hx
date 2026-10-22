package dbe.launcher.update;

import dbe.launcher.util.Hasher;
import dbe.launcher.util.PathUtil;
import haxe.Json;

typedef ManifestFile = {
	/** Relative path inside the install root (forward slashes). */
	var path:String;
	var size:Int;
	var sha256:String;
	/** POSIX executable bit should be set after writing. */
	@:optional var exec:Bool;
}

class ManifestError extends haxe.Exception {}

/**
 * Describes the complete *target state* of one release for one platform.
 * Generated in CI by `tools/manifest-gen` and uploaded as
 * `manifest-<platform>.json` next to `DBE-<platform>.zip`.
 */
class Manifest {
	public static inline var FORMAT = 1;

	public var format:Int = FORMAT;
	public var tag:String;
	public var platform:String;

	/**
	 * Asset-format generation. Bump it in a release whenever the way the
	 * engine reads/organises assets changes. A different epoch from the
	 * installed one switches the launcher into *migration* mode
	 * (full verification + orphan cleanup inside `managedDirs`).
	 */
	public var assetsEpoch:Int = 1;

	/** Show a "breaking changes" confirmation before updating. */
	public var breaking:Bool = false;

	/** Minimum launcher version able to apply this manifest. */
	public var minLauncher:String = "0.0.0";

	/** Engine executable (relative path), launched by the "Play" button. */
	public var executable:String = "";

	/** Release asset holding the files (default `DBE-<platform>.zip`). */
	public var packageAsset:String = "";

	/** Folder prefix inside the zip (empty when files sit at the zip root). */
	public var zipPrefix:String = "";

	/** Directories fully owned by the engine; orphans here are removed on migration. */
	public var managedDirs:Array<String> = [];

	/** Files explicitly removed since previous releases. */
	public var removed:Array<String> = [];

	public var files:Array<ManifestFile> = [];
	public var generatedAt:String = "";

	/** Version of the launcher published with this release (`DBE-Launcher-<platform>.zip`). Empty = none. */
	public var launcherVersion:String = "";

	public function new() {}

	public function totalSize():Float {
		var t = 0.0;
		for (f in files) t += f.size;
		return t;
	}

	public function fileMap(caseInsensitive:Bool):Map<String, ManifestFile> {
		var m = new Map<String, ManifestFile>();
		for (f in files) m.set(PathUtil.key(f.path, caseInsensitive), f);
		return m;
	}

	public function toJson():String {
		return Json.stringify({
			format: format,
			tag: tag,
			platform: platform,
			assetsEpoch: assetsEpoch,
			breaking: breaking,
			minLauncher: minLauncher,
			launcherVersion: launcherVersion,
			executable: executable,
			packageAsset: packageAsset,
			zipPrefix: zipPrefix,
			managedDirs: managedDirs,
			removed: removed,
			generatedAt: generatedAt,
			files: files
		}, null, "\t");
	}

	public static function parse(json:String):Manifest {
		var d:Dynamic = try Json.parse(json) catch (e:Dynamic) throw new ManifestError('Invalid manifest JSON: $e');
		if (d == null) throw new ManifestError("Empty manifest");

		var m = new Manifest();
		m.format = intField(d, "format", FORMAT);
		if (m.format > FORMAT) throw new ManifestError('Manifest format ${m.format} is newer than supported ($FORMAT). Update the launcher.');
		m.tag = strField(d, "tag", null);
		if (m.tag == null || m.tag == "") throw new ManifestError("Manifest has no tag");
		m.platform = strField(d, "platform", "");
		m.assetsEpoch = intField(d, "assetsEpoch", 1);
		m.breaking = Reflect.field(d, "breaking") == true;
		m.minLauncher = strField(d, "minLauncher", "0.0.0");
		m.launcherVersion = strField(d, "launcherVersion", "");
		m.executable = strField(d, "executable", "");
		m.packageAsset = strField(d, "packageAsset", "");
		m.zipPrefix = strField(d, "zipPrefix", "");
		m.generatedAt = strField(d, "generatedAt", "");
		m.managedDirs = strArray(d, "managedDirs").map(normalizeDir);
		m.removed = [];
		for (r in strArray(d, "removed")) {
			if (!PathUtil.isSafeRelative(r)) throw new ManifestError('Unsafe removed path: $r');
			m.removed.push(PathUtil.normalize(r));
		}

		var raw:Array<Dynamic> = Reflect.field(d, "files");
		if (raw == null) throw new ManifestError("Manifest has no files list");
		var seen = new Map<String, Bool>();
		for (rf in raw) {
			var path:String = Reflect.field(rf, "path");
			if (!PathUtil.isSafeRelative(path)) throw new ManifestError('Unsafe file path: $path');
			var sha:String = Reflect.field(rf, "sha256");
			if (!Hasher.isValidSha256(sha)) throw new ManifestError('Invalid sha256 for $path');
			var size:Dynamic = Reflect.field(rf, "size");
			if (size == null || Std.int(size) < 0) throw new ManifestError('Invalid size for $path');
			var n = PathUtil.normalize(path);
			var k = n.toLowerCase();
			if (seen.exists(k)) throw new ManifestError('Duplicate path (case-insensitive): $path');
			seen.set(k, true);
			var f:ManifestFile = {path: n, size: Std.int(size), sha256: sha.toLowerCase()};
			if (Reflect.field(rf, "exec") == true) f.exec = true;
			m.files.push(f);
		}
		return m;
	}

	static function normalizeDir(d:String):String {
		var n = PathUtil.normalize(d);
		if (n.length > 0 && !StringTools.endsWith(n, "/")) n += "/";
		if (n.indexOf("..") != -1) throw new ManifestError('Unsafe managed dir: $d');
		return n;
	}

	static function strField(d:Dynamic, name:String, def:String):String {
		var v = Reflect.field(d, name);
		return v == null ? def : Std.string(v);
	}

	static function intField(d:Dynamic, name:String, def:Int):Int {
		var v:Dynamic = Reflect.field(d, name);
		return v == null ? def : Std.int(v);
	}

	static function strArray(d:Dynamic, name:String):Array<String> {
		var v:Array<Dynamic> = Reflect.field(d, name);
		return v == null ? [] : [for (x in v) Std.string(x)];
	}
}
