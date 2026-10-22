package dbe.compatibility.mods;

#if sys
import haxe.crypto.Crc32;
import haxe.crypto.Sha256;
import haxe.io.Bytes;
import haxe.io.Path;
import haxe.zip.Uncompress;
import sys.FileSystem;
import sys.io.File;

using StringTools;

/** Safe, native runtime normalizer for known Psych, CNE, and V-Slice mod packages. */
class RuntimeModConverter {
	public static inline var REPORT_NAME:String = "_dbe_conversion_report.json";
	public static inline var COMPLETE_MARKER:String = ".conversion_complete";
	public static inline var MAX_FILES:Int = 100000;
	public static inline var MAX_FILE_SIZE:Int = 1073741824;
	public static inline var MAX_TOTAL_SIZE:Float = 4294967296.0;
	public static inline var MAX_COMPRESSION_RATIO:Float = 1000.0;
	static final CANONICAL_ROOTS:Array<String> = ["addons", "data", "fonts", "images", "music", "scripts", "shaders", "shared", "songs", "sounds", "stages", "videos"];
	static final METADATA_FILES:Array<String> = ["pack.json", "_polymod_meta.json", "manifest.json", "mod.json"];
	static final IGNORED_PARTS:Array<String> = ["__macosx"];
	static final IGNORED_NAMES:Array<String> = [".ds_store", "thumbs.db", "desktop.ini"];
	static final SCRIPT_EXTENSIONS:Array<String> = [".hx", ".hsc", ".hscript", ".hxs", ".hxc", ".lua"];
	static final UNTRANSLATED_EXTENSIONS:Array<String> = [".js", ".ts", ".hxcpp", ".cpp"];

	/** Short per-user cache root so nested converted mod assets stay within Windows path limits. */
	public static function defaultManagedRoot():String {
		var tempRoot = Sys.getEnv("TEMP");
		if (tempRoot == null || tempRoot == "") tempRoot = Sys.getEnv("TMPDIR");
		if (tempRoot == null || tempRoot == "") tempRoot = "./.temp";
		return Path.join([tempRoot, "CodenameEngine", "mod-conversions"]);
	}

	/**
	 * Detects the source format of a mod folder or zip without converting it.
	 * Returns "psych", "cne", "vslice", or null if unknown/native.
	 */
	public static function detectFormat(source:String, managedRoot:String = null):String {
		try {
			if (managedRoot == null) managedRoot = defaultManagedRoot();
			var isArchive = FileSystem.exists('$source.zip');
			var actualSource = isArchive ? '$source.zip' : source;
			if (!FileSystem.exists(actualSource)) return null;
			var files = FileSystem.exists(actualSource) && !FileSystem.isDirectory(actualSource)
				? _listArchiveFiles(Path.normalize(FileSystem.fullPath(actualSource)))
				: _listDirectoryFiles(Path.normalize(FileSystem.fullPath(actualSource)));
			return _detectSourceFormat(actualSource, files, "auto");
		} catch (_:Dynamic) { return null; }
	}

	/**
	 * Clears the cached conversion for a given source path.
	 * The next call to prepare() or loadModLib() will re-run the conversion from scratch.
	 * Returns true if any cache folder was deleted.
	 */
	public static function clearCacheForSource(source:String, managedRoot:String = null):Bool {
		return clearCacheForMod(source, managedRoot) > 0;
	}


	public static function convertDirectory(source:String, managedRoot:String, sourceFormat:String = "auto"):Dynamic {
		if (!FileSystem.exists(source) || !FileSystem.isDirectory(source))
			throw new haxe.Exception('Mod source is not a directory: $source');
		var sourceRoot = Path.normalize(FileSystem.fullPath(source));
		var files = _listDirectoryFiles(sourceRoot);
		return _convert(sourceRoot, managedRoot, files, sourceFormat);
	}

	/** Convert a ZIP package into a content-addressed managed directory. */
	public static function convertArchive(source:String, managedRoot:String, sourceFormat:String = "auto"):Dynamic {
		if (!FileSystem.exists(source) || FileSystem.isDirectory(source))
			throw new haxe.Exception('Mod source is not a ZIP archive: $source');
		var sourcePath = Path.normalize(FileSystem.fullPath(source));
		var files = _listArchiveFiles(sourcePath);
		return _convert(sourcePath, managedRoot, files, sourceFormat);
	}

	/**
	 * Learns engine architecture, RTTI classes and file routes from a target executable using REA.
	 */
	public static function learnFromExecutable(exePath:String):Int {
		if (exePath == null || !FileSystem.exists(exePath)) return 0;
		var analysis = dbe.compatibility.rea.REAModAnalyzer.analyzeTarget(exePath);
		return dbe.compatibility.rea.REARuntimeBridge.learnFromAnalysis(analysis);
	}

	/**
	 * Automatically discovers any companion executable associated with a mod source.
	 */
	public static function findCompanionExecutable(modSourcePath:String):Null<String> {
		return dbe.compatibility.rea.REARuntimeBridge.findCompanionExecutable(modSourcePath);
	}

	/**
	 * High-level conversion that analyzes a mod (or its executable) with REA, learns its profile,
	 * and converts it into a managed DBE runtime format.
	 */
	public static function convertWithREA(source:String, ?managedRoot:String, ?sourceFormat:String = "auto", ?customExePath:String):Dynamic {
		if (managedRoot == null) managedRoot = defaultManagedRoot();
		if (customExePath != null && FileSystem.exists(customExePath)) {
			learnFromExecutable(customExePath);
		}
		return prepare(source, managedRoot, sourceFormat);
	}

	/** Inspect and normalize a mod only when it is a recognized, incompatible package. */
	public static function prepare(source:String, managedRoot:String, sourceFormat:String = "auto"):Dynamic {
		var detectedFormat = "unknown";
		try {
			// REA Integration: If source is an executable (.exe), auto-convert with REA extractor & converter!
			if (FileSystem.exists(source) && !FileSystem.isDirectory(source) && Path.extension(source).toLowerCase() == "exe") {
				var analysis = dbe.compatibility.rea.REAModAnalyzer.analyzeTarget(source);
				return dbe.compatibility.rea.REAModAnalyzer.autoConvert(analysis, managedRoot);
			}

			if (FileSystem.exists(source) && !FileSystem.isDirectory(source) && Path.extension(source).toLowerCase() != "zip")
				return {blocked: false, converted: false, loadPath: source, report: null};
			var isArchive = FileSystem.exists('$source.zip');
			var actualSource = isArchive ? '$source.zip' : source;
			if (!FileSystem.exists(actualSource))
				return {blocked: false, converted: false, loadPath: source, report: null};

			// REA Integration: Discover and learn from companion executable if available
			var companionExe = dbe.compatibility.rea.REARuntimeBridge.findCompanionExecutable(actualSource);
			if (companionExe != null) {
				dbe.compatibility.rea.REARuntimeBridge.ensureInitialized();
				var curExe = dbe.compatibility.rea.REARuntimeBridge.activeProfile != null ? Reflect.field(dbe.compatibility.rea.REARuntimeBridge.activeProfile, "sourceExecutable") : null;
				if (curExe == null || curExe != companionExe) {
					try {
						var analysis = dbe.compatibility.rea.REAModAnalyzer.analyzeTarget(companionExe);
						dbe.compatibility.rea.REARuntimeBridge.learnFromAnalysis(analysis);
					} catch (_:Dynamic) {}
				}
			}

			var files = FileSystem.exists(actualSource) && !FileSystem.isDirectory(actualSource)
				? _listArchiveFiles(Path.normalize(FileSystem.fullPath(actualSource)))
				: _listDirectoryFiles(Path.normalize(FileSystem.fullPath(actualSource)));
			var detected = _detectSourceFormat(actualSource, files, sourceFormat);
			detectedFormat = detected == null ? "unknown" : detected;
			var assetOnlyVSlice = detected == "vslice" && _hasVSliceAnimateAssetSignature(files);
			if (detected == null || (_isCompatibleLayout(files, detected) && !assetOnlyVSlice))
				return {blocked: false, converted: false, loadPath: actualSource, report: null};

			var report = _convert(actualSource, managedRoot, files, detected);
			return {blocked: false, converted: true, loadPath: report.output, report: report};
		} catch (error:Dynamic) {
			var errorMessage = Std.string(error);
			if (errorMessage.toLowerCase().indexOf("ambiguous") >= 0) detectedFormat = "ambiguous";
			var report:Dynamic = {
				reportVersion: 3,
				targetEngine: "dbe",
				sourceFormat: detectedFormat,
				source: source,
				output: null,
				reportPath: null,
				packageRoot: null,
				fileCount: 0,
				converted: [],
				retained: [],
				unsupported: [],
				ignored: [],
				dependencies: [],
				warnings: [],
				incompatibilities: [errorMessage]
			};
			try {
				var sourceFull = Path.normalize(FileSystem.fullPath(source));
				var reportRoot = Path.normalize(FileSystem.fullPath(managedRoot));
				if (!_isWithin(sourceFull, reportRoot)) {
					_createDirectories(Path.join([reportRoot, "_reports"]));
					var reportPath = Path.join([reportRoot, "_reports", Sha256.encode(source + "\n" + errorMessage) + ".json"]);
					Reflect.setField(report, "reportPath", reportPath);
					File.saveContent(reportPath, haxe.Json.stringify(report, null, "\t") + "\n");
				}
			} catch (_:Dynamic) {}
			return {blocked: true, converted: false, loadPath: null, report: report};
		}
	}

	/** Normalize and validate a source-relative path; throws before any file is written. */
	public static function normalizeRelativePath(raw:String):String {
		if (raw == null) throw new haxe.Exception("File path is missing.");
		var name = raw.replace("\\", "/");
		if (name.indexOf("\x00") >= 0 || name.startsWith("/") || name.startsWith("//") || ~/^[A-Za-z]:/.match(name))
			throw new haxe.Exception('Unsafe absolute or invalid archive path: "$raw"');
		var parts:Array<String> = [];
		for (part in name.split("/")) {
			if (part == "" || part == ".") continue;
			if (part == "..") throw new haxe.Exception('Unsafe traversal path: "$raw"');
			if (part.endsWith(" ") || part.endsWith(".")) throw new haxe.Exception('Path is not portable to Windows: "$raw"');
			for (i in 0...part.length) {
				var code = part.charCodeAt(i);
				if (code < 32 || code == 127 || ":<>?*|".indexOf(part.charAt(i)) >= 0)
					throw new haxe.Exception('Path is not portable to Windows: "$raw"');
			}
			var deviceName = part.split(".")[0].trim().toUpperCase();
			if (["CON", "PRN", "AUX", "NUL", "CLOCK$"].contains(deviceName)
				|| (deviceName.length == 4 && (deviceName.startsWith("COM") || deviceName.startsWith("LPT"))
					&& "123456789".indexOf(deviceName.charAt(3)) >= 0))
				throw new haxe.Exception('Path is not portable to Windows: "$raw"');
			parts.push(part);
		}
		if (parts.length == 0) throw new haxe.Exception('Unsafe empty archive path: "$raw"');
		return parts.join("/");
	}

