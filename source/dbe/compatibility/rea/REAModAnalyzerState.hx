package dbe.compatibility.rea;

#if sys
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import funkin.backend.MusicBeatState;
import funkin.backend.assets.Paths;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.Process;
import dbe.compatibility.rea.REAModAnalyzer;

#if lime
import lime.ui.FileDialog;
import lime.ui.FileDialogFilter;
import lime.system.Clipboard;
#end

using StringTools;

/**
 * REAModAnalyzerState: In-engine UI for inspecting custom executables (.exe),
 * unconfigured mods, and understanding how to run or convert them in DBE.
 *
 * Supports:
 * - Automatic discovery of .EXE files and folders in mods/, export/, and game root
 * - [TAB] Filter between ALL, ONLY .EXE, and ONLY FOLDERS
 * - [O] Native File Picker (Browse any .exe or .zip on your computer)
 * - [P] Windows Native OpenFileDialog (.exe picker fallback)
 * - [F] Native Folder Picker (Browse any mod directory on your computer)
 * - [Ctrl+V] Paste any .exe or folder path from clipboard
 * - Drag-and-Drop any .exe or folder directly into the game window
 * - Clickable toolbar buttons + Mouse wheel selection
 */
class REAModAnalyzerState extends MusicBeatState {
	var allCandidates:Array<String> = [];
	var customCandidates:Array<String> = [];
	var candidates:Array<String> = [];
	var curSelected:Int = 0;
	var filterMode:Int = 0; // 0 = ALL, 1 = ONLY .EXE, 2 = ONLY FOLDERS
	var currentResult:Null<REAModAnalysisResult> = null;

	var listText:FlxText;
	var detailsText:FlxText;
	var statusText:FlxText;
	var headerTitle:FlxText;
	var hintText:FlxText;

	var toolbarButtons:Array<{bg:FlxSprite, label:FlxText, onClick:Void->Void}> = [];

	public override function create():Void {
		super.create();

		FlxG.mouse.visible = true;

		var bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0xFF0D1117);
		add(bg);

		headerTitle = new FlxText(20, 12, FlxG.width - 40, "DBE - REA EXECUTABLE (.EXE) & MOD INSPECTOR", 22);
		headerTitle.setFormat(Paths.font("vcr.ttf"), 22, 0xFF00FFCC, LEFT);
		add(headerTitle);

		var subTitle = new FlxText(20, 38, FlxG.width - 40, "Select or Drag & Drop any custom .EXE or Mod folder to reverse engineer and extract/convert for DBE", 13);
		subTitle.setFormat(Paths.font("vcr.ttf"), 13, 0xFF8892B0, LEFT);
		add(subTitle);

		// Create Interactive Toolbar Buttons
		createToolbar();

		// Left Panel Background
		var leftBg = new FlxSprite(16, 96).makeGraphic(400, FlxG.height - 166, 0xFF161B22);
		add(leftBg);

		// Right Panel Background
		var rightBg = new FlxSprite(426, 96).makeGraphic(FlxG.width - 442, FlxG.height - 166, 0xFF161B22);
		add(rightBg);

		// Left Panel: Candidates
		listText = new FlxText(24, 102, 384, "", 13);
		listText.setFormat(Paths.font("vcr.ttf"), 13, FlxColor.WHITE, LEFT);
		add(listText);

		// Right Panel: Details & Prescriptions
		detailsText = new FlxText(436, 102, FlxG.width - 462, "", 13);
		detailsText.setFormat(Paths.font("vcr.ttf"), 13, FlxColor.WHITE, LEFT);
		detailsText.wordWrap = true;
		add(detailsText);

		statusText = new FlxText(20, FlxG.height - 62, FlxG.width - 40, "", 14);
		statusText.setFormat(Paths.font("vcr.ttf"), 14, 0xFFFFCC00, LEFT);
		add(statusText);

		hintText = new FlxText(20, FlxG.height - 34, FlxG.width - 40, "[UP/DOWN/Wheel] Select | [O/P] Pick .EXE | [F] Pick Folder | [TAB] Filter .EXE/Folders | [Ctrl+V] Paste | [ENTER] Extract/Convert | [E] Export | [ESC] Back", 11);
		hintText.setFormat(Paths.font("vcr.ttf"), 11, 0xFF888888, LEFT);
		add(hintText);

