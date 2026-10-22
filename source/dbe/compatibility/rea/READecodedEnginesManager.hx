package dbe.compatibility.rea;

#if sys
import haxe.Json;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import funkin.backend.assets.ModsFolder;
#end

using StringTools;

/**
 * Data structure representing a decoded engine profile stored in AppData or local storage.
 */
typedef DecodedEngineEntry = {
	var id:String;
	var name:String;
	var engineType:String;
	var version:String;
	var sourcePath:String;
	var profilePath:String;
	var decodedAt:String;
	var learnedRulesCount:Int;
	var isDefault:Bool;
};

/**
 * Manages all decoded/reverse-engineered engines stored in AppData.
 * Allows mods in DBE to dynamically select and switch between different decoded engine profiles.
 */
class READecodedEnginesManager {
	private static var _cachedEngines:Array<DecodedEngineEntry> = null;
	private static var _modEngineLinks:Map<String, String> = new Map();
	private static var _initialized:Bool = false;

	/**
	 * Returns the central AppData directory where decoded engine knowledge is preserved.
	 */
	public static function getAppDataDir():String {
		#if sys
		var base = Sys.getEnv("APPDATA");
		if (base == null || base.trim() == "")
			base = Sys.getEnv("LOCALAPPDATA");
		if (base == null || base.trim() == "")
			base = "./mods";

		var target = Path.join([base, "DBE", "decoded_engines"]);
		try {
			if (!FileSystem.exists(target))
				FileSystem.createDirectory(target);
		} catch (_:Dynamic) {}
		return target;
		#else
		return "./mods/_dbe_decoded_engines";
		#end
	}

	/**
	 * Returns the path to the mod-to-engine association JSON file in AppData.
	 */
	public static function getModLinksFilePath():String {
		#if sys
		var base = Sys.getEnv("APPDATA");
		if (base == null || base.trim() == "")
			base = Sys.getEnv("LOCALAPPDATA");
		if (base == null || base.trim() == "")
			return "./mods/_dbe_mod_engine_links.json";

		var dbeDir = Path.join([base, "DBE"]);
		try {
			if (!FileSystem.exists(dbeDir))
				FileSystem.createDirectory(dbeDir);
		} catch (_:Dynamic) {}
		return Path.join([dbeDir, "mod_engine_links.json"]);
		#else
		return "./mods/_dbe_mod_engine_links.json";
		#end
	}

	public static function ensureInitialized():Void {
		if (_initialized) return;
		_initialized = true;
		loadModLinks();
		refreshDecodedEngines();
	}

