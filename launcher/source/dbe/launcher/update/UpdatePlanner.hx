package dbe.launcher.update;

typedef ReleaseAsset = {
	var name:String;
	var url:String; // browser_download_url
	var size:Float;
}

/** Network-independent view of a GitHub release. */
typedef ReleaseInfo = {
	var tag:String;
	var name:String;
	var body:String;
	var prerelease:Bool;
	var draft:Bool;
	var publishedAt:String;
	var htmlUrl:String;
	var assets:Array<ReleaseAsset>;
}

typedef UpdateDecision = {
	/** Best release for the selected channel/platform (null if none). */
	var target:Null<ReleaseInfo>;
	/** Target is newer than what is installed (or nothing is installed). */
	var isNewer:Bool;
	/** Releases strictly after installed up to and including target, oldest first (changelog). */
	var between:Array<ReleaseInfo>;
}

/** Pure decision logic: which release to offer, and how to apply it. */
class UpdatePlanner {
	public static function manifestAssetName(platform:String):String
		return 'manifest-$platform.json';

	public static function packageAssetName(platform:String):String
		return 'DBE-$platform.zip';

	public static function launcherAssetName(platform:String):String
		return 'DBE-Launcher-$platform.zip';

	public static function findAsset(r:ReleaseInfo, name:String):Null<ReleaseAsset> {
		for (a in r.assets) if (a.name.toLowerCase() == name.toLowerCase()) return a;
		return null;
	}

	public static function channelOf(r:ReleaseInfo):Null<Channel> {
		var t = TagInfo.parse(r.tag, r.prerelease);
		return t == null ? null : t.channel;
	}

	/** Releases usable on `platform` in `channel`, newest first. */
	public static function eligible(releases:Array<ReleaseInfo>, channel:Channel, platform:String):Array<ReleaseInfo> {
		var out = [];
		for (r in releases) {
			if (r.draft) continue;
			var t = TagInfo.parse(r.tag, r.prerelease);
			if (t == null || !channel.accepts(t.channel)) continue;
			if (findAsset(r, manifestAssetName(platform)) == null) continue;
			out.push(r);
		}
		out.sort((a, b) -> TagInfo.compareStrings(b.tag, a.tag));
		return out;
	}

	public static function decide(releases:Array<ReleaseInfo>, channel:Channel, platform:String, installedTag:Null<String>):UpdateDecision {
		var list = eligible(releases, channel, platform);
		var target = list.length > 0 ? list[0] : null;
		if (target == null) return {target: null, isNewer: false, between: []};

		var isNewer = installedTag == null || TagInfo.compareStrings(target.tag, installedTag) > 0;
		var between = [];
		for (r in list) {
			if (installedTag != null && TagInfo.compareStrings(r.tag, installedTag) <= 0) continue;
			if (TagInfo.compareStrings(r.tag, target.tag) > 0) continue;
			between.push(r);
		}
		between.reverse();
		return {target: target, isNewer: isNewer, between: between};
	}

	/**
	 * Migration mode = asset epoch differs from the installed one,
	 * or there is no reliable record of what is installed.
	 */
	public static function needsMigration(installed:Null<InstalledState>, manifest:Manifest):Bool
		return installed == null || installed.assetsEpoch != manifest.assetsEpoch;

	/** True if this launcher is too old for the manifest. */
	public static function launcherTooOld(launcherVersion:String, manifest:Manifest):Bool
		return TagInfo.compareStrings(launcherVersion, manifest.minLauncher) < 0;
}
