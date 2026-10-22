package dbe.compatibility.rea;

#if sys
import flixel.FlxG;
import funkin.backend.assets.ModsFolder;
import funkin.backend.system.Logs.Level;
import funkin.backend.system.Main;
import haxe.Json;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

using StringTools;

typedef DBEConsoleEntry = {
	var id:Int;
	var timestamp:String;
	var level:String;
	var category:String; // "INFO", "ERROR", "WARNING", "SCRIPT", "ASSET", "COMPAT", "CRASH"
	var text:String;
};

/**
 * In-engine Haxe Console & Diagnostic Capture system.
 * Captures 100% of Logs, HScript/Lua errors, missing assets, state transitions,
 * mod conversions, and crash stack traces inside the engine without relying on external terminals.
 */
class DBEConsoleCapture {
	public static inline var MAX_ENTRIES:Int = 4000;
	public static inline var LATEST_LOG_PATH:String = "logs/dbe_console_latest.log";
	public static inline var ERRORS_LOG_PATH:String = "logs/dbe_errors_latest.log";
	public static inline var SUMMARY_LOG_PATH:String = "logs/dbe_diagnostic_summary.txt";

	public static var entries:Array<DBEConsoleEntry> = [];
	public static var totalRecorded:Int = 0;
	public static var errorCount:Int = 0;
	public static var warningCount:Int = 0;
	public static var scriptIssueCount:Int = 0;
	public static var missingAssetCount:Int = 0;
	public static var compatEventCount:Int = 0;
	public static var crashReports:Array<String> = [];

	private static var _initialized:Bool = false;
	private static var _lastMessageBody:String = "";
	private static var _lastRepeatCount:Int = 0;

	public static function init():Void {
		if (_initialized) return;
		_initialized = true;
		try {
			if (!FileSystem.exists("logs")) {
				FileSystem.createDirectory("logs");
			}
			var header = '=== DBE In-Engine Console Capture Started at ${Date.now().toString()} ===\n';
			File.saveContent(LATEST_LOG_PATH, header);
			File.saveContent(ERRORS_LOG_PATH, header);
		} catch (_:Dynamic) {}
	}

	public static function clear():Void {
		entries = [];
		totalRecorded = 0;
		errorCount = 0;
		warningCount = 0;
		scriptIssueCount = 0;
		missingAssetCount = 0;
		compatEventCount = 0;
		crashReports = [];
		_lastMessageBody = "";
		_lastRepeatCount = 0;
	}

