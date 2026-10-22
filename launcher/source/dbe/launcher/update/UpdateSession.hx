package dbe.launcher.update;

import dbe.launcher.net.ByteSource;
import dbe.launcher.net.GitHubApi;
import dbe.launcher.net.HttpClient;
import dbe.launcher.net.ZipIndex;
import dbe.launcher.update.DiffEngine;
import dbe.launcher.update.Journal;
import dbe.launcher.update.Manifest.ManifestFile;
import dbe.launcher.update.UpdatePlanner;
import dbe.launcher.util.Hasher;
import dbe.launcher.util.PathUtil;
import dbe.launcher.util.ProtectedPaths;
import sys.FileSystem;
import sys.io.File;

typedef SessionConfig = {
	var root:String;
	var owner:String;
	var repo:String;
	var channel:Channel;
	var platform:String;
	var launcherVersion:String;
	@:optional var protectedRules:Array<String>;
	@:optional var keepBackups:Int;
	/** Relative paths never deleted as orphans (e.g. the launcher executable). */
	@:optional var keep:Array<String>;
	@:optional var caseInsensitive:Bool;
}

enum Phase {
	Idle;
	FetchingReleases;
	FetchingManifest;
	Verifying;
	Downloading;
	Applying;
	RollingBack;
	Done;
}

typedef CheckResult = {
	var installed:Null<InstalledState>;
	var decision:UpdateDecision;
	var manifest:Null<Manifest>;
	var migration:Bool;
	var launcherTooOld:Bool;
}

class FilesLockedException extends haxe.Exception {
	public var files(default, null):Array<String>;

	public function new(files:Array<String>) {
		super("Files in use (close the game first): " + files.slice(0, 5).join(", ") + (files.length > 5 ? "..." : ""));
		this.files = files;
	}
}

/**
 * UI-independent update workflow:
 *   check() → plan() → run()  (download → stage → journal → apply → commit)
 * plus crash recovery, repair and backup restore.
 * Every method is blocking; call from a worker thread.
 */
class UpdateSession {
	public var config(default, null):SessionConfig;
	public var layout(default, null):Layout;
	public var protectedPaths(default, null):ProtectedPaths;

	/** Set from the UI thread to abort network / verification phases. */
	public var cancelRequested:Bool = false;

	public var onProgress:(phase:Phase, done:Float, total:Float, detail:String) -> Void;
	public var log:String->Void;

	// ---- injectable I/O (tests replace these) ----
	public var releasesProvider:() -> Array<ReleaseInfo>;
	public var fetchText:String->String;
	public var openRemote:String->ByteSource;
	public var downloadFile:(url:String, path:String, onBytes:Float->Void) -> Void;

	/** Use the full zip when more than this fraction of the package must be fetched. */
	public var fullDownloadRatio = 0.6;

	var ci:Bool;

	public function new(config:SessionConfig) {
		this.config = config;
		ci = config.caseInsensitive == null ? dbe.launcher.util.Platform.caseInsensitive(config.platform) : config.caseInsensitive;
		layout = new Layout(config.root);
		protectedPaths = new ProtectedPaths(config.protectedRules, ci);

		var api = new GitHubApi(config.owner, config.repo, PathUtil.join(layout.dbeDir, "cache/releases.json"));
		releasesProvider = () -> api.fetchReleases(isCancelled);
		fetchText = (url) -> HttpClient.getText(url, null, isCancelled);
		openRemote = (url) -> new HttpRangeSource(url, isCancelled);
		downloadFile = (url, path, onBytes) -> HttpClient.download(url, path, onBytes, isCancelled);
	}

	public function isCancelled():Bool
		return cancelRequested;

	inline function progress(p:Phase, d:Float, t:Float, s:String)
		if (onProgress != null) onProgress(p, d, t, s);

	inline function info(s:String)
		if (log != null) log(s);

	public function installed():Null<InstalledState>
		return InstalledState.load(layout.installedFile);

	// ------------------------------------------------------------------ check

	public function fetchReleases():Array<ReleaseInfo> {
		progress(FetchingReleases, 0, 1, "");
		var r = releasesProvider();
		progress(FetchingReleases, 1, 1, "");
		return r;
	}

	public function fetchManifest(release:ReleaseInfo):Manifest {
		var a = UpdatePlanner.findAsset(release, UpdatePlanner.manifestAssetName(config.platform));
		if (a == null) throw 'Release ${release.tag} has no manifest for ${config.platform}';
		progress(FetchingManifest, 0, 1, release.tag);
		var m = Manifest.parse(fetchText(a.url));
		if (m.tag != release.tag) throw 'Manifest tag ${m.tag} does not match release ${release.tag}';
		progress(FetchingManifest, 1, 1, release.tag);
		return m;
	}

