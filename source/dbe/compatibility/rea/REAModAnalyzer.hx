package dbe.compatibility.rea;

#if sys
import haxe.io.Bytes;
import haxe.io.Path;
import haxe.Json;
import sys.FileSystem;
import sys.io.File;
import dbe.compatibility.mods.RuntimeModConverter;

using StringTools;

/**
 * REAModAnalyzer: In-engine Reverse Engineering & Mod Compatibility Analyzer.
 *
 * Implements binary PE header inspection, Haxe RTTI symbol extraction,
 * native DLL dependency detection, string signature hunting, and standalone
 * executable (.exe) mod extraction/conversion directly inside DBE.
 */
typedef PESectionInfo = {
	name:String,
	virtualSize:Int,
	virtualAddress:Int,
	rawSize:Int,
	rawOffset:Int,
	entropy:Float
};

typedef BinaryAnalysis = {
	filePath:String,
	fileSize:Int,
	isPE:Bool,
	machine:String,
	subsystem:String,
	compileTime:String,
	isPacked:Bool,
	sections:Array<PESectionInfo>,
	detectedEngines:Array<String>,
	versionHint:String,
	nativeDependencies:Array<String>,
	haxeSymbols:Array<String>,
	customModClasses:Array<String>,
	detectedSongs:Array<String>,
	referencedAssets:Array<String>
};

typedef DirectoryAnalysis = {
	rootPath:String,
	totalFiles:Int,
	hasModsFolder:Bool,
	hasAssetsFolder:Bool,
	hasPreloadFolder:Bool,
	hasDataFolder:Bool,
	hasSongsFolder:Bool,
	executablesFound:Array<String>,
	luaScripts:Array<String>,
	hscriptFiles:Array<String>,
	chartFiles:Array<String>,
	characterFiles:Array<String>,
	shaderFiles:Array<String>,
	activeLuaHooks:Array<String>,
	riskyLuaCalls:Map<String, Int>
};

typedef REAModAnalysisResult = {
	target:String,
	targetType:String, // "executable", "directory", "archive"
	primaryEngine:String,
	engineConfidence:String, // "high", "medium", "low"
	scriptingMode:String,
	assetLayout:String,
	binaryAnalysis:Null<BinaryAnalysis>,
	directoryAnalysis:Null<DirectoryAnalysis>,
	canConvertToDBE:Bool,
	conversionComplexity:String, // "Low", "Medium", "High", "Complex"
	warnings:Array<String>,
	prescriptions:Array<String>,
	suggestedCommands:Array<String>
};

class REAModAnalyzer {
	// Engine signatures in binary strings
	static final ENGINE_SIGNATURES:Map<String, Array<String>> = [
		"CodenameEngine" => ["fnf.codename.engine", "CodenameEngine", "CustomState", "codenameengine", "FunkinEngine"],
		"PsychEngine" => ["psychlua.FunkinLua", "psychlua.", "PsychEngineVersion", "PsychEngine", "editors.MasterEditorMenu"],
		"VSlice" => ["funkin.play.PlayState", "funkin.data.song.SongRegistry", "polymod.Polymod"],
		"KadeEngine" => ["kade.KadeEngine", "KadeEngineData", "PlayStateChangeables", "kadeEngine"],
		"MicdUp" => ["MicdUp", "CustomModifier", "OptionsMenuOld"],
		"LeatherEngine" => ["LeatherEngine", "leather."],
		"ForeverEngine" => ["ForeverEngine", "forever."],
		"VanillaFNF" => ["ninja.muffin99", "ninjamuffin99", "funkin.vis."],
		"Electron" => ["electron.asar", "process.versions.electron"],
		"Godot" => ["GDScript", "Godot Engine", "engine.cfg"],
		"Unity" => ["UnityPlayer.dll", "UnityEngine", "Unity Technologies"]
	];

	static final KNOWN_LUA_HOOKS:Array<String> = [
		"onCreate", "onCreatePost", "onDestroy", "onUpdate", "onUpdatePost",
		"onStepHit", "onBeatHit", "onSectionHit", "goodNoteHit", "opponentNoteHit",
		"noteMiss", "onEvent", "onTimerCompleted", "onTweenCompleted",
		"onCustomSubstateCreate", "onCustomSubstateUpdate"
	];

	static final RISKY_LUA_APIS:Map<String, String> = [
		"runHaxeCode" => "Executes raw Haxe code via hscript; requires DBE HScript bridge or manual rewrite.",
		"addHaxeLibrary" => "Dynamically imports Haxe classes into Lua runtime; requires DBE class exports.",
		"initLuaShader" => "Compiles custom runtime GLSL shader; requires DBE FlxRuntimeShader pipeline.",
		"setShaderFloat" => "Shader uniform binding; map to DBE shader variables.",
		"createCustomSubstate" => "Spawns custom substate; map to DBE FlxSubState."
	];

	static inline function readUInt16(bytes:Bytes, pos:Int):Int {
		return bytes.get(pos) | (bytes.get(pos + 1) << 8);
	}

	static inline function readInt32(bytes:Bytes, pos:Int):Int {
		return bytes.getInt32(pos);
	}

	/**
	 * Discovers all candidate executables (.exe), archives (.zip), and mod folders
	 * across mods/, export/, and the game directory.
	 */
	public static function discoverTargets(?extraDirs:Array<String>):Array<String> {
		var found:Array<String> = [];
		var seen:Map<String, Bool> = new Map();

		function addCandidate(p:String) {
			try {
				if (!FileSystem.exists(p)) return;
				var norm = Path.normalize(FileSystem.fullPath(p));
				var key = norm.toLowerCase();
				if (!seen.exists(key)) {
					seen.set(key, true);
					found.push(norm);
				}
			} catch (_:Dynamic) {}
		}

		// 1. Scan current directory & parent directory for .exe files first
		for (root in [".", ".."]) {
			try {
				if (FileSystem.exists(root) && FileSystem.isDirectory(root)) {
					for (entry in FileSystem.readDirectory(root)) {
						var full = Path.join([root, entry]);
						if (!FileSystem.isDirectory(full) && Path.extension(entry).toLowerCase() == "exe") {
							addCandidate(full);
						}
					}
				}
			} catch (_:Dynamic) {}
		}

		// 2. Scan mods/ for .exe files (recursively up to depth 3), .zip archives, and mod folders
		var modsRoots = ["mods", "./mods", "../mods", "../../../../mods"];
		if (extraDirs != null) for (d in extraDirs) modsRoots.push(d);

		for (mRoot in modsRoots) {
			if (!FileSystem.exists(mRoot) || !FileSystem.isDirectory(mRoot)) continue;
			// First pass: find all .exe files inside mods/ and its subfolders so executables appear prominently
			scanForExecutables(mRoot, addCandidate, 3);

			// Second pass: add mod directories and .zip archives in mods/
			try {
				for (entry in FileSystem.readDirectory(mRoot)) {
					var full = Path.join([mRoot, entry]);
					var ext = Path.extension(entry).toLowerCase();
					if (FileSystem.isDirectory(full)) {
						addCandidate(full);
					} else if (ext == "exe" || ext == "zip") {
						addCandidate(full);
					}
				}
			} catch (_:Dynamic) {}
		}

		// 3. Scan export/ for compiled .exe binaries
		for (expRoot in ["export", "../export", "../../../../export"]) {
			if (FileSystem.exists(expRoot) && FileSystem.isDirectory(expRoot)) {
				scanForExecutables(expRoot, addCandidate, 4);
			}
		}

		return found;
	}

	static function scanForExecutables(dir:String, onFound:String->Void, maxDepth:Int):Void {
		if (maxDepth <= 0) return;
		try {
			for (entry in FileSystem.readDirectory(dir)) {
				var lower = entry.toLowerCase();
				if (lower == ".git" || lower == "node_modules" || lower == "obj") continue;
				var full = Path.join([dir, entry]);
				if (FileSystem.isDirectory(full)) {
					scanForExecutables(full, onFound, maxDepth - 1);
				} else if (Path.extension(lower) == "exe") {
					onFound(full);
				}
			}
		} catch (_:Dynamic) {}
	}

