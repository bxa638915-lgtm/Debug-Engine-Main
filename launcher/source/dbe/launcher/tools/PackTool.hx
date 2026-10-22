package dbe.launcher.tools;

import dbe.launcher.update.Manifest;
import sys.FileSystem;
import sys.io.File;

/**
 * CLI used by CI to produce release assets.
 *
 *   haxe -cp launcher/source --run dbe.launcher.tools.PackTool \
 *     --dir export/release/windows/bin --tag v1.2.0 --platform windows \
 *     --epoch 3 [--breaking] [--min-launcher 1.0.0] --exe DBE.exe \
 *     [--managed assets/,addons/] [--exclude "*.pdb,logs/"] [--exec lime.ndll] \
 *     [--previous old-manifest.json] --out dist/
 *
 * Writes `<out>/DBE-<platform>.zip` and `<out>/manifest-<platform>.json`.
 */
class PackTool {
	static function main() {
		var a = parseArgs(Sys.args());
		function req(k:String):String {
			if (!a.exists(k)) {
				Sys.println('Missing --$k');
				usage();
				Sys.exit(2);
			}
			return a.get(k);
		}
		function list(k:String):Array<String>
			return a.exists(k) ? [for (s in a.get(k).split(",")) if (StringTools.trim(s) != "") StringTools.trim(s)] : null;

		var platform = req("platform");
		var out = req("out");
		var previous:Manifest = null;
		if (a.exists("previous") && FileSystem.exists(a.get("previous"))) {
			previous = Manifest.parse(File.getContent(a.get("previous")));
			Sys.println('Previous manifest: ${previous.tag} (${previous.files.length} files)');
		}

		var m = PackageBuilder.build({
			dir: req("dir"),
			tag: req("tag"),
			platform: platform,
			zipOut: haxe.io.Path.join([out, 'DBE-$platform.zip']),
			manifestOut: haxe.io.Path.join([out, 'manifest-$platform.json']),
			assetsEpoch: a.exists("epoch") ? Std.parseInt(a.get("epoch")) : 1,
			breaking: a.get("breaking") == "true",
			minLauncher: a.get("min-launcher"),
			executable: a.get("exe"),
			managedDirs: list("managed"),
			exclude: list("exclude"),
			execs: list("exec"),
			previous: previous,
			log: Sys.println
		});
		Sys.println('OK ${m.tag} ${m.platform}: ${m.files.length} files, epoch ${m.assetsEpoch}');
	}

	static function parseArgs(args:Array<String>):Map<String, String> {
		var m = new Map<String, String>();
		var i = 0;
		while (i < args.length) {
			var k = args[i];
			if (StringTools.startsWith(k, "--")) {
				k = k.substr(2);
				if (i + 1 < args.length && !StringTools.startsWith(args[i + 1], "--")) {
					m.set(k, args[i + 1]);
					i++;
				} else m.set(k, "true");
			}
			i++;
		}
		return m;
	}

	static function usage()
		Sys.println("Usage: PackTool --dir <build> --tag <vX.Y.Z> --platform <windows|linux|macos> --out <dir> [--epoch N] [--breaking] [--min-launcher X] [--exe path] [--managed a/,b/] [--exclude rules] [--exec files] [--previous manifest.json]");
}
