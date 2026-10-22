package;

import dbe.launcher.update.*;
import dbe.launcher.update.DiffEngine;
import dbe.launcher.update.TagInfo;
import dbe.launcher.update.UpdatePlanner;
import dbe.launcher.util.*;
import sys.FileSystem;
import sys.io.File;

class CoreTests {
	public static function tmpDir(name:String):String {
		var d = haxe.io.Path.join([Sys.getCwd(), "tests", ".tmp", name + "_" + Std.int(Math.random() * 1e8)]);
		FileSystem.createDirectory(d);
		return d;
	}

	public static function write(root:String, rel:String, content:String) {
		var p = PathUtil.join(root, rel);
		PathUtil.ensureDirFor(p);
		File.saveContent(p, content);
	}

	public static function entry(path:String, content:String):Manifest.ManifestFile
		return {path: path, size: haxe.io.Bytes.ofString(content).length, sha256: Hasher.sha256Bytes(haxe.io.Bytes.ofString(content))};

	public static function run() {
		T.run("PathUtil.normalize/isSafeRelative", () -> {
			T.eq("assets/images/a.png", PathUtil.normalize(".\\assets\\\\images/a.png"));
			T.ok(PathUtil.isSafeRelative("assets/a.png"));
			T.ok(!PathUtil.isSafeRelative("../evil.exe"));
			T.ok(!PathUtil.isSafeRelative("assets/../../evil"));
			T.ok(!PathUtil.isSafeRelative("C:/Windows/x.dll"));
			T.ok(!PathUtil.isSafeRelative("/etc/passwd"));
			T.ok(!PathUtil.isSafeRelative(""));
		});

		T.run("ProtectedPaths", () -> {
			var p = new ProtectedPaths(["*.log", "saves/**", "settings.json"], true);
			T.ok(p.isProtected("mods/MyMod/song.ogg"));
			T.ok(p.isProtected("MODS/x.txt"), "case-insensitive");
			T.ok(p.isProtected("mods"));
			T.ok(p.isProtected(".dbe/installed.json"));
			T.ok(p.isProtected("crash.log"));
			T.ok(!p.isProtected("logs/crash.log"), "* doesn't cross folders");
			T.ok(p.isProtected("saves/a/b/c.sav"));
			T.ok(p.isProtected("settings.json"));
			T.ok(!p.isProtected("modsextra/file.txt"), "prefix must match a whole folder");
			T.ok(!p.isProtected("assets/mods/x.png"));
			var cs = new ProtectedPaths(null, false);
			T.ok(!cs.isProtected("MODS/x.txt"), "case-sensitive on linux");
		});

		T.run("TagInfo parse + channel", () -> {
			var t = TagInfo.parse("v1.3.0-beta.2");
			T.eq(1, t.major);
			T.eq(3, t.minor);
			T.eq(Channel.Beta, t.channel);
			T.eq(Channel.Stable, TagInfo.parse("v2.0").channel);
			T.eq(Channel.Beta, TagInfo.parse("v2.0", true).channel, "GitHub prerelease flag");
			T.eq(Channel.Nightly, TagInfo.parse("v2.1.0-nightly.20261022").channel);
			T.eq(Channel.Beta, TagInfo.parse("1.0.0-rc1").channel);
			T.eq(null, TagInfo.parse("latest"));
		});

		T.run("TagInfo SemVer ordering", () -> {
			var order = [
				"v1.0.0-alpha", "v1.0.0-alpha.1", "v1.0.0-alpha.beta", "v1.0.0-beta", "v1.0.0-beta.2", "v1.0.0-beta.11", "v1.0.0-rc.1", "v1.0.0",
				"v1.0.1", "v1.1.0", "v2.0.0"
			];
			for (i in 0...order.length - 1)
				T.ok(TagInfo.compareStrings(order[i], order[i + 1]) < 0, '${order[i]} < ${order[i + 1]}');
			T.eq(0, TagInfo.compareStrings("v1.2", "1.2.0"));
		});

		T.run("Channel.accepts", () -> {
			T.ok(Channel.Stable.accepts(Stable));
			T.ok(!Channel.Stable.accepts(Beta));
			T.ok(Channel.Beta.accepts(Stable));
			T.ok(!Channel.Beta.accepts(Nightly));
			T.ok(Channel.Nightly.accepts(Beta));
		});

		T.run("Manifest roundtrip + validation", () -> {
			var m = new Manifest();
			m.tag = "v1.2.0";
			m.platform = "windows";
			m.assetsEpoch = 3;
			m.managedDirs = ["assets/"];
			m.files = [entry("assets/a.txt", "A"), entry("DBE.exe", "exe")];
			m.files[1].exec = true;
			var p = Manifest.parse(m.toJson());
			T.eq("v1.2.0", p.tag);
			T.eq(3, p.assetsEpoch);
			T.eq(2, p.files.length);
			T.eq(true, p.files[1].exec);

			T.throws(() -> Manifest.parse('{"tag":"v1","files":[{"path":"../x","size":1,"sha256":"${m.files[0].sha256}"}]}'), "path traversal");
			T.throws(() -> Manifest.parse('{"tag":"v1","files":[{"path":"a","size":1,"sha256":"zz"}]}'), "bad sha");
			T.throws(() -> Manifest.parse('{"tag":"v1","files":[{"path":"a","size":1,"sha256":"${m.files[0].sha256}"},{"path":"A","size":1,"sha256":"${m.files[0].sha256}"}]}'),
				"dup");
			T.throws(() -> Manifest.parse('{"format":99,"tag":"v1","files":[]}'), "future format");
			T.throws(() -> Manifest.parse('not json'));
		});

		T.run("DiffEngine detects missing / corrupted / changed; respects mods/", () -> {
			var root = tmpDir("diff");
			write(root, "assets/ok.txt", "same");
			write(root, "assets/corrupt.txt", "XXXX"); // same size, different content
			write(root, "assets/changed.txt", "old content");
			write(root, "mods/user/song.txt", "user data");

			var m = new Manifest();
			m.tag = "v1.1.0";
			m.files = [
				entry("assets/ok.txt", "same"),
				entry("assets/corrupt.txt", "good"),
				entry("assets/changed.txt", "new"),
				entry("assets/missing.txt", "m"),
				entry("mods/user/song.txt", "overwrite!")
			];
			var r = DiffEngine.compute({root: root, manifest: m, caseInsensitive: true});
			T.eq(1, r.unchanged);
			T.eq(3, r.downloads.length);
			var reasons = [for (d in r.downloads) d.file.path => d.reason];
			T.eq(HashMismatch, reasons.get("assets/corrupt.txt"));
			T.eq(SizeMismatch, reasons.get("assets/changed.txt"));
			T.eq(Missing, reasons.get("assets/missing.txt"));
			T.eq(1, r.skippedProtected.length, "mods/ never touched");
			T.eq(0, r.deletes.length);
		});

		T.run("DiffEngine hash cache + fullVerify", () -> {
			var root = tmpDir("cache");
			write(root, "a.txt", "aaaa");
			var m = new Manifest();
			m.tag = "v1";
			m.files = [entry("a.txt", "aaaa")];
			var cachePath = PathUtil.join(root, ".dbe/hashcache.json");
			var cache = HashCache.load(cachePath, true);
			T.eq(1, DiffEngine.compute({root: root, manifest: m, cache: cache, caseInsensitive: true}).unchanged);
			T.ok(FileSystem.exists(cachePath), "cache saved");

			// Poison cache: pretend the stored hash is different. Quick check trusts cache,
			// full verify must re-hash and find the file is actually fine.
			var st = FileSystem.stat(PathUtil.join(root, "a.txt"));
			cache.store("a.txt", st.size, st.mtime.getTime(), StringTools.lpad("", "0", 64));
			T.eq(1, DiffEngine.compute({root: root, manifest: m, cache: cache, caseInsensitive: true}).downloads.length, "quick uses cache");
			T.eq(1, DiffEngine.compute({root: root, manifest: m, cache: cache, fullVerify: true, caseInsensitive: true}).unchanged, "full verify re-hashes");
		});

		T.run("DiffEngine removed[] and migration orphans", () -> {
			var root = tmpDir("orphans");
			write(root, "assets/keep.txt", "k");
			write(root, "assets/old_format/x.json", "old");
			write(root, "assets/removed.txt", "r");
			write(root, "mods/assets/foo.txt", "user");
			write(root, "notes.txt", "user file in root");
			write(root, "DBE Launcher.exe", "launcher");

			var m = new Manifest();
			m.tag = "v2.0.0";
			m.assetsEpoch = 2;
			m.managedDirs = ["assets/"];
			m.removed = ["assets/removed.txt", "mods/assets/foo.txt"];
			m.files = [entry("assets/keep.txt", "k")];

			var normal = DiffEngine.compute({root: root, manifest: m, caseInsensitive: true});
			T.eq(1, normal.deletes.length, "only removed[] without migration; protected removed entry ignored");
			T.eq(Removed, normal.deletes[0].reason);

			var mig = DiffEngine.compute({root: root, manifest: m, migration: true, caseInsensitive: true, keep: ["DBE Launcher.exe"]});
			var paths = [for (d in mig.deletes) d.path];
			T.eq(2, paths.length);
			T.ok(paths.indexOf("assets/old_format/x.json") != -1, "orphan in managed dir");
			T.ok(paths.indexOf("notes.txt") == -1, "files outside managed dirs untouched");
		});

		T.run("UpdatePlanner channel selection + changelog range", () -> {
			function rel(tag:String, ?pre = false, ?withManifest = true):ReleaseInfo
				return {
					tag: tag,
					name: tag,
					body: "notes " + tag,
					prerelease: pre,
					draft: false,
					publishedAt: "",
					htmlUrl: "",
					assets: withManifest ? [{name: "manifest-windows.json", url: "u", size: 1}] : []
				};
			var rs = [
				rel("v1.0.0"), rel("v1.1.0"), rel("v1.2.0-beta.1", true), rel("v1.2.0-nightly.5"), rel("v1.1.5"), rel("v1.3.0", false, false)
			];
			var d = UpdatePlanner.decide(rs, Stable, "windows", "v1.0.0");
			T.eq("v1.1.5", d.target.tag, "v1.3.0 has no manifest");
			T.ok(d.isNewer);
			T.eq("v1.1.0,v1.1.5", [for (r in d.between) r.tag].join(","));

			T.eq("v1.2.0-beta.1", UpdatePlanner.decide(rs, Beta, "windows", "v1.1.5").target.tag);
			T.eq("v1.2.0-nightly.5", UpdatePlanner.decide(rs, Nightly, "windows", null).target.tag);
			T.ok(!UpdatePlanner.decide(rs, Stable, "windows", "v1.1.5").isNewer);
			T.eq(null, UpdatePlanner.decide(rs, Stable, "linux", null).target);
		});

		T.run("UpdatePlanner migration + min launcher", () -> {
			var m = new Manifest();
			m.tag = "v2";
			m.assetsEpoch = 2;
			m.minLauncher = "1.2.0";
			T.ok(UpdatePlanner.needsMigration(null, m));
			T.ok(UpdatePlanner.needsMigration(new InstalledState("v1", 1, "windows", "stable"), m));
			T.ok(!UpdatePlanner.needsMigration(new InstalledState("v1", 2, "windows", "stable"), m));
			T.ok(UpdatePlanner.launcherTooOld("1.1.9", m));
			T.ok(!UpdatePlanner.launcherTooOld("1.2.0", m));
		});

		T.run("InstalledState save/load", () -> {
			var root = tmpDir("installed");
			var f = PathUtil.join(root, ".dbe/installed.json");
			new InstalledState("v1.2.0", 3, "windows", "beta").save(f);
			var s = InstalledState.load(f);
			T.eq("v1.2.0", s.tag);
			T.eq(3, s.assetsEpoch);
			T.eq("beta", s.channel);
			T.eq(null, InstalledState.load(PathUtil.join(root, "nope.json")));
		});
	}
}