	/**
	 * Analyzes a given target path (executable .exe, mod directory, or .zip package).
	/**
	 * Resolves the companion build folder for an .exe file without accidentally scanning
	 * DBE's own mods/ root when a standalone .exe is dropped directly inside mods/.
	 */
	static function resolveCompanionBuildDir(exePath:String):String {
		var parentDir = Path.directory(exePath);
		var parentName = Path.withoutDirectory(parentDir).toLowerCase();
		var exeBase = Path.withoutExtension(Path.withoutDirectory(exePath));

		// If the .exe was dropped directly into DBE's own 'mods' folder (e.g. mods/PsychEngine.exe),
		// check if a matching subfolder (mods/PsychEngine/) exists; otherwise do not scan all unrelated mods!
		if (parentName == "mods") {
			var matchingSubdir = Path.join([parentDir, exeBase]);
			if (FileSystem.exists(matchingSubdir) && FileSystem.isDirectory(matchingSubdir)) {
				return matchingSubdir;
			}
			return "";
		}
		return parentDir;
	}

	/**
	 * Analyzes a given target path (executable .exe, mod directory, or .zip package).
	 */
	public static function analyzeTarget(targetPath:String):REAModAnalysisResult {
		var normalizedPath = Path.normalize(FileSystem.fullPath(targetPath));
		if (!FileSystem.exists(normalizedPath)) {
			throw new haxe.Exception('Target path does not exist: $targetPath');
		}

		var targetType = "unknown";
		var executables:Array<String> = [];
		var dirToScan = normalizedPath;

		if (!FileSystem.isDirectory(normalizedPath)) {
			var ext = Path.extension(normalizedPath).toLowerCase();
			if (ext == "exe") {
				targetType = "executable";
				executables.push(normalizedPath);
				dirToScan = resolveCompanionBuildDir(normalizedPath);
			} else if (ext == "zip" || ext == "rar" || ext == "7z") {
				targetType = "archive";
				dirToScan = Path.directory(normalizedPath);
			} else {
				// Any other binary/file treated as executable candidate
				targetType = "executable";
				executables.push(normalizedPath);
				dirToScan = resolveCompanionBuildDir(normalizedPath);
			}
		} else {
			targetType = "directory";
			// Search for .exe in directory (up to 3 levels deep)
			scanForExecutables(dirToScan, function(exe) {
				executables.push(exe);
			}, 3);
		}

		// 1. Analyze Directory Assets & Scripts
		var dirAnalysis:DirectoryAnalysis = analyzeDirectory(dirToScan);
		for (exe in executables) {
			if (!dirAnalysis.executablesFound.contains(exe)) {
				dirAnalysis.executablesFound.push(exe);
			}
		}

		// 2. Analyze Primary Binary if present
		var binAnalysis:Null<BinaryAnalysis> = null;
		if (executables.length > 0) {
			try {
				binAnalysis = analyzeExecutable(executables[0]);
			} catch (e:Dynamic) {
				// Continue even if binary parsing fails partially
			}
		}

		// 3. Engine Fingerprinting
		var engineVotes:Map<String, Int> = new Map();
		if (binAnalysis != null) {
			for (eng in binAnalysis.detectedEngines) {
				// Prioritize PsychEngine / Kade / VSlice / Custom signatures over generic base signatures
				var weight = (eng == "PsychEngine" || eng == "KadeEngine" || eng == "VSlice" || eng == "CodenameEngine") ? 6 : 3;
				engineVotes.set(eng, (engineVotes.exists(eng) ? engineVotes.get(eng) : 0) + weight);
			}
		}
		if (dirAnalysis.hasModsFolder || dirAnalysis.luaScripts.length > 0 || dirAnalysis.hasPreloadFolder) {
			engineVotes.set("PsychEngine", (engineVotes.exists("PsychEngine") ? engineVotes.get("PsychEngine") : 0) + 2);
		}
		if (dirAnalysis.hscriptFiles.length > 0) {
			engineVotes.set("CodenameEngine", (engineVotes.exists("CodenameEngine") ? engineVotes.get("CodenameEngine") : 0) + 2);
		}

		var primaryEngine = "Unknown / Custom FNF";
		var engineConfidence = "low";
		var highestVotes = 0;
		for (eng in engineVotes.keys()) {
			var v = engineVotes.get(eng);
			if (v > highestVotes) {
				highestVotes = v;
				primaryEngine = eng;
			}
		}
		if (highestVotes >= 4) engineConfidence = "high";
		else if (highestVotes >= 2) engineConfidence = "medium";

		// 4. Scripting Mode
		var scriptingMode = "none";
		if (dirAnalysis.luaScripts.length > 0 && dirAnalysis.hscriptFiles.length > 0)
			scriptingMode = "hybrid (Lua + HScript)";
		else if (dirAnalysis.luaScripts.length > 0)
			scriptingMode = "Lua (Psych / Polymod)";
		else if (dirAnalysis.hscriptFiles.length > 0)
			scriptingMode = "HScript (Codename / DBE native)";
		else if (binAnalysis != null && (binAnalysis.haxeSymbols.length > 0 || binAnalysis.customModClasses.length > 0))
			scriptingMode = "Compiled-Only (Hardcoded Haxe C++ logic in .EXE)";
		else
			scriptingMode = "Static Data Only (JSON / Assets)";

		// 5. Asset Layout
		var assetLayout = "unknown";
		if (dirAnalysis.hasModsFolder && dirAnalysis.hasAssetsFolder)
			assetLayout = "Standalone Executable Build (assets/ + mods/)";
		else if (dirAnalysis.hasModsFolder)
			assetLayout = "Psych Mods Layout (mods/)";
		else if (dirAnalysis.hasPreloadFolder)
			assetLayout = "Standalone Preload Layout (assets/preload/ + assets/shared/)";
		else if (dirAnalysis.hasAssetsFolder)
			assetLayout = "Standard Assets Layout (assets/)";
		else if (dirAnalysis.hasDataFolder || dirAnalysis.hasSongsFolder)
			assetLayout = "Loose Layout (data/, songs/ in root)";
		else
			assetLayout = "Standalone .EXE (Embedded PE Resources / RTTI)";

		// 6. Build Result & Formulate Prescriptions
		var result:REAModAnalysisResult = {
			target: normalizedPath,
			targetType: targetType,
			primaryEngine: primaryEngine,
			engineConfidence: engineConfidence,
			scriptingMode: scriptingMode,
			assetLayout: assetLayout,
			binaryAnalysis: binAnalysis,
			directoryAnalysis: dirAnalysis,
			canConvertToDBE: true,
			conversionComplexity: "Low",
			warnings: [],
			prescriptions: [],
			suggestedCommands: []
		};

		formulatePrescriptions(result, dirToScan);
		if (binAnalysis != null && binAnalysis.isPE) {
			var learned = REARuntimeBridge.learnFromAnalysis(result);
			if (learned > 0) {
				result.prescriptions.unshift('DBE Runtime Bridge learned ${learned} engine classes, APIs & file routing rules from ${Path.withoutDirectory(binAnalysis.filePath)}!');
			}
		}
		return result;
	}