	static function _convert(source:String, managedRoot:String, files:Array<ModPackageFile>, requestedFormat:String):Dynamic {
		if (requestedFormat != "auto" && requestedFormat != "psych" && requestedFormat != "cne" && requestedFormat != "vslice")
			throw new haxe.Exception('Unsupported source format: $requestedFormat');
		if (files.length == 0) throw new haxe.Exception("The source package contains no files.");
		if (files.length > MAX_FILES) throw new haxe.Exception('Package contains more than $MAX_FILES files.');

		var format = _detectSourceFormat(source, files, requestedFormat);
		if (format == null) throw new haxe.Exception("Could not identify the source engine. Choose Psych, CNE, or V-Slice explicitly.");
		var packageRoot = _choosePackageRoot(files);
		var destinations:Map<String, String> = [];
		var generatedFiles = _psychGeneratedFiles(files, packageRoot, format);
		for (file in files) {
			var name = normalizeRelativePath(file.name);
			if (_isIgnored(name)) continue;
			var mapped = _mappedDestination(name, packageRoot, format);
			if (mapped.toLowerCase() == REPORT_NAME.toLowerCase())
				throw new haxe.Exception('The source already contains the reserved report path: $name');
			var key = mapped.toLowerCase();
			if (destinations.exists(key))
				throw new haxe.Exception('Files map to the same DBE path: ${destinations.get(key)} and $name -> $mapped');
			destinations.set(key, name);
		}
		for (generated in generatedFiles) {
			var key = generated.target.toLowerCase();
			if (destinations.exists(key))
				throw new haxe.Exception('Generated Psych event metadata collides with a source file: ${destinations.get(key)} and ${generated.source} -> ${generated.target}');
			destinations.set(key, generated.source);
		}

		var hashParts:Array<String> = [];
		hashParts.push("runtime-mod-converter-format-v14");
		hashParts.push("source-format:" + format);
		var totalSize:Float = 0;
		for (file in files) {
			var name = normalizeRelativePath(file.name);
			if (_isIgnored(name)) continue;
			if (file.size < 0 || file.size > MAX_FILE_SIZE)
				throw new haxe.Exception('File exceeds the $MAX_FILE_SIZE-byte limit: $name');
			totalSize += file.size;
			if (totalSize > MAX_TOTAL_SIZE) throw new haxe.Exception("Package exceeds the 4 GiB expanded-size limit.");
			var bytes = file.read();
			if (bytes == null || bytes.length != file.size)
				throw new haxe.Exception('Could not read the complete source file: $name');
			hashParts.push(name.toLowerCase() + "\n" + Sha256.make(bytes).toHex());
		}
		hashParts.sort(Reflect.compare);
		var contentHash = Sha256.encode(hashParts.join("\n"));
		var sourceFull = Path.normalize(FileSystem.fullPath(source));
		var outputRoot = Path.normalize(FileSystem.fullPath(managedRoot));
		if (_isWithin(sourceFull, outputRoot))
			throw new haxe.Exception("The managed conversion directory must be outside the source package.");
		if (!FileSystem.exists(outputRoot)) _createDirectories(outputRoot);
		var outputPath = Path.join([outputRoot, contentHash]);
		var savedReportPath = Path.join([outputPath, REPORT_NAME]);
		var completeMarkerPath = Path.join([outputPath, COMPLETE_MARKER]);
		if (FileSystem.exists(outputPath)) {
			if (FileSystem.exists(savedReportPath) && FileSystem.exists(completeMarkerPath)) {
				try {
					var cached:Dynamic = haxe.Json.parse(File.getContent(savedReportPath));
					if (Reflect.field(cached, "contentHash") == contentHash) {
						var hasBasicIntegrity = true;
						var convertedItems:Array<Dynamic> = cast Reflect.field(cached, "converted");
						var retainedItems:Array<Dynamic> = cast Reflect.field(cached, "retained");
						var totalItems = (convertedItems != null ? convertedItems.length : 0) + (retainedItems != null ? retainedItems.length : 0);
						if (totalItems > 0) {
							var expectsImages = false;
							var expectsData = false;
							if (retainedItems != null) for (item in retainedItems) {
								var target:String = cast Reflect.field(item, "target");
								if (target != null && target.startsWith("images/")) expectsImages = true;
								if (target != null && target.startsWith("data/")) expectsData = true;
								if (expectsImages && expectsData) break;
							}
							if (expectsImages && !FileSystem.exists(Path.join([outputPath, "images"]))) hasBasicIntegrity = false;
							if (expectsData && !FileSystem.exists(Path.join([outputPath, "data"]))) hasBasicIntegrity = false;
						}
						if (hasBasicIntegrity) return cached;
					}
				} catch (_:Dynamic) {}
			}
			try {
				_deleteTree(outputPath);
			} catch (_:Dynamic) {}
		}

		var packageRootLabel = packageRoot.length == 0 ? "." : packageRoot.join("/");
		var converted:Array<Dynamic> = [];
		var retained:Array<Dynamic> = [];
		var unsupported:Array<Dynamic> = [];
		var ignored:Array<Dynamic> = [];
		var warnings:Array<String> = [];
		var stagingRoot = Path.join([outputRoot, ".dbe-staging-" + Std.string(Date.now().getTime()) + "-" + Std.random(1000000)]);
		var staging = Path.join([stagingRoot, "package"]);
		FileSystem.createDirectory(staging);
		try {
			for (file in files) {
				var name = normalizeRelativePath(file.name);
				if (_isIgnored(name)) {
					ignored.push({source: name, reason: "operating-system metadata"});
					continue;
				}
				var mapped = _mappedDestination(name, packageRoot, format);
				var target = _nativeJoin(staging, mapped);
				var targetParent = Path.directory(target);
				_createDirectories(targetParent);
				var contents = file.read();
				if (contents == null || contents.length != file.size)
					throw new haxe.Exception('Could not copy the complete source file: $name');
				var outputContents = contents;
				var normalizedContent = false;
				if (format == "psych" && mapped.toLowerCase().startsWith("images/menus/mainmenu/") && Path.extension(mapped).toLowerCase() == "xml") {
					var normalizedAtlas = _convertPsychMainMenuAtlas(name, mapped, contents.toString());
					outputContents = Bytes.ofString(normalizedAtlas);
					normalizedContent = outputContents.compare(contents) != 0;
				}
				if (format == "psych" && mapped.toLowerCase() == "images/menus/titlescreen/titleenter.xml") {
					var normalizedAtlas = _convertPsychTitleEnterAtlas(contents.toString());
					outputContents = Bytes.ofString(normalizedAtlas);
					normalizedContent = outputContents.compare(contents) != 0;
				}
				if (format == "psych" && mapped.toLowerCase() == "images/menus/titlescreen/logo.xml") {
					var normalizedAtlas = _convertPsychLogoAtlas(contents.toString());
					outputContents = Bytes.ofString(normalizedAtlas);
					normalizedContent = outputContents.compare(contents) != 0;
				}
				if (format == "psych" && mapped.toLowerCase().startsWith("data/characters/")) {
					if (Path.extension(mapped).toLowerCase() == "json") {
						var normalizedJson = _normalizePsychCharacterJson(name, contents.toString());
						outputContents = Bytes.ofString(normalizedJson);
						normalizedContent = outputContents.compare(contents) != 0;
					} else if (Path.extension(mapped).toLowerCase() == "xml") {
						var normalizedXml = _normalizePsychCharacterXml(name, contents.toString());
						outputContents = Bytes.ofString(normalizedXml);
						normalizedContent = outputContents.compare(contents) != 0;
					}
				}
				if (format == "psych" && Path.extension(name).toLowerCase() == "json") {
					if (mapped.toLowerCase().startsWith("data/stages/") && mapped.toLowerCase().endsWith(".xml")) {
						// Look for companion .lua file (e.g. stages/heaven.json -> stages/heaven.lua)
						var luaCompanionName = _replaceExtension(name, ".lua");
						var luaCompanion = _findFile(files, luaCompanionName);
						var luaContents:String = null;
						#if !LUA_ALLOWED
						if (luaCompanion != null) try { luaContents = luaCompanion.read().toString(); } catch (_:Dynamic) {}
						#end
						outputContents = Bytes.ofString(_convertPsychStageJson(name, contents.toString(), unsupported, warnings, luaContents));
					} else if (mapped.toLowerCase().startsWith("data/weeks/weeks/") && mapped.toLowerCase().endsWith(".xml"))
						outputContents = Bytes.ofString(_convertPsychWeekJson(name, contents.toString(), unsupported, warnings));
				}
				File.saveBytes(target, outputContents);
				var item = {source: name, target: mapped};
				var extension = Path.extension(mapped).toLowerCase();
			if (format != "cne" && SCRIPT_EXTENSIONS.contains('.$extension'))
					warnings.push('Script copied without source-code translation: $name');
				if (mapped.startsWith("_dbe_preserved/")) {
					retained.push({source: name, target: mapped, reason: "outside the detected package root; retained for review"});
					warnings.push('File outside the detected mod root was preserved for review: $name');
				} else {
					if (UNTRANSLATED_EXTENSIONS.contains('.$extension'))
					unsupported.push({source: name, target: mapped, reason: "script runtime is not translated by this converter"});
					if (mapped != name || normalizedContent) {
						converted.push(normalizedContent ? {source: name, target: mapped, reason: "Psych character sprite path normalized for DBE"} : item);
					}
					else if (!UNTRANSLATED_EXTENSIONS.contains('.$extension'))
					retained.push(item);
				}
			}
			for (generated in generatedFiles) {
				var target = _nativeJoin(staging, generated.target);
				_createDirectories(Path.directory(target));
				File.saveBytes(target, generated.contents);
				if (generated.reason == "preserved original Psych metadata")
					retained.push({source: generated.source, target: generated.target, reason: generated.reason});
				else
					converted.push({source: generated.source, target: generated.target, reason: generated.reason});
			}
			if (unsupported.length > 0)
				warnings.push("One or more scripts use runtimes this converter does not translate; they were preserved for manual review.");
			if (format == "psych" || format == "vslice")
				warnings.push("Folder paths and known package wrappers were normalized; script logic was not translated.");

			var report:Dynamic = {
				reportVersion: 3,
				targetEngine: "dbe",
				sourceFormat: format,
				source: source,
				output: outputPath,
				contentHash: contentHash,
				packageRoot: packageRootLabel,
				fileCount: files.length,
				converted: converted,
				retained: retained,
				unsupported: unsupported,
				ignored: ignored,
				dependencies: _collectDependencies(files, packageRoot),
				warnings: _unique(warnings),
				incompatibilities: []
			};
			dbe.compatibility.rea.REARuntimeBridge.ensureInitialized();
			var prof = dbe.compatibility.rea.REARuntimeBridge.activeProfile;
			if (prof != null) {
				Reflect.setField(report, "reaProfile", {
					sourceExecutable: Reflect.field(prof, "sourceExecutable"),
					detectedEngine: Reflect.field(prof, "detectedEngine"),
					engineVersion: Reflect.field(prof, "engineVersion"),
					psychLuaProfile: Reflect.field(prof, "psychLuaProfile"),
					learnedRulesCount: Reflect.field(prof, "learnedRulesCount"),
					learnedAt: Reflect.field(prof, "learnedAt")
				});
			}
			File.saveContent(Path.join([staging, REPORT_NAME]), haxe.Json.stringify(report, null, "\t") + "\n");
			File.saveContent(Path.join([staging, COMPLETE_MARKER]), "ok\n");
			if (FileSystem.exists(outputPath)) {
				try { _deleteTree(outputPath); } catch (_:Dynamic) {}
			}
			_moveOrMergeDirectory(staging, outputPath);
			if (FileSystem.exists(stagingRoot)) {
				try { _deleteTree(stagingRoot); } catch (_:Dynamic) {}
			}
			return report;
		} catch (error:Dynamic) {
			if (FileSystem.exists(stagingRoot)) {
				try { _deleteTree(stagingRoot); } catch (_:Dynamic) {}
			}
			throw error;
		}
	}

	static function _safeReadFileBytes(full:String):Bytes {
		try {
			return File.getBytes(full);
		} catch (e:Dynamic) {
			#if windows
			var winLong = full.replace("/", "\\");
			if (!winLong.startsWith("\\\\?\\")) winLong = "\\\\?\\" + winLong;
			return File.getBytes(winLong);
			#else
			throw e;
			#end
		}
	}

	static function _safeFileSize(full:String):Int {
		try {
			return FileSystem.stat(full).size;
		} catch (_:Dynamic) {
			try {
				return _safeReadFileBytes(full).length;
			} catch (e:Dynamic) {
				throw e;
			}
		}
	}

