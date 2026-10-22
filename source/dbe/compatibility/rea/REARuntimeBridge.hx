package dbe.compatibility.rea;

#if sys
import haxe.Json;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
#if flixel
import funkin.backend.assets.ModsFolder;
import funkin.backend.assets.Paths;
#end

using StringTools;

/**
 * Learned Engine Knowledge Profile extracted by REA from custom executables (.exe).
 * Allows DBE (the main engine) to understand how external engines load files, paths,
 * JSON schemas, and compiled Haxe classes that DBE does not natively handle.
 */
typedef REAKnowledgeProfile = {
	var sourceExecutable:String;
	var detectedEngine:String;
	var engineVersion:String;
	var psychLuaProfile:String;
	var learnedAt:String;
	var knownClasses:Map<String, Array<String>>;
	var knownFileRoutes:Map<String, String>;
	var supportedExtensions:Array<String>;
};

class REARuntimeBridge {
	public static inline var PROFILE_FILE:String = "./mods/_dbe_rea_learned_profile.json";
	public static inline var MOD_EXE_LINKS_FILE:String = "./mods/_dbe_mod_executables.json";

	public static var activeProfile:Null<Dynamic> = null;
	private static var _initialized:Bool = false;
	private static var _learnedClasses:Map<String, Array<String>> = new Map();
	private static var _learnedRoutes:Map<String, String> = new Map();
	private static var _modExeLinks:Map<String, String> = new Map();
	private static var _modSettingsCache:Map<String, Map<String, Dynamic>> = new Map();

	/**
	 * Initializes the REA Runtime Bridge, loading any previously learned executable profile and mod-executable associations.
	 */
	public static function ensureInitialized():Void {
		if (_initialized) return;
		_initialized = true;
		loadLearnedProfile();
		loadModExeLinks();
	}

