package funkin.backend.assets;

import flixel.FlxG;
import openfl.utils.Assets;
#if sys
import sys.FileSystem;
import sys.io.File;
#end
import funkin.backend.system.Logs;

/**
 * Pre-warms video file buffers into RAM/OS cache to eliminate disk seek latency when videos start.
 * DOES NOT create background FlxVideoSprite objects to prevent green screen texture flashing.
 */
class VideoPreloadCache {
	public static var cachedFileBytes:Map<String, Float> = [];
	public static var prewarmedPaths:Map<String, String> = [];

	public static function clear():Void {
		cachedFileBytes.clear();
		prewarmedPaths.clear();
	}

	public static function precacheVideo(path:String):Bool {
		if (path == null || StringTools.trim(path) == "") return false;

		var key = normalizeKey(path);
		if (prewarmedPaths.exists(key)) return true;

		var localPath = Assets.getPath(path);
		#if sys
		if (localPath == null || !FileSystem.exists(localPath)) {
			var fallbackPath = Paths.video(path);
			localPath = Assets.getPath(fallbackPath);
			if (localPath == null || !FileSystem.exists(localPath)) return false;
		}

		// Pre-read and warm up file I/O cache into system memory
		try {
			var stat = FileSystem.stat(localPath);
			var fileSize = stat.size;
			cachedFileBytes.set(key, fileSize);

			var file = File.read(localPath, true);
			var buf = haxe.io.Bytes.alloc(1024 * 512); // 512KB chunks
			var remaining = stat.size;
			while (remaining > 0) {
				var toRead = Std.int(Math.min(buf.length, remaining));
				file.readBytes(buf, 0, toRead);
				remaining -= toRead;
			}
			file.close();

			prewarmedPaths.set(key, localPath);
			var baseName = haxe.io.Path.withoutDirectory(haxe.io.Path.withoutExtension(localPath)).toLowerCase();
			if (baseName != "" && baseName != key) {
				prewarmedPaths.set(baseName, localPath);
			}

			Logs.trace('VideoPreloadCache: Video file buffered in memory: $localPath (${Math.round(fileSize / (1024*1024)*10)/10} MB)', GREEN);
			return true;
		} catch (e:Dynamic) {
			Logs.warn('VideoPreloadCache: Could not pre-warm file for $localPath: $e');
		}
		#end
		return false;
	}

	public static function has(path:String):Bool {
		if (path == null) return false;
		var key = normalizeKey(path);
		if (prewarmedPaths.exists(key)) return true;
		var base = haxe.io.Path.withoutDirectory(haxe.io.Path.withoutExtension(path)).toLowerCase();
		return prewarmedPaths.exists(base);
	}

	public static function normalizeKey(path:String):String {
		if (path == null) return "";
		var p = StringTools.replace(path.toLowerCase().trim(), "\\", "/");
		return p;
	}
}