	/**
	 * Scans an executable binary (Windows PE32 / PE32+) for headers, sections, DLLs, and Haxe RTTI symbols.
	 */
	public static function analyzeExecutable(exePath:String):BinaryAnalysis {
		var bytes:Bytes = File.getBytes(exePath);
		var len:Int = bytes.length;

		var isPE = false;
		var machine = "Unknown";
		var subsystem = "Unknown";
		var compileTime = "";
		var isPacked = false;
		var sections:Array<PESectionInfo> = [];
		var detectedEngines:Array<String> = [];
		var versionHint = "Unknown";
		var nativeDependencies:Array<String> = [];
		var haxeSymbols:Array<String> = [];
		var customModClasses:Array<String> = [];
		var detectedSongs:Array<String> = [];
		var referencedAssets:Array<String> = [];

		// Parse PE Header
		if (len >= 64 && bytes.get(0) == 0x4D && bytes.get(1) == 0x5A) { // 'MZ'
			var peOffset = readInt32(bytes, 60);
			if (peOffset > 0 && peOffset + 24 <= len && bytes.get(peOffset) == 0x50 && bytes.get(peOffset + 1) == 0x45) { // 'PE\0\0'
				isPE = true;
				var coff = peOffset + 4;
				var machineRaw = readUInt16(bytes, coff);
				machine = switch (machineRaw) {
					case 0x014c: "x86 (32-bit)";
					case 0x8664: "x64 (64-bit)";
					case 0xaa64: "ARM64";
					default: '0x' + StringTools.hex(machineRaw, 4);
				};

				var numSections = readUInt16(bytes, coff + 2);
				var timestamp = readInt32(bytes, coff + 4);
				try {
					var date = Date.fromTime(timestamp * 1000.0);
					compileTime = date.toString() + " UTC";
				} catch (_:Dynamic) {
					compileTime = '0x' + StringTools.hex(timestamp, 8);
				}

				var optHdrSize = readUInt16(bytes, coff + 16);
				var optHdrOffset = coff + 20;
				if (optHdrSize >= 68 && optHdrOffset + 70 <= len) {
					var subsysVal = readUInt16(bytes, optHdrOffset + 68);
					subsystem = switch (subsysVal) {
						case 2: "Windows GUI";
						case 3: "Windows CUI (Console)";
						default: 'Subsystem($subsysVal)';
					};
				}

				// Sections
				var secOffset = optHdrOffset + optHdrSize;
				for (i in 0...numSections) {
					var currentSec = secOffset + i * 40;
					if (currentSec + 40 > len) break;

					var nameBuf = new StringBuf();
					for (c in 0...8) {
						var b = bytes.get(currentSec + c);
						if (b != 0) nameBuf.addChar(b);
					}
					var secName = nameBuf.toString().trim();
					var vSize = readInt32(bytes, currentSec + 8);
					var vAddr = readInt32(bytes, currentSec + 12);
					var rawSz = readInt32(bytes, currentSec + 16);
					var rawOff = readInt32(bytes, currentSec + 20);

					var sampleLen = Std.int(Math.min(rawSz, 32768));
					var entropy = 0.0;
					if (sampleLen > 0 && rawOff >= 0 && rawOff + sampleLen <= len) {
						entropy = calculateEntropy(bytes, rawOff, sampleLen);
					}

					if (entropy > 7.3 || secName.toUpperCase().indexOf("UPX") != -1) {
						isPacked = true;
					}

					sections.push({
						name: secName,
						virtualSize: vSize,
						virtualAddress: vAddr,
						rawSize: rawSz,
						rawOffset: rawOff,
						entropy: Math.round(entropy * 100) / 100.0
					});
				}
			}
		}

		// Extract ASCII strings from PE data/rdata/rsrc sections (even in 30MB+ 64-bit binaries where .rdata starts >20MB)
		var strings = extractAsciiStringsFromPE(bytes, sections, 4);

		// Match engine signatures
		for (eng in ENGINE_SIGNATURES.keys()) {
			var sigs = ENGINE_SIGNATURES.get(eng);
			var matched = false;
			for (sig in sigs) {
				for (str in strings) {
					if (str.indexOf(sig) != -1) {
						detectedEngines.push(eng);
						matched = true;
						break;
					}
				}
				if (matched) break;
			}
		}

		// Detect Psych version
		for (str in strings) {
			if (str.indexOf("1.0.") != -1) { versionHint = "1.0.x"; break; }
			if (str.indexOf("0.7.") != -1) { versionHint = "0.7.x"; break; }
			if (str.indexOf("0.6.") != -1) { versionHint = "0.6.x"; break; }
			if (str.indexOf("0.5.") != -1) { versionHint = "0.5.x"; break; }
		}

		// Detect Haxe classes, custom states, DLLs, and songs
		var symbolMap:Map<String, Bool> = new Map();
		var customClassMap:Map<String, Bool> = new Map();
		var dllMap:Map<String, Bool> = new Map();
		var songMap:Map<String, Bool> = new Map();
		var assetMap:Map<String, Bool> = new Map();

		for (str in strings) {
			var lower = str.toLowerCase();

			// Native DLL / NDLL dependencies
			if ((lower.endsWith(".dll") || lower.endsWith(".ndll")) && str.length <= 48 && str.indexOf(" ") == -1 && str.indexOf("/") == -1) {
				dllMap.set(str, true);
			}

			// Standard Haxe engine symbols
			if (str.length >= 6 && str.length <= 70 && str.indexOf(".") != -1 && str.indexOf(" ") == -1 && str.indexOf("/") == -1) {
				if (str.startsWith("flixel.") || str.startsWith("funkin.") || str.startsWith("psychlua.")
					|| str.startsWith("states.") || str.startsWith("backend.") || str.startsWith("objects.")
					|| str.startsWith("substates.") || str.startsWith("shaders.") || str.startsWith("cutscenes.")) {
					symbolMap.set(str, true);
				}
			}

			// Custom compiled State / SubState / Stage / Mechanic classes in Haxe RTTI
			if (str.length >= 6 && str.length <= 65 && str.indexOf(" ") == -1 && str.indexOf("/") == -1) {
				if ((str.endsWith("State") || str.endsWith("Substate") || str.endsWith("SubState") || str.endsWith("Mechanic") || str.endsWith("Shader") || str.startsWith("states.stages."))
					&& !str.startsWith("flixel.") && !str.startsWith("openfl.") && !str.startsWith("lime.")) {
					var firstChar = str.charCodeAt(0);
					if ((firstChar >= 65 && firstChar <= 90) || str.startsWith("states.") || str.startsWith("substates.") || str.startsWith("shaders.") || str.startsWith("objects.")) {
						// Only record class names, not individual method refs like states.PlayState.update
						var dotCount = str.split(".").length - 1;
						if (dotCount <= 2) {
							customClassMap.set(str, true);
						}
					}
				}
			}

			// Referenced songs and assets
			if ((str.startsWith("songs/") || str.startsWith("data/") || str.startsWith("assets/songs/") || str.startsWith("assets/data/")) && str.length > 6 && str.length < 100) {
				var clean = str;
				if (clean.startsWith("assets/")) clean = clean.substr("assets/".length);
				var parts = clean.split("/");
				if (parts.length >= 2 && parts[1].length > 1 && parts[1].indexOf(" ") == -1 && parts[1].indexOf(".") == -1) {
					var candidateSong = parts[1].toLowerCase();
					if (!["characters", "stages", "weeks", "events", "custom_events", "scripts", "config", "global", "notes"].contains(candidateSong)) {
						songMap.set(candidateSong, true);
					}
				}
			}

			if ((str.startsWith("assets/") || str.startsWith("mods/") || str.startsWith("__ASSET__")) && str.length <= 90) {
				assetMap.set(str, true);
			}
		}

		for (d in dllMap.keys()) if (nativeDependencies.length < 25) nativeDependencies.push(d);
		for (sym in symbolMap.keys()) if (haxeSymbols.length < 50) haxeSymbols.push(sym);
		for (cls in customClassMap.keys()) if (customModClasses.length < 40) customModClasses.push(cls);
		for (sng in songMap.keys()) if (detectedSongs.length < 40) detectedSongs.push(sng);
		for (ast in assetMap.keys()) if (referencedAssets.length < 40) referencedAssets.push(ast);

		return {
			filePath: exePath,
			fileSize: len,
			isPE: isPE,
			machine: machine,
			subsystem: subsystem,
			compileTime: compileTime,
			isPacked: isPacked,
			sections: sections,
			detectedEngines: detectedEngines,
			versionHint: versionHint,
			nativeDependencies: nativeDependencies,
			haxeSymbols: haxeSymbols,
			customModClasses: customModClasses,
			detectedSongs: detectedSongs,
			referencedAssets: referencedAssets
		};
	}

