package;

import CoreTests.write;
import dbe.launcher.net.ByteSource;
import dbe.launcher.net.ZipIndex;
import dbe.launcher.tools.PackageBuilder;
import dbe.launcher.update.*;
import dbe.launcher.update.UpdatePlanner;
import dbe.launcher.update.UpdateSession;
import dbe.launcher.util.*;
import sys.FileSystem;
import sys.io.File;

/** Counts reads so we can assert partial (Range-style) downloads really are partial. */
class CountingSource implements ByteSource {
	var inner:FileByteSource;

	public var reads = 0;
	public var bytes = 0.0;

	public function new(path:String)
		inner = new FileByteSource(path);

	public function size()
		return inner.size();

	public function read(s:Int, l:Int) {
		reads++;
		bytes += l;
		return inner.read(s, l);
	}

	public function close()
		inner.close();
}

class SessionTests {
	static var repo:String;
	static var releases:Array<ReleaseInfo>;
	static var m1:Manifest;
	static var m2:Manifest;
	static var lastSource:CountingSource;
	static var fullDownloads = 0;

	static function bigText(seed:String, n:Int):String {
		var b = new StringBuf();
		for (i in 0...n) b.add('$seed line $i ${i * 7919 % 1000}\n');
		return b.toString();
	}

	static function makeRepo() {
		repo = CoreTests.tmpDir("repo");
		var v1 = PathUtil.join(repo, "build1");
		write(v1, "DBE.exe", "engine v1");
		write(v1, "assets/data/song.json", bigText("song", 200));
		write(v1, "assets/images/bf.png", "PNGDATA-v1");
		write(v1, "assets/old/legacy.xml", "<legacy/>");
		write(v1, "assets/unicode/ção.txt", "acentos");
		write(v1, "lime.ndll", "ndll");
		write(v1, "mods/readme.txt", "must never be packaged");

		var v2 = PathUtil.join(repo, "build2");
		write(v2, "DBE.exe", "engine v2 !!");
		write(v2, "assets/data/song.json", bigText("song", 200));
		write(v2, "assets/images/bf.png", "PNGDATA-v2");
		write(v2, "assets/new_format/bf.atlas", "atlas");
		write(v2, "assets/unicode/ção.txt", "acentos");
		write(v2, "lime.ndll", "ndll");

		// Large incompressible (stored) file so partial fetches are measurably smaller than the zip.
		var rnd = haxe.io.Bytes.alloc(400 * 1024);
		for (i in 0...rnd.length) rnd.set(i, Std.random(256));
		for (d in [v1, v2]) {
			PathUtil.ensureDirFor(PathUtil.join(d, "assets/music/big.ogg"));
			File.saveBytes(PathUtil.join(d, "assets/music/big.ogg"), rnd);
		}

		m1 = PackageBuilder.build({
			dir: v1,
			tag: "v1.0.0",
			platform: "windows",
			zipOut: PathUtil.join(repo, "r1/DBE-windows.zip"),
			manifestOut: PathUtil.join(repo, "r1/manifest-windows.json"),
			assetsEpoch: 1,
			executable: "DBE.exe"
		});
		m2 = PackageBuilder.build({
			dir: v2,
			tag: "v2.0.0",
			platform: "windows",
			zipOut: PathUtil.join(repo, "r2/DBE-windows.zip"),
			manifestOut: PathUtil.join(repo, "r2/manifest-windows.json"),
			assetsEpoch: 2,
			breaking: true,
			executable: "DBE.exe",
			previous: m1
		});

		function rel(tag:String, dir:String):ReleaseInfo
			return {
				tag: tag,
				name: tag,
				body: "notes",
				prerelease: false,
				draft: false,
				publishedAt: "",
				htmlUrl: "",
				assets: [
					{name: "manifest-windows.json", url: PathUtil.join(repo, dir + "/manifest-windows.json"), size: 0},
					{name: "DBE-windows.zip", url: PathUtil.join(repo, dir + "/DBE-windows.zip"), size: FileSystem.stat(PathUtil.join(repo, dir + "/DBE-windows.zip")).size}
				]
			};
		releases = [rel("v1.0.0", "r1"), rel("v2.0.0", "r2")];
	}