	/**
	 * Learns how a target executable (.exe) handles files, paths, and Haxe classes,
	 * persists the profile to mods/_dbe_rea_learned_profile.json, and activates it in DBE.
	 */
	public static function learnFromAnalysis(result:REAModAnalyzer.REAModAnalysisResult):Int {
		ensureInitialized();

		var exePath = result.target;
		if (result.binaryAnalysis != null && result.binaryAnalysis.filePath != null && result.binaryAnalysis.filePath != "") {
			exePath = result.binaryAnalysis.filePath;
		}

		var hasBinary = exePath != null && FileSystem.exists(exePath) && !FileSystem.isDirectory(exePath) && Path.extension(exePath).toLowerCase() == "exe";
		if (!hasBinary) {
			// Return count of currently active learned rules without overwriting the executable profile
			var count = 8;
			for (_ in _learnedClasses.keys()) count++;
			for (_ in _learnedRoutes.keys()) count++;
			return count;
		}

		var classMap:Dynamic = {};
		var routeMap:Dynamic = {
			"data/settings.json": "psych_mod_settings",
			"data/achievements.json": "psych_achievements",
			"data/LoadingScreen.hx": "psych_loading_script",
			"stages/*/custom*.json": "preserve_custom_stage_data_json",
			"*-chart.json": "vslice_chart_json",
			"*-metadata.json": "vslice_metadata_json",
			"characters/*/*.json": "nested_character_json",
			"Animation.json": "flxanimate_atlas_json"
		};

		try {
			var bytes = File.getBytes(exePath);
			var sections = result.binaryAnalysis != null ? result.binaryAnalysis.sections : [];
			var strings = REAModAnalyzer.extractAsciiStringsFromPE(bytes, sections, 4);

			for (s in strings) {
				// Learn compiled Haxe classes and their methods/fields from RTTI
				if (s.indexOf(".") != -1 && s.indexOf(" ") == -1 && s.indexOf("/") == -1 && s.length >= 5 && s.length <= 80) {
					if (s.startsWith("backend.") || s.startsWith("objects.") || s.startsWith("states.")
						|| s.startsWith("substates.") || s.startsWith("psychlua.") || s.startsWith("shaders.")
						|| s.startsWith("options.") || s.startsWith("cutscenes.") || s.startsWith("tjson.")
						|| s.startsWith("flxanimate.") || s.startsWith("hxvlc.")) {
						var parts = s.split(".");
						if (parts.length >= 3) {
							var member = parts.pop();
							var cls = parts.join(".");
							if (!_learnedClasses.exists(cls)) {
								_learnedClasses.set(cls, []);
							}
							var arr = _learnedClasses.get(cls);
							if (!arr.contains(member)) arr.push(member);
						} else if (parts.length == 2) {
							if (!_learnedClasses.exists(s)) {
								_learnedClasses.set(s, []);
							}
						}
					}
				}

				// Learn file path conventions referenced inside the .EXE
				if (s.indexOf("/") != -1 && s.indexOf(" ") == -1 && s.length >= 5 && s.length <= 70) {
					var lower = s.toLowerCase();
					if (lower.endsWith(".json") || lower.endsWith(".hx") || lower.endsWith(".lua") || lower.endsWith(".txt") || lower.endsWith(".xml") || lower.endsWith(".ini")) {
						if (!_learnedRoutes.exists(s)) {
							_learnedRoutes.set(s, "exe_referenced_asset");
						}
					}
				}
			}
		} catch (_:Dynamic) {}

		var learnedRules = 8;
		for (cls in _learnedClasses.keys()) {
			Reflect.setField(classMap, cls, _learnedClasses.get(cls));
			learnedRules++;
		}
		for (rt in _learnedRoutes.keys()) {
			Reflect.setField(routeMap, rt, _learnedRoutes.get(rt));
			learnedRules++;
		}

		var versionHint = (result.binaryAnalysis != null && result.binaryAnalysis.versionHint != null) ? result.binaryAnalysis.versionHint : "1.0.x";
		var psychProfile = versionHint.startsWith("0.6") || versionHint.startsWith("0.5") ? "0.6.3" : "1.0.4";

		var profileObj:Dynamic = {
			sourceExecutable: exePath,
			detectedEngine: result.primaryEngine,
			engineVersion: versionHint,
			psychLuaProfile: psychProfile,
			learnedAt: Date.now().toString(),
			learnedRulesCount: learnedRules,
			knownClasses: classMap,
			knownFileRoutes: routeMap
		};

		activeProfile = profileObj;

		try {
			var modsDir = Path.directory(PROFILE_FILE);
			if (modsDir != "" && !FileSystem.exists(modsDir)) FileSystem.createDirectory(modsDir);
			File.saveContent(PROFILE_FILE, Json.stringify(profileObj, null, "  "));
		} catch (_:Dynamic) {}

		// Clear cached conversions so DBE re-evaluates mods with the newly learned REA rules!
		try {
			dbe.compatibility.mods.RuntimeModConverter.clearCache();
		} catch (_:Dynamic) {}

		return learnedRules;
	}

	public static function loadLearnedProfile():Void {
		try {
			if (FileSystem.exists(PROFILE_FILE)) {
				var raw = File.getContent(PROFILE_FILE);
				activeProfile = Json.parse(raw);
				var kc:Dynamic = Reflect.field(activeProfile, "knownClasses");
				if (kc != null) {
					for (cls in Reflect.fields(kc)) {
						var members:Array<Dynamic> = cast Reflect.field(kc, cls);
						if (members != null) {
							_learnedClasses.set(cls, [for (m in members) Std.string(m)]);
						}
					}
				}
				var kr:Dynamic = Reflect.field(activeProfile, "knownFileRoutes");
				if (kr != null) {
					for (route in Reflect.fields(kr)) {
						_learnedRoutes.set(route, Std.string(Reflect.field(kr, route)));
					}
				}
			}
		} catch (_:Dynamic) {}
	}

	public static function loadModExeLinks():Void {
		try {
			if (FileSystem.exists(MOD_EXE_LINKS_FILE)) {
				var raw = File.getContent(MOD_EXE_LINKS_FILE);
				var parsed:Dynamic = Json.parse(raw);
				if (parsed != null) {
					for (field in Reflect.fields(parsed)) {
						var val:Dynamic = Reflect.field(parsed, field);
						if (val != null) {
							_modExeLinks.set(field.toLowerCase(), Std.string(val));
						}
					}
				}
			}
		} catch (_:Dynamic) {}
	}