	/**
	 * Analyzes directory tree for Lua scripts, HScript, charts, characters, and shaders.
	 */
	public static function analyzeDirectory(dirPath:String):DirectoryAnalysis {
		var analysis:DirectoryAnalysis = {
			rootPath: dirPath,
			totalFiles: 0,
			hasModsFolder: dirPath != "" && FileSystem.exists(Path.join([dirPath, "mods"])),
			hasAssetsFolder: dirPath != "" && FileSystem.exists(Path.join([dirPath, "assets"])),
			hasPreloadFolder: dirPath != "" && FileSystem.exists(Path.join([dirPath, "assets", "preload"])),
			hasDataFolder: dirPath != "" && (FileSystem.exists(Path.join([dirPath, "data"]))
				|| FileSystem.exists(Path.join([dirPath, "assets", "data"]))
				|| FileSystem.exists(Path.join([dirPath, "assets", "preload", "data"]))),
			hasSongsFolder: dirPath != "" && (FileSystem.exists(Path.join([dirPath, "songs"]))
				|| FileSystem.exists(Path.join([dirPath, "assets", "songs"]))),
			executablesFound: [],
			luaScripts: [],
			hscriptFiles: [],
			chartFiles: [],
			characterFiles: [],
			shaderFiles: [],
			activeLuaHooks: [],
			riskyLuaCalls: new Map()
		};

		if (dirPath == "" || !FileSystem.exists(dirPath) || !FileSystem.isDirectory(dirPath)) return analysis;

		var hookSet:Map<String, Bool> = new Map();
		var filesList = listFilesRecursive(dirPath);
		analysis.totalFiles = filesList.length;

		for (rel in filesList) {
			var full = Path.join([dirPath, rel]);
			var lower = rel.toLowerCase();
			var ext = Path.extension(lower);

			if (ext == "exe") {
				analysis.executablesFound.push(full);
			} else if (ext == "lua") {
				analysis.luaScripts.push(rel);
				scanLuaScript(full, hookSet, analysis.riskyLuaCalls);
			} else if (ext == "hx" || ext == "hscript" || ext == "hxs" || ext == "hsc") {
				analysis.hscriptFiles.push(rel);
			} else if (ext == "json") {
				if (lower.indexOf("data/") != -1 || lower.indexOf("charts/") != -1 || lower.indexOf("songs/") != -1) {
					analysis.chartFiles.push(rel);
				} else if (lower.indexOf("characters/") != -1) {
					analysis.characterFiles.push(rel);
				}
			} else if (ext == "frag" || ext == "vert") {
				analysis.shaderFiles.push(rel);
			}
		}

		for (hk in hookSet.keys()) {
			analysis.activeLuaHooks.push(hk);
		}
		analysis.activeLuaHooks.sort(Reflect.compare);

		return analysis;
	}

	static function scanLuaScript(filePath:String, hookSet:Map<String, Bool>, riskyMap:Map<String, Int>):Void {
		try {
			var content = File.getContent(filePath);
			for (hook in KNOWN_LUA_HOOKS) {
				if (content.indexOf("function " + hook) != -1) {
					hookSet.set(hook, true);
				}
			}
			for (api in RISKY_LUA_APIS.keys()) {
				var idx = 0;
				var occurrences = 0;
				while ((idx = content.indexOf(api, idx)) != -1) {
					occurrences++;
					idx += api.length;
				}
				if (occurrences > 0) {
					riskyMap.set(api, (riskyMap.exists(api) ? riskyMap.get(api) : 0) + occurrences);
				}
			}
		} catch (_:Dynamic) {}
	}

	static function formulatePrescriptions(result:REAModAnalysisResult, dirPath:String):Void {
		var prescriptions:Array<String> = [];
		var warnings:Array<String> = [];
		var commands:Array<String> = [];
		var complexity = "Low";

		var isExeTarget = result.targetType == "executable" || (result.binaryAnalysis != null && result.binaryAnalysis.isPE);

		if (result.binaryAnalysis != null) {
			var bp = result.binaryAnalysis;
			if (bp.isPacked) {
				warnings.push("Executable is packed/compressed (UPX/High Entropy). Unpack with 'upx -d' if embedded strings/assets are hidden.");
			}
			if (bp.customModClasses.length > 0) {
				warnings.push('Executable contains ${bp.customModClasses.length} compiled Haxe State/Stage/Shader classes (${bp.customModClasses.slice(0, 5).join(", ")}).');
				complexity = "Medium";
			}
		}

		if (isExeTarget) {
			var exeName = Path.withoutExtension(Path.withoutDirectory(result.target));
			prescriptions.push('Executable Target Detected: "${Path.withoutDirectory(result.target)}" (${result.primaryEngine}, ${result.binaryAnalysis != null ? result.binaryAnalysis.machine : "PE"}).');
			if (dirPath == "" || (result.directoryAnalysis != null && result.directoryAnalysis.totalFiles == 0)) {
				warnings.push("Standalone .EXE without companion 'assets/' or 'mods/' folder next to it. Only embedded PE assets (PNGs, Shaders, OGGs) and Haxe RTTI decompiled class stubs can be carved directly from the .EXE binary. Select the .EXE inside its original game folder (with [O] or [P]) to also extract its external songs/charts!");
				prescriptions.push('Press [ENTER] to carve embedded PNGs, GLSL Shaders, OGGs, and reconstructed Haxe RTTI scripts directly from "${Path.withoutDirectory(result.target)}" into "mods/${exeName}_REA".');
			} else {
				prescriptions.push('Press [ENTER] in REA Inspector to extract companion assets/mods AND carve embedded PE resources into "mods/${exeName}_REA".');
			}
		}

		if (result.primaryEngine == "PsychEngine") {
			prescriptions.push("Engine is Psych Engine (" + (result.binaryAnalysis != null ? result.binaryAnalysis.versionHint : "auto") + "). DBE converts Psych charts, characters, stages, and weeks automatically.");

			if (result.directoryAnalysis != null && result.directoryAnalysis.riskyLuaCalls != null) {
				for (api in result.directoryAnalysis.riskyLuaCalls.keys()) {
					var count = result.directoryAnalysis.riskyLuaCalls.get(api);
					warnings.push('Lua uses "$api" (${count}x): ' + RISKY_LUA_APIS.get(api));
					if (api == "runHaxeCode" || api == "addHaxeLibrary") {
						complexity = "High";
					} else if (complexity == "Low") {
						complexity = "Medium";
					}
				}
			}

			if (result.directoryAnalysis != null && result.directoryAnalysis.chartFiles.length > 0) {
				prescriptions.push('Found ${result.directoryAnalysis.chartFiles.length} chart(s) to normalize into DBE strumLines format.');
			}

			var modName = Path.withoutExtension(Path.withoutDirectory(result.target));
			if (dirPath != "") {
				commands.push('python tools/dbe_mod_converter.py "$dirPath" --output "mods/$modName"');
			}

		} else if (result.primaryEngine == "CodenameEngine") {
			prescriptions.push("Target uses Codename Engine / DBE architecture natively!");
			var modName = Path.withoutExtension(Path.withoutDirectory(result.target));
			prescriptions.push('Press [ENTER] to link/extract into "mods/${modName}_REA" and switch to it in ModSwitchMenu.');
			if (dirPath != "") {
				commands.push('robocopy "$dirPath" "mods\\$modName" /E');
			}

		} else if (result.primaryEngine == "VSlice") {
			prescriptions.push("Target uses V-Slice / Funkin architecture. DBE supports V-Slice chart and asset conversion.");
			prescriptions.push("Press [ENTER] to run V-Slice to DBE conversion.");

		} else if (result.primaryEngine == "KadeEngine" || result.primaryEngine == "VanillaFNF") {
			complexity = "High";
			warnings.push("Legacy engine format (" + result.primaryEngine + "). Uses assets/preload & assets/shared layout.");
			prescriptions.push("Press [ENTER] to extract assets/preload and assets/songs into a DBE mod package and convert charts.");

		} else {
			complexity = "Complex";
			warnings.push('Engine "${result.primaryEngine}" may use custom compiled C++ states or non-standard asset bundles.');
			if (result.binaryAnalysis != null && result.binaryAnalysis.haxeSymbols.length > 0) {
				prescriptions.push("Haxe RTTI symbols found in .EXE. Press [ENTER] to carve embedded assets & decompile RTTI stubs into mods/.");
			}
		}

		result.conversionComplexity = complexity;
		result.warnings = warnings;
		result.prescriptions = prescriptions;
		result.suggestedCommands = commands;
	}