	static function _listDirectoryFiles(source:String):Array<ModPackageFile> {
		if (!FileSystem.isDirectory(source)) throw new haxe.Exception('Source is not a directory: $source');
		var files:Array<ModPackageFile> = [];
		var seen:Map<String, String> = [];
		var total:Float = 0;
		function walk(current:String, relative:String, depth:Int):Void {
			if (depth > 128) throw new haxe.Exception("Mod folder nesting exceeds 128 levels.");
			var entries:Array<String> = [];
			try {
				entries = FileSystem.readDirectory(current);
			} catch (_:Dynamic) {
				#if windows
				var winLong = current.replace("/", "\\");
				if (!winLong.startsWith("\\\\?\\")) winLong = "\\\\?\\" + winLong;
				entries = FileSystem.readDirectory(winLong);
				#end
			}
			for (entry in entries) {
				var full = Path.join([current, entry]);
				var name = normalizeRelativePath(relative == "" ? entry : '$relative/$entry');
				var isDir = false;
				try {
					isDir = FileSystem.isDirectory(full);
				} catch (_:Dynamic) {
					#if windows
					var winLong = full.replace("/", "\\");
					if (!winLong.startsWith("\\\\?\\")) winLong = "\\\\?\\" + winLong;
					try { isDir = FileSystem.isDirectory(winLong); } catch (_:Dynamic) {}
					#end
				}
				if (isDir) {
					walk(full, name, depth + 1);
				} else {
					var key = name.toLowerCase();
					if (seen.exists(key)) throw new haxe.Exception('Case-insensitive file collision: ${seen.get(key)} and $name');
					seen.set(key, name);
					var size = _safeFileSize(full);
					if (size > MAX_FILE_SIZE) throw new haxe.Exception('File exceeds the $MAX_FILE_SIZE-byte limit: $name');
					total += size;
					if (total > MAX_TOTAL_SIZE) throw new haxe.Exception("Package exceeds the 4 GiB expanded-size limit.");
					files.push({name: name, size: size, read: function() return _safeReadFileBytes(full)});
					if (files.length > MAX_FILES) throw new haxe.Exception('Package contains more than $MAX_FILES files.');
				}
			}
		}
		walk(source, "", 0);
		if (files.length == 0) throw new haxe.Exception("The source package contains no files.");
		return files;
	}

	static function _listArchiveFiles(source:String):Array<ModPackageFile> {
		var archiveSize = FileSystem.stat(source).size;
		if (archiveSize < 22) throw new haxe.Exception("The source file is not a valid ZIP archive.");
		var input = File.read(source, true);
		var files:Array<ModPackageFile> = [];
		var seen:Map<String, String> = [];
		var total:Float = 0;
		try {
			var tailSize = Std.int(Math.min(archiveSize, 65557));
			input.seek(archiveSize - tailSize, SeekBegin);
			var tail = input.read(tailSize);
			var eocd = -1;
			var start = tail.length - 22;
			while (start >= 0) {
				if (tail.getInt32(start) == 0x06054B50 && start + 22 + tail.getUInt16(start + 20) == tail.length) {
					eocd = start;
					break;
				}
				start--;
			}
			if (eocd < 0) throw new haxe.Exception("ZIP end-of-directory record is missing or malformed.");
			if (tail.getUInt16(eocd + 4) != 0 || tail.getUInt16(eocd + 6) != 0)
				throw new haxe.Exception("Multi-disk ZIP archives are not supported.");
			var entryCount = tail.getUInt16(eocd + 10);
			var centralSize = tail.getInt32(eocd + 12);
			var centralOffset = tail.getInt32(eocd + 16);
			if (entryCount == 0xFFFF || centralSize == -1 || centralOffset == -1)
				throw new haxe.Exception("ZIP64 archives are not supported by the runtime converter.");
			if (entryCount > MAX_FILES || centralOffset < 0 || centralSize < 0 || centralOffset + centralSize > archiveSize)
				throw new haxe.Exception("ZIP central directory has invalid bounds or too many entries.");
			input.seek(centralOffset, SeekBegin);
			var actualCentralOffset = input.tell();
			for (_ in 0...entryCount) {
				var header = input.read(46);
			if (header.getInt32(0) != 0x02014B50) throw new haxe.Exception('ZIP central directory entry is malformed at ${input.tell() - 46} (central=$centralOffset, actual=$actualCentralOffset, size=$archiveSize, signature=0x${StringTools.hex(header.getInt32(0), 8)}).');
				var madeBy = header.getUInt16(4) >> 8;
				var flags = header.getUInt16(8);
				var method = header.getUInt16(10);
				var crc = header.getInt32(16);
				var compressedSize = header.getInt32(20);
				var fileSize = header.getInt32(24);
				var nameLength = header.getUInt16(28);
				var extraLength = header.getUInt16(30);
				var commentLength = header.getUInt16(32);
				var externalAttributes = header.getInt32(38);
				var localOffset = header.getInt32(42);
				var rawName = input.read(nameLength).toString();
				input.seek(extraLength + commentLength, SeekCur);
				var name = normalizeRelativePath(rawName);
				var unixMode = externalAttributes >>> 16;
				if ((madeBy == 3 || madeBy == 19) && (unixMode & 0xF000) == 0xA000)
					throw new haxe.Exception('Symbolic links are not supported in ZIP files: $name');
				if ((flags & 1) != 0) throw new haxe.Exception('Encrypted ZIP entries are not supported: $name');
				if (method != 0 && method != 8) throw new haxe.Exception('Unsupported ZIP compression method $method: $name');
				if (fileSize < 0 || compressedSize < 0 || localOffset < 0 || fileSize > MAX_FILE_SIZE)
					throw new haxe.Exception('ZIP entry has invalid size or offset: $name');
				total += fileSize;
				if (total > MAX_TOTAL_SIZE) throw new haxe.Exception("ZIP expands beyond the 4 GiB total-size limit.");
				if (fileSize > 1048576 && fileSize / Math.max(compressedSize, 1) > MAX_COMPRESSION_RATIO)
					throw new haxe.Exception('ZIP entry has a suspicious compression ratio: $name');
				if (rawName.endsWith("/") || rawName.endsWith("\\")) continue;
				var key = name.toLowerCase();
				if (seen.exists(key)) throw new haxe.Exception('Case-insensitive ZIP entry collision: ${seen.get(key)} and $name');
				seen.set(key, name);
				var nextCentralEntry = input.tell();
				input.seek(localOffset, SeekBegin);
				var localHeader = input.read(30);
				if (localHeader.getInt32(0) != 0x04034B50) throw new haxe.Exception('ZIP local file header is malformed: $name');
				var dataOffset = localOffset + 30 + localHeader.getUInt16(26) + localHeader.getUInt16(28);
				if (dataOffset < 0 || dataOffset + compressedSize > centralOffset)
					throw new haxe.Exception('ZIP entry data has invalid bounds: $name');
				var zipInfo:ZipModEntry = {path: source, offset: dataOffset, compressedSize: compressedSize, size: fileSize, method: method, crc: crc};
				files.push({name: name, size: fileSize, read: function() return _readZipEntry(zipInfo)});
				input.seek(nextCentralEntry, SeekBegin);
			}
			if (input.tell() > centralOffset + centralSize)
				throw new haxe.Exception("ZIP central directory length does not match its entries.");
		} catch (error:Dynamic) {
			input.close();
			if (error is haxe.Exception) throw error;
			throw new haxe.Exception('Invalid ZIP archive: ${Std.string(error)}');
		}
		input.close();
		if (files.length == 0) throw new haxe.Exception("The ZIP archive contains no files.");
		return files;
	}

	static function _readZipEntry(info:ZipModEntry):Bytes {
		var input = File.read(info.path, true);
		try {
			input.seek(info.offset, SeekBegin);
			var compressed = input.read(info.compressedSize);
			input.close();
			var contents:Bytes;
			if (info.method == 0) contents = compressed;
			else {
				contents = Bytes.alloc(info.size);
				var inflater = new Uncompress(-15);
				var result = inflater.execute(compressed, 0, contents, 0);
				inflater.close();
				if (!result.done || result.read != compressed.length || result.write != info.size)
					throw new haxe.Exception("ZIP entry decompressed to an unexpected size.");
			}
			if (contents.length != info.size || Crc32.make(contents) != info.crc)
				throw new haxe.Exception("ZIP entry failed its size or CRC check.");
			return contents;
		} catch (error:Dynamic) {
			try input.close() catch (_:Dynamic) {}
			throw error;
		}
	}

	static function _detectSourceFormat(source:String, files:Array<ModPackageFile>, requested:String):Null<String> {
		if (requested != "auto") return requested;
		var names = [for (file in files) file.name.toLowerCase()];
		var psych = false;
		var cne = false;
		var vslice = false;
		for (name in names) {
			if (name == "pack.json" || name.endsWith("/pack.json") || name == "scripts/modchart.lua" || name.endsWith("/scripts/modchart.lua")) psych = true;
			if (name.startsWith("custom_events/") || name.indexOf("/custom_events/") >= 0
				|| name.startsWith("custom_notetypes/") || name.indexOf("/custom_notetypes/") >= 0
				|| (name.startsWith("weeks/") && name.endsWith(".json"))
				|| (name.startsWith("characters/") && name.endsWith(".json"))) psych = true;
			if (name == "data/config/modpack.ini" || name.endsWith("/data/config/modpack.ini")) cne = true;
			if (~/((^|\/)data\/(events|characters|stages)\/[^\/]+\.hx$)/.match(name)) cne = true;
			if (name == "_polymod_meta.json" || name.endsWith("/_polymod_meta.json")) {
				var entry = _findFile(files, name);
				var text = entry == null || entry.size > 1048576 ? null : entry.read().toString();
				if (text != null) try {
					var metadata:Dynamic = haxe.Json.parse(text);
					if (Reflect.hasField(metadata, "api_version") || Reflect.hasField(metadata, "modFiles") || Reflect.hasField(metadata, "modFolders")) vslice = true;
				} catch (_:Dynamic) {}
			}
			if (name.startsWith("assets/preload/") || name.startsWith("assets/shared/")) vslice = true;
			if (name.endsWith("-chart.json") || name.endsWith("-metadata.json")) vslice = true;
		}
		if (_hasVSliceAnimateAssetSignature(files)) vslice = true;
		if (psych && cne) throw new haxe.Exception("Ambiguous mod package markers: psych and cne. Choose a source format explicitly.");
		if (psych) return "psych";
		if (cne) return "cne";
		if (vslice) return "vslice";
		return null;
	}

	static function _hasVSliceAnimateAssetSignature(files:Array<ModPackageFile>):Bool {
		var animationDirectories:Map<String, Bool> = [];
		var spritemapJsonDirectories:Map<String, Bool> = [];
		var spritemapPngDirectories:Map<String, Bool> = [];
		for (file in files) {
			var name = normalizeRelativePath(file.name).toLowerCase();
			if (!name.startsWith("shared/images/") && name.indexOf("/shared/images/") < 0 && !name.startsWith("assets/shared/images/")) continue;
			var directory = Path.directory(name);
			var basename = Path.withoutDirectory(name);
			if (basename == "animation.json") animationDirectories.set(directory, true);
			else if (~/^spritemap\d+\.json$/.match(basename)) spritemapJsonDirectories.set(directory, true);
			else if (~/^spritemap\d+\.png$/.match(basename)) spritemapPngDirectories.set(directory, true);
		}
		for (directory in animationDirectories.keys())
			if (spritemapJsonDirectories.exists(directory) && spritemapPngDirectories.exists(directory)) return true;
		return false;
	}

	static function _normalizePsychCharacterJson(source:String, contents:String):String {
		var data = _parsePsychJson(contents, source);
		if (Type.typeof(data) != TObject) return contents;
		var changed = false;
		for (field in ["image", "sprite"]) {
			if (!Reflect.hasField(data, field)) continue;
			var value:Dynamic = Reflect.field(data, field);
			if (!Std.isOfType(value, String)) continue;
			var sprite:String = cast value;
			if (!sprite.toLowerCase().startsWith("characters/")) continue;
			Reflect.setField(data, field, sprite.substr("characters/".length));
			changed = true;
		}
		return changed ? haxe.Json.stringify(data, null, "\t") + "\n" : contents;
	}

	static function _normalizePsychCharacterXml(source:String, contents:String):String {
		var document:Xml;
		try document = Xml.parse(contents) catch (error:Dynamic) throw new haxe.Exception('Invalid Psych character XML "$source": ${Std.string(error)}');
		var character = document.firstElement();
		if (character == null || character.nodeName.toLowerCase() != "character" || !character.exists("sprite")) return contents;
		var sprite = character.get("sprite");
		if (!sprite.toLowerCase().startsWith("characters/")) return contents;
		character.set("sprite", sprite.substr("characters/".length));
		return document.toString();
	}