	public static function saveModExeLinks():Void {
		try {
			var obj:Dynamic = {};
			for (k in _modExeLinks.keys()) {
				Reflect.setField(obj, k, _modExeLinks.get(k));
			}
			var dir = Path.directory(MOD_EXE_LINKS_FILE);
			if (dir != "" && !FileSystem.exists(dir)) FileSystem.createDirectory(dir);
			File.saveContent(MOD_EXE_LINKS_FILE, Json.stringify(obj, null, "  "));
		} catch (_:Dynamic) {}
	}

	/**
	 * Returns the executable (.exe) explicitly associated with a mod by the user or REA prompt.
	 */
	public static function getAssociatedExecutable(modName:String):Null<String> {
		ensureInitialized();
		if (modName == null || modName == "") return null;
		var key = modName.toLowerCase().replace("\\", "/");
		var baseKey = Path.withoutDirectory(key);
		var target = _modExeLinks.get(key);
		if (target == null) target = _modExeLinks.get(baseKey);
		if (target != null && FileSystem.exists(target) && !FileSystem.isDirectory(target) && Path.extension(target).toLowerCase() == "exe") {
			return Path.normalize(FileSystem.fullPath(target));
		}
		return null;
	}

	/**
	 * Explicitly associates a mod folder name with a target executable (.exe), saving to disk.
	 */
	public static function setAssociatedExecutable(modName:String, exePath:String):Void {
		ensureInitialized();
		if (modName == null || modName == "" || exePath == null || !FileSystem.exists(exePath)) return;
		var normExe = Path.normalize(FileSystem.fullPath(exePath));
		var key = Path.withoutDirectory(modName.toLowerCase().replace("\\", "/"));
		_modExeLinks.set(key, normExe);
		saveModExeLinks();
	}

	/**
	 * Queries learned file routes extracted from executable RTTI/strings.
	 */
	public static function getLearnedRoute(relativePath:String):Null<String> {
		ensureInitialized();
		if (relativePath == null || relativePath == "") return null;
		var norm = relativePath.replace("\\", "/").toLowerCase();
		if (_learnedRoutes.exists(norm)) return _learnedRoutes.get(norm);
		for (pattern => mapped in _learnedRoutes) {
			if (pattern.indexOf("*") != -1) {
				var regexStr = "^" + pattern.replace(".", "\\.").replace("*", ".*") + "$";
				try {
					var ereg = new EReg(regexStr, "i");
					if (ereg.match(norm)) return mapped;
				} catch (_:Dynamic) {}
			}
		}
		return null;
	}

	/**
	 * Discovers any companion executable (.exe) related to a target mod directory or package.
	 * Checks explicit associations, inside the mod, parent folder, and engine root.
	 */
	public static function findCompanionExecutable(path:String):Null<String> {
		if (path == null || path == "") return null;

		// 0. Check if an explicit executable was associated by the user or REA prompt
		var modBase = Path.withoutDirectory(path);
		var linkedExe = getAssociatedExecutable(modBase);
		if (linkedExe != null) return linkedExe;

		// 1. If path itself is an .exe
		if (FileSystem.exists(path) && !FileSystem.isDirectory(path) && Path.extension(path).toLowerCase() == "exe")
			return Path.normalize(FileSystem.fullPath(path));

		// 2. If path is a folder, look inside it
		if (FileSystem.exists(path) && FileSystem.isDirectory(path)) {
			try {
				var items = FileSystem.readDirectory(path);
				for (item in items) {
					if (Path.extension(item).toLowerCase() == "exe") {
						return Path.normalize(FileSystem.fullPath(Path.join([path, item])));
					}
				}
			} catch (_:Dynamic) {}
		}

		// 3. Look in parent directory
		try {
			var parent = Path.directory(path);
			if (parent != "" && FileSystem.exists(parent)) {
				var items = FileSystem.readDirectory(parent);
				for (item in items) {
					if (Path.extension(item).toLowerCase() == "exe") {
						return Path.normalize(FileSystem.fullPath(Path.join([parent, item])));
					}
				}
			}
		} catch (_:Dynamic) {}

		// 4. Look in current working directory (e.g. ./PsychEngine.exe, ./FridayNightFunkin.exe)
		try {
			var rootItems = FileSystem.readDirectory("./");
			for (item in rootItems) {
				var low = item.toLowerCase();
				if (Path.extension(item).toLowerCase() == "exe" && low != "dbe.exe" && low != "codenameengine.exe") {
					return Path.normalize(FileSystem.fullPath(item));
				}
			}
		} catch (_:Dynamic) {}

		return null;
	}