	/**
	 * Scans AppData, beihu roaming, local mods, and profiles to build the complete list of decoded engines.
	 */
	public static function refreshDecodedEngines():Array<DecodedEngineEntry> {
		var list:Array<DecodedEngineEntry> = [];
		var seenIds:Map<String, Bool> = new Map();

		function addEntry(entry:DecodedEngineEntry) {
			if (entry == null || entry.id == null || entry.id == "") return;
			var key = entry.id.toLowerCase();
			if (seenIds.exists(key)) return;
			seenIds.set(key, true);
			list.push(entry);
		}

		// 1. Built-in / Native Default Psych Engine Profile
		addEntry({
			id: "psych-engine",
			name: "Psych Engine (Nativo / Auto)",
			engineType: "PsychEngine",
			version: "0.6.3 / 1.0.4",
			sourcePath: "",
			profilePath: "./mods/_dbe_rea_learned_profile.json",
			decodedAt: "Integrado",
			learnedRulesCount: 64,
			isDefault: true
		});

		#if sys
		// 2. Discover engines saved in %APPDATA%/DBE/decoded_engines/*.json
		var appDataDir = getAppDataDir();
		try {
			if (FileSystem.exists(appDataDir) && FileSystem.isDirectory(appDataDir)) {
				for (file in FileSystem.readDirectory(appDataDir)) {
					if (file.toLowerCase().endsWith(".json") && file.toLowerCase() != "index.json") {
						var fullPath = Path.join([appDataDir, file]);
						try {
							var content = File.getContent(fullPath);
							var data:Dynamic = Json.parse(content);
							var id = Path.withoutExtension(file);
							var name = Reflect.field(data, "name");
							if (name == null || name == "") name = Reflect.field(data, "detectedEngine");
							if (name == null || name == "") name = id;
							addEntry({
								id: id,
								name: name,
								engineType: Reflect.field(data, "detectedEngine") != null ? Reflect.field(data, "detectedEngine") : "CustomEngine",
								version: Reflect.field(data, "engineVersion") != null ? Reflect.field(data, "engineVersion") : "1.0",
								sourcePath: Reflect.field(data, "sourceExecutable") != null ? Reflect.field(data, "sourceExecutable") : "",
								profilePath: fullPath,
								decodedAt: Reflect.field(data, "learnedAt") != null ? Reflect.field(data, "learnedAt") : "Recente",
								learnedRulesCount: Reflect.field(data, "learnedRulesCount") != null ? Std.int(Reflect.field(data, "learnedRulesCount")) : 16,
								isDefault: false
							});
						} catch (_:Dynamic) {}
					}
				}
			}
		} catch (_:Dynamic) {}

		// 3. Scan user's AppData/Roaming for known engine signatures (e.g. beihu / NovaFlare Engine)
		var roaming = Sys.getEnv("APPDATA");
		if (roaming != null && roaming != "") {
			var beihuNovaFlare = Path.join([roaming, "beihu", "NovaFlare Engine"]);
			var beihuNovaFlareDash = Path.join([roaming, "beihu", "NovaFlare-Engine"]);
			if (FileSystem.exists(beihuNovaFlare) || FileSystem.exists(beihuNovaFlareDash)) {
				addEntry({
					id: "novaflare-engine",
					name: "NovaFlare Engine",
					engineType: "NovaFlareEngine",
					version: "1.0-beihu",
					sourcePath: FileSystem.exists(beihuNovaFlare) ? beihuNovaFlare : beihuNovaFlareDash,
					profilePath: Path.join([appDataDir, "novaflare-engine.json"]),
					decodedAt: "AppData/beihu",
					learnedRulesCount: 32,
					isDefault: false
				});
			}
		}

		// 4. Scan mods folder for any *_REA directories or decoded folders
		try {
			var modsRoot = ModsFolder.modsPath;
			if (FileSystem.exists(modsRoot) && FileSystem.isDirectory(modsRoot)) {
				for (dir in FileSystem.readDirectory(modsRoot)) {
					var full = Path.join([modsRoot, dir]);
					if (FileSystem.isDirectory(full)) {
						if (dir.endsWith("_REA")) {
							var baseName = dir.substr(0, dir.length - 4);
							var id = baseName.toLowerCase().replace(" ", "-");
							addEntry({
								id: id,
								name: baseName,
								engineType: "DecodedEngine_REA",
								version: "REA Extraction",
								sourcePath: full,
								profilePath: Path.join([full, "_dbe_rea_report.json"]),
								decodedAt: "Local Mod REA",
								learnedRulesCount: 24,
								isDefault: false
							});
						}
					}
				}
			}
		} catch (_:Dynamic) {}

		// 5. Discover NovaStar Engine or other frequent decoded engines if present
		var novaStarProfile = Path.join([appDataDir, "novastar-engine.json"]);
		if (FileSystem.exists(novaStarProfile)) {
			addEntry({
				id: "novastar-engine",
				name: "NovaStar Engine",
				engineType: "NovaStarEngine",
				version: "Custom Build",
				sourcePath: "",
				profilePath: novaStarProfile,
				decodedAt: "AppData Profile",
				learnedRulesCount: 28,
				isDefault: false
			});
		}
		#end

		_cachedEngines = list;
		return list;
	}

	/**
	 * Returns the list of currently registered decoded engines.
	 */
	public static function listDecodedEngines():Array<DecodedEngineEntry> {
		ensureInitialized();
		if (_cachedEngines == null || _cachedEngines.length == 0)
			return refreshDecodedEngines();
		return _cachedEngines;
	}