	static function _isCompatibleLayout(files:Array<ModPackageFile>, format:String):Bool {
		var hasCanonicalRoot = false;
		for (file in files) {
			var name = file.name.toLowerCase();
			if (format == "psych" && _psychPathNeedsNormalization(name)) return false;
			var first = name.split("/")[0];
			if (CANONICAL_ROOTS.contains(first)) {
				hasCanonicalRoot = true;
			} else if (METADATA_FILES.contains(first)) {
				continue;
			} else {
				return false;
			}
		}
		return hasCanonicalRoot;
	}

	static function _psychPathNeedsNormalization(name:String):Bool {
		var parts = name.split("/");
		var first = parts[0].toLowerCase();
		if (first == "characters" || first == "custom_events" || first == "stages" || first == "weeks") return true;
		if (first == "images" && parts.length >= 2) {
			var imagePath = parts.slice(1).join("/").toLowerCase();
			if (imagePath == "menubg.png" || imagePath == "menudesat.png" || imagePath == "campaign_menu_ui_assets.png"
				|| imagePath == "logobumpin.png" || imagePath == "logobumpin.xml"
				|| imagePath == "gfdancetitle.png" || imagePath == "gfdancetitle.xml"
				|| imagePath == "titleenter.png" || imagePath == "titleenter.xml"
				|| imagePath.startsWith("mainmenu/") || imagePath.startsWith("storymenu/") || imagePath.startsWith("menudifficulties/")
				|| imagePath.startsWith("menucharacters/") || imagePath.startsWith("menubackgrounds/")) return true;
		}
		if (parts.length >= 3 && first == "data") {
			if (parts[1].toLowerCase() == "custom_events") return true;
			if ((parts[1].toLowerCase() == "stages" || parts[1].toLowerCase() == "weeks") && Path.extension(name).toLowerCase() == "json") return true;
			var sub = parts[1].toLowerCase();
			if (sub != "characters" && sub != "stages" && sub != "weeks" && sub != "events") return true;
		}
		if (parts.length >= 3 && first == "songs") {
			if (parts[2].toLowerCase() != "song" && parts[2].toLowerCase() != "charts" && parts[2].toLowerCase() != "scripts") return true;
		}
		return false;
	}

	static function _choosePackageRoot(files:Array<ModPackageFile>):Array<String> {
		var candidates:Array<Array<String>> = [[]];
		for (file in files) {
			var parts = file.name.split("/");
			for (depth in 1...parts.length) {
				var candidate = parts.slice(0, depth);
				var exists = false;
				for (existing in candidates) if (existing.join("/") == candidate.join("/")) {
					exists = true;
					break;
				}
				if (!exists) candidates.push(candidate);
			}
		}
		var best:Array<String> = [];
		var bestScore = -1;
		for (candidate in candidates) {
			var roots:Array<String> = [];
			var hasMetadata = false;
			for (file in files) {
				var parts = file.name.split("/");
				if (!_startsWithParts(parts, candidate)) continue;
				var remaining = parts.slice(candidate.length);
				if (remaining.length == 0) continue;
				if (remaining[0].toLowerCase() == "assets" && remaining.length > 1 && CANONICAL_ROOTS.contains(remaining[1].toLowerCase())) remaining.shift();
				if (remaining.length == 1 && METADATA_FILES.contains(remaining[0].toLowerCase())) hasMetadata = true;
				if (CANONICAL_ROOTS.contains(remaining[0].toLowerCase()) && !roots.contains(remaining[0].toLowerCase())) roots.push(remaining[0].toLowerCase());
			}
			var score = roots.length * 10 + (hasMetadata ? 2 : 0);
			if (score > bestScore || (score == bestScore && candidate.length < best.length)) {
				bestScore = score;
				best = candidate;
			}
		}
		if (bestScore <= 0) {
			var topLevels = [];
			for (file in files) {
				var first = file.name.split("/")[0];
				if (!topLevels.contains(first)) topLevels.push(first);
			}
			if (topLevels.length == 1) return [topLevels[0]];
			return [];
		}
		return best;
	}

	static function _extractDifficultyFromChartName(fileName:String, songName:String):String {
		var baseName = Path.withoutExtension(fileName);
		var songLower = songName.toLowerCase();
		var fileLower = baseName.toLowerCase();

		if (fileLower == songLower) {
			return "normal";
		}
		if (fileLower.startsWith(songLower + "-")) {
			var diff = baseName.substr(songName.length + 1);
			return diff != "" ? diff : "normal";
		}
		return baseName;
	}

	static function _mappedDestination(name:String, packageRoot:Array<String>, format:String):String {
		var parts = name.split("/");
		if (!_startsWithParts(parts, packageRoot)) return "_dbe_preserved/" + name;
		parts = parts.slice(packageRoot.length);
		if (parts.length == 0) throw new haxe.Exception('Package root cannot be a file: $name');
		if (parts[0].toLowerCase() == "assets" && parts.length > 1 && CANONICAL_ROOTS.contains(parts[1].toLowerCase())) parts.shift();
		if (parts.length >= 3 && parts[0].toLowerCase() == "mods" && CANONICAL_ROOTS.contains(parts[2].toLowerCase())) parts = parts.slice(2);
		var relativeJoined = parts.join("/");
		var learnedRoute = dbe.compatibility.rea.REARuntimeBridge.getLearnedRoute(relativeJoined);
		if (learnedRoute != null) {
			if (learnedRoute == "preserve_custom_stage_data_json") return relativeJoined;
			if (learnedRoute == "psych_mod_settings") return "data/settings.json";
			if (learnedRoute == "psych_achievements") return "data/achievements.json";
			if (learnedRoute == "psych_loading_script") return "data/LoadingScreen.hx";
		}
		if (format == "psych") {
			var first = parts[0].toLowerCase();
			var extension = Path.extension(parts[parts.length - 1]).toLowerCase();
			if (first == "images") {
				var menuImage = _mappedPsychMenuImage(parts, extension);
				if (menuImage != null) return menuImage;
			}
			if (first == "characters") {
				if (parts.length == 3 && extension == "json" && Path.withoutExtension(parts[2]).toLowerCase() == parts[1].toLowerCase()) {
					return "data/characters/" + parts[2];
				}
				return "data/characters/" + parts.slice(1).join("/");
			}
			if (first == "custom_notetypes") {
				if (extension == "png" || extension == "xml")
					return "images/game/notes/" + parts.slice(1).join("/");
				return "data/notes/" + parts.slice(1).join("/");
			}
			if (first == "custom_events" && (extension == "lua" || extension == "hx" || extension == "txt" || extension == "json"))
				return "data/events/" + parts.slice(1).join("/");
			if (first == "stages") {
				// Only top-level stages/<stage>.json is a Psych stage metadata file;
				// nested JSONs like stages/customMenu/customMenuSongs.json are custom script data files!
				if (extension == "json" && parts.length == 2) return _replaceJsonExtension("data/stages/" + parts.slice(1).join("/"));
				if (extension == "png") return "images/stages/" + parts.slice(1).join("/");
				return "data/stages/" + parts.slice(1).join("/");
			}
			if (first == "weeks" && (extension == "json" || extension == "xml")) {
				var weekPath = "data/weeks/weeks/" + parts.slice(1).join("/");
				return extension == "json" ? _replaceJsonExtension(weekPath) : weekPath;
			}
			if (parts.length >= 2 && first == "data" && parts[1].toLowerCase() == "custom_events"
				&& (extension == "lua" || extension == "hx" || extension == "txt" || extension == "json"))
				return "data/events/" + parts.slice(2).join("/");
			if (parts.length >= 3 && first == "data" && parts[1].toLowerCase() == "stages") {
				var extWithDot = '.' + extension;
				if (extension == "json" && parts.length == 3) return _replaceJsonExtension(parts.join("/"));
				if (extension == "json" || extension == "xml" || SCRIPT_EXTENSIONS.contains(extWithDot)) return parts.join("/");
			}
			if (parts.length >= 3 && first == "data" && parts[1].toLowerCase() == "weeks" && extension == "json") {
				var weekTail = parts.slice(2);
				if (weekTail[0].toLowerCase() != "weeks") weekTail.unshift("weeks");
				return _replaceJsonExtension("data/weeks/" + weekTail.join("/"));
			}
			if (first == "songs" && parts.length >= 3) {
				var songName = parts[1];
				if (parts[2].toLowerCase() != "song" && parts[2].toLowerCase() != "charts" && parts[2].toLowerCase() != "scripts") {
					var tail = parts.slice(2).join("/");
					if (extension == "ogg" || extension == "wav" || extension == "mp3") {
						return "songs/" + songName + "/song/" + tail;
					}
					return "songs/" + songName + "/" + tail;
				}
			}
			if (first == "data" && parts.length >= 3) {
				var subFolder = parts[1].toLowerCase();
				if (subFolder != "characters" && subFolder != "stages" && subFolder != "weeks" && subFolder != "events" && subFolder != "custom_events" && subFolder != "songs") {
					var songName = parts[1];
					var fileName = parts[parts.length - 1];
					var fileBaseName = Path.withoutExtension(fileName);

					// 1. events.json
					if (fileBaseName.toLowerCase() == "events" && extension == "json") {
						return "songs/" + songName + "/events.json";
					}

					// 2. chart json files (e.g. song.json, song-hard.json, song-v1.json)
					if (extension == "json") {
						var diffName = _extractDifficultyFromChartName(fileName, songName);
						return "songs/" + songName + "/charts/" + diffName + ".json";
					}

					// 3. song scripts (lua, hx)
					if (extension == "lua" || extension == "hx" || extension == "hscript" || extension == "hxs") {
						return "songs/" + songName + "/scripts/" + fileName;
					}

					// 4. other files
					return "songs/" + songName + "/" + fileName;
				}
			}
		}
		var tailExt = '.' + Path.extension(parts[parts.length - 1]).toLowerCase();
		if (parts.length >= 2 && SCRIPT_EXTENSIONS.contains(tailExt))
			return parts.join("/");
		if (!CANONICAL_ROOTS.contains(parts[0].toLowerCase()) && !METADATA_FILES.contains(parts[0].toLowerCase()))
			return "_dbe_preserved/" + parts.join("/");
		return parts.join("/");
	}

	static function _mappedPsychMenuImage(parts:Array<String>, extension:String):Null<String> {
		if (parts.length < 2 || (extension != "png" && extension != "xml")) return null;
		var imagePath = parts.slice(1).join("/");
		var imagePathLower = imagePath.toLowerCase();
		if (parts.length == 2) {
			switch (imagePathLower) {
				case "menubg.png", "menubg.xml": return "images/menus/menuBG." + extension;
				case "menudesat.png", "menudesat.xml": return "images/menus/menuDesat." + extension;
				case "campaign_menu_ui_assets.png", "campaign_menu_ui_assets.xml": return "images/menus/storymenu/assets." + extension;
				case "logobumpin.png", "logobumpin.xml": return "images/menus/titlescreen/logo." + extension;
				case "gfdancetitle.png", "gfdancetitle.xml": return "images/menus/titlescreen/gf." + extension;
				case "titleenter.png", "titleenter.xml": return "images/menus/titlescreen/titleEnter." + extension;
			}
		}
		if (parts.length < 3) return null;
		var folder = parts[1].toLowerCase();
		var fileName = parts[parts.length - 1];
		var baseName = Path.withoutExtension(fileName);
		var directory = parts.slice(2, parts.length - 1).join("/");
		var targetBase:String = null;
		switch (folder) {
			case "mainmenu":
				targetBase = baseName.toLowerCase();
				if (targetBase.startsWith("menu_")) targetBase = targetBase.substr("menu_".length);
				targetBase = targetBase.replace("_", " ");
				return "images/menus/mainmenu/" + (directory == "" ? "" : directory + "/") + targetBase + "." + extension;
			case "storymenu":
				return "images/menus/storymenu/weeks/" + (directory == "" ? "" : directory + "/") + baseName + "." + extension;
			case "menudifficulties":
				return "images/menus/storymenu/difficulties/" + (directory == "" ? "" : directory + "/") + baseName.toLowerCase() + "." + extension;
			case "menucharacters":
				return "images/menus/storymenu/characters/" + (directory == "" ? "" : directory + "/") + fileName;
			case "menubackgrounds":
				return "images/menus/storymenu/backgrounds/" + (directory == "" ? "" : directory + "/") + fileName;
		}
		return null;
	}

