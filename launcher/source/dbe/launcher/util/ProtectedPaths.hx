package dbe.launcher.util;

/**
 * Paths the updater must never create, overwrite or delete.
 *
 * Rule syntax:
 *  - `mods/`        → directory prefix (the folder and everything inside)
 *  - `settings.json`→ exact file
 *  - `*.log`, `logs/**` → glob (`*` = within one segment, `**` = any depth, `?` = one char)
 */
class ProtectedPaths {
	/**
	 * `mods/` is user content, `.dbe/` is the launcher's state and `launcher/`
	 * holds the launcher itself (it self-updates from its own package).
	 */
	public static final DEFAULTS:Array<String> = ["mods/", ".dbe/", "launcher/"];

	public var rules(default, null):Array<String>;

	var caseInsensitive:Bool;
	var compiled:Array<String->Bool> = [];

	public function new(?rules:Array<String>, ?caseInsensitive:Bool) {
		this.caseInsensitive = caseInsensitive == null ? Platform.caseInsensitive() : caseInsensitive;
		this.rules = [];
		for (r in DEFAULTS) add(r);
		if (rules != null) for (r in rules) add(r);
	}

	public function add(rule:String) {
		if (rule == null) return;
		var r = PathUtil.normalize(StringTools.trim(rule));
		if (r.length == 0 || rules.indexOf(r) != -1) return;
		rules.push(r);
		compiled.push(compile(r));
	}

	public function isProtected(rel:String):Bool {
		var n = PathUtil.normalize(rel);
		if (caseInsensitive) n = n.toLowerCase();
		for (m in compiled) if (m(n)) return true;
		return false;
	}

	function compile(rule:String):String->Bool {
		var r = caseInsensitive ? rule.toLowerCase() : rule;
		if (r.indexOf("*") != -1 || r.indexOf("?") != -1) {
			var re = new EReg("^" + globToRegex(r) + "$", "");
			return (p) -> re.match(p);
		}
		if (StringTools.endsWith(r, "/")) {
			var bare = r.substr(0, r.length - 1);
			return (p) -> p == bare || StringTools.startsWith(p, r);
		}
		return (p) -> p == r;
	}

	static function globToRegex(g:String):String {
		var b = new StringBuf();
		var i = 0;
		while (i < g.length) {
			var c = g.charAt(i);
			if (c == "*") {
				if (g.charAt(i + 1) == "*") {
					b.add(".*");
					i++;
				} else b.add("[^/]*");
			} else if (c == "?") b.add("[^/]");
			else if ("\\^$.|+()[]{}".indexOf(c) != -1) b.add("\\" + c);
			else b.add(c);
			i++;
		}
		return b.toString();
	}
}