	/**
	 * Automatically converts or extracts the analyzed target (supports .EXE executables,
	 * standalone game folders without pack.json, mod folders, and .ZIP archives) into DBE!
	 */
	public static function autoConvert(result:REAModAnalysisResult, managedRoot:String = null):Dynamic {
		if (managedRoot == null) managedRoot = RuntimeModConverter.defaultManagedRoot();

		var learnedRules = REARuntimeBridge.learnFromAnalysis(result);

		var target = result.target;
		var isExeFile = FileSystem.exists(target) && !FileSystem.isDirectory(target) && Path.extension(target).toLowerCase() == "exe";

		// Determine source format hint from REA binary/directory inspection
		var formatHint = switch (result.primaryEngine) {
			case "PsychEngine", "KadeEngine", "VanillaFNF", "MicdUp", "LeatherEngine", "ForeverEngine": "psych";
			case "CodenameEngine": "cne";
			case "VSlice": "vslice";
			default: "auto";
		};

		// If target is an .EXE file or a standalone build directory with .EXE / assets/preload
		if (isExeFile || (result.directoryAnalysis != null && (result.directoryAnalysis.executablesFound.length > 0 || result.directoryAnalysis.hasPreloadFolder))) {
			var standaloneRes:Dynamic = convertStandaloneExecutableBuild(result, formatHint, managedRoot);
			try {
				Reflect.setField(standaloneRes, "learnedRules", learnedRules);
			} catch (_:Dynamic) {}
			return standaloneRes;
		}

		var convRes:Dynamic = RuntimeModConverter.prepare(target, managedRoot, formatHint);
		try {
			Reflect.setField(convRes, "learnedRules", learnedRules);
		} catch (_:Dynamic) {}
		return convRes;
	}

	/**
	 * Extracts a standalone .EXE game build (or folder containing an .EXE) into
	 * a clean, playable DBE mod inside ./mods/<ExeName>_REA, carving embedded binary
	 * resources (PNGs, OGGs, GLSL Shaders, Haxe RTTI decompiled class/stage stubs)
	 * AND copying companion assets/mods folders if present, then runs RuntimeModConverter.
	 */
	public static function convertStandaloneExecutableBuild(result:REAModAnalysisResult, formatHint:String, managedRoot:String):Dynamic {
		var target = result.target;
		var isExeFile = !FileSystem.isDirectory(target) && Path.extension(target).toLowerCase() == "exe";
		var buildRoot = FileSystem.isDirectory(target) ? target : resolveCompanionBuildDir(target);
		var baseName = Path.withoutExtension(Path.withoutDirectory(target));
		if (baseName == "" || baseName.toLowerCase() == "bin" || baseName.toLowerCase() == "windows") {
			if (result.binaryAnalysis != null) {
				baseName = Path.withoutExtension(Path.withoutDirectory(result.binaryAnalysis.filePath));
			} else {
				baseName = "CustomExeMod";
			}
		}

		var modsRoot = FileSystem.exists("./mods") ? "./mods" : "mods";
		if (!FileSystem.exists(modsRoot)) FileSystem.createDirectory(modsRoot);

		var extractedModDir = Path.normalize(FileSystem.fullPath(Path.join([modsRoot, baseName + "_REA"])));
		if (!FileSystem.exists(extractedModDir)) FileSystem.createDirectory(extractedModDir);

		var copiedCount = 0;

		if (buildRoot != "" && FileSystem.exists(buildRoot) && FileSystem.isDirectory(buildRoot)) {
			// 1. Copy from buildRoot/assets/preload, buildRoot/assets/shared, buildRoot/assets/songs, buildRoot/assets/
			var assetsDir = Path.join([buildRoot, "assets"]);
			if (FileSystem.exists(assetsDir) && FileSystem.isDirectory(assetsDir)) {
				var preloadDir = Path.join([assetsDir, "preload"]);
				if (FileSystem.exists(preloadDir) && FileSystem.isDirectory(preloadDir)) {
					copiedCount += copyModAssetsFiltered(preloadDir, extractedModDir);
				}
				var sharedDir = Path.join([assetsDir, "shared"]);
				if (FileSystem.exists(sharedDir) && FileSystem.isDirectory(sharedDir)) {
					copiedCount += copyModAssetsFiltered(sharedDir, extractedModDir);
				}
				for (sub in ["songs", "data", "images", "weeks", "characters", "stages", "scripts", "shaders", "custom_events", "custom_notetypes", "music", "sounds", "fonts", "videos"]) {
					var srcSub = Path.join([assetsDir, sub]);
					if (FileSystem.exists(srcSub) && FileSystem.isDirectory(srcSub)) {
						copiedCount += copyModAssetsFiltered(srcSub, Path.join([extractedModDir, sub]));
					}
				}
			}

			// 2. Copy from buildRoot/mods/ (if the standalone .exe also has a mods/ folder)
			var exeModsDir = Path.join([buildRoot, "mods"]);
			if (FileSystem.exists(exeModsDir) && FileSystem.isDirectory(exeModsDir) && Path.normalize(FileSystem.fullPath(exeModsDir)) != Path.normalize(FileSystem.fullPath(modsRoot))) {
				var canonicalSubfolders = ["songs", "data", "images", "weeks", "characters", "stages", "scripts", "shaders", "custom_events", "custom_notetypes", "music", "sounds", "fonts", "videos"];
				try {
					for (entry in FileSystem.readDirectory(exeModsDir)) {
						var fullEntry = Path.join([exeModsDir, entry]);
						if (FileSystem.isDirectory(fullEntry)) {
							if (canonicalSubfolders.contains(entry.toLowerCase())) {
								copiedCount += copyModAssetsFiltered(fullEntry, Path.join([extractedModDir, entry]));
							} else {
								copiedCount += copyModAssetsFiltered(fullEntry, extractedModDir);
							}
						} else if (entry.toLowerCase() == "pack.json") {
							File.copy(fullEntry, Path.join([extractedModDir, "pack.json"]));
						}
					}
				} catch (_:Dynamic) {}
			}

			// 3. Also check if buildRoot itself has loose canonical folders (data/, songs/, characters/, etc.)
			for (sub in ["songs", "data", "images", "weeks", "characters", "stages", "scripts", "shaders", "custom_events", "custom_notetypes"]) {
				var srcSub = Path.join([buildRoot, sub]);
				if (FileSystem.exists(srcSub) && FileSystem.isDirectory(srcSub)) {
					copiedCount += copyModAssetsFiltered(srcSub, Path.join([extractedModDir, sub]));
				}
			}
		}

		// 4. Carve Embedded Binary Resources (PNGs, GLSL Shaders, OGGs, and Haxe RTTI decompiled class/stage stubs) directly from the .EXE!
		var exeToCarve = isExeFile ? target : (result.binaryAnalysis != null ? result.binaryAnalysis.filePath : "");
		var carvedCount = 0;
		if (exeToCarve != "" && FileSystem.exists(exeToCarve) && !FileSystem.isDirectory(exeToCarve)) {
			carvedCount = carveBinaryResourcesAndRTTI(exeToCarve, extractedModDir, result);
		}

		var totalExtracted = copiedCount + carvedCount;

		// 5. Ensure metadata marker exists so RuntimeModConverter recognizes the format identified by REA
		if (!FileSystem.exists(Path.join([extractedModDir, "pack.json"]))) {
			var packMeta = {
				name: baseName + " (REA Extracted)",
				description: 'Extracted via DBE REA from ${Path.withoutDirectory(target)} (${result.primaryEngine} | ${copiedCount} external + ${carvedCount} PE carved files)',
				restart: false,
				color: [0, 255, 204]
			};
			File.saveContent(Path.join([extractedModDir, "pack.json"]), Json.stringify(packMeta, null, "  "));
		}

		// 6. Save the REA reverse-engineering report inside the extracted mod
		exportReportJson(result, Path.join([extractedModDir, "_dbe_rea_report.json"]));
		exportReportMarkdown(result, Path.join([extractedModDir, "_dbe_rea_report.md"]));

		// 7. Now run RuntimeModConverter.prepare on the extracted mod directory!
		try {
			var conv = RuntimeModConverter.prepare(extractedModDir, managedRoot, formatHint == "auto" ? "psych" : formatHint);
			return {
				blocked: conv.blocked,
				converted: true,
				extractedFiles: totalExtracted,
				externalFiles: copiedCount,
				carvedBinaryFiles: carvedCount,
				modFolderName: baseName + "_REA",
				loadPath: conv.loadPath != null ? conv.loadPath : extractedModDir,
				report: conv.report
			};
		} catch (e:Dynamic) {
			return {
				blocked: false,
				converted: totalExtracted > 0,
				extractedFiles: totalExtracted,
				externalFiles: copiedCount,
				carvedBinaryFiles: carvedCount,
				modFolderName: baseName + "_REA",
				loadPath: extractedModDir,
				report: null
			};
		}
	}