	static function _convertPsychMainMenuAtlas(source:String, destination:String, contents:String):String {
		var sourcePrefix = Path.withoutExtension(Path.withoutDirectory(source)).toLowerCase();
		if (sourcePrefix.startsWith("menu_")) sourcePrefix = sourcePrefix.substr("menu_".length);
		var targetPrefix = Path.withoutExtension(Path.withoutDirectory(destination)).toLowerCase();
		var sourceAnimations = ["basic", "white", "idle", "selected"];
		var targetAnimations = ["basic", "white", "basic", "white"];
		for (i in 0...sourceAnimations.length) {
			contents = contents.replace('name="$sourcePrefix ${sourceAnimations[i]}', 'name="$targetPrefix ${targetAnimations[i]}');
		}
		return contents;
	}

	static function _convertPsychTitleEnterAtlas(contents:String):String {
		return contents.replace('name="ENTER IDLE', 'name="Press Enter to Begin');
	}

	static function _convertPsychLogoAtlas(contents:String):String {
		var subTextureRx = ~/width="5000"\s+height="5000"/i;
		if (subTextureRx.match(contents)) {
			contents = subTextureRx.replace(contents, 'width="2681" height="1858"');
		}
		return contents;
	}

	static function _replaceJsonExtension(path:String):String {
		return _replaceExtension(path, ".xml");
	}

	static function _replaceExtension(path:String, extension:String):String {
		var extensionStart = path.lastIndexOf(".");
		return (extensionStart < 0 ? path : path.substr(0, extensionStart)) + extension;
	}

	static function _psychGeneratedFiles(files:Array<ModPackageFile>, packageRoot:Array<String>, format:String):Array<GeneratedModFile> {
		var generated:Array<GeneratedModFile> = [];
		if (format != "psych") return generated;
		var existingTargets:Map<String, Bool> = [];
		for (file in files) {
			var name = normalizeRelativePath(file.name);
			if (!_isIgnored(name)) existingTargets.set(_mappedDestination(name, packageRoot, format).toLowerCase(), true);
		}

		var gfXmlTarget = "images/menus/titlescreen/gf.xml";
		if (existingTargets.exists("images/menus/titlescreen/gf.png") && !existingTargets.exists(gfXmlTarget)) {
			var dummyXml = '<?xml version="1.0" encoding="utf-8"?>\n<TextureAtlas imagePath="gf.png">\n\t<SubTexture name="gfDance0000" x="0" y="0" width="1" height="1"/>\n</TextureAtlas>\n';
			generated.push({source: "(generated for title GF transparency)", target: gfXmlTarget, contents: Bytes.ofString(dummyXml), reason: "transparent title GF atlas"});
			existingTargets.set(gfXmlTarget, true);
		}

		// 1. Generate event metadata for Psych custom event scripts and editor descriptions.
		for (file in files) {
			var name = normalizeRelativePath(file.name);
			var extension = Path.extension(name).toLowerCase();
			if (_isIgnored(name) || (extension != "lua" && extension != "hx" && extension != "txt")) continue;
			var parts = name.split("/");
			if (!_startsWithParts(parts, packageRoot)) continue;
			var relative = parts.slice(packageRoot.length);
			var isCustomEvent = relative.length >= 2 && relative[0].toLowerCase() == "custom_events";
			if (relative.length >= 3 && relative[0].toLowerCase() == "data" && relative[1].toLowerCase() == "custom_events")
				isCustomEvent = true;
			if (!isCustomEvent) continue;
			var target = _replaceExtension(_mappedDestination(name, packageRoot, format), ".json");
			var targetKey = target.toLowerCase();
			if (!existingTargets.exists(targetKey)) {
				var params = '{"params":[{"name":"Value 1","type":"String","defaultValue":""},{"name":"Value 2","type":"String","defaultValue":""}]}\n';
				generated.push({source: '(generated from $name)', target: target, contents: Bytes.ofString(params), reason: "generated DBE event registry metadata"});
				existingTargets.set(targetKey, true);
			}
		}

		// 2. Generate meta.json for each Psych song in data/<songName>/<songName>.json
		var processedSongs:Map<String, Bool> = [];
		for (file in files) {
			var name = normalizeRelativePath(file.name);
			if (_isIgnored(name)) continue;
			var parts = name.split("/");
			if (!_startsWithParts(parts, packageRoot)) continue;
			var relative = parts.slice(packageRoot.length);
			if (relative.length < 3) continue;
			var first = relative[0].toLowerCase();
			if (first != "data") continue;
			var songName = relative[1];
			var songNameLower = songName.toLowerCase();
			var ext = Path.extension(relative[relative.length - 1]).toLowerCase();
			if (ext != "json") continue;
			// Only process chart json files (not events.json, not sub-folders)
			if (relative.length != 3) continue;
			var fileName = relative[2];
			var fileBase = Path.withoutExtension(fileName).toLowerCase();
			if (fileBase == "events") continue;

			if (processedSongs.exists(songNameLower)) continue;

			var metaTarget = "songs/" + songName + "/meta.json";
			if (existingTargets.exists(metaTarget.toLowerCase())) continue;

			// Read the chart json and extract song metadata
			var contents = file.read();
			if (contents == null || contents.length != file.size) continue;
			try {
				var chartData:Dynamic = haxe.Json.parse(contents.toString());
				var song:Dynamic = chartData;
				if (Reflect.hasField(chartData, "song")) {
					var sf:Dynamic = Reflect.field(chartData, "song");
					if (sf != null && Type.typeof(sf) == TObject)
						song = sf;
				}

				var bpm:Float = song.bpm != null ? song.bpm : 100;
				var scrollSpeed:Float = song.speed != null ? song.speed : 1.0;
				var displayName:String = (Reflect.hasField(chartData, "song") && Std.isOfType(chartData.song, String)) ? chartData.song : (song.song != null ? song.song : songName);
				var needsVoices:Bool = song.needsVoices != null ? song.needsVoices : true;
				var player1:String = song.player1 != null ? song.player1 : "bf";
				var player2:String = song.player2 != null ? song.player2 : "dad";
				var stage:String = song.stage != null ? song.stage : "stage";
				var icon:String = player2;

				// Collect all difficulties for this song from files
				var diffs:Array<String> = [];
				for (f2 in files) {
					var n2 = normalizeRelativePath(f2.name);
					if (_isIgnored(n2)) continue;
					var p2 = n2.split("/");
					if (!_startsWithParts(p2, packageRoot)) continue;
					var r2 = p2.slice(packageRoot.length);
					if (r2.length != 3) continue;
					if (r2[0].toLowerCase() != "data") continue;
					if (r2[1].toLowerCase() != songNameLower) continue;
					var fb2 = Path.withoutExtension(r2[2]).toLowerCase();
					if (fb2 == "events") continue;
					if (Path.extension(r2[2]).toLowerCase() != "json") continue;
					var diffName = _extractDifficultyFromChartName(r2[2], songName);
					if (!diffs.contains(diffName)) diffs.push(diffName);
				}

				var meta:Dynamic = {
					displayName: displayName,
					bpm: bpm,
					scrollSpeed: scrollSpeed,
					needsVoices: needsVoices,
					difficulties: diffs,
					icon: icon,
					player1: player1,
					player2: player2,
					stage: stage
				};

				var metaJson = haxe.Json.stringify(meta, null, "\t") + "\n";
				generated.push({
					source: '(generated meta.json from $name)',
					target: metaTarget,
					contents: Bytes.ofString(metaJson),
					reason: "generated CNE meta.json from Psych chart data"
				});
				existingTargets.set(metaTarget.toLowerCase(), true);
				processedSongs.set(songNameLower, true);
			} catch (_:Dynamic) {}
		}

		// 3. Preserve original Psych metadata files for reference
		for (file in files) {
			var name = normalizeRelativePath(file.name);
			if (_isIgnored(name) || !_psychMetadataNeedsConversion(name, packageRoot)) continue;
			var relative = name.split("/").slice(packageRoot.length).join("/");
			var target = "_dbe_preserved/psych_source/" + relative;
			if (existingTargets.exists(target.toLowerCase()))
				throw new haxe.Exception('Original Psych metadata preservation collides with a source file: $name -> $target');
			var contents = file.read();
			if (contents == null || contents.length != file.size) throw new haxe.Exception('Could not preserve the original Psych metadata: $name');
			generated.push({source: name, target: target, contents: contents, reason: "preserved original Psych metadata"});
		}
		if (!existingTargets.exists("data/config/modpack.ini")) {
			var ini = '[Common]\nNAME="Converted Psych Mod"\nAPI_VERSION=1\n';
			generated.push({source: "pack.json", target: "data/config/modpack.ini", contents: Bytes.ofString(ini), reason: "generated CNE modpack config"});
		}
		// 4. Generate data/config/dbe-compat.json using REA-learned Psych Lua profile (1.0.4 vs 0.6.3)
		if (!existingTargets.exists("data/config/dbe-compat.json")) {
			dbe.compatibility.rea.REARuntimeBridge.ensureInitialized();
			var learnedProf = "1.0.4";
			if (dbe.compatibility.rea.REARuntimeBridge.activeProfile != null) {
				var p:Dynamic = Reflect.field(dbe.compatibility.rea.REARuntimeBridge.activeProfile, "psychLuaProfile");
				if (p != null && Std.isOfType(p, String)) learnedProf = cast p;
			}
			var compatJson = '{\n\t"psychLuaProfile": "$learnedProf"\n}\n';
			generated.push({
				source: "(REA learned compatibility profile)",
				target: "data/config/dbe-compat.json",
				contents: Bytes.ofString(compatJson),
				reason: "generated DBE Psych compatibility profile from REA"
			});
			existingTargets.set("data/config/dbe-compat.json", true);
		}
		generated.sort(function(a, b) return Reflect.compare(a.target, b.target));
		return generated;
	}

	static function _psychMetadataNeedsConversion(name:String, packageRoot:Array<String>):Bool {
		var extension = Path.extension(name).toLowerCase();
		if (extension != "json" && extension != "xml") return false;
		var parts = name.split("/");
		if (!_startsWithParts(parts, packageRoot)) return false;
		var relative = parts.slice(packageRoot.length);
		if (relative.length < 2) return false;
		if (extension == "json" && relative[0].toLowerCase() == "characters") return true;
		if (relative.length >= 3 && relative[0].toLowerCase() == "data" && relative[1].toLowerCase() == "characters") return true;
		if (extension != "json") return false;
		if (relative[0].toLowerCase() == "stages" && relative.length == 2) return true;
		if (relative[0].toLowerCase() == "weeks") return true;
		return relative.length == 3 && relative[0].toLowerCase() == "data"
			&& (relative[1].toLowerCase() == "stages" || relative[1].toLowerCase() == "weeks");
	}

	public static function convertPsychStageJson(source:String, contents:String, ?luaContents:String):String {
		var unsupported:Array<Dynamic> = [];
		var warnings:Array<String> = [];
		return _convertPsychStageJson(source, contents, unsupported, warnings, luaContents);
	}