	public function check(?releases:Array<ReleaseInfo>):CheckResult {
		if (releases == null) releases = fetchReleases();
		var inst = installed();
		var d = UpdatePlanner.decide(releases, config.channel, config.platform, inst == null ? null : inst.tag);
		var m = d.target == null ? null : fetchManifest(d.target);
		return {
			installed: inst,
			decision: d,
			manifest: m,
			migration: m != null && UpdatePlanner.needsMigration(inst, m),
			launcherTooOld: m != null && UpdatePlanner.launcherTooOld(config.launcherVersion, m)
		};
	}

	// ------------------------------------------------------------------ plan

	public function plan(manifest:Manifest, fullVerify:Bool, migration:Bool):DiffResult {
		var cache = HashCache.load(layout.hashCacheFile, ci);
		return DiffEngine.compute({
			root: config.root,
			manifest: manifest,
			protectedPaths: protectedPaths,
			cache: cache,
			fullVerify: fullVerify,
			migration: migration,
			caseInsensitive: ci,
			keep: config.keep,
			onProgress: (d, t, p) -> progress(Verifying, d, t, p),
			isCancelled: isCancelled
		});
	}

	// ------------------------------------------------------------------ run

	/** Downloads what `diff` needs, then applies it transactionally. */
	public function run(release:ReleaseInfo, manifest:Manifest, diff:DiffResult):InstalledState {
		if (FileSystem.exists(layout.journalFile)) throw "An interrupted update must be resumed or rolled back first";
		var ops = buildOps(manifest, diff);
		var locked = Applier.findLockedFiles(config.root, ops);
		if (locked.length > 0) throw new FilesLockedException(locked);

		var staging = layout.stagingFor(manifest.tag);
		stage(release, manifest, diff, staging);

		var inst = installed();
		var j = new Journal();
		j.fromTag = inst == null ? null : inst.tag;
		j.fromEpoch = inst == null ? 0 : inst.assetsEpoch;
		j.toTag = manifest.tag;
		j.toEpoch = manifest.assetsEpoch;
		j.channel = config.channel;
		j.platform = config.platform;
		j.stagingDir = staging;
		j.backupDir = layout.newBackupDir(j.fromTag, j.toTag);
		j.ops = ops;
		j.save(layout.journalFile);

		info('Applying ${ops.length} operations (${j.fromTag} -> ${j.toTag})');
		Applier.apply(config.root, j, (d, t, p) -> progress(Applying, d, t, p));
		return commit(j);
	}

	/** Convenience: check → plan → run for a given release. */
	public function updateTo(release:ReleaseInfo, ?fullVerify = false):InstalledState {
		var m = fetchManifest(release);
		var diff = plan(m, fullVerify, UpdatePlanner.needsMigration(installed(), m));
		return run(release, m, diff);
	}

	function buildOps(m:Manifest, diff:DiffResult):Array<JournalOp> {
		var ops:Array<JournalOp> = [];
		for (d in diff.downloads)
			ops.push({
				kind: Write,
				path: d.file.path,
				existed: FileSystem.exists(PathUtil.join(config.root, d.file.path)),
				exec: d.file.exec == true,
				sha256: d.file.sha256
			});
		for (d in diff.deletes) ops.push({kind: Delete, path: d.path, existed: true});
		return ops;
	}