	/**
	 * Called automatically by `Logs.__showInConsole` for every engine trace/log/warn/error.
	 */
	public static function recordLog(plainLine:String, level:Level):Void {
		if (!_initialized) init();
		if (plainLine == null) return;

		var clean = plainLine.replace("\r", "").trim();
		if (clean == "") return;

		// Strip any residual ANSI escape sequences
		clean = stripAnsi(clean);

		// Extract message body after "[ HH:MM:SS | LEVEL ] " for consecutive deduplication
		var bodyIdx = clean.indexOf("] ");
		var msgBody = bodyIdx != -1 ? clean.substr(bodyIdx + 2).trim() : clean;
		if (msgBody == _lastMessageBody && entries.length > 0) {
			_lastRepeatCount++;
			var lastEntry = entries[entries.length - 1];
			var baseText = lastEntry.text;
			var repIdx = baseText.lastIndexOf(" (repeated ");
			if (repIdx != -1) baseText = baseText.substr(0, repIdx);
			lastEntry.text = '${baseText} (repeated ${_lastRepeatCount + 1}x)';
			return;
		}
		_lastMessageBody = msgBody;
		_lastRepeatCount = 0;

		var now = Date.now();
		var timeStr = '${Std.string(now.getHours()).lpad("0", 2)}:${Std.string(now.getMinutes()).lpad("0", 2)}:${Std.string(now.getSeconds()).lpad("0", 2)}';

		var levelName = switch (level) {
			case WARNING: "WARNING";
			case ERROR: "ERROR";
			case TRACE: "TRACE";
			case VERBOSE: "VERBOSE";
			case SUCCESS: "SUCCESS";
			case FAILURE: "FAILURE";
			default: "INFO";
		};

		var lower = clean.toLowerCase();
		var isShaderPropWarn = lower.indexOf("flxruntimeshader.hx") != -1 || lower.indexOf("shader float property") != -1;

		var isErr = (level == ERROR || level == FAILURE)
			|| lower.indexOf("error") != -1
			|| lower.indexOf("uncaught") != -1
			|| lower.indexOf("exception") != -1
			|| lower.indexOf("null object reference") != -1;

		var isWarn = !isErr && ((level == WARNING)
			|| lower.indexOf("warning") != -1
			|| lower.indexOf("[warn]") != -1
			|| lower.indexOf("deprecated") != -1
			|| lower.indexOf("blocked") != -1
			|| lower.indexOf("incompatible") != -1);

		var isScript = !isShaderPropWarn && (
			lower.indexOf(".lua") != -1
			|| lower.indexOf("hscript") != -1
			|| lower.indexOf("psychlua") != -1
			|| lower.indexOf("customclass") != -1
			|| lower.indexOf("unknown variable") != -1
			|| lower.indexOf("invalid field") != -1
			|| (lower.indexOf(".hx") != -1 && lower.indexOf("flixel/") == -1)
		);

		var isAsset = !isShaderPropWarn && (
			lower.indexOf("missing") != -1
			|| lower.indexOf("could not find") != -1
			|| (lower.indexOf("not found") != -1 && lower.indexOf("property") == -1)
			|| lower.indexOf("does not exist") != -1
			|| lower.indexOf("null graphic") != -1
			|| lower.indexOf("failed to load") != -1
			|| lower.indexOf("returnsound") != -1
			|| lower.indexOf("getsparrowatlas") != -1
		);

		var isCompat = lower.indexOf("compatibility") != -1
			|| lower.indexOf("runtimemodconverter") != -1
			|| lower.indexOf("rea") != -1
			|| lower.indexOf("switching mod") != -1
			|| lower.indexOf("loaded mod") != -1
			|| lower.indexOf("_dbe_") != -1;

		var category = "INFO";
		if (isErr) {
			category = "ERROR";
			errorCount++;
		} else if (isWarn) {
			category = "WARNING";
			warningCount++;
		} else if (isCompat) {
			category = "COMPAT";
			compatEventCount++;
		}

		if (isScript && (isErr || isWarn || lower.indexOf("fail") != -1 || lower.indexOf("null") != -1 || lower.indexOf("unknown") != -1)) {
			category = "SCRIPT";
			scriptIssueCount++;
		} else if (isAsset && (isErr || isWarn)) {
			category = "ASSET";
			missingAssetCount++;
		}

		totalRecorded++;
		var entry:DBEConsoleEntry = {
			id: totalRecorded,
			timestamp: timeStr,
			level: levelName,
			category: category,
			text: clean
		};

		entries.push(entry);
		if (entries.length > MAX_ENTRIES) {
			entries.shift();
		}

		// Write to disk files
		try {
			var out = File.append(LATEST_LOG_PATH, false);
			out.writeString('[#${entry.id}][${entry.category}] ${clean}\n');
			out.flush();
			out.close();

			if (isErr || isWarn || category == "SCRIPT" || category == "ASSET") {
				var errOut = File.append(ERRORS_LOG_PATH, false);
				errOut.writeString('[#${entry.id}][${entry.category}] ${clean}\n');
				errOut.flush();
				errOut.close();
			}
		} catch (_:Dynamic) {}
	}

	/**
	 * Records a full crash report from `CrashHandler`.
	 */
	public static function recordCrash(report:String):Void {
		if (!_initialized) init();
		if (report == null) return;
		var clean = report.replace("\r", "");
		crashReports.push(clean);
		errorCount++;
		totalRecorded++;
		entries.push({
			id: totalRecorded,
			timestamp: Date.now().toString(),
			level: "CRASH",
			category: "CRASH",
			text: clean
		});
		try {
			var errOut = File.append(ERRORS_LOG_PATH, false);
			errOut.writeString('\n=== CRASH REPORT ===\n${clean}\n====================\n');
			errOut.flush();
			errOut.close();
			saveDiagnosticSummary();
		} catch (_:Dynamic) {}
	}