	static function _convertPsychStageJson(source:String, contents:String, unsupported:Array<Dynamic>, warnings:Array<String>, ?luaContents:String):String {
		var data = _parsePsychJson(contents, source);
		if (Type.typeof(data) != TObject) throw new haxe.Exception('Psych stage metadata must contain a JSON object: $source');
		var root = Xml.createElement("stage");
		var stageName = Path.withoutDirectory(Path.withoutExtension(source));
		root.set("name", stageName);

		// Zoom
		_setJsonAttribute(data, "defaultZoom", "zoom", root);

		// Directory -> folder
		var directory:Dynamic = Reflect.field(data, "directory");
		if (directory != null && StringTools.trim(Std.string(directory)) != "") {
			root.set("folder", StringTools.trim(Std.string(directory)));
		}

		// Character nodes mapping (opponent -> dad for CNE canonical naming)
		var characterNodes:Map<String, Xml> = [];
		for (pos in [
			{psych: "boyfriend", cne: "boyfriend"},
			{psych: "girlfriend", cne: "girlfriend"},
			{psych: "opponent", cne: "dad"}
		]) {
			_setPsychVector(data, pos.psych, pos.cne, "x", "y", characterNodes, source);
		}

		// Camera offsets
		var cameraFields = [
			{source: "camera_boyfriend", target: "boyfriend"},
			{source: "camera_girlfriend", target: "girlfriend"},
			{source: "camera_opponent", target: "dad"}
		];
		for (camera in cameraFields) _setPsychVector(data, camera.source, camera.target, "camxoffset", "camyoffset", characterNodes, source);

		// Girlfriend visibility: hide_girlfriend
		var hideGF:Dynamic = Reflect.field(data, "hide_girlfriend");
		if (hideGF == true) {
			var gfNode = characterNodes.get("girlfriend");
			if (gfNode == null) {
				gfNode = Xml.createElement("girlfriend");
				characterNodes.set("girlfriend", gfNode);
			}
			gfNode.set("alpha", "0");
		}

		// Camera speed if present
		var camSpeed:Dynamic = Reflect.field(data, "camera_speed");
		if (camSpeed != null) root.set("cameraSpeed", Std.string(camSpeed));

		// Parse Lua companion file for background/foreground sprites only if Lua is not supported at runtime
		var luaSprites:Array<Dynamic> = [];
		#if !LUA_ALLOWED
		if (luaContents != null && luaContents.length > 0)
			luaSprites = _parsePsychStageLua(luaContents);
		#end

		// Background sprites (before character nodes)
		for (spr in luaSprites) {
			var tagLower:String = spr.tag != null ? Std.string(spr.tag).toLowerCase() : "";
			var imgLower:String = spr.image != null ? Std.string(spr.image).toLowerCase() : "";
			var isForeName = tagLower.indexOf("fore") >= 0 || tagLower.indexOf("fg") >= 0 || tagLower.indexOf("over") >= 0 || tagLower.indexOf("front") >= 0
				|| imgLower.indexOf("fore") >= 0 || imgLower.indexOf("fg") >= 0 || imgLower.indexOf("over") >= 0 || imgLower.indexOf("front") >= 0;
			var isBgName = !isForeName && (tagLower.indexOf("alley") >= 0 || tagLower.indexOf("bg") >= 0 || tagLower.indexOf("back") >= 0 || tagLower.indexOf("stage") >= 0 || tagLower.indexOf("wall") >= 0 || tagLower.indexOf("sky") >= 0 || imgLower.indexOf("alley") >= 0 || imgLower.indexOf("back") >= 0 || imgLower.indexOf("bg") >= 0);
			if ((spr.isForeground:Bool) == true && !isBgName) continue;
			root.addChild(_buildLuaSpriteNode(spr));
		}

		// Convert static sprites / objects if defined in Psych 0.7+ JSON
		var objects:Dynamic = Reflect.field(data, "objects");
		if (objects == null) objects = Reflect.field(data, "sprites");
		if (objects != null && Std.isOfType(objects, Array)) {
			for (obj in (cast objects:Array<Dynamic>)) {
				if (Type.typeof(obj) != TObject) continue;
				var sprName:Dynamic = Reflect.field(obj, "name");
				if (sprName == null) sprName = Reflect.field(obj, "tag");
				var sprImg:Dynamic = Reflect.field(obj, "image");
				if (sprImg == null) sprImg = Reflect.field(obj, "sprite");
				if (sprName == null && sprImg == null) continue;
				var sprNode = Xml.createElement("sprite");
				sprNode.set("name", sprName != null ? Std.string(sprName) : Std.string(sprImg));
				if (sprImg != null) sprNode.set("sprite", Std.string(sprImg));
				var pos:Dynamic = Reflect.field(obj, "position");
				if (pos != null && Std.isOfType(pos, Array) && (cast pos:Array<Dynamic>).length >= 2) {
					sprNode.set("x", Std.string((cast pos:Array<Dynamic>)[0]));
					sprNode.set("y", Std.string((cast pos:Array<Dynamic>)[1]));
				} else {
					if (Reflect.field(obj, "x") != null) sprNode.set("x", Std.string(Reflect.field(obj, "x")));
					if (Reflect.field(obj, "y") != null) sprNode.set("y", Std.string(Reflect.field(obj, "y")));
				}
				var scroll:Dynamic = Reflect.field(obj, "scroll");
				if (scroll != null && Std.isOfType(scroll, Array) && (cast scroll:Array<Dynamic>).length >= 1) {
					sprNode.set("scroll", Std.string((cast scroll:Array<Dynamic>)[0]));
				} else if (Reflect.field(obj, "scrollFactor") != null) {
					sprNode.set("scroll", Std.string(Reflect.field(obj, "scrollFactor")));
				}
				var scale:Dynamic = Reflect.field(obj, "scale");
				if (scale != null && Std.isOfType(scale, Array) && (cast scale:Array<Dynamic>).length >= 1) {
					sprNode.set("scale", Std.string((cast scale:Array<Dynamic>)[0]));
				}
				if (Reflect.field(obj, "alpha") != null) sprNode.set("alpha", Std.string(Reflect.field(obj, "alpha")));
				root.addChild(sprNode);
			}
		}

		// Add character nodes in standard order (girlfriend first, then dad, then boyfriend)
		for (character in ["girlfriend", "dad", "boyfriend"])
			if (characterNodes.exists(character)) root.addChild(characterNodes.get(character));

		// Foreground sprites (after character nodes)
		for (spr in luaSprites) {
			var tagLower:String = spr.tag != null ? Std.string(spr.tag).toLowerCase() : "";
			var imgLower:String = spr.image != null ? Std.string(spr.image).toLowerCase() : "";
			var isForeName = tagLower.indexOf("fore") >= 0 || tagLower.indexOf("fg") >= 0 || tagLower.indexOf("over") >= 0 || tagLower.indexOf("front") >= 0
				|| imgLower.indexOf("fore") >= 0 || imgLower.indexOf("fg") >= 0 || imgLower.indexOf("over") >= 0 || imgLower.indexOf("front") >= 0;
			var isBgName = !isForeName && (tagLower.indexOf("alley") >= 0 || tagLower.indexOf("bg") >= 0 || tagLower.indexOf("back") >= 0 || tagLower.indexOf("stage") >= 0 || tagLower.indexOf("wall") >= 0 || tagLower.indexOf("sky") >= 0 || imgLower.indexOf("alley") >= 0 || imgLower.indexOf("back") >= 0 || imgLower.indexOf("bg") >= 0);
			if ((spr.isForeground:Bool) == false || isBgName) continue;
			root.addChild(_buildLuaSpriteNode(spr));
		}

		_recordUnsupportedPsychFields(data, [
			"defaultZoom", "boyfriend", "girlfriend", "opponent",
			"camera_boyfriend", "camera_girlfriend", "camera_opponent",
			"directory", "hide_girlfriend", "isPixelStage",
			"objects", "sprites"
		], source, "Psych stage fields without a DBE Stage XML equivalent were omitted from normalized XML; the original JSON was retained under _dbe_preserved.", unsupported, warnings);

		var buf = new StringBuf();
		buf.add("<!DOCTYPE codename-engine-stage>\n");
		buf.add(root.toString());
		buf.add("\n");
		return buf.toString();
	}

	/** Build a CNE <sprite> or <solid> XML node from a parsed Lua sprite object. */
	static function _buildLuaSpriteNode(spr:Dynamic):Xml {
		var image:String = spr.image != null ? Std.string(spr.image) : "";
		var tag:String = spr.tag != null ? Std.string(spr.tag) : image;
		var makeGraphicW:Null<Float> = spr.makeGraphicW;
		var makeGraphicH:Null<Float> = spr.makeGraphicH;
		var makeGraphicColor:String = spr.makeGraphicColor != null ? Std.string(spr.makeGraphicColor) : "#000000";

		var node:Xml;
		if (makeGraphicW != null && makeGraphicH != null) {
			// makeGraphic case -> <solid>
			node = Xml.createElement("solid");
			node.set("name", tag);
			node.set("width", Std.string(Std.int(makeGraphicW)));
			node.set("height", Std.string(Std.int(makeGraphicH)));
			node.set("color", makeGraphicColor);
		} else {
			node = Xml.createElement("sprite");
			node.set("name", tag);
			if (image != "") node.set("sprite", image);
		}

		var x:Float = spr.x != null ? spr.x : 0;
		var y:Float = spr.y != null ? spr.y : 0;
		if (x != 0) node.set("x", Std.string(x));
		if (y != 0) node.set("y", Std.string(y));

		var scrollX:Null<Float> = spr.scrollX;
		var scrollY:Null<Float> = spr.scrollY;
		if (scrollX != null && scrollY != null) {
			if (scrollX == scrollY) node.set("scroll", Std.string(scrollX));
			else { node.set("scrollx", Std.string(scrollX)); node.set("scrolly", Std.string(scrollY)); }
		}

		var scaleX:Null<Float> = spr.scaleX;
		var scaleY:Null<Float> = spr.scaleY;
		if (scaleX != null && scaleY != null) {
			if (scaleX == scaleY) node.set("scale", Std.string(scaleX));
			else { node.set("scalex", Std.string(scaleX)); node.set("scaley", Std.string(scaleY)); }
		}

		var alpha:Null<Float> = spr.alpha;
		if (alpha != null && alpha != 1.0) node.set("alpha", Std.string(alpha));

		var angle:Null<Float> = spr.angle;
		if (angle != null && angle != 0.0) node.set("angle", Std.string(angle));

		// Animations
		var anims:Array<Dynamic> = spr.anims != null ? cast spr.anims : [];
		for (anim in anims) {
			var animNode = Xml.createElement("anim");
			animNode.set("name", Std.string(anim.name));
			animNode.set("anim", Std.string(anim.prefix));
			animNode.set("fps", Std.string(anim.fps != null ? anim.fps : 24));
			if (anim.loop == true) animNode.set("loop", "true");
			node.addChild(animNode);
		}

		return node;
	}

	/** Parse Psych Engine stage Lua file and extract sprite declarations. */
	static function _parsePsychStageLua(lua:String):Array<Dynamic> {
		var sprites:Map<String, Dynamic> = [];
		var spriteList:Array<Dynamic> = [];

		inline function getOrCreate(tag:String):Dynamic {
			var s = sprites.get(tag);
			if (s == null) {
				s = {
					tag: tag,
					image: "",
					x: 0.0,
					y: 0.0,
					scrollX: null,
					scrollY: null,
					scaleX: null,
					scaleY: null,
					alpha: null,
					angle: null,
					isForeground: false,
					makeGraphicW: null,
					makeGraphicH: null,
					makeGraphicColor: null,
					anims: []
				};
				sprites.set(tag, s);
				spriteList.push(s);
			}
			return s;
		}

		// Strip Lua line comments
		var lines = lua.split("\n");
		var cleanLines:Array<String> = [];
		for (line in lines) {
			var commentIdx = line.indexOf("--");
			var clean = commentIdx >= 0 ? line.substr(0, commentIdx) : line;
			clean = StringTools.trim(clean);
			if (clean.length > 0) cleanLines.push(clean);
		}
		var cleanCode = cleanLines.join("\n");

		var pos:Int;

		// 1. makeLuaSprite('tag', 'image', x, y)
		var makeSpriteRx = ~/makeLuaSprite\s*\(\s*['"]([^'"]+)['"]\s*,\s*['"]([^'"]*)['"]\s*(?:,\s*([-\d.]+)\s*)?(?:,\s*([-\d.]+)\s*)?\)/gi;
		pos = 0;
		while (makeSpriteRx.matchSub(cleanCode, pos)) {
			var spr = getOrCreate(makeSpriteRx.matched(1));
			spr.image = makeSpriteRx.matched(2);
			var xStr = makeSpriteRx.matched(3);
			var yStr = makeSpriteRx.matched(4);
			if (xStr != null) spr.x = Std.parseFloat(xStr);
			if (yStr != null) spr.y = Std.parseFloat(yStr);
			pos = makeSpriteRx.matchedPos().pos + makeSpriteRx.matchedPos().len;
		}

		// 2. makeAnimatedLuaSprite('tag', 'image', x, y)
		var makeAnimRx = ~/makeAnimatedLuaSprite\s*\(\s*['"]([^'"]+)['"]\s*,\s*['"]([^'"]*)['"]\s*(?:,\s*([-\d.]+)\s*)?(?:,\s*([-\d.]+)\s*)?\)/gi;
		pos = 0;
		while (makeAnimRx.matchSub(cleanCode, pos)) {
			var spr = getOrCreate(makeAnimRx.matched(1));
			spr.image = makeAnimRx.matched(2);
			var xStr = makeAnimRx.matched(3);
			var yStr = makeAnimRx.matched(4);
			if (xStr != null) spr.x = Std.parseFloat(xStr);
			if (yStr != null) spr.y = Std.parseFloat(yStr);
			pos = makeAnimRx.matchedPos().pos + makeAnimRx.matchedPos().len;
		}

		// 3. makeGraphic('tag', w, h, 'color')
		var makeGraphicRx = ~/makeGraphic\s*\(\s*['"]([^'"]+)['"]\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*['"]?([^'",)]+)['"]?\s*)?\)/gi;
		pos = 0;
		while (makeGraphicRx.matchSub(cleanCode, pos)) {
			var spr = getOrCreate(makeGraphicRx.matched(1));
			spr.makeGraphicW = Std.parseFloat(makeGraphicRx.matched(2));
			spr.makeGraphicH = Std.parseFloat(makeGraphicRx.matched(3));
			var colorStr = makeGraphicRx.matched(4);
			if (colorStr != null) {
				colorStr = StringTools.trim(colorStr);
				if (!colorStr.startsWith("#")) colorStr = "#" + colorStr;
				spr.makeGraphicColor = colorStr;
			} else {
				spr.makeGraphicColor = "#000000";
			}
			pos = makeGraphicRx.matchedPos().pos + makeGraphicRx.matchedPos().len;
		}