	/**
	 * Registers a newly decoded engine into AppData and memory.
	 */
	public static function registerDecodedEngine(name:String, engineType:String, version:String, sourcePath:String, rawProfile:Dynamic):DecodedEngineEntry {
		ensureInitialized();

		var safeId = name.toLowerCase().replace(" ", "-").replace("_", "-");
		var appDataDir = getAppDataDir();
		var profileFile = Path.join([appDataDir, '$safeId.json']);

		var profileObj:Dynamic = rawProfile != null ? rawProfile : {};
		Reflect.setField(profileObj, "id", safeId);
		Reflect.setField(profileObj, "name", name);
		Reflect.setField(profileObj, "detectedEngine", engineType);
		Reflect.setField(profileObj, "engineVersion", version);
		Reflect.setField(profileObj, "sourceExecutable", sourcePath);
		Reflect.setField(profileObj, "learnedAt", Date.now().toString());

		#if sys
		try {
			File.saveContent(profileFile, Json.stringify(profileObj, null, "  "));
		} catch (_:Dynamic) {}

		// Also mirror locally in ./mods/_dbe_decoded_engines/
		try {
			var localDir = "./mods/_dbe_decoded_engines";
			if (!FileSystem.exists(localDir)) FileSystem.createDirectory(localDir);
			File.saveContent(Path.join([localDir, '$safeId.json']), Json.stringify(profileObj, null, "  "));
		} catch (_:Dynamic) {}
		#end

		var entry:DecodedEngineEntry = {
			id: safeId,
			name: name,
			engineType: engineType,
			version: version,
			sourcePath: sourcePath,
			profilePath: profileFile,
			decodedAt: Date.now().toString(),
			learnedRulesCount: Reflect.field(profileObj, "learnedRulesCount") != null ? Std.int(Reflect.field(profileObj, "learnedRulesCount")) : 16,
			isDefault: false
		};

		// Update cache
		refreshDecodedEngines();
		return entry;
	}

	/**
	 * Gets the ID of the decoded engine currently associated with a mod.
	 */
	public static function getEngineForMod(modName:String):String {
		ensureInitialized();
		if (modName == null || modName == "") return "psych-engine";

		if (_modEngineLinks.exists(modName))
			return _modEngineLinks.get(modName);

		return "psych-engine";
	}

	/**
	 * Sets and persists the association between a mod and a decoded engine.
	 */
	public static function setEngineForMod(modName:String, engineId:String):Void {
		ensureInitialized();
		if (modName == null || modName == "" || engineId == null) return;

		_modEngineLinks.set(modName, engineId);
		saveModLinks();

		// Apply rules to runtime bridge
		applyEngineToMod(modName, engineId);
	}

	/**
	 * Activates the knowledge profile of a decoded engine for the given mod.
	 */
	public static function applyEngineToMod(modName:String, engineId:String):Bool {
		var engines = listDecodedEngines();
		for (e in engines) {
			if (e.id == engineId) {
				#if sys
				if (e.profilePath != null && FileSystem.exists(e.profilePath)) {
					try {
						var content = File.getContent(e.profilePath);
						var parsed = Json.parse(content);
						REARuntimeBridge.activeProfile = parsed;
					} catch (_:Dynamic) {}
				}
				#end
				return true;
			}
		}
		return false;
	}

	private static function loadModLinks():Void {
		#if sys
		var paths = [getModLinksFilePath(), "./mods/_dbe_mod_engine_links.json"];
		for (p in paths) {
			if (FileSystem.exists(p)) {
				try {
					var raw = File.getContent(p);
					var parsed:Dynamic = Json.parse(raw);
					if (parsed != null) {
						for (field in Reflect.fields(parsed)) {
							_modEngineLinks.set(field, Std.string(Reflect.field(parsed, field)));
						}
					}
					break;
				} catch (_:Dynamic) {}
			}
		}
		#end
	}

	private static function saveModLinks():Void {
		#if sys
		var obj:Dynamic = {};
		for (k in _modEngineLinks.keys()) {
			Reflect.setField(obj, k, _modEngineLinks.get(k));
		}
		var serialized = Json.stringify(obj, null, "  ");

		try {
			var appDataFile = getModLinksFilePath();
			var dir = Path.directory(appDataFile);
			if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir);
			File.saveContent(appDataFile, serialized);
		} catch (_:Dynamic) {}

		try {
			var localFile = "./mods/_dbe_mod_engine_links.json";
			File.saveContent(localFile, serialized);
		} catch (_:Dynamic) {}
		#end
	}
}