	/**
	 * Carves embedded PNG images, GLSL shaders, OGG streams, and reconstructs Haxe RTTI
	 * class/stage/state definitions directly from a compiled Windows PE (.exe) binary.
	 */
	public static function carveBinaryResourcesAndRTTI(exePath:String, extractedModDir:String, result:REAModAnalysisResult):Int {
		var carvedFiles = 0;
		try {
			var bytes = File.getBytes(exePath);
			var len = bytes.length;
			var sections = result.binaryAnalysis != null ? result.binaryAnalysis.sections : [];
			var strings = extractAsciiStringsFromPE(bytes, sections, 4);

			// Collect embedded __ASSET__ image names so carved PNGs get meaningful names when possible
			var embeddedPngNames:Array<String> = [];
			var validIdent = ~/^[A-Za-z0-9_]+$/;
			for (s in strings) {
				if (s.startsWith("__ASSET__") && s.endsWith("_png") && s.indexOf(":") == -1 && s.indexOf(".") == -1) {
					var cleanName = s.substr("__ASSET__".length);
					if (cleanName.length > 3 && validIdent.match(cleanName) && !embeddedPngNames.contains(cleanName)) {
						embeddedPngNames.push(cleanName);
					}
				}
			}

			// 1. Carve Embedded PNG Images (\x89PNG\r\n\x1a\n ... IEND\xaeB`\x82)
			var imgOutDir = Path.join([extractedModDir, "images", "extracted_bin"]);
			createDirectoriesRecursive(imgOutDir);

			// Start scanning after .text if PE sections are available (skips 20MB+ of machine code)
			var startScanPos = 0;
			if (sections != null && sections.length > 1) {
				for (sec in sections) {
					if (sec.name.toLowerCase() != ".text" && sec.rawOffset > 0 && sec.rawOffset < len) {
						startScanPos = sec.rawOffset;
						break;
					}
				}
			}

			var pos = startScanPos;
			var pngIndex = 0;
			while (pos + 24 < len) {
				if (bytes.get(pos) == 0x89 && bytes.get(pos + 1) == 0x50 && bytes.get(pos + 2) == 0x4E && bytes.get(pos + 3) == 0x47
					&& bytes.get(pos + 4) == 0x0D && bytes.get(pos + 5) == 0x0A && bytes.get(pos + 6) == 0x1A && bytes.get(pos + 7) == 0x0A) {
					// Search for IEND\xAE\x42\x60\x82 within 8MB
					var maxEnd = Std.int(Math.min(len - 8, pos + 8 * 1024 * 1024));
					var endPos = -1;
					var cur = pos + 8;
					while (cur < maxEnd) {
						if (bytes.get(cur) == 0x49 && bytes.get(cur + 1) == 0x45 && bytes.get(cur + 2) == 0x4E && bytes.get(cur + 3) == 0x44
							&& bytes.get(cur + 4) == 0xAE && bytes.get(cur + 5) == 0x42 && bytes.get(cur + 6) == 0x60 && bytes.get(cur + 7) == 0x82) {
							endPos = cur + 8;
							break;
						}
						cur++;
					}
					if (endPos != -1 && endPos > pos + 32) {
						var pngLen = endPos - pos;
						var pngBytes = bytes.sub(pos, pngLen);
						var fileName = pngIndex < embeddedPngNames.length
							? '${pngIndex}_${embeddedPngNames[pngIndex]}.png'
							: 'carved_sprite_${pngIndex}.png';
						try {
							File.saveBytes(Path.join([imgOutDir, fileName]), pngBytes);
							carvedFiles++;
						} catch (_:Dynamic) {}
						pngIndex++;
						pos = endPos;
						continue;
					}
				}
				pos++;
			}

			// 2. Extract Embedded GLSL Shaders from PE strings
			var shaderOutDir = Path.join([extractedModDir, "shaders", "extracted_bin"]);
			createDirectoriesRecursive(shaderOutDir);
			var shaderIdx = 0;
			var seenShaders:Map<String, Bool> = new Map();
			for (s in strings) {
				if (s.length >= 45 && (s.indexOf("gl_FragColor") != -1 || s.indexOf("#pragma header") != -1 || s.indexOf("flixel_texture2D") != -1 || s.indexOf("openfl_TextureCoordv") != -1)) {
					if (!seenShaders.exists(s)) {
						seenShaders.set(s, true);
						File.saveContent(Path.join([shaderOutDir, 'carved_shader_${shaderIdx}.frag']), "// Carved from PE binary (.rdata) by DBE REA\n" + s + "\n");
						shaderIdx++;
						carvedFiles++;
					}
				}
			}

			// 3. Reconstruct Haxe RTTI Classes, Stages, States, and Lua Modules into scripts/reconstructed_rtti/
			var rttiOutDir = Path.join([extractedModDir, "scripts", "reconstructed_rtti"]);
			createDirectoriesRecursive(rttiOutDir);

			var classMethods:Map<String, Array<String>> = new Map();
			var compiledHxSources:Array<String> = [];
			var seenHx:Map<String, Bool> = new Map();

			for (s in strings) {
				if (s.endsWith(".hx") && s.indexOf(" ") == -1 && !s.startsWith("C:") && !s.startsWith("flixel/") && !s.startsWith("openfl/") && !s.startsWith("lime/")) {
					if (!seenHx.exists(s)) {
						seenHx.set(s, true);
						compiledHxSources.push(s);
					}
				}
				// Match package.ClassName.methodName
				if (s.indexOf(".") != -1 && s.indexOf(" ") == -1 && s.indexOf("/") == -1 && s.length >= 6 && s.length <= 80) {
					if (s.startsWith("states.") || s.startsWith("substates.") || s.startsWith("objects.") || s.startsWith("backend.") || s.startsWith("psychlua.") || s.startsWith("shaders.") || s.startsWith("cutscenes.")) {
						var parts = s.split(".");
						if (parts.length >= 3) {
							var method = parts.pop();
							var clsName = parts.join(".");
							if (!classMethods.exists(clsName)) {
								classMethods.set(clsName, []);
							}
							var list = classMethods.get(clsName);
							if (!list.contains(method)) list.push(method);
						} else if (parts.length == 2) {
							if (!classMethods.exists(s)) {
								classMethods.set(s, []);
							}
						}
					}
				}
			}

			// Generate reconstructed stage/state/class HScript stubs grouped by package
			var stageBuf = new StringBuf();
			stageBuf.add("// ============================================================================\n");
			stageBuf.add('// DBE REA Reconstructed Hardcoded Stages & States from ${Path.withoutDirectory(exePath)}\n');
			stageBuf.add("// ============================================================================\n\n");

			var stageCount = 0;
			for (cls in classMethods.keys()) {
				var methods = classMethods.get(cls);
				if (cls.startsWith("states.stages.")) {
					var shortStage = cls.substr("states.stages.".length);
					stageBuf.add('// Reconstructed Stage Class: $cls\n');
					stageBuf.add('// Compiled Methods/Fields: ${methods.join(", ")}\n');
					var singleStageBuf = new StringBuf();
					singleStageBuf.add('// Reconstructed by DBE REA from compiled class: $cls\n');
					singleStageBuf.add('// Original binary: ${Path.withoutDirectory(exePath)}\n\n');
					for (m in methods) {
						if (m == "new" || m == "boot") continue;
						singleStageBuf.add('function $m() {\n\t// Compiled in native C++ binary ($cls.$m)\n}\n\n');
					}
					File.saveContent(Path.join([rttiOutDir, 'stage_${shortStage}.hx']), singleStageBuf.toString());
					carvedFiles++;
					stageCount++;
				} else if (cls.startsWith("states.") || cls.startsWith("substates.") || cls.startsWith("shaders.")) {
					stageBuf.add('// Class: $cls\n');
					if (methods.length > 0) {
						stageBuf.add('//   -> Members (${methods.length}): ${methods.join(", ")}\n\n');
					}
				}
			}

			File.saveContent(Path.join([rttiOutDir, "_reconstructed_classes_overview.hx"]), stageBuf.toString());
			carvedFiles++;

			// Save full compiled .hx source tree & symbol manifest
			compiledHxSources.sort(Reflect.compare);
			var manifestBuf = new StringBuf();
			manifestBuf.add('# DBE REA Binary Symbol & Compiled Source Tree Dump\n');
			manifestBuf.add('# Executable: ${Path.withoutDirectory(exePath)} (${bytes.length} bytes)\n');
			manifestBuf.add('# Carved PNGs: $pngIndex | Carved GLSL Shaders: $shaderIdx | Reconstructed Stages: $stageCount\n\n');
			manifestBuf.add('## Compiled Haxe Source Files (${compiledHxSources.length})\n');
			for (hx in compiledHxSources) {
				manifestBuf.add('- $hx\n');
			}
			manifestBuf.add('\n## Reconstructed Haxe Classes & RTTI Methods\n');
			var sortedClasses = [for (k in classMethods.keys()) k];
			sortedClasses.sort(Reflect.compare);
			for (cls in sortedClasses) {
				manifestBuf.add('- $cls: [${classMethods.get(cls).join(", ")}]\n');
			}
			File.saveContent(Path.join([extractedModDir, "_dbe_rea_binary_symbols.txt"]), manifestBuf.toString());
			carvedFiles++;
		} catch (_:Dynamic) {}

		return carvedFiles;
	}