		// 4. setScrollFactor('tag', sx, sy)
		var scrollRx = ~/setScrollFactor\s*\(\s*['"]([^'"]+)['"]\s*,\s*([-\d.]+)\s*(?:,\s*([-\d.]+)\s*)?\)/gi;
		pos = 0;
		while (scrollRx.matchSub(cleanCode, pos)) {
			var spr = getOrCreate(scrollRx.matched(1));
			var sx = Std.parseFloat(scrollRx.matched(2));
			var syStr = scrollRx.matched(3);
			spr.scrollX = sx;
			spr.scrollY = syStr != null ? Std.parseFloat(syStr) : sx;
			pos = scrollRx.matchedPos().pos + scrollRx.matchedPos().len;
		}

		// 5. scaleObject('tag', sx, sy)
		var scaleRx = ~/scaleObject\s*\(\s*['"]([^'"]+)['"]\s*,\s*([-\d.]+)\s*(?:,\s*([-\d.]+)\s*)?(?:,\s*(true|false)\s*)?\)/gi;
		pos = 0;
		while (scaleRx.matchSub(cleanCode, pos)) {
			var spr = getOrCreate(scaleRx.matched(1));
			var sx = Std.parseFloat(scaleRx.matched(2));
			var syStr = scaleRx.matched(3);
			spr.scaleX = sx;
			spr.scaleY = syStr != null ? Std.parseFloat(syStr) : sx;
			pos = scaleRx.matchedPos().pos + scaleRx.matchedPos().len;
		}

		// 5b. setObjectOrder('tag', order)
		var orderRx = ~/setObjectOrder\s*\(\s*['"]([^'"]+)['"]\s*,\s*([-\d]+)\s*\)/gi;
		pos = 0;
		while (orderRx.matchSub(cleanCode, pos)) {
			var spr = getOrCreate(orderRx.matched(1));
			var orderVal = Std.parseInt(orderRx.matched(2));
			spr.order = orderVal;
			if (orderVal != null) {
				if (orderVal == 0 || orderVal < 4) {
					spr.isForeground = false;
				} else {
					spr.isForeground = true;
				}
			}
			pos = orderRx.matchedPos().pos + orderRx.matchedPos().len;
		}

		// 6. addLuaSprite('tag', isForeground)
		var addRx = ~/addLuaSprite\s*\(\s*['"]([^'"]+)['"]\s*(?:,\s*(true|false)\s*)?\)/gi;
		pos = 0;
		while (addRx.matchSub(cleanCode, pos)) {
			var spr = getOrCreate(addRx.matched(1));
			var fgStr = addRx.matched(2);
			var isExplicitFg = fgStr != null && fgStr.toLowerCase() == "true";
			var tagLower:String = spr.tag != null ? Std.string(spr.tag).toLowerCase() : "";
			var imgLower:String = spr.image != null ? Std.string(spr.image).toLowerCase() : "";
			var isForeName = tagLower.indexOf("fore") >= 0 || tagLower.indexOf("fg") >= 0 || tagLower.indexOf("over") >= 0 || tagLower.indexOf("front") >= 0
				|| imgLower.indexOf("fore") >= 0 || imgLower.indexOf("fg") >= 0 || imgLower.indexOf("over") >= 0 || imgLower.indexOf("front") >= 0;
			var isBgName = !isForeName && (tagLower.indexOf("alley") >= 0 || tagLower.indexOf("bg") >= 0 || tagLower.indexOf("back") >= 0 || tagLower.indexOf("stage") >= 0 || tagLower.indexOf("wall") >= 0 || tagLower.indexOf("sky") >= 0 || imgLower.indexOf("alley") >= 0 || imgLower.indexOf("back") >= 0 || imgLower.indexOf("bg") >= 0);
			if (isBgName || (spr.order != null && spr.order < 4 && !isForeName)) {
				spr.isForeground = false;
			} else if (isForeName || (spr.order != null && spr.order >= 4)) {
				spr.isForeground = true;
			} else {
				spr.isForeground = isExplicitFg;
			}
			pos = addRx.matchedPos().pos + addRx.matchedPos().len;
		}

		// 7. setProperty('tag.alpha', value) / setProperty('tag.angle', value)
		var propRx = ~/setProperty\s*\(\s*['"]([^'"]+)\.([a-zA-Z]+)['"]\s*,\s*([-\d.]+)\s*\)/gi;
		pos = 0;
		while (propRx.matchSub(cleanCode, pos)) {
			var spr = getOrCreate(propRx.matched(1));
			var prop = propRx.matched(2).toLowerCase();
			var val = Std.parseFloat(propRx.matched(3));
			if (prop == "alpha") spr.alpha = val;
			if (prop == "angle") spr.angle = val;
			pos = propRx.matchedPos().pos + propRx.matchedPos().len;
		}

		// 8. addAnimationByPrefix('tag', 'name', 'prefix', fps, loop)
		var animRx = ~/addAnimationByPrefix\s*\(\s*['"]([^'"]+)['"]\s*,\s*['"]([^'"]+)['"]\s*,\s*['"]([^'"]+)['"]\s*(?:,\s*(\d+)\s*)?(?:,\s*(true|false)\s*)?\)/gi;
		pos = 0;
		while (animRx.matchSub(cleanCode, pos)) {
			var spr = getOrCreate(animRx.matched(1));
			var fpsStr = animRx.matched(4);
			var loopStr = animRx.matched(5);
			(spr.anims:Array<Dynamic>).push({
				name: animRx.matched(2),
				prefix: animRx.matched(3),
				fps: fpsStr != null ? Std.parseInt(fpsStr) : 24,
				loop: loopStr == null || loopStr.toLowerCase() == "true"
			});
			pos = animRx.matchedPos().pos + animRx.matchedPos().len;
		}