	/**
	 * Resolves a mod-relative or "mods/<currentMod>/..." file path to its real disk path in DBE
	 * (checking both the raw mod directory in ./mods/<mod> and the converted cache directory).
	 */
	public static function resolveModFilePath(requestedPath:String):String {
		if (requestedPath == null || requestedPath == "") return requestedPath;
		var norm = requestedPath.replace("\\", "/");
		if (FileSystem.exists(norm)) return norm;

		var curMod:Null<String> = #if flixel ModsFolder.currentModFolder #else null #end;
		var curLoad:Null<String> = #if flixel ModsFolder.currentModLoadPath #else null #end;
		var modsRootPath:String = #if flixel ModsFolder.modsPath #else "./mods" #end;

		// Strip leading "mods/<curMod>/" or "mods/" if present
		var rel = norm;
		if (rel.toLowerCase().startsWith("mods/")) {
			var afterMods = rel.substr(5);
			if (curMod != null && afterMods.toLowerCase().startsWith(curMod.toLowerCase() + "/")) {
				rel = afterMods.substr(curMod.length + 1);
			} else {
				var slashIdx = afterMods.indexOf("/");
				if (slashIdx > 0) {
					var firstSeg = afterMods.substr(0, slashIdx);
					if (!["stages", "scripts", "data", "images", "songs", "characters", "weeks", "custom_events", "custom_notetypes", "shaders", "sounds", "music", "fonts", "videos"].contains(firstSeg.toLowerCase())) {
						rel = afterMods.substr(slashIdx + 1);
					} else {
						rel = afterMods;
					}
				}
			}
		}

		var candidates:Array<String> = [];
		if (curMod != null) {
			candidates.push(Path.join([modsRootPath, curMod, rel]));
			if (rel.startsWith("stages/")) candidates.push(Path.join([modsRootPath, curMod, "data", rel]));
			if (rel.startsWith("characters/")) candidates.push(Path.join([modsRootPath, curMod, "data", rel]));
		}
		if (curLoad != null) {
			candidates.push(Path.join([curLoad, rel]));
			if (rel.startsWith("stages/")) candidates.push(Path.join([curLoad, "data", rel]));
			if (rel.startsWith("characters/")) candidates.push(Path.join([curLoad, "data", rel]));
			candidates.push(Path.join([curLoad, "_dbe_preserved", rel]));
			candidates.push(Path.join([curLoad, "_dbe_preserved", "psych_source", rel]));
		}

		for (c in candidates) {
			if (FileSystem.exists(c)) return c;
		}
		return requestedPath;
	}