	/**
	 * Returns entries filtered by mode:
	 * 0 = ALL, 1 = ERRORS & CRASHES, 2 = WARNINGS, 3 = SCRIPTS (HScript/Lua), 4 = MISSING ASSETS, 5 = MODS & REA
	 */
	public static function getFilteredEntries(filterMode:Int):Array<DBEConsoleEntry> {
		if (filterMode == 0) return entries;
		var result:Array<DBEConsoleEntry> = [];
		for (e in entries) {
			var low = e.text.toLowerCase();
			var isShaderWarn = low.indexOf("flxruntimeshader.hx") != -1 || low.indexOf("shader float property") != -1;
			var match = switch (filterMode) {
				case 1: e.category == "ERROR" || e.category == "CRASH" || e.level == "ERROR" || e.level == "FAILURE";
				case 2: e.category == "WARNING" || e.level == "WARNING";
				case 3: e.category == "SCRIPT" || (!isShaderWarn && (low.indexOf(".lua") != -1 || low.indexOf("hscript") != -1));
				case 4: e.category == "ASSET" || (!isShaderWarn && (low.indexOf("missing") != -1 || low.indexOf("could not find") != -1));
				case 5: e.category == "COMPAT" || low.indexOf("mod") != -1 || low.indexOf("rea") != -1;
				default: true;
			};
			if (match) result.push(e);
		}
		return result;
	}