		// Register Drag & Drop listener
		#if lime
		try {
			if (FlxG.stage != null && FlxG.stage.window != null) {
				FlxG.stage.window.onDropFile.add(onFileDropped);
			}
		} catch (_:Dynamic) {}
		#end

		refreshCandidates();
		updateSelection();
	}

	function createToolbar():Void {
		var btnDefs:Array<{text:String, color:Int, action:Void->Void}> = [
			{text: "[O] Browse .EXE", color: 0xFF1F6FEB, action: browseCustomExecutable},
			{text: "[P] Win .EXE Dialog", color: 0xFF238636, action: browseWindowsExeFallback},
			{text: "[F] Browse Folder", color: 0xFF30363D, action: browseCustomFolder},
			{text: "[TAB] Filter: ALL", color: 0xFF6E40C9, action: cycleFilterMode},
			{text: "[ENTER] Convert/Extract", color: 0xFF9E6A03, action: triggerAutoConvert},
			{text: "[L] Console Capture", color: 0xFF8B2635, action: function() FlxG.switchState(new DBEConsoleCaptureState())}
		];

		var curX:Float = 20;
		var btnY:Float = 60;
		var btnH:Int = 28;

		for (def in btnDefs) {
			var btnW = Std.int(def.text.length * 8.5 + 20);
			var btnBg = new FlxSprite(curX, btnY).makeGraphic(btnW, btnH, def.color);
			add(btnBg);

			var lbl = new FlxText(curX, btnY + 6, btnW, def.text, 12);
			lbl.setFormat(Paths.font("vcr.ttf"), 12, FlxColor.WHITE, CENTER);
			add(lbl);

			toolbarButtons.push({bg: btnBg, label: lbl, onClick: def.action});
			curX += btnW + 10;
		}
	}

	override function destroy():Void {
		#if lime
		try {
			if (FlxG.stage != null && FlxG.stage.window != null) {
				FlxG.stage.window.onDropFile.remove(onFileDropped);
			}
		} catch (_:Dynamic) {}
		#end
		super.destroy();
	}

	function onFileDropped(droppedPath:String, type:String, x:Float, y:Float):Void {
		if (droppedPath == null || droppedPath.trim() == "") return;
		var clean = droppedPath.trim().replace('"', '');
		if (FileSystem.exists(clean)) {
			statusText.text = "Dropped target loaded: " + Path.withoutDirectory(clean);
			addCustomCandidate(clean);
		}
	}

	/**
	 * Prepend a custom target path (.exe, .zip, or folder) to candidates and immediately analyze it.
	 */
	public function addCustomCandidate(targetPath:String):Void {
		try {
			var norm = Path.normalize(FileSystem.fullPath(targetPath));
			if (!FileSystem.exists(norm)) {
				statusText.text = "Path not found: " + targetPath;
				return;
			}
			customCandidates.remove(norm);
			customCandidates.unshift(norm);

			// If current filter would hide this item, reset filter to ALL
			var isExe = !FileSystem.isDirectory(norm) && Path.extension(norm).toLowerCase() == "exe";
			if ((filterMode == 1 && !isExe) || (filterMode == 2 && isExe)) {
				filterMode = 0;
				updateFilterButtonLabel();
			}

			applyFilter();
			curSelected = 0;
			updateSelection();
		} catch (e:Dynamic) {
			statusText.text = "Failed to add target: " + Std.string(e);
		}
	}

	function refreshCandidates():Void {
		allCandidates = REAModAnalyzer.discoverTargets();
		applyFilter();
	}

	function applyFilter():Void {
		candidates = [];
		var seen:Map<String, Bool> = new Map();

		var combined = customCandidates.concat(allCandidates);
		for (item in combined) {
			var key = item.toLowerCase();
			if (seen.exists(key)) continue;
			if (!FileSystem.exists(item)) continue;

			var isDir = FileSystem.isDirectory(item);
			var ext = Path.extension(item).toLowerCase();
			var isExe = !isDir && ext == "exe";

			if (filterMode == 1 && !isExe) continue;
			if (filterMode == 2 && isExe) continue;

			seen.set(key, true);
			candidates.push(item);
		}

		if (curSelected >= candidates.length) {
			curSelected = Std.int(Math.max(0, candidates.length - 1));
		}
	}

	function cycleFilterMode():Void {
		filterMode = (filterMode + 1) % 3;
		updateFilterButtonLabel();
		applyFilter();
		curSelected = 0;
		updateSelection();
	}

	function updateFilterButtonLabel():Void {
		if (toolbarButtons.length >= 4) {
			toolbarButtons[3].label.text = switch (filterMode) {
				case 1: "[TAB] Filter: .EXE";
				case 2: "[TAB] Filter: DIRS";
				default: "[TAB] Filter: ALL";
			};
		}
	}

	function formatCandidateLabel(path:String):String {
		var isDir = FileSystem.exists(path) && FileSystem.isDirectory(path);
		var ext = Path.extension(path).toLowerCase();
		var tag = isDir ? "[DIR] " : (ext == "exe" ? "[EXE] " : "[ZIP] ");
		var base = Path.withoutDirectory(path);
		var parent = Path.withoutDirectory(Path.directory(path));
		var display = (parent != "" && parent != "." && parent.toLowerCase() != "mods") ? '$base ($parent)' : base;
		var fullLabel = tag + display;
		if (fullLabel.length > 42) {
			fullLabel = fullLabel.substr(0, 39) + "...";
		}
		return fullLabel;
	}

	function updateSelection():Void {
		var modeName = switch (filterMode) {
			case 1: "ONLY EXECUTABLES (.EXE)";
			case 2: "ONLY FOLDERS / ARCHIVES";
			default: "ALL (.EXE + FOLDERS)";
		};

		var b = new StringBuf();
		b.add('Target Queue [$modeName] (${candidates.length}):\n\n');

		if (candidates.length == 0) {
			b.add("  (No targets match current filter)\n");
			b.add("  Press [O] or [P] to select an .EXE file\n");
			b.add("  or Drag & Drop an .EXE into the window!\n");
			listText.text = b.toString();
			detailsText.text = "No target selected.\n\nUse [O] or [P] to browse for any custom .EXE executable on your PC, or Drag & Drop an .EXE here.";
			return;
		}

		var startIdx = Std.int(Math.max(0, curSelected - 9));
		var endIdx = Std.int(Math.min(candidates.length, startIdx + 19));

		for (i in startIdx...endIdx) {
			var prefix = (i == curSelected) ? "> " : "  ";
			b.add(prefix + formatCandidateLabel(candidates[i]) + "\n");
		}
		if (candidates.length > 19) {
			b.add('\n  Showing ${startIdx + 1}-${endIdx} of ${candidates.length}');
		}
		listText.text = b.toString();

		// Auto inspect current target
		inspectCurrentTarget();
	}

	function inspectCurrentTarget():Void {
		if (candidates.length == 0 || curSelected < 0 || curSelected >= candidates.length) return;

		var target = candidates[curSelected];
		statusText.text = "Analyzing: " + target;

		try {
			currentResult = REAModAnalyzer.analyzeTarget(target);
			statusText.text = "Ready: " + Path.withoutDirectory(target) + " (" + currentResult.targetType.toUpperCase() + ")";
			renderAnalysis(currentResult);
		} catch (e:Dynamic) {
			currentResult = null;
			detailsText.text = "Error analyzing target: " + Std.string(e);
			statusText.text = "Analysis failed.";
		}
	}

	function renderAnalysis(res:REAModAnalysisResult):Void {
		var b = new StringBuf();
		b.add('=== Target Diagnosis (${res.targetType.toUpperCase()}) ===\n');
		b.add('Path:               ${res.target}\n');
		b.add('Detected Engine:    ${res.primaryEngine} (Confidence: ${res.engineConfidence.toUpperCase()})\n');
		b.add('Scripting Mode:     ${res.scriptingMode}\n');
		b.add('Asset Layout:       ${res.assetLayout}\n');
		b.add('DBE Compatibility:  ${res.canConvertToDBE ? "FEASIBLE" : "INCOMPATIBLE"} (Complexity: ${res.conversionComplexity})\n\n');

		if (res.binaryAnalysis != null && res.binaryAnalysis.isPE) {
			var bp = res.binaryAnalysis;
			b.add('=== Executable (.EXE) Binary Inspection ===\n');
			b.add('Executable File:    ${Path.withoutDirectory(bp.filePath)} (${Std.int(bp.fileSize / 1024)} KB)\n');
			b.add('Architecture:       ${bp.machine} | Subsystem: ${bp.subsystem}\n');
			b.add('Compiled At:        ${bp.compileTime} | Packed/UPX: ${bp.isPacked ? "YES (High Entropy)" : "No"}\n');
			b.add('PE Sections (${bp.sections.length}):    ${[for (s in bp.sections) s.name].join(", ")}\n');
			if (bp.nativeDependencies.length > 0) {
				b.add('Native DLLs (${bp.nativeDependencies.length}):    ${bp.nativeDependencies.slice(0, 6).join(", ")}\n');
			}
			if (bp.customModClasses.length > 0) {
				b.add('Custom Classes (${bp.customModClasses.length}): ${bp.customModClasses.slice(0, 5).join(", ")}\n');
			}
			if (bp.detectedSongs.length > 0) {
				b.add('Binary Songs (${bp.detectedSongs.length}):   ${bp.detectedSongs.slice(0, 8).join(", ")}\n');
			}
			if (bp.haxeSymbols.length > 0) {
				b.add('Haxe RTTI (${bp.haxeSymbols.length}):      ${bp.haxeSymbols.slice(0, 4).join(", ")}...\n');
			}
			b.add('\n');
		}

		if (res.directoryAnalysis != null) {
			var dp = res.directoryAnalysis;
			b.add('=== Companion Assets & Scripts ===\n');
			b.add('Files: ${dp.totalFiles} | .EXEs: ${dp.executablesFound.length} | Charts: ${dp.chartFiles.length} | Lua: ${dp.luaScripts.length} | HScript: ${dp.hscriptFiles.length} | Shaders: ${dp.shaderFiles.length}\n');
			if (dp.activeLuaHooks.length > 0) {
				b.add('Active Lua Hooks:   ${dp.activeLuaHooks.slice(0, 6).join(", ")}\n');
			}
			b.add('\n');
		}

		b.add('=== Warnings & Friction Points ===\n');
		if (res.warnings.length == 0) {
			b.add('  None! Target appears structurally clean.\n');
		} else {
			for (w in res.warnings) b.add('  [!] $w\n');
		}
		b.add('\n');

		b.add('=== Prescription (How to Run / Convert in DBE) ===\n');
		for (p in res.prescriptions) b.add('  * $p\n');

		detailsText.text = b.toString();
	}

	/**
	 * [O] Opens Lime Native File Dialog to browse for any custom .EXE executable or .ZIP.
	 * Uses the exact 4-argument signature proven in UIFileExplorer (omitting defaultPath so Windows COM doesn't reject forward slashes).
	 */
	function browseCustomExecutable():Void {
		statusText.text = "Opening .EXE File Picker...";
		var opened = false;

		#if lime
		try {
			var win = (FlxG.stage != null && FlxG.stage.window != null) ? FlxG.stage.window : lime.app.Application.current.window;
			FileDialog.openFile(win, "Select Custom Executable (.exe) or Mod Package", function(files:Array<String>, activeFilter:FileDialogFilter) {
				if (files != null && files.length > 0 && files[0] != null && files[0] != "") {
					addCustomCandidate(files[0]);
				} else {
					statusText.text = "File selection cancelled.";
				}
			}, [
				new FileDialogFilter("Executable Files (*.exe)", "exe"),
				new FileDialogFilter("Executables & Mod Archives (*.exe;*.zip)", "exe;zip"),
				new FileDialogFilter("All Files (*.*)", "*")
			]);
			opened = true;
		} catch (_:Dynamic) {
			opened = false;
		}
		#end

		#if windows
		if (!opened) {
			browseWindowsExeFallback();
		}
		#end
	}

	/**
	 * [P] Direct Windows Forms OpenFileDialog specifically for .EXE files.
	 */
	function browseWindowsExeFallback():Void {
		#if windows
		statusText.text = "Opening Windows .EXE File Dialog...";
		var picked = openWindowsNativeFileDialog(false);
		if (picked != null) {
			addCustomCandidate(picked);
		} else {
			statusText.text = "Executable selection cancelled.";
		}
		#else
		browseCustomExecutable();
		#end
	}

	/**
	 * [F] Opens Windows / Native Folder Dialog to browse for any custom mod folder.
	 */
	function browseCustomFolder():Void {
		statusText.text = "Opening Folder Dialog...";
		var opened = false;

		#if lime
		try {
			var win = (FlxG.stage != null && FlxG.stage.window != null) ? FlxG.stage.window : lime.app.Application.current.window;
			FileDialog.openDirectory(win, "Select Mod Directory to Reverse Engineer", function(dirs:Array<String>) {
				if (dirs != null && dirs.length > 0 && dirs[0] != null && dirs[0] != "") {
					addCustomCandidate(dirs[0]);
				} else {
					statusText.text = "Folder selection cancelled.";
				}
			});
			opened = true;
		} catch (_:Dynamic) {
			opened = false;
		}
		#end

		#if windows
		if (!opened) {
			var picked = openWindowsNativeFileDialog(true);
			if (picked != null) {
				addCustomCandidate(picked);
			} else {
				statusText.text = "Folder selection cancelled.";
			}
		}
		#end
	}

	#if windows
	static function openWindowsNativeFileDialog(isFolder:Bool):Null<String> {
		try {
			var script = if (isFolder) {
				"Add-Type -AssemblyName System.Windows.Forms; $f = New-Object System.Windows.Forms.FolderBrowserDialog; $f.Description = 'Select Mod Directory'; if($f.ShowDialog() -eq 'OK'){ [Console]::Out.WriteLine($f.SelectedPath) }";
			} else {
				"Add-Type -AssemblyName System.Windows.Forms; $f = New-Object System.Windows.Forms.OpenFileDialog; $f.Filter = 'Executable Files (*.exe)|*.exe|Executables and Archives (*.exe;*.zip)|*.exe;*.zip|All Files (*.*)|*.*'; $f.Title = 'Select Custom Executable (.exe)'; if($f.ShowDialog() -eq 'OK'){ [Console]::Out.WriteLine($f.FileName) }";
			};

			var proc = new Process("powershell", ["-NoProfile", "-STA", "-Command", script]);
			var out = proc.stdout.readAll().toString().trim();
			proc.close();
			if (out.length > 0 && FileSystem.exists(out)) return out;
		} catch (_:Dynamic) {}
		return null;
	}
	#end

	function pasteClipboardPath():Void {
		var text:String = null;
		#if lime
		try {
			text = Clipboard.text;
		} catch (_:Dynamic) {}
		#end

		if (text == null || text.trim() == "") {
			statusText.text = "Clipboard is empty.";
			return;
		}

		var clean = text.trim().replace('"', '');
		if (FileSystem.exists(clean)) {
			statusText.text = "Target loaded from clipboard: " + Path.withoutDirectory(clean);
			addCustomCandidate(clean);
		} else {
			statusText.text = "Clipboard path does not exist on disk: " + clean;
		}
	}

	function triggerAutoConvert():Void {
		if (currentResult != null && currentResult.canConvertToDBE) {
			statusText.text = "Learning engine rules & converting target for DBE...";
			try {
				var res:Dynamic = REAModAnalyzer.autoConvert(currentResult);
				var modFolder:Dynamic = Reflect.field(res, "modFolderName");
				var extractedCount:Dynamic = Reflect.field(res, "extractedFiles");
				var externalCount:Dynamic = Reflect.field(res, "externalFiles");
				var carvedCount:Dynamic = Reflect.field(res, "carvedBinaryFiles");
				var learnedRules:Dynamic = Reflect.field(res, "learnedRules");
				var learnedNote = (learnedRules != null && learnedRules > 0) ? ' | Learned ${learnedRules} engine API/file rules!' : '';
				var engineName = (currentResult.primaryEngine != null && currentResult.primaryEngine != "Unknown") ? currentResult.primaryEngine : haxe.io.Path.withoutDirectory(currentResult.target);
				var versionHint = (currentResult.binaryAnalysis != null && currentResult.binaryAnalysis.versionHint != null) ? currentResult.binaryAnalysis.versionHint : "1.0";
				READecodedEnginesManager.registerDecodedEngine(engineName, currentResult.primaryEngine, versionHint, currentResult.target, REARuntimeBridge.activeProfile);

				if (modFolder != null) {
					if (externalCount != null && carvedCount != null) {
						statusText.text = 'SUCCESS! Extracted ${extractedCount} files (${externalCount} external + ${carvedCount} carved) -> mods/${modFolder}${learnedNote}';
					} else {
						statusText.text = 'SUCCESS! Extracted ${extractedCount} files -> mods/${modFolder}${learnedNote}';
					}
					refreshCandidates();
				} else {
					statusText.text = "Conversion complete: " + (res.converted ? "CONVERTED -> " + res.loadPath : "READY -> " + res.loadPath) + learnedNote;
				}

				// Prompt user which mod to load this newly decoded engine with!
				openSubState(new REAModSelectTargetSubState(engineName, null, function(chosenMod:String) {
					if (chosenMod != null) {
						statusText.text = 'Engine $engineName vinculada ao mod $chosenMod! Carregando...';
						new flixel.util.FlxTimer().start(0.5, function(_) {
							funkin.backend.assets.ModsFolder.switchMod(chosenMod);
							FlxG.switchState(new funkin.menus.TitleState());
						});
					}
				}));
			} catch (e:Dynamic) {
				statusText.text = "Conversion error: " + Std.string(e);
			}
		}
	}

	function exportCurrentReport():Void {
		if (currentResult == null) return;
		var baseDir = FileSystem.isDirectory(currentResult.target) ? currentResult.target : Path.directory(currentResult.target);
		var jsonPath = Path.join([baseDir, "_dbe_rea_report.json"]);
		var mdPath = Path.join([baseDir, "_dbe_rea_report.md"]);
		try {
			REAModAnalyzer.exportReportJson(currentResult, jsonPath);
			REAModAnalyzer.exportReportMarkdown(currentResult, mdPath);
			statusText.text = 'Reports exported to: $jsonPath and $mdPath';
		} catch (e:Dynamic) {
			statusText.text = "Failed to export report: " + Std.string(e);
		}
	}

	public override function update(elapsed:Float):Void {
		super.update(elapsed);

		// Mouse wheel scrolling on candidate list
		if (FlxG.mouse.wheel != 0 && candidates.length > 0) {
			curSelected -= FlxG.mouse.wheel;
			if (curSelected < 0) curSelected = candidates.length - 1;
			if (curSelected >= candidates.length) curSelected = 0;
			updateSelection();
		}

		// Mouse clicks on toolbar buttons
		if (FlxG.mouse.justPressed) {
			for (btn in toolbarButtons) {
				if (FlxG.mouse.overlaps(btn.bg)) {
					btn.onClick();
					return;
				}
			}
		}

		if (FlxG.keys.justPressed.UP) {
			if (candidates.length > 0) {
				curSelected--;
				if (curSelected < 0) curSelected = candidates.length - 1;
				updateSelection();
			}
		} else if (FlxG.keys.justPressed.DOWN) {
			if (candidates.length > 0) {
				curSelected++;
				if (curSelected >= candidates.length) curSelected = 0;
				updateSelection();
			}
		}

		// [TAB] Cycle Filter (ALL / ONLY .EXE / ONLY FOLDERS)
		if (FlxG.keys.justPressed.TAB) {
			cycleFilterMode();
		}

		// [O] Browse .EXE File (Lime Native)
		if (FlxG.keys.justPressed.O) {
			browseCustomExecutable();
		}

		// [P] Browse .EXE File (Windows Forms Direct)
		if (FlxG.keys.justPressed.P) {
			browseWindowsExeFallback();
		}

		// [F] Browse Folder
		if (FlxG.keys.justPressed.F) {
			browseCustomFolder();
		}

		// [Ctrl+V] Paste Path
		if (FlxG.keys.pressed.CONTROL && FlxG.keys.justPressed.V) {
			pasteClipboardPath();
		}

		// [ENTER] Run Auto-Convert / Extract .EXE Mod
		if (FlxG.keys.justPressed.ENTER) {
			triggerAutoConvert();
		}

		// [E] Export Report
		if (FlxG.keys.justPressed.E) {
			exportCurrentReport();
		}

		// [L] Open In-Engine Console & Diagnostic Capture Tool
		if (FlxG.keys.justPressed.L) {
			FlxG.switchState(new DBEConsoleCaptureState());
		}

		if (FlxG.keys.justPressed.ESCAPE) {
			FlxG.switchState(new funkin.menus.MainMenuState());
		}
	}
}
#end