	/**
	 * Reads a mod setting defined in Psych 1.0's `data/settings.json`.
	 */
	public static function getModSetting(saveTag:String, ?modName:String):Dynamic {
		var targetMod:Null<String> = modName != null ? modName : (#if flixel ModsFolder.currentModFolder #else null #end);
		if (targetMod == null) targetMod = "(default)";

		if (!_modSettingsCache.exists(targetMod)) {
			var map:Map<String, Dynamic> = new Map();
			_modSettingsCache.set(targetMod, map);
			var settingsPath = resolveModFilePath("data/settings.json");
			if (FileSystem.exists(settingsPath)) {
				try {
					var parsed:Dynamic = parseRelaxedJson(File.getContent(settingsPath));
					if (Std.isOfType(parsed, Array)) {
						var arr:Array<Dynamic> = cast parsed;
						for (entry in arr) {
							if (entry != null && Reflect.hasField(entry, "save")) {
								var key = Std.string(Reflect.field(entry, "save"));
								var val = Reflect.field(entry, "value");
								map.set(key, val);
							}
						}
					} else if (Reflect.isObject(parsed)) {
						for (f in Reflect.fields(parsed)) {
							map.set(f, Reflect.field(parsed, f));
						}
					}
				} catch (_:Dynamic) {}
			}
		}

		var settings = _modSettingsCache.get(targetMod);
		if (settings != null && settings.exists(saveTag)) {
			return settings.get(saveTag);
		}
		return null;
	}

	/**
	 * Parses TJSON / relaxed JSON (with // comments, /* * / block comments, and trailing commas)
	 * used by Psych 1.0 (`tjson.TJSON`) and custom mod JSON files.
	 */
	public static function parseRelaxedJson(raw:String):Dynamic {
		if (raw == null) return null;
		var cleaned = stripJsonCommentsAndTrailingCommas(raw);
		return Json.parse(cleaned);
	}

	public static function stripJsonCommentsAndTrailingCommas(input:String):String {
		if (input == null) return "";
		var out = new StringBuf();
		var inString = false;
		var stringQuote = '"';
		var escaped = false;
		var i = 0;
		var len = input.length;

		while (i < len) {
			var ch = input.charAt(i);
			var next = i + 1 < len ? input.charAt(i + 1) : "";

			if (inString) {
				out.add(ch);
				if (escaped) {
					escaped = false;
				} else if (ch == "\\") {
					escaped = true;
				} else if (ch == stringQuote) {
					inString = false;
				}
				i++;
				continue;
			}

			if (ch == '"' || ch == "'") {
				inString = true;
				stringQuote = ch;
				out.add(ch);
				i++;
				continue;
			}

			// Line comment //
			if (ch == "/" && next == "/") {
				i += 2;
				while (i < len && input.charAt(i) != "\n") i++;
				continue;
			}

			// Block comment /* ... */
			if (ch == "/" && next == "*") {
				i += 2;
				while (i + 1 < len && !(input.charAt(i) == "*" && input.charAt(i + 1) == "/")) i++;
				i += 2;
				continue;
			}

			out.add(ch);
			i++;
		}

		// Second pass: remove trailing commas before } or ]
		var noComments = out.toString();
		var out2 = new StringBuf();
		inString = false;
		escaped = false;
		i = 0;
		len = noComments.length;
		while (i < len) {
			var ch = noComments.charAt(i);
			if (inString) {
				out2.add(ch);
				if (escaped) escaped = false;
				else if (ch == "\\") escaped = true;
				else if (ch == '"') inString = false;
			} else if (ch == '"') {
				inString = true;
				out2.add(ch);
			} else if (ch == ",") {
				var j = i + 1;
				while (j < len && StringTools.isSpace(noComments, j)) j++;
				if (j >= len || (noComments.charAt(j) != "}" && noComments.charAt(j) != "]")) {
					out2.add(ch);
				}
			} else {
				out2.add(ch);
			}
			i++;
		}
		return out2.toString();
	}

	#if flixel
	/**
	 * Injects REA-learned global helpers and class bridges into an HScript instance.
	 */
	public static function injectHScriptGlobals(script:funkin.backend.scripting.HScript):Void {
		ensureInitialized();
		var vars = script.interp.variables;

		// Provide initHScript(path) used by Psych 0.7 / 1.0 mods
		if (!vars.exists("initHScript")) {
			vars.set("initHScript", function(scriptPath:String):Dynamic {
				var resolved = resolveModFilePath(scriptPath);
				if (funkin.game.PlayState.instance != null && funkin.game.PlayState.instance.scripts != null) {
					try {
						var sub = funkin.backend.scripting.Script.create(resolved);
						if (sub != null) {
							funkin.game.PlayState.instance.scripts.add(sub);
							sub.load();
							return sub;
						}
					} catch (_:Dynamic) {}
				}
				return null;
			});
		}

		// Provide getModSetting(tag, ?mod) used by Psych 1.0 mods (reads data/settings.json)
		if (!vars.exists("getModSetting")) {
			vars.set("getModSetting", function(tag:String, ?mod:String):Dynamic {
				return getModSetting(tag, mod);
			});
		}

		// Provide ClientPrefs with .data proxy so ClientPrefs.data.antialiasing etc. never fail
		vars.set("ClientPrefs", buildClientPrefsBridge());
		vars.set("Mods", buildModsBridge());
		vars.set("TJSON", buildTJSONBridge());
		vars.set("WeekData", buildWeekDataBridge());
		vars.set("Difficulty", buildDifficultyBridge());
		vars.set("Highscore", buildHighscoreBridge());
	}

	/**
	 * Resolves unknown HScript `import` statements using classes learned by REA from custom .EXEs
	 * and built-in engine bridges.
	 */
	public static function resolveHScriptImport(interp:hscript.Interp, cl:Array<String>, ?asName:String):Bool {
		ensureInitialized();
		var full = cl.join(".");
		var shortName = cl[cl.length - 1];
		var targetVar = asName != null ? asName : shortName;

		switch (full) {
			case "backend.Mods" | "Mods":
				interp.variables.set(targetVar, buildModsBridge());
				return true;
			case "backend.ClientPrefs" | "ClientPrefs":
				interp.variables.set(targetVar, buildClientPrefsBridge());
				return true;
			case "tjson.TJSON" | "TJSON":
				interp.variables.set(targetVar, buildTJSONBridge());
				return true;
			case "backend.WeekData" | "WeekData":
				interp.variables.set(targetVar, buildWeekDataBridge());
				return true;
			case "backend.Difficulty" | "Difficulty":
				interp.variables.set(targetVar, buildDifficultyBridge());
				return true;
			case "backend.Highscore" | "Highscore":
				interp.variables.set(targetVar, buildHighscoreBridge());
				return true;
			case "backend.Achievements" | "Achievements":
				interp.variables.set(targetVar, cne.compat.PsychAchievementStore);
				return true;
			case "backend.Discord" | "backend.DiscordClient" | "DiscordClient" | "Discord":
				interp.variables.set(targetVar, funkin.backend.utils.DiscordUtil);
				return true;
			case "backend.StageData" | "StageData":
				interp.variables.set(targetVar, {
					getStageFile: function(stage:String) return {directory: "", defaultZoom: 0.9, isPixelStage: false}
				});
				return true;
			case "backend.Language" | "Language":
				interp.variables.set(targetVar, {
					getPhrase: function(key:String, ?def:String, ?values:Array<Dynamic>) return def != null ? def : key
				});
				return true;
			case "psychlua.FunkinLua" | "FunkinLua":
				interp.variables.set(targetVar, buildFunkinLuaBridge());
				return true;
			case "psychlua.CustomSubstate" | "CustomSubstate":
				interp.variables.set(targetVar, cne.compat.PsychLuaSubState);
				return true;
			case "objects.Character" | "Character":
				interp.variables.set(targetVar, funkin.game.Character);
				return true;
			case "objects.HealthIcon" | "HealthIcon":
				interp.variables.set(targetVar, funkin.game.HealthIcon);
				return true;
			case "objects.Note" | "Note":
				interp.variables.set(targetVar, funkin.game.Note);
				return true;
			case "objects.StrumNote" | "StrumNote":
				interp.variables.set(targetVar, funkin.game.Strum);
				return true;
			case "objects.Alphabet" | "objects.TypedAlphabet" | "Alphabet" | "TypedAlphabet":
				interp.variables.set(targetVar, funkin.menus.ui.Alphabet);
				return true;
			case "objects.AttachedSprite" | "objects.BGSprite" | "AttachedSprite" | "BGSprite":
				interp.variables.set(targetVar, flixel.FlxSprite);
				return true;
			case "objects.AttachedText" | "AttachedText":
				interp.variables.set(targetVar, flixel.text.FlxText);
				return true;
			case "objects.Bar" | "Bar":
				interp.variables.set(targetVar, flixel.ui.FlxBar);
				return true;
			case "states.FreeplayState" | "FreeplayState":
				interp.variables.set(targetVar, funkin.menus.FreeplayState);
				return true;
			case "states.StoryMenuState" | "StoryMenuState":
				interp.variables.set(targetVar, funkin.menus.StoryMenuState);
				return true;
			case "states.MainMenuState" | "MainMenuState":
				interp.variables.set(targetVar, funkin.menus.MainMenuState);
				return true;
			case "states.TitleState" | "TitleState":
				interp.variables.set(targetVar, funkin.menus.TitleState);
				return true;
			case "states.CreditsState" | "CreditsState":
				interp.variables.set(targetVar, funkin.menus.credits.CreditsMain);
				return true;
			case "states.LoadingState" | "LoadingState":
				interp.variables.set(targetVar, {
					loadAndSwitchState: function(target:flixel.FlxState, ?stopMusic:Bool) flixel.FlxG.switchState(target)
				});
				return true;
			case "substates.PauseSubState" | "PauseSubState":
				interp.variables.set(targetVar, funkin.menus.PauseSubState);
				return true;
			case "substates.GameOverSubstate" | "GameOverSubstate":
				interp.variables.set(targetVar, funkin.game.GameOverSubstate);
				return true;
			case "options.OptionsState" | "OptionsState" | "options.ModSettingsSubState" | "ModSettingsSubState" | "options.GameplayChangersSubstate" | "GameplayChangersSubstate" | "substates.ResetScoreSubState" | "ResetScoreSubState":
				interp.variables.set(targetVar, funkin.options.OptionsMenu);
				return true;
			default:
		}

		// Dynamic RTTI class synthesizer: if REA learned this class from an analyzed .EXE,
		// synthesize a live runtime proxy with all learned methods/fields so scripts never crash!
		if (_learnedClasses.exists(full)) {
			var members = _learnedClasses.get(full);
			var proxy:Dynamic = {};
			for (m in members) {
				if (m == "new" || m == "boot") continue;
				Reflect.setField(proxy, m, Reflect.makeVarArgs(function(args:Array<Dynamic>):Dynamic {
					return null;
				}));
			}
			interp.variables.set(targetVar, proxy);
			return true;
		}

		return false;
	}

	static function buildModsBridge():Dynamic {
		return {
			currentModDirectory: ModsFolder.currentModFolder != null ? ModsFolder.currentModFolder : "",
			getModDirectories: function():Array<String> {
				return ModsFolder.getModsList();
			},
			directoriesWithFile: function(defaultPath:String, fileToFind:String, ?mods:Bool = true):Array<String> {
				var folders:Array<String> = [];
				var resolved = resolveModFilePath(fileToFind);
				if (FileSystem.exists(resolved)) {
					folders.push(Path.addTrailingSlash(resolved));
				}
				if (ModsFolder.currentModFolder != null) {
					var rawModPath = Path.join([ModsFolder.modsPath, ModsFolder.currentModFolder, fileToFind]);
					if (FileSystem.exists(rawModPath)) {
						var withSlash = Path.addTrailingSlash(rawModPath);
						if (!folders.contains(withSlash)) folders.push(withSlash);
					}
				}
				if (ModsFolder.currentModLoadPath != null) {
					var loadModPath = Path.join([ModsFolder.currentModLoadPath, fileToFind]);
					if (FileSystem.exists(loadModPath)) {
						var withSlash = Path.addTrailingSlash(loadModPath);
						if (!folders.contains(withSlash)) folders.push(withSlash);
					}
				}
				if (defaultPath != null && defaultPath != "") {
					var defCandidate = Path.join([defaultPath, fileToFind]);
					if (FileSystem.exists(defCandidate)) {
						var withSlash = Path.addTrailingSlash(defCandidate);
						if (!folders.contains(withSlash)) folders.push(withSlash);
					}
				}
				return folders;
			},
			mergeAllTextsNamed: function(path:String, ?defaultDirectory:String, ?allowDuplicates:Bool = false):Array<String> {
				var resolved = resolveModFilePath(path);
				if (FileSystem.exists(resolved) && !FileSystem.isDirectory(resolved)) {
					try {
						return [for (l in File.getContent(resolved).split("\n")) if (l.trim() != "") l.trim()];
					} catch (_:Dynamic) {}
				}
				return [];
			}
		};
	}

	static function buildClientPrefsBridge():Dynamic {
		return {
			data: {
				antialiasing: funkin.options.Options.antialiasing,
				downScroll: funkin.options.Options.downscroll,
				middleScroll: false,
				opponentStrums: true,
				showFPS: true,
				flashing: funkin.options.Options.flashingMenu,
				lowQuality: funkin.options.Options.lowMemoryMode,
				shaders: funkin.options.Options.gameplayShaders,
				cacheOnGPU: false,
				 framerate: funkin.options.Options.framerate,
				camZooms: funkin.options.Options.camZoomOnBeat,
				hideHud: false,
				noteOffset: funkin.options.Options.songOffset,
				ghostTapping: funkin.options.Options.ghostTapping,
				timeBarType: "Time Left",
				scoreZoom: true,
				noReset: false,
				healthBarAlpha: 1.0,
				hitsoundVolume: 0.0,
				pauseMusic: "Tea Time"
			},
			defaultData: {
				antialiasing: true,
				downScroll: false,
				middleScroll: false,
				flashing: true,
				lowQuality: false,
				shaders: true
			},
			getGameplaySetting: function(name:String, ?defaultValue:Dynamic):Dynamic {
				var val = getModSetting(name);
				return val != null ? val : defaultValue;
			},
			saveSettings: function():Void {},
			loadPrefs: function():Void {}
		};
	}

	static function buildTJSONBridge():Dynamic {
		return {
			parse: function(json:String):Dynamic {
				return parseRelaxedJson(json);
			},
			encode: function(obj:Dynamic, ?style:Dynamic):String {
				return Json.stringify(obj, null, "\t");
			}
		};
	}

	static function buildWeekDataBridge():Dynamic {
		return {
			weeksLoaded: new Map<String, Dynamic>(),
			weeksList: [],
			reloadWeekFiles: function(?isStoryMode:Bool):Void {},
			getWeekFileName: function():String return "week1",
			getCurrentWeek: function():Dynamic return null,
			setDirectoryFromWeek: function(?data:Dynamic):Void {}
		};
	}

	static function buildDifficultyBridge():Dynamic {
		return {
			defaultList: ["Easy", "Normal", "Hard"],
			list: ["Easy", "Normal", "Hard"],
			getString: function(?num:Int):String return "Normal",
			getFilePath: function(?num:Int):String return "",
			loadFromWeek: function(?week:Dynamic):Void {},
			resetList: function():Void {}
		};
	}

	static function buildHighscoreBridge():Dynamic {
		return {
			getScore: function(song:String, ?diff:Int = 0):Int return 0,
			getRating: function(song:String, ?diff:Int = 0):Float return 0.0,
			getWeekScore: function(week:String, ?diff:Int = 0):Int return 0,
			formatSong: function(pie:String, ?diff:Int = 0):String return pie.toLowerCase()
		};
	}

	static function buildFunkinLuaBridge():Dynamic {
		return function(scriptPath:String):Dynamic {
			var resolved = resolveModFilePath(scriptPath);
			#if LUA_ALLOWED
			if (funkin.game.PlayState.instance != null && funkin.game.PlayState.instance.scripts != null) {
				try {
					var luaScript = new funkin.backend.scripting.LuaScript(resolved);
					funkin.game.PlayState.instance.scripts.add(luaScript);
					luaScript.load();
					return luaScript;
				} catch (_:Dynamic) {}
			}
			#end
			return null;
		};
	}
	#end
}
#end