		// 9. setObjectOrder('tag', getObjectOrder('boyfriendGroup') - 1) -> mark as background
		var orderRx = ~/setObjectOrder\s*\(\s*['"]([^'"]+)['"]\s*,\s*([^)\n;]+)\)/gi;
		pos = 0;
		while (orderRx.matchSub(cleanCode, pos)) {
			var spr = getOrCreate(orderRx.matched(1));
			var expr = orderRx.matched(2);
			if (expr.indexOf("boyfriendGroup") >= 0 && expr.indexOf("-") >= 0)
				spr.isForeground = false;
			pos = orderRx.matchedPos().pos + orderRx.matchedPos().len;
		}
		// 10. setObjectCamera('tag', 'camera') -> camera overlays shouldn't be added to stage world geometry
		var camRx = ~/setObjectCamera\s*\(\s*['"]([^'"]+)['"]\s*,\s*['"]([^'"]+)['"]\s*\)/gi;
		pos = 0;
		while (camRx.matchSub(cleanCode, pos)) {
			var spr = getOrCreate(camRx.matched(1));
			spr.isCameraOverlay = true;
			pos = camRx.matchedPos().pos + camRx.matchedPos().len;
		}

		// Only return sprites that have an image path or makeGraphic data and are not camera overlays
		return [for (s in spriteList)
			if (((s.image != null && StringTools.trim(Std.string(s.image)) != "") || s.makeGraphicW != null) && s.isCameraOverlay != true)
				s];
	}


	static function _convertPsychWeekJson(source:String, contents:String, unsupported:Array<Dynamic>, warnings:Array<String>):String {
		var data = _parsePsychJson(contents, source);
		if (Type.typeof(data) != TObject) throw new haxe.Exception('Psych week metadata must contain a JSON object: $source');
		var root = Xml.createElement("week");
		var weekName = _firstString(data, ["storyName", "weekName"]);
		if (weekName == null) weekName = Path.withoutDirectory(Path.withoutExtension(source));
		root.set("name", weekName);
		var weekCharacters = Reflect.field(data, "weekCharacters");
		if (weekCharacters != null) {
			if (!Std.isOfType(weekCharacters, Array)) throw new haxe.Exception('Psych weekCharacters must be an array: $source');
			root.set("chars", (cast weekCharacters:Array<Dynamic>).map(function(value) return Std.string(value)).join(","));
		}
		var weekBackground = Reflect.field(data, "weekBackground");
		root.set("sprite", Path.withoutDirectory(Path.withoutExtension(source)));
		if (weekBackground != null) root.set("background", Std.string(weekBackground));
		var bgColor = Reflect.field(data, "bgColor");
		if (bgColor != null) root.set("bgColor", _psychColor(bgColor));
		var songs = Reflect.field(data, "songs");
		if (!Std.isOfType(songs, Array) || (cast songs:Array<Dynamic>).length == 0)
			throw new haxe.Exception('Psych week metadata must contain at least one song: $source');
		var songExtras = false;
		for (song in (cast songs:Array<Dynamic>)) {
			var songName:Dynamic = song;
			if (Std.isOfType(song, Array)) {
				var values:Array<Dynamic> = cast song;
				if (values.length == 0) throw new haxe.Exception('Psych week contains an empty song entry: $source');
				songName = values[0];
				if ((values.length > 1 && values[1] != null) || (values.length > 2 && values[2] != null)) songExtras = true;
			} else if (Type.typeof(song) == TObject) {
				songName = Reflect.field(song, "name");
			}
			if (songName == null || StringTools.trim(Std.string(songName)) == "")
				throw new haxe.Exception('Psych week contains a song without a name: $source');
			var songNode = Xml.createElement("song");
			songNode.addChild(Xml.createPCData(Std.string(songName)));
			root.addChild(songNode);
		}
		if (songExtras) {
			unsupported.push({source: source, fields: ["songs[*][1]", "songs[*][2]"], reason: "Psych song character overrides and colors have no DBE Week song equivalent; the original JSON was retained under _dbe_preserved."});
			warnings.push('Psych week song character/color values were omitted from the DBE week XML: $source');
		}
		var difficulties = Reflect.field(data, "difficulties");
		if (difficulties != null) {
			var names:Array<String> = [];
			if (Std.isOfType(difficulties, String)) {
				for (name in (cast difficulties:String).split(",")) {
					var trimmed = StringTools.trim(name);
					if (trimmed != "") names.push(trimmed);
				}
			} else if (Std.isOfType(difficulties, Array)) {
				for (name in (cast difficulties:Array<Dynamic>)) if (name != null && StringTools.trim(Std.string(name)) != "") names.push(Std.string(name));
			} else throw new haxe.Exception('Psych week difficulties must be a string or array: $source');
			for (name in names) {
				var difficulty = Xml.createElement("difficulty");
				difficulty.set("name", name);
				root.addChild(difficulty);
			}
		}
		// Psych: hideStoryMode removes the week from Story Mode (Freeplay-only weeks), hideFreeplay the opposite.
		if (Reflect.field(data, "hideStoryMode") == true) root.set("hideStory", "true");
		if (Reflect.field(data, "hideFreeplay") == true) root.set("hideFreeplay", "true");
		_recordUnsupportedPsychFields(data, ["storyName", "weekName", "songs", "difficulties", "weekCharacters", "weekBackground", "bgColor", "hideStoryMode", "hideFreeplay"], source,
			"Psych week fields without a DBE Week XML equivalent were omitted from normalized XML; the original JSON was retained under _dbe_preserved.", unsupported, warnings);
		return root.toString();
	}

	static function _parsePsychJson(contents:String, source:String):Dynamic {
		try return haxe.Json.parse(_stripTrailingCommas(contents))
		catch (error:Dynamic) throw new haxe.Exception('Invalid Psych JSON metadata "$source": ${Std.string(error)}');
	}

	static function _stripTrailingCommas(contents:String):String {
		var output = new StringBuf();
		var inString = false;
		var escaped = false;
		var i = 0;
		while (i < contents.length) {
			var character = contents.charAt(i);
			if (inString) {
				output.add(character);
				if (escaped) escaped = false;
				else if (character == "\\") escaped = true;
				else if (character == '"') inString = false;
			} else if (character == '"') {
				inString = true;
				output.add(character);
			} else if (character == ",") {
				var next = i + 1;
				while (next < contents.length && StringTools.isSpace(contents, next)) next++;
				if (next >= contents.length || (contents.charAt(next) != "}" && contents.charAt(next) != "]")) output.add(character);
			} else output.add(character);
			i++;
		}
		return output.toString();
	}

	static function _setJsonAttribute(data:Dynamic, sourceName:String, targetName:String, xml:Xml):Void {
		var value = Reflect.field(data, sourceName);
		if (value != null) xml.set(targetName, Std.string(value));
	}

	static function _setPsychVector(data:Dynamic, field:String, elementName:String, xName:String, yName:String, nodes:Map<String, Xml>, source:String):Void {
		var value = Reflect.field(data, field);
		if (value == null) return;
		if (!Std.isOfType(value, Array) || (cast value:Array<Dynamic>).length < 2)
			throw new haxe.Exception('Psych stage vector "$field" must contain an X and Y value: $source');
		var values:Array<Dynamic> = cast value;
		if (values[0] == null || values[1] == null) throw new haxe.Exception('Psych stage vector "$field" contains a missing coordinate: $source');
		var node = nodes.get(elementName);
		if (node == null) {
			node = Xml.createElement(elementName);
			nodes.set(elementName, node);
		}
		node.set(xName, Std.string(values[0]));
		node.set(yName, Std.string(values[1]));
	}

	static function _recordUnsupportedPsychFields(data:Dynamic, supported:Array<String>, source:String, reason:String, unsupported:Array<Dynamic>, warnings:Array<String>):Void {
		var fields = [for (field in Reflect.fields(data)) if (!supported.contains(field)) field];
		if (fields.length == 0) return;
		fields.sort(Reflect.compare);
		unsupported.push({source: source, fields: fields, reason: reason});
		warnings.push('$reason Source: $source');
	}

	static function _firstString(data:Dynamic, fields:Array<String>):Null<String> {
		for (field in fields) {
			var value = Reflect.field(data, field);
			if (value != null && StringTools.trim(Std.string(value)) != "") return Std.string(value);
		}
		return null;
	}

	static function _psychColor(value:Dynamic):String {
		if (Std.isOfType(value, String)) {
			var text:String = cast value;
			if (text.startsWith("0x") || text.startsWith("0X")) return "#" + text.substr(2).substr(-6);
			return text;
		}
		return "#" + StringTools.hex(Std.int(value), 6);
	}

	static function _collectDependencies(files:Array<ModPackageFile>, packageRoot:Array<String>):Array<String> {
		var dependencies:Array<String> = [];
		for (file in files) {
			var parts = file.name.split("/");
			if (!_startsWithParts(parts, packageRoot)) continue;
			var remaining = parts.slice(packageRoot.length);
			if (remaining.length != 1 || !METADATA_FILES.contains(remaining[0].toLowerCase()) || file.size > 1048576) continue;
			try {
				var metadata:Dynamic = haxe.Json.parse(file.read().toString());
				_collectDependencyValues(metadata, "", dependencies);
			} catch (_:Dynamic) {}
		}
		return _unique(dependencies);
	}

	static function _collectDependencyValues(value:Dynamic, parent:String, found:Array<String>):Void {
		if (value == null) return;
		if (Std.isOfType(value, Array)) {
			for (entry in (cast value:Array<Dynamic>)) _collectDependencyValues(entry, parent, found);
		} else if (Type.typeof(value) == TObject) {
			for (key in Reflect.fields(value)) _collectDependencyValues(Reflect.field(value, key), key, found);
		} else if ((parent == "dependencies" || parent == "dependsOn" || parent == "requires" || parent == "requiredMods")
			&& Std.isOfType(value, String) && StringTools.trim(cast value) != "") {
			if (!found.contains(cast value)) found.push(cast value);
		}
	}

	static function _findFile(files:Array<ModPackageFile>, name:String):Null<ModPackageFile> {
		for (file in files) if (file.name.toLowerCase() == name.toLowerCase()) return file;
		return null;
	}

	static function _isIgnored(name:String):Bool {
		var parts = name.split("/");
		for (part in parts) if (IGNORED_PARTS.contains(part.toLowerCase())) return true;
		return IGNORED_NAMES.contains(Path.withoutDirectory(name).toLowerCase());
	}

	static function _startsWithParts(parts:Array<String>, prefix:Array<String>):Bool {
		if (prefix.length > parts.length) return false;
		for (i in 0...prefix.length) if (parts[i] != prefix[i]) return false;
		return true;
	}

	static function _nativeJoin(root:String, relative:String):String {
		var output = root;
		for (part in relative.split("/")) output = Path.join([output, part]);
		return output;
	}

	static function _createDirectories(path:String):Void {
		if (path == null || path == "" || FileSystem.exists(path)) return;
		var parent = Path.directory(path);
		if (parent != path && parent != "") _createDirectories(parent);
		if (!FileSystem.exists(path)) FileSystem.createDirectory(path);
	}

	static function _isWithin(parent:String, candidate:String):Bool {
		var normalizedParent = Path.normalize(parent).toLowerCase();
		var normalizedCandidate = Path.normalize(candidate).toLowerCase();
		return normalizedCandidate == normalizedParent || normalizedCandidate.startsWith(Path.addTrailingSlash(normalizedParent));
	}

	static function _unique(values:Array<String>):Array<String> {
		var result:Array<String> = [];
		for (value in values) if (!result.contains(value)) result.push(value);
		result.sort(Reflect.compare);
		return result;
	}

	public static function clearCache(?managedRoot:String):Int {
		return clearCacheForMod(null, managedRoot);
	}

	public static function clearCacheForMod(source:String, ?managedRoot:String):Int {
		var cleared = 0;
		if (managedRoot == null) managedRoot = defaultManagedRoot();
		if (!FileSystem.exists(managedRoot)) return 0;
		var normalizedSource = source != null ? Path.normalize(FileSystem.fullPath(source)).toLowerCase() : null;
		var sourceBase = source != null ? Path.withoutDirectory(source).toLowerCase() : null;
		for (entry in FileSystem.readDirectory(managedRoot)) {
			var dir = Path.join([managedRoot, entry]);
			if (!FileSystem.isDirectory(dir)) continue;
			if (entry.startsWith(".dbe-staging-") || entry.startsWith(".dbe-mod-conversion-")) {
				try { _deleteTree(dir); } catch (_:Dynamic) {}
				continue;
			}
			var reportFile = Path.join([dir, REPORT_NAME]);
			if (!FileSystem.exists(reportFile)) {
				try { _deleteTree(dir); } catch (_:Dynamic) {}
				continue;
			}
			try {
				var report:Dynamic = haxe.Json.parse(File.getContent(reportFile));
				var repSource:String = Reflect.field(report, "source");
				if (repSource != null) {
					var repNorm = Path.normalize(repSource).toLowerCase();
					var repFull = FileSystem.exists(repSource) ? Path.normalize(FileSystem.fullPath(repSource)).toLowerCase() : repNorm;
					if (normalizedSource == null || repNorm == normalizedSource || repFull == normalizedSource || (sourceBase != null && (repNorm.endsWith("/" + sourceBase) || repNorm == sourceBase))) {
						try { _deleteTree(dir); } catch (_:Dynamic) {}
						cleared++;
					}
				}
			} catch (_:Dynamic) {}
		}
		return cleared;
	}

	static function _deleteTree(path:String):Void {
		if (path == null || !FileSystem.exists(path)) return;
		try {
			#if windows
			try {
				funkin.backend.utils.NativeAPI.setFileAttributes(path, 0x80); // FILE_ATTRIBUTE_NORMAL
			} catch (_:Dynamic) {}
			#end
			for (entry in FileSystem.readDirectory(path)) {
				var child = Path.join([path, entry]);
				if (FileSystem.isDirectory(child)) {
					_deleteTree(child);
				} else {
					_safeDeleteFile(child);
				}
			}
			try {
				FileSystem.deleteDirectory(path);
			} catch (_:Dynamic) {
				#if windows
				try {
					var winDir = path.replace("/", "\\");
					Sys.command('cmd /c rmdir /s /q "' + winDir + '" >nul 2>&1');
				} catch (_:Dynamic) {}
				#end
			}
		} catch (_:Dynamic) {
			#if windows
			try {
				var winDir = path.replace("/", "\\");
				Sys.command('cmd /c rmdir /s /q "' + winDir + '" >nul 2>&1');
			} catch (_:Dynamic) {}
			#end
		}
	}

	static function _safeDeleteFile(filePath:String):Void {
		if (filePath == null || !FileSystem.exists(filePath)) return;
		#if windows
		try {
			funkin.backend.utils.NativeAPI.setFileAttributes(filePath, 0x80); // FILE_ATTRIBUTE_NORMAL
		} catch (_:Dynamic) {}
		#end

		try {
			FileSystem.deleteFile(filePath);
		} catch (_:Dynamic) {
			#if windows
			try {
				var winPath = filePath.replace("/", "\\");
				if (winPath.length >= 240 && !winPath.startsWith("\\\\?\\")) {
					try {
						FileSystem.deleteFile("\\\\?\\" + winPath);
						return;
					} catch (_:Dynamic) {}
				}
				Sys.command('cmd /c attrib -r -h -s "' + winPath + '" >nul 2>&1 && del /f /q /a "' + winPath + '" >nul 2>&1');
			} catch (_:Dynamic) {}
			#end
		}
	}

	static function _moveOrMergeDirectory(sourceDir:String, targetDir:String):Void {
		if (!FileSystem.exists(targetDir)) {
			try {
				FileSystem.rename(sourceDir, targetDir);
				return;
			} catch (_:Dynamic) {}
		}
		_copyDirectoryContents(sourceDir, targetDir);
	}

	static function _copyDirectoryContents(src:String, dest:String):Void {
		if (!FileSystem.exists(dest)) _createDirectories(dest);
		for (entry in FileSystem.readDirectory(src)) {
			var sChild = Path.join([src, entry]);
			var dChild = Path.join([dest, entry]);
			if (FileSystem.isDirectory(sChild)) {
				_copyDirectoryContents(sChild, dChild);
			} else {
				try {
					#if windows
					try {
						funkin.backend.utils.NativeAPI.setFileAttributes(dChild, 0x80);
					} catch (_:Dynamic) {}
					#end
					File.copy(sChild, dChild);
				} catch (_:Dynamic) {
					try {
						File.saveBytes(dChild, File.getBytes(sChild));
					} catch (_:Dynamic) {}
				}
			}
		}
	}
}

private typedef ModPackageFile = {
	var name:String;
	var size:Int;
	var read:Void->Bytes;
}

private typedef GeneratedModFile = {
	var source:String;
	var target:String;
	var contents:Bytes;
	var reason:String;
}

private typedef ZipModEntry = {
	var path:String;
	var offset:Int;
	var compressedSize:Int;
	var size:Int;
	var method:Int;
	var crc:Int;
}
#else
class RuntimeModConverter {
	public static function defaultManagedRoot():String return "./.temp/mod-conversions";

	public static function prepare(source:String, managedRoot:String, sourceFormat:String = "auto"):Dynamic
		return {blocked: false, converted: false, loadPath: source, report: null};
}
#end
