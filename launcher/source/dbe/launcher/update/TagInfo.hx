package dbe.launcher.update;

/**
 * Parsed release tag, e.g. `v1.3.0`, `v1.3.0-beta.2`, `v1.4.0-nightly.20261022`.
 *
 * Channel classification:
 *  - no pre-release suffix                       → stable
 *  - `nightly` / `dev` / `canary` suffix         → nightly
 *  - any other suffix (`alpha`, `beta`, `rc`...) → beta
 */
class TagInfo {
	static final RE = ~/^v?(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:-([0-9A-Za-z.\-]+))?(?:\+[0-9A-Za-z.\-]+)?$/;

	public var raw(default, null):String;
	public var major(default, null):Int;
	public var minor(default, null):Int;
	public var patch(default, null):Int;
	public var pre(default, null):Array<String>;
	public var channel(default, null):Channel;

	function new() {}

	public static function parse(tag:String, githubPrerelease:Bool = false):Null<TagInfo> {
		if (tag == null || !RE.match(StringTools.trim(tag))) return null;
		var t = new TagInfo();
		t.raw = StringTools.trim(tag);
		t.major = Std.parseInt(RE.matched(1));
		t.minor = RE.matched(2) == null ? 0 : Std.parseInt(RE.matched(2));
		t.patch = RE.matched(3) == null ? 0 : Std.parseInt(RE.matched(3));
		t.pre = RE.matched(4) == null ? [] : RE.matched(4).split(".");
		t.channel = if (t.pre.length == 0) {
			githubPrerelease ? Beta : Stable;
		} else switch (t.pre[0].toLowerCase()) {
			case "nightly" | "dev" | "canary": Nightly;
			default: Beta;
		}
		return t;
	}

	public function versionString():String
		return '$major.$minor.$patch' + (pre.length > 0 ? "-" + pre.join(".") : "");

	public function toString():String
		return raw;

	/** SemVer 2.0 precedence. Returns <0, 0, >0. */
	public static function compare(a:TagInfo, b:TagInfo):Int {
		if (a.major != b.major) return a.major - b.major;
		if (a.minor != b.minor) return a.minor - b.minor;
		if (a.patch != b.patch) return a.patch - b.patch;
		if (a.pre.length == 0 && b.pre.length == 0) return 0;
		if (a.pre.length == 0) return 1;
		if (b.pre.length == 0) return -1;
		var n = a.pre.length < b.pre.length ? a.pre.length : b.pre.length;
		for (i in 0...n) {
			var x = a.pre[i], y = b.pre[i];
			var xi = Std.parseInt(x), yi = Std.parseInt(y);
			var xNum = xi != null && Std.string(xi) == x;
			var yNum = yi != null && Std.string(yi) == y;
			var c = if (xNum && yNum) xi - yi else if (xNum) -1 else if (yNum) 1 else Reflect.compare(x, y);
			if (c != 0) return c;
		}
		return a.pre.length - b.pre.length;
	}

	/** Convenience: compare two raw strings (unparseable sorts lowest). */
	public static function compareStrings(a:String, b:String):Int {
		var ta = parse(a), tb = parse(b);
		if (ta == null && tb == null) return 0;
		if (ta == null) return -1;
		if (tb == null) return 1;
		return compare(ta, tb);
	}
}