	/**
	 * Builds a complete, structured diagnostic report in Haxe with all engine, mod, REA,
	 * conversion, script, and asset information.
	 */
	public static function buildDiagnosticReport():String {
		var b = new StringBuf();
		b.add("================================================================================\n");
		b.add("  DBE IN-ENGINE CONSOLE & DIAGNOSTIC CAPTURE REPORT\n");
		b.add("================================================================================\n");
		b.add('  Generated At     : ${Date.now().toString()}\n');
		var curStateName = (FlxG.state != null) ? Type.getClassName(Type.getClass(FlxG.state)) : "null";
		b.add('  Current State    : ${curStateName}\n');
		b.add('  Current Mod      : ${ModsFolder.currentModFolder != null ? ModsFolder.currentModFolder : "(none / base game)"}\n');
		b.add('  Mod Load Path    : ${ModsFolder.currentModLoadPath != null ? ModsFolder.currentModLoadPath : "(none)"}\n');
		b.add('  Verbose Logging  : ${Main.verbose}\n');
		b.add('  Total Captured   : ${totalRecorded} lines (Buffer: ${entries.length})\n');
		b.add('  Errors / Crashes : ${errorCount} (Crashes: ${crashReports.length})\n');
		b.add('  Warnings         : ${warningCount}\n');
		b.add('  Script Issues    : ${scriptIssueCount}\n');
		b.add('  Missing Assets   : ${missingAssetCount}\n');
		b.add("================================================================================\n\n");

		// 1. REA Learned Profile Status
		b.add("--- [1] REA LEARNED ENGINE PROFILE STATUS ---\n");
		REARuntimeBridge.ensureInitialized();
		var prof = REARuntimeBridge.activeProfile;
		if (prof != null) {
			b.add('  Source Executable: ${Reflect.field(prof, "sourceExecutable")}\n');
			b.add('  Detected Engine  : ${Reflect.field(prof, "detectedEngine")} (${Reflect.field(prof, "engineVersion")})\n');
			b.add('  Psych Lua Profile: ${Reflect.field(prof, "psychLuaProfile")}\n');
			b.add('  Learned Rules    : ${Reflect.field(prof, "learnedRulesCount")}\n');
			b.add('  Learned At       : ${Reflect.field(prof, "learnedAt")}\n');
		} else {
			b.add("  (No REA executable profile learned yet)\n");
		}
		b.add("\n");

		// 2. Current Mod Conversion Report (if loaded from converted cache)
		b.add("--- [2] CURRENT MOD CONVERSION REPORT ---\n");
		if (ModsFolder.currentModLoadPath != null) {
			var repPath = Path.join([ModsFolder.currentModLoadPath, "_dbe_conversion_report.json"]);
			if (FileSystem.exists(repPath)) {
				try {
					var rep:Dynamic = Json.parse(File.getContent(repPath));
					b.add('  Source           : ${Reflect.field(rep, "source")}\n');
					b.add('  Source Format    : ${Reflect.field(rep, "sourceFormat")} -> ${Reflect.field(rep, "targetEngine")}\n');
					var incomps:Array<Dynamic> = cast Reflect.field(rep, "incompatibilities");
					var warns:Array<Dynamic> = cast Reflect.field(rep, "warnings");
					b.add('  Incompatibilities: ${incomps != null ? incomps.length : 0}\n');
					b.add('  Warnings         : ${warns != null ? warns.length : 0}\n');
					if (incomps != null && incomps.length > 0) {
						for (inc in incomps) {
							b.add('    [BLOCKED] ${Reflect.field(inc, "code")}: ${Reflect.field(inc, "message")}\n');
						}
					}
					if (warns != null && warns.length > 0) {
						var maxW = Std.int(Math.min(20, warns.length));
						for (i in 0...maxW) {
							b.add('    [WARN] ${Std.string(warns[i])}\n');
						}
					}
				} catch (_:Dynamic) {}
			} else {
				b.add("  (Current mod is not using a converted cache report)\n");
			}
		} else {
			b.add("  (No active mod load path)\n");
		}
		b.add("\n");

		// 3. Crashes
		if (crashReports.length > 0) {
			b.add('--- [3] CRASH STACK TRACES (${crashReports.length}) ---\n');
			for (cr in crashReports) {
				b.add(cr + "\n\n");
			}
		}

		// 4. Script Issues (HScript / Lua)
		var scriptEntries = getFilteredEntries(3);
		b.add('--- [4] HSCRIPT / LUA SCRIPT LOGS & ERRORS (${scriptEntries.length}) ---\n');
		if (scriptEntries.length == 0) {
			b.add("  (None recorded)\n");
		} else {
			var startIdx = Std.int(Math.max(0, scriptEntries.length - 80));
			for (i in startIdx...scriptEntries.length) {
				var e = scriptEntries[i];
				b.add('  [#${e.id}][${e.level}] ${e.text}\n');
			}
		}
		b.add("\n");

		// 5. Missing Assets
		var assetEntries = getFilteredEntries(4);
		b.add('--- [5] MISSING ASSETS & PATH ERRORS (${assetEntries.length}) ---\n');
		if (assetEntries.length == 0) {
			b.add("  (None recorded)\n");
		} else {
			var startIdx = Std.int(Math.max(0, assetEntries.length - 80));
			for (i in startIdx...assetEntries.length) {
				var e = assetEntries[i];
				b.add('  [#${e.id}][${e.level}] ${e.text}\n');
			}
		}
		b.add("\n");

		// 6. All Errors
		var errEntries = getFilteredEntries(1);
		b.add('--- [6] ALL ERRORS & FAILURES (${errEntries.length}) ---\n');
		if (errEntries.length == 0) {
			b.add("  (None recorded)\n");
		} else {
			var startIdx = Std.int(Math.max(0, errEntries.length - 100));
			for (i in startIdx...errEntries.length) {
				var e = errEntries[i];
				b.add('  [#${e.id}][${e.level}] ${e.text}\n');
			}
		}
		b.add("\n");

		// 7. Recent Chronological Logs
		b.add('--- [7] LAST 100 CONSOLE LOG LINES ---\n');
		var startAll = Std.int(Math.max(0, entries.length - 100));
		for (i in startAll...entries.length) {
			var e = entries[i];
			b.add('  [#${e.id}][${e.category}] ${e.text}\n');
		}

		return b.toString();
	}

	/**
	 * Saves the full diagnostic report to `logs/dbe_diagnostic_summary.txt` and returns the path.
	 */
	public static function saveDiagnosticSummary():String {
		if (!_initialized) init();
		var report = buildDiagnosticReport();
		try {
			File.saveContent(SUMMARY_LOG_PATH, report);
		} catch (_:Dynamic) {}
		return SUMMARY_LOG_PATH;
	}

	static function stripAnsi(input:String):String {
		if (input == null || input.indexOf("\x1b") == -1) return input;
		var out = new StringBuf();
		var i = 0;
		var len = input.length;
		while (i < len) {
			var c = input.charCodeAt(i);
			if (c == 0x1B && i + 1 < len && input.charAt(i + 1) == "[") {
				i += 2;
				while (i < len) {
					var ch = input.charCodeAt(i);
					i++;
					if ((ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122)) break;
				}
				continue;
			}
			out.addChar(c);
			i++;
		}
		return out.toString();
	}
}
#end
