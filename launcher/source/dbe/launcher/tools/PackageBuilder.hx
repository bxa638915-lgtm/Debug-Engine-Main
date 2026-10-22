package dbe.launcher.tools;

import dbe.launcher.update.Manifest;
import dbe.launcher.util.Hasher;
import dbe.launcher.util.PathUtil;
import dbe.launcher.util.ProtectedPaths;
import sys.FileSystem;
import sys.io.File;

typedef PackOptions = {
	/** Folder with the exported game build (e.g. export/release/windows/bin). */
	var dir:String;
	var tag:String;
	var platform:String;
	/** Output paths. */
	var zipOut:String;
	var manifestOut:String;
	@:optional var assetsEpoch:Int;
	@:optional var breaking:Bool;
	@:optional var minLauncher:String;
	@:optional var executable:String;
	@:optional var managedDirs:Array<String>;
	/** Extra exclusion rules (ProtectedPaths syntax). `mods/` and `.dbe/` are always excluded. */
	@:optional var exclude:Array<String>;
	/** Files that need the POSIX executable bit. */
	@:optional var execs:Array<String>;
	/** Previous release manifest, used to compute `removed`. */
	@:optional var previous:Manifest;
	@:optional var log:String->Void;
}

/** Builds `DBE-<platform>.zip` + `manifest-<platform>.json` from an exported build (used by CI). */
class PackageBuilder {
	static final STORED_EXT = ["png", "jpg", "jpeg", "ogg", "mp3", "mp4", "webm", "zip", "gz", "7z", "webp", "astc", "ktx2"];

	public static function build(o:PackOptions):Manifest {
		var excl = new ProtectedPaths(o.exclude, false);
		// Packaging must also never include its own outputs.
		var files = [for (f in PathUtil.listFilesRecursive(o.dir)) if (!excl.isProtected(f)) f];
		if (files.length == 0) throw 'No files found in ${o.dir}';

		var m = new Manifest();
		m.tag = o.tag;
		m.platform = o.platform;
		m.assetsEpoch = o.assetsEpoch == null ? 1 : o.assetsEpoch;
		m.breaking = o.breaking == true;
		m.minLauncher = o.minLauncher == null ? "0.0.0" : o.minLauncher;
		m.executable = o.executable == null ? "" : PathUtil.normalize(o.executable);
		m.packageAsset = haxe.io.Path.withoutDirectory(o.zipOut);
		m.managedDirs = o.managedDirs == null ? ["assets/"] : o.managedDirs.map(d -> {
			var n = PathUtil.normalize(d);
			StringTools.endsWith(n, "/") ? n : n + "/";
		});
		m.generatedAt = Date.now().toString();

		var execSet = new Map<String, Bool>();
		if (o.execs != null) for (e in o.execs) execSet.set(PathUtil.normalize(e), true);
		if (m.executable != "" && o.platform != "windows") execSet.set(m.executable, true);

		PathUtil.ensureDirFor(o.zipOut);
		var zw = new ZipWriter(File.write(o.zipOut, true));
		var i = 0;
		for (rel in files) {
			var data = File.getBytes(PathUtil.join(o.dir, rel));
			var ext = haxe.io.Path.extension(rel).toLowerCase();
			zw.add(rel, data, STORED_EXT.indexOf(ext) == -1);
			var f:ManifestFile = {path: rel, size: data.length, sha256: Hasher.sha256Bytes(data)};
			if (execSet.exists(rel)) f.exec = true;
			m.files.push(f);
			i++;
			if (o.log != null && i % 250 == 0) o.log('  packed $i/${files.length}');
		}
		zw.close();

		if (o.previous != null) {
			var now = m.fileMap(true);
			var removed = new Map<String, String>();
			for (f in o.previous.files) if (!now.exists(f.path.toLowerCase())) removed.set(f.path.toLowerCase(), f.path);
			for (r in o.previous.removed) if (!now.exists(r.toLowerCase())) removed.set(r.toLowerCase(), r);
			m.removed = [for (v in removed) v];
			m.removed.sort(Reflect.compare);
		}

		PathUtil.ensureDirFor(o.manifestOut);
		File.saveContent(o.manifestOut, m.toJson());
		if (o.log != null) o.log('Packed ${files.length} files (${Std.int(zw.bytesWritten / 1048576)} MiB), removed: ${m.removed.length}');
		return m;
	}
}
