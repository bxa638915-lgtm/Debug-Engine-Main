package dbe.launcher.update;

import dbe.launcher.net.ByteSource;
import dbe.launcher.net.ZipIndex;
import dbe.launcher.util.PathUtil;
import dbe.launcher.util.Platform;
import sys.FileSystem;
import sys.io.File;

/**
 * Replaces the running launcher with a new build.
 *
 * Running executables/libraries can't be overwritten on Windows but they *can*
 * be renamed, so each file is moved aside to `*.dbe-old` and the new one is
 * written in its place. Leftovers are cleaned on the next start.
 */
class SelfUpdater {
	public static inline var OLD_SUFFIX = ".dbe-old";

	public static function needsUpdate(current:String, m:Manifest):Bool
		return m.launcherVersion != "" && TagInfo.compareStrings(m.launcherVersion, current) > 0;

	/** Deletes `*.dbe-old` files left by a previous self-update. */
	public static function cleanup(launcherDir:String) {
		for (rel in PathUtil.listFilesRecursive(launcherDir)) {
			if (StringTools.endsWith(rel, OLD_SUFFIX)) try FileSystem.deleteFile(PathUtil.join(launcherDir, rel)) catch (_:Dynamic) {}
		}
	}

	/** Extracts every entry of the launcher zip into `launcherDir`, moving current files aside. */
	public static function apply(zipPath:String, launcherDir:String, executableName:String) {
		var src = new FileByteSource(zipPath);
		try {
			var idx = ZipIndex.read(src);
			var files = [for (e in idx.entries) if (!StringTools.endsWith(e.name, "/")) e];
			for (e in files) if (!PathUtil.isSafeRelative(e.name)) throw 'Unsafe path in launcher package: ${e.name}';
			idx.extract(src, files, (e, data) -> {
				var target = PathUtil.join(launcherDir, e.name);
				if (FileSystem.exists(target)) {
					var old = target + OLD_SUFFIX;
					if (FileSystem.exists(old)) try FileSystem.deleteFile(old) catch (_:Dynamic) old = target + "." + Std.random(99999) + OLD_SUFFIX;
					FileSystem.rename(target, old);
				}
				PathUtil.ensureDirFor(target);
				File.saveBytes(target, data);
				if (haxe.io.Path.withoutDirectory(e.name) == executableName || !Platform.isWindows() && haxe.io.Path.extension(e.name) == "")
					Platform.makeExecutable(target);
			});
		} catch (e:Dynamic) {
			src.close();
			throw e;
		}
		src.close();
	}
}