	static function copyModAssetsFiltered(srcDir:String, dstDir:String, depth:Int = 0):Int {
		if (depth > 8 || !FileSystem.exists(srcDir) || !FileSystem.isDirectory(srcDir)) return 0;
		if (!FileSystem.exists(dstDir)) {
			createDirectoriesRecursive(dstDir);
		}
		var count = 0;
		var skipExts = ["exe", "dll", "ndll", "pdb", "lib", "exp", "obj", "ilk"];
		try {
			for (entry in FileSystem.readDirectory(srcDir)) {
				var lower = entry.toLowerCase();
				if (lower == ".git" || lower == "manifest" || lower == "plugins") continue;
				var fullSrc = Path.join([srcDir, entry]);
				var fullDst = Path.join([dstDir, entry]);
				if (FileSystem.isDirectory(fullSrc)) {
					count += copyModAssetsFiltered(fullSrc, fullDst, depth + 1);
				} else {
					var ext = Path.extension(lower);
					if (skipExts.contains(ext)) continue;
					try {
						File.copy(fullSrc, fullDst);
						count++;
					} catch (_:Dynamic) {}
				}
			}
		} catch (_:Dynamic) {}
		return count;
	}

	static function createDirectoriesRecursive(path:String):Void {
		var norm = Path.normalize(path);
		if (norm == "" || FileSystem.exists(norm)) return;
		var parent = Path.directory(norm);
		if (parent != "" && parent != norm && !FileSystem.exists(parent)) {
			createDirectoriesRecursive(parent);
		}
		try {
			FileSystem.createDirectory(norm);
		} catch (_:Dynamic) {}
	}

	/**
	 * Exports the analysis result as a formatted JSON file.
	 */
	public static function exportReportJson(result:REAModAnalysisResult, outPath:String):Void {
		var json = Json.stringify(result, null, "  ");
		File.saveContent(outPath, json);
	}

	/**
	 * Exports the analysis result as a Markdown document.
	 */
	public static function exportReportMarkdown(result:REAModAnalysisResult, outPath:String):Void {
		var b = new StringBuf();
		b.add('# DBE REA Mod Analysis: ${Path.withoutDirectory(result.target)}\n\n');
		b.add('- **Target**: `${result.target}`\n');
		b.add('- **Type**: `${result.targetType}`\n');
		b.add('- **Detected Engine**: `${result.primaryEngine}` (${result.engineConfidence})\n');
		b.add('- **Scripting Mode**: `${result.scriptingMode}`\n');
		b.add('- **Asset Layout**: `${result.assetLayout}`\n');
		b.add('- **Conversion Complexity**: `${result.conversionComplexity}`\n\n');

		if (result.binaryAnalysis != null && result.binaryAnalysis.isPE) {
			var bp = result.binaryAnalysis;
			b.add('## Binary (.EXE) Inspection\n');
			b.add('- **Architecture**: `${bp.machine}`\n');
			b.add('- **Subsystem**: `${bp.subsystem}`\n');
			b.add('- **Compiled At**: `${bp.compileTime}`\n');
			b.add('- **Packed/UPX**: `${bp.isPacked}`\n');
			if (bp.nativeDependencies.length > 0)
				b.add('- **Native DLLs**: `${bp.nativeDependencies.join(", ")}`\n');
			if (bp.customModClasses.length > 0)
				b.add('- **Custom Compiled Classes**: `${bp.customModClasses.join(", ")}`\n');
			if (bp.detectedSongs.length > 0)
				b.add('- **Detected Songs in Binary**: `${bp.detectedSongs.join(", ")}`\n');
			b.add('\n');
		}

		b.add('## Warnings\n');
		if (result.warnings.length == 0) {
			b.add('No critical friction points detected.\n\n');
		} else {
			for (w in result.warnings) b.add('- ⚠️ $w\n');
			b.add('\n');
		}

		b.add('## How to Run / Convert this Mod in DBE\n');
		for (p in result.prescriptions) b.add('- $p\n');
		b.add('\n');

		if (result.suggestedCommands.length > 0) {
			b.add('### Suggested Commands\n```bash\n');
			for (c in result.suggestedCommands) b.add('$c\n');
			b.add('```\n');
		}

		File.saveContent(outPath, b.toString());
	}

	// -------------------------------------------------------------------------
	// Utility Helpers
	// -------------------------------------------------------------------------

	static function calculateEntropy(bytes:Bytes, offset:Int, len:Int):Float {
		var counts:Array<Int> = [for (_ in 0...256) 0];
		for (i in 0...len) {
			var b = bytes.get(offset + i);
			counts[b]++;
		}
		var entropy = 0.0;
		for (c in counts) {
			if (c > 0) {
				var p = c / len;
				entropy -= p * (Math.log(p) / Math.log(2.0));
			}
		}
		return entropy;
	}