	/** Puts verified copies of every needed file in `staging`. Already-staged valid files are reused (resume). */
	function stage(release:ReleaseInfo, m:Manifest, diff:DiffResult, staging:String) {
		var needed:Array<ManifestFile> = [];
		var bytes = 0.0;
		for (d in diff.downloads) {
			var sp = PathUtil.join(staging, d.file.path);
			if (FileSystem.exists(sp) && FileSystem.stat(sp).size == d.file.size && Hasher.sha256File(sp) == d.file.sha256) continue;
			needed.push(d.file);
			bytes += d.file.size;
		}
		if (needed.length == 0) return;

		var assetName = m.packageAsset != "" ? m.packageAsset : UpdatePlanner.packageAssetName(config.platform);
		var asset = UpdatePlanner.findAsset(release, assetName);
		if (asset == null) throw 'Release ${release.tag} has no asset $assetName';

		var useFull = m.totalSize() > 0 && bytes / m.totalSize() > fullDownloadRatio;
		var src:ByteSource = null;
		var idx:ZipIndex = null;
		var zipPath:String = null;

		if (!useFull) {
			try {
				src = openRemote(asset.url);
				idx = ZipIndex.read(src);
				info('Partial download via HTTP Range: ${needed.length} files');
			} catch (e:RangeUnsupported) {
				info('Range unsupported (${e.message}); falling back to full package');
				useFull = true;
			}
		}
		if (useFull) {
			zipPath = PathUtil.join(layout.downloadsDir, assetName);
			info('Downloading full package $assetName');
			downloadFile(asset.url, zipPath, (b) -> progress(Downloading, b, asset.size, assetName));
			src = new FileByteSource(zipPath);
			idx = ZipIndex.read(src);
		}

		var byEntry = new Map<String, ManifestFile>();
		var entries:Array<ZipEntry> = [];
		for (f in needed) {
			var name = m.zipPrefix + f.path;
			var e = idx.get(name);
			if (e == null) throw 'Package is missing $name';
			byEntry.set(name, f);
			entries.push(e);
		}

		var doneBytes = 0.0;
		try {
			idx.extract(src, entries, (e, data) -> {
				var f = byEntry.get(e.name);
				if (data.length != f.size || Hasher.sha256Bytes(data) != f.sha256) throw 'Integrity check failed for ${f.path}';
				var sp = PathUtil.join(staging, f.path);
				PathUtil.ensureDirFor(sp);
				File.saveBytes(sp, data);
				doneBytes += f.size;
				progress(Downloading, doneBytes, bytes, f.path);
			}, isCancelled);
		} catch (e:Dynamic) {
			src.close();
			throw e;
		}
		src.close();
		if (zipPath != null && FileSystem.exists(zipPath)) FileSystem.deleteFile(zipPath);
	}

	function commit(j:Journal):InstalledState {
		var cache = HashCache.load(layout.hashCacheFile, ci);
		for (op in j.ops) {
			var abs = PathUtil.join(config.root, op.path);
			if (op.kind == Write && op.sha256 != null && FileSystem.exists(abs)) {
				var st = FileSystem.stat(abs);
				cache.store(op.path, st.size, st.mtime.getTime(), op.sha256);
			} else if (op.kind == Delete) cache.remove(op.path);
		}
		cache.save();

		var state = new InstalledState(j.toTag, j.toEpoch, j.platform, j.channel);
		state.save(layout.installedFile);

		if (j.ops.length > 0) {
			if (!FileSystem.exists(j.backupDir)) FileSystem.createDirectory(j.backupDir);
			var rec = PathUtil.join(j.backupDir, BackupManager.RECORD);
			if (FileSystem.exists(rec)) FileSystem.deleteFile(rec);
			FileSystem.rename(layout.journalFile, rec);
		} else if (FileSystem.exists(layout.journalFile)) FileSystem.deleteFile(layout.journalFile);

		PathUtil.deleteRecursive(j.stagingDir);
		BackupManager.prune(layout, config.keepBackups == null ? 3 : config.keepBackups);
		progress(Done, 1, 1, j.toTag);
		info('Installed ${j.toTag}');
		return state;
	}

	// ------------------------------------------------------------------ recovery

	public function pendingJournal():Null<Journal>
		return try Journal.load(layout.journalFile) catch (_:Dynamic) null;

	/** Finishes an interrupted update. */
	public function resumeInterrupted():InstalledState {
		var j = pendingJournal();
		if (j == null) throw "No interrupted update";
		Applier.apply(config.root, j, (d, t, p) -> progress(Applying, d, t, p));
		return commit(j);
	}

	/** Undoes an interrupted update, restoring the previous files. */
	public function rollbackInterrupted() {
		var j = pendingJournal();
		if (j == null) throw "No interrupted update";
		Applier.rollback(config.root, j, (d, t, p) -> progress(RollingBack, d, t, p));
		FileSystem.deleteFile(layout.journalFile);
		PathUtil.deleteRecursive(j.backupDir);
		PathUtil.deleteRecursive(j.stagingDir);
		progress(Done, 1, 1, "");
	}

	/** Restores the install as it was before backup `b` (undoing newer ones first). */
	public function restoreBackup(b:BackupManager.BackupEntry):InstalledState {
		var s = BackupManager.restoreChain(layout, b, (d, t, p) -> progress(RollingBack, d, t, p));
		// cached hashes may now be stale for restored files; full re-hash happens lazily via mtime change
		progress(Done, 1, 1, s == null ? "" : s.tag);
		return s;
	}
}
