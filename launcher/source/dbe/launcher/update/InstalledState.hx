package dbe.launcher.update;

import dbe.launcher.util.PathUtil;
import haxe.Json;
import sys.FileSystem;
import sys.io.File;

/** Contents of `.dbe/installed.json` — what is currently on disk. */
class InstalledState {
	public var tag:String;
	public var assetsEpoch:Int;
	public var platform:String;
	public var channel:String;
	public var installedAt:String;

	public function new(tag:String, assetsEpoch:Int, platform:String, channel:String, ?installedAt:String) {
		this.tag = tag;
		this.assetsEpoch = assetsEpoch;
		this.platform = platform;
		this.channel = channel;
		this.installedAt = installedAt == null ? Date.now().toString() : installedAt;
	}

	public static function fromManifest(m:Manifest, channel:String):InstalledState
		return new InstalledState(m.tag, m.assetsEpoch, m.platform, channel);

	public static function load(file:String):Null<InstalledState> {
		if (!FileSystem.exists(file)) return null;
		try {
			var d:Dynamic = Json.parse(File.getContent(file));
			if (d.tag == null) return null;
			return new InstalledState(d.tag, d.assetsEpoch == null ? 0 : Std.int(d.assetsEpoch), d.platform, d.channel, d.installedAt);
		} catch (_:Dynamic) {
			return null;
		}
	}

	public function toJson():String
		return Json.stringify({
			tag: tag,
			assetsEpoch: assetsEpoch,
			platform: platform,
			channel: channel,
			installedAt: installedAt
		}, null, "\t");

	public function save(file:String) {
		PathUtil.ensureDirFor(file);
		var tmp = file + ".tmp";
		File.saveContent(tmp, toJson());
		if (FileSystem.exists(file)) FileSystem.deleteFile(file);
		FileSystem.rename(tmp, file);
	}
}