	/**
	 * Extracts ASCII strings from PE data sections (.rdata, .data, .rsrc) so that
	 * even large 30MB+ 64-bit executables (where .rdata starts past 20MB) are scanned
	 * completely and quickly without wasting time on 23MB of .text machine instructions.
	 */
	public static function extractAsciiStringsFromPE(bytes:Bytes, sections:Array<PESectionInfo>, minLen:Int = 4):Array<String> {
		var strings:Array<String> = [];

		function scanRange(startOffset:Int, rangeLen:Int) {
			var endOffset = Std.int(Math.min(bytes.length, startOffset + rangeLen));
			if (startOffset < 0 || startOffset >= endOffset) return;
			var cur = new StringBuf();
			for (i in startOffset...endOffset) {
				var b = bytes.get(i);
				if (b >= 32 && b <= 126) {
					cur.addChar(b);
				} else {
					if (cur.length >= minLen) {
						strings.push(cur.toString());
					}
					cur = new StringBuf();
				}
			}
			if (cur.length >= minLen) strings.push(cur.toString());
		}

		if (sections != null && sections.length > 0) {
			var scannedAny = false;
			for (sec in sections) {
				var secLower = sec.name.toLowerCase();
				// Skip pure machine code (.text), exception tables (.pdata), and relocations (.reloc)
				if (secLower == ".text" || secLower == ".pdata" || secLower == ".reloc") continue;
				if (sec.rawOffset > 0 && sec.rawSize > 0 && sec.rawOffset < bytes.length) {
					scanRange(sec.rawOffset, sec.rawSize);
					scannedAny = true;
				}
			}
			if (scannedAny && strings.length > 50) {
				return strings;
			}
		}

		// Fallback if packed or non-standard sections: scan entire binary up to 48MB
		scanRange(0, Std.int(Math.min(bytes.length, 48 * 1024 * 1024)));
		return strings;
	}

	static function listFilesRecursive(dir:String, maxFiles:Int = 3000):Array<String> {
		var list:Array<String> = [];
		var lowerDir = dir.toLowerCase();
		if (lowerDir == "c:" || lowerDir == "c:/" || lowerDir == "c:\\" || lowerDir.indexOf("c:/windows") != -1 || lowerDir.indexOf("c:\\windows") != -1) {
			return list; // Do not recursively walk system drives/folders
		}

		function walk(curr:String, relPrefix:String, depth:Int) {
			if (depth > 5 || list.length >= maxFiles) return;
			try {
				for (entry in FileSystem.readDirectory(curr)) {
					if (list.length >= maxFiles) break;
					var lower = entry.toLowerCase();
					if (lower == ".git" || lower == "node_modules" || lower == "$recycle.bin" || lower == "windows" || lower == "system32" || lower == "appdata") continue;

					var full = Path.join([curr, entry]);
					var rel = relPrefix == "" ? entry : relPrefix + "/" + entry;
					if (FileSystem.isDirectory(full)) {
						walk(full, rel, depth + 1);
					} else {
						list.push(rel);
					}
				}
			} catch (_:Dynamic) {}
		}
		walk(dir, "", 0);
		return list;
	}

	/**
	 * CLI Main Entry Point: allows running REAModAnalyzer directly with Haxe!
	 */
	public static function main():Void {
		var args = Sys.args();
		if (args.length == 0) {
			Sys.println("Usage: haxe -cp source --run dbe.compatibility.rea.REAModAnalyzer <target_exe_or_folder> [--json] [--export] [--convert]");
			return;
		}

		var target = args[0];
		var asJson = false;
		var doExport = false;
		var doConvert = false;

		for (i in 1...args.length) {
			if (args[i] == "--json") asJson = true;
			if (args[i] == "--export") doExport = true;
			if (args[i] == "--convert") doConvert = true;
		}

		var result = analyzeTarget(target);

		if (asJson) {
			Sys.println(Json.stringify(result, null, "  "));
		} else {
			Sys.println("================================================================================");
			Sys.println("  DBE HAXE REA MOD ANALYZER - REVERSE ENGINEERING REPORT");
			Sys.println("================================================================================");
			Sys.println(' Target:              ${result.target}');
			Sys.println(' Type:                ${result.targetType.toUpperCase()}');
			Sys.println(' Detected Engine:     ${result.primaryEngine} (${result.engineConfidence.toUpperCase()})');
			Sys.println(' Scripting Engine:    ${result.scriptingMode}');
			Sys.println(' Asset Layout:        ${result.assetLayout}');
			Sys.println(' DBE Feasibility:     ${result.canConvertToDBE ? "FEASIBLE" : "INCOMPATIBLE"} (Complexity: ${result.conversionComplexity})');

			if (result.binaryAnalysis != null && result.binaryAnalysis.isPE) {
				var bp = result.binaryAnalysis;
				Sys.println("\n--- Binary Analysis (PE / RTTI / .EXE) ---");
				Sys.println('  Executable:         ${Path.withoutDirectory(bp.filePath)}');
				Sys.println('  Architecture:       ${bp.machine}');
				Sys.println('  Subsystem:          ${bp.subsystem}');
				Sys.println('  Compiled:           ${bp.compileTime}');
				Sys.println('  Packed / Protected: ${bp.isPacked ? "YES (UPX/High Entropy)" : "No"}');
				Sys.println('  Sections (${bp.sections.length}):      ${[for (s in bp.sections) s.name].join(", ")}');
				if (bp.nativeDependencies.length > 0) {
					Sys.println('  Native DLLs (${bp.nativeDependencies.length}):   ${bp.nativeDependencies.slice(0, 8).join(", ")}');
				}
				if (bp.customModClasses.length > 0) {
					Sys.println('  Custom Classes (${bp.customModClasses.length}): ${bp.customModClasses.slice(0, 8).join(", ")}');
				}
				if (bp.detectedSongs.length > 0) {
					Sys.println('  Binary Songs (${bp.detectedSongs.length}):   ${bp.detectedSongs.slice(0, 10).join(", ")}');
				}
				if (bp.haxeSymbols.length > 0) {
					Sys.println('  Haxe Symbols:       ${bp.haxeSymbols.slice(0, 6).join(", ")}...');
				}
			}

			if (result.directoryAnalysis != null) {
				var dp = result.directoryAnalysis;
				Sys.println("\n--- Asset & Script Inventory ---");
				Sys.println('  Total Files:        ${dp.totalFiles}');
				Sys.println('  Executables Found:  ${dp.executablesFound.length}');
				Sys.println('  Lua Scripts:        ${dp.luaScripts.length}');
				Sys.println('  HScript Files:      ${dp.hscriptFiles.length}');
				Sys.println('  Charts:             ${dp.chartFiles.length}');
				Sys.println('  Shaders:            ${dp.shaderFiles.length}');
				if (dp.activeLuaHooks.length > 0) {
					Sys.println('  Active Lua Hooks:   ${dp.activeLuaHooks.slice(0, 8).join(", ")}');
				}
			}

			if (result.warnings.length > 0) {
				Sys.println("\n--- Warnings & Friction Points ---");
				for (w in result.warnings) Sys.println('  [!] $w');
			}

			Sys.println("\n--- Prescription (How to Run / Convert in DBE) ---");
			for (p in result.prescriptions) Sys.println('  * $p');

			if (result.suggestedCommands.length > 0) {
				Sys.println("\n--- Ready-to-Run Commands ---");
				for (c in result.suggestedCommands) Sys.println('  > $c');
			}
			Sys.println("================================================================================\n");
		}

		if (doExport) {
			var outJson = Path.join([Path.directory(result.target), "_dbe_rea_report.json"]);
			exportReportJson(result, outJson);
			Sys.println('Report exported to $outJson');
		}

		if (doConvert) {
			var conv = autoConvert(result);
			Sys.println('Conversion result: ' + Json.stringify(conv));
		}
	}
}
#end