	static function session(root:String, ?rangeWorks = true):UpdateSession {
		var s = new UpdateSession({
			root: root,
			owner: "x",
			repo: "y",
			channel: Stable,
			platform: "windows",
			launcherVersion: "1.0.0",
			caseInsensitive: true,
			keep: ["DBE Launcher.exe"]
		});
		s.releasesProvider = () -> releases;
		s.fetchText = (url) -> File.getContent(url);
		s.openRemote = (url) -> {
			if (!rangeWorks) throw new RangeUnsupported("test");
			return lastSource = new CountingSource(url);
		};
		s.downloadFile = (url, path, _) -> {
			fullDownloads++;
			PathUtil.ensureDirFor(path);
			File.copy(url, path);
		};
		return s;
	}

	static function assertMatches(root:String, m:Manifest, label:String) {
		for (f in m.files) {
			var p = PathUtil.join(root, f.path);
			T.ok(FileSystem.exists(p) && Hasher.sha256File(p) == f.sha256, '$label: ${f.path}');
		}
	}

	public static function run() {
		makeRepo();

		T.run("PackageBuilder excludes mods/, computes removed[], UTF-8 names", () -> {
			T.ok(m1.fileMap(true).get("mods/readme.txt") == null);
			T.eq(7, m1.files.length);
			T.eq("assets/old/legacy.xml", m2.removed.join(","));
			T.eq(true, m2.breaking);
			var src = new FileByteSource(PathUtil.join(repo, "r1/DBE-windows.zip"));
			var idx = ZipIndex.read(src);
			T.ok(idx.get("assets/unicode/ção.txt") != null, "utf-8 entry name");
			var got = null;
			idx.extract(src, [idx.get("assets/data/song.json")], (e, b) -> got = b);
			T.eq(bigText("song", 200), got.toString(), "deflate roundtrip");
			src.close();
		});

		var root = CoreTests.tmpDir("install");
		write(root, "mods/MyMod/data.json", "{\"mine\":true}");
		write(root, "DBE Launcher.exe", "launcher");

		T.run("Fresh install of v1 (stable channel)", () -> {
			var s = session(root);
			var c = s.check();
			T.eq("v2.0.0", c.decision.target.tag);
			var st = s.updateTo(releases[0]);
			T.eq("v1.0.0", st.tag);
			assertMatches(root, m1, "v1");
			T.eq("{\"mine\":true}", File.getContent(PathUtil.join(root, "mods/MyMod/data.json")), "mods preserved");
			T.ok(!FileSystem.exists(PathUtil.join(root, "mods/readme.txt")));
			T.ok(!FileSystem.exists(PathUtil.join(root, ".dbe/journal.json")), "journal committed");
			T.eq(1, BackupManager.list(s.layout).length);
		});

		T.run("Repair downloads only corrupted/missing files (partial range)", () -> {
			File.saveContent(PathUtil.join(root, "assets/images/bf.png"), "PNGDATA-XX"); // same size, corrupted
			FileSystem.deleteFile(PathUtil.join(root, "lime.ndll"));
			var s = session(root);
			var diff = s.plan(m1, true, false);
			T.eq(2, diff.downloads.length);
			T.eq(0, diff.deletes.length);
			s.fullDownloadRatio = 1.1; // force partial path
			lastSource = null;
			s.run(releases[0], m1, diff);
			assertMatches(root, m1, "repaired");
			T.ok(lastSource != null && lastSource.bytes < FileSystem.stat(PathUtil.join(repo, "r1/DBE-windows.zip")).size, "fetched less than whole zip");
		});

		T.run("Interrupted update → rollback restores v1", () -> {
			var s = session(root);
			var m = s.fetchManifest(releases[1]);
			var diff = s.plan(m, false, true);
			var applied = 0;
			s.onProgress = (ph, d, t, p) -> if (ph == Applying && d >= 2 && applied++ == 0) throw "simulated crash";
			T.throws(() -> s.run(releases[1], m, diff));
			T.ok(s.pendingJournal() != null, "journal left behind");
			var s2 = session(root);
			s2.rollbackInterrupted();
			assertMatches(root, m1, "after rollback");
			T.eq("v1.0.0", s2.installed().tag);
			T.ok(s2.pendingJournal() == null);
		});

		T.run("Interrupted update → resume finishes v2", () -> {
			var s = session(root);
			var m = s.fetchManifest(releases[1]);
			var diff = s.plan(m, false, true);
			var crashed = false;
			s.onProgress = (ph, d, t, p) -> if (ph == Applying && d >= 1 && !crashed) {
				crashed = true;
				throw "simulated crash";
			};
			T.throws(() -> s.run(releases[1], m, diff));
			var s2 = session(root);
			var st = s2.resumeInterrupted();
			T.eq("v2.0.0", st.tag);
			T.eq(2, st.assetsEpoch);
			assertMatches(root, m2, "v2 resumed");
			T.ok(!FileSystem.exists(PathUtil.join(root, "assets/old/legacy.xml")), "removed[] applied");
			T.ok(FileSystem.exists(PathUtil.join(root, "DBE Launcher.exe")), "launcher kept");
			T.eq("{\"mine\":true}", File.getContent(PathUtil.join(root, "mods/MyMod/data.json")), "mods preserved");
		});

		T.run("Epoch migration removes orphans in managed dirs only", () -> {
			// Simulate a user on v1 epoch with junk inside assets/ and a personal file at root.
			write(root, "assets/old_junk/x.bin", "junk");
			write(root, "my_notes.txt", "mine");
			new InstalledState("v1.0.0", 1, "windows", "stable").save(new Layout(root).installedFile);
			var s = session(root);
			s.updateTo(releases[1]);
			T.ok(!FileSystem.exists(PathUtil.join(root, "assets/old_junk/x.bin")), "orphan removed");
			T.ok(!FileSystem.exists(PathUtil.join(root, "assets/old_junk")), "empty dir pruned");
			T.ok(FileSystem.exists(PathUtil.join(root, "my_notes.txt")), "root files untouched");
		});

		T.run("Restore backup chain back to v1", () -> {
			var s = session(root);
			var list = BackupManager.list(s.layout);
			T.ok(list.length >= 2, "has backups");
			var target = null;
			for (b in list) if (b.journal.toTag == "v2.0.0") target = b; // list is newest-first → ends on the oldest
			var st = s.restoreBackup(target);
			T.eq("v1.0.0", st.tag);
			assertMatches(root, m1, "restored v1");
			T.eq("{\"mine\":true}", File.getContent(PathUtil.join(root, "mods/MyMod/data.json")), "mods preserved");
		});

		T.run("Full-package fallback when Range is unsupported", () -> {
			var root2 = CoreTests.tmpDir("install2");
			var before = fullDownloads;
			var s = session(root2, false);
			s.updateTo(releases[1]);
			T.eq(before + 1, fullDownloads);
			assertMatches(root2, m2, "full fallback");
			T.ok(!FileSystem.exists(PathUtil.join(root2, ".dbe/downloads/DBE-windows.zip")), "temp zip deleted");
		});

		T.run("Backup retention", () -> {
			var s = session(root);
			for (_ in 0...4) {
				File.saveContent(PathUtil.join(root, "lime.ndll"), "tampered" + Math.random());
				s.updateTo(releases[0], true);
			}
			T.ok(BackupManager.list(s.layout).length <= 3, "keeps at most 3");
		});
	}
}
