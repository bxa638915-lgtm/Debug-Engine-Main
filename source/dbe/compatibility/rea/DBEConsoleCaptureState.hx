package dbe.compatibility.rea;

#if sys
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import funkin.backend.MusicBeatState;
import funkin.backend.assets.ModsFolder;
import funkin.backend.assets.Paths;
import funkin.backend.system.Logs;
import funkin.backend.system.Main;
import funkin.backend.utils.NativeAPI.ConsoleColor;
import sys.FileSystem;

#if lime
import lime.system.Clipboard;
#end

using StringTools;

/**
 * In-Engine Haxe UI Tool for viewing, filtering, testing, copying, and exporting
 * 100% of DBE's console logs, script errors (HScript/Lua), missing assets, and REA diagnostics.
 *
 * Accessible via:
 * - [F10] anywhere in the engine
 * - [7] Editor Picker -> "Console & Log Capture"
 * - [L] inside REAModAnalyzerState
 */
class DBEConsoleCaptureState extends MusicBeatState {
	var filterMode:Int = 0; // 0=ALL, 1=ERRORS, 2=WARNINGS, 3=SCRIPTS, 4=ASSETS, 5=MODS/REA, 6=DIAGNOSTIC REPORT
	var scrollOffset:Int = 0;
	var autoFollowTail:Bool = true;
	var lastRecordedCount:Int = -1;

	var headerTitle:FlxText;
	var statsBarText:FlxText;
	var logDisplay:FlxText;
	var statusText:FlxText;
	var hintText:FlxText;

	var toolbarButtons:Array<{bg:FlxSprite, label:FlxText, onClick:Void->Void}> = [];

	static final FILTER_NAMES:Array<String> = [
		"ALL LOGS",
		"ERRORS & CRASHES",
		"WARNINGS",
		"HSCRIPT & LUA",
		"MISSING ASSETS",
		"MODS & REA",
		"FULL DIAGNOSTIC REPORT"
	];

	public override function create():Void {
		super.create();

		DBEConsoleCapture.init();
		FlxG.mouse.visible = true;

		// Enable verbose logging automatically when opening the diagnostic capture tool
		Main.verbose = true;

		var bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0xFF0A0E14);
		add(bg);

		headerTitle = new FlxText(20, 10, FlxG.width - 40, "DBE - IN-ENGINE CONSOLE & DIAGNOSTIC CAPTURE TOOL", 21);
		headerTitle.setFormat(Paths.font("vcr.ttf"), 21, 0xFF00FFCC, LEFT);
		add(headerTitle);

		statsBarText = new FlxText(20, 35, FlxG.width - 40, "", 13);
		statsBarText.setFormat(Paths.font("vcr.ttf"), 13, 0xFF8892B0, LEFT);
		add(statsBarText);

		createToolbar();

		// Main Console Panel
		var panelBg = new FlxSprite(16, 94).makeGraphic(FlxG.width - 32, FlxG.height - 162, 0xFF121721);
		add(panelBg);

		logDisplay = new FlxText(24, 100, FlxG.width - 48, "", 13);
		logDisplay.setFormat(Paths.font("vcr.ttf"), 13, FlxColor.WHITE, LEFT);
		logDisplay.wordWrap = true;
		add(logDisplay);

		statusText = new FlxText(20, FlxG.height - 60, FlxG.width - 40, "Capturing all engine logs in real time (Verbose Mode: ON).", 14);
		statusText.setFormat(Paths.font("vcr.ttf"), 14, 0xFFFFCC00, LEFT);
		add(statusText);

		hintText = new FlxText(20, FlxG.height - 34, FlxG.width - 40,
			"[1-7 / TAB] Filter | [UP/DOWN/PGUP/PGDN/Wheel] Scroll | [T] Test & Capture Current Mod | [C] Copy All | [S] Save Dump | [X] Clear | [R] REA Tool | [ESC] Back", 11);
		hintText.setFormat(Paths.font("vcr.ttf"), 11, 0xFF888888, LEFT);
		add(hintText);

		refreshDisplay();
	}

	function createToolbar():Void {
		var btnDefs:Array<{text:String, color:Int, action:Void->Void}> = [
			{text: "[TAB] View: ALL LOGS", color: 0xFF6E40C9, action: cycleFilter},
			{text: "[T] Test & Capture Mod", color: 0xFF238636, action: testAndCaptureCurrentMod},
			{text: "[C] Copy Diagnostic", color: 0xFF1F6FEB, action: copyToClipboard},
			{text: "[S] Save Full Dump", color: 0xFF9E6A03, action: saveFullDump},
			{text: "[X] Clear Buffer", color: 0xFF8B2635, action: clearCapturedLogs},
			{text: "[R] REA Inspector", color: 0xFF30363D, action: openREAInspector}
		];

		var xPos:Float = 16;
		var yPos:Float = 58;
		var btnHeight:Int = 28;

		for (def in btnDefs) {
			var btnWidth = Std.int(Math.max(140, def.text.length * 8 + 18));
			var btnBg = new FlxSprite(xPos, yPos).makeGraphic(btnWidth, btnHeight, def.color);
			add(btnBg);

			var btnLabel = new FlxText(xPos + 6, yPos + 5, btnWidth - 12, def.text, 12);
			btnLabel.setFormat(Paths.font("vcr.ttf"), 12, FlxColor.WHITE, CENTER);
			add(btnLabel);

			toolbarButtons.push({bg: btnBg, label: btnLabel, onClick: def.action});
			xPos += btnWidth + 8;
		}
	}

	function cycleFilter():Void {
		filterMode = (filterMode + 1) % FILTER_NAMES.length;
		scrollOffset = 0;
		autoFollowTail = (filterMode != 6);
		if (toolbarButtons.length >= 1) {
			toolbarButtons[0].label.text = "[TAB] " + FILTER_NAMES[filterMode];
		}
		statusText.text = 'Filter switched to: ${FILTER_NAMES[filterMode]}';
		refreshDisplay();
	}

	function setFilter(mode:Int):Void {
		filterMode = mode % FILTER_NAMES.length;
		scrollOffset = 0;
		autoFollowTail = (filterMode != 6);
		if (toolbarButtons.length >= 1) {
			toolbarButtons[0].label.text = "[TAB] " + FILTER_NAMES[filterMode];
		}
		statusText.text = 'Filter switched to: ${FILTER_NAMES[filterMode]}';
		refreshDisplay();
	}

	function testAndCaptureCurrentMod():Void {
		var curMod = ModsFolder.currentModFolder;
		Main.verbose = true;
		Logs.infos('=== [DBE DIAGNOSTIC PROBE] Testing mod: ${curMod != null ? curMod : "(base game)"} ===', CYAN, "DBECapture");

		if (curMod != null) {
			var rawModDir = ModsFolder.modsPath + curMod;
			if (FileSystem.exists(rawModDir)) {
				try {
					var analysis = REAModAnalyzer.analyzeTarget(rawModDir);
					Logs.infos('REA Analysis: engine=${analysis.primaryEngine} (${analysis.engineConfidence}), scripts=${analysis.scriptingMode}, files=${analysis.directoryAnalysis != null ? analysis.directoryAnalysis.totalFiles : 0}', CYAN, "DBECapture");
					for (w in analysis.warnings) {
						Logs.warn('REA Warning: $w', YELLOW, "DBECapture");
					}
				} catch (e:Dynamic) {
					Logs.error('REA Analysis error: ${Std.string(e)}', RED, "DBECapture");
				}
			}
		}

		try {
			ModsFolder.switchMod(curMod);
			var savedPath = DBEConsoleCapture.saveDiagnosticSummary();
			statusText.text = 'Mod "${curMod != null ? curMod : "base"}" reloaded & captured! Saved report to ${savedPath}';
		} catch (e:Dynamic) {
			Logs.error('Mod reload probe failed: ${Std.string(e)}', RED, "DBECapture");
		}
		refreshDisplay();
	}

	function copyToClipboard():Void {
		var content = (filterMode == 6) ? DBEConsoleCapture.buildDiagnosticReport() : buildCurrentFilterText(250);
		#if lime
		try {
			Clipboard.text = content;
			statusText.text = 'COPIED TO CLIPBOARD! (${content.length} chars) - Press Ctrl+V anywhere to paste!';
			return;
		} catch (_:Dynamic) {}
		#end
		statusText.text = "Clipboard unavailable; saving to logs/dbe_diagnostic_summary.txt instead.";
		saveFullDump();
	}

	function saveFullDump():Void {
		var outPath = DBEConsoleCapture.saveDiagnosticSummary();
		statusText.text = 'SAVED! Full diagnostic report -> ${outPath} & ${DBEConsoleCapture.LATEST_LOG_PATH}';
	}

	function clearCapturedLogs():Void {
		DBEConsoleCapture.clear();
		scrollOffset = 0;
		statusText.text = "Console capture buffer cleared.";
		refreshDisplay();
	}

	function openREAInspector():Void {
		FlxG.switchState(new REAModAnalyzerState());
	}

	function buildCurrentFilterText(maxLines:Int):String {
		if (filterMode == 6) {
			return DBEConsoleCapture.buildDiagnosticReport();
		}
		var list = DBEConsoleCapture.getFilteredEntries(filterMode);
		var b = new StringBuf();
		var startIdx = Std.int(Math.max(0, list.length - maxLines));
		for (i in startIdx...list.length) {
			var e = list[i];
			b.add('[#${e.id}][${e.category}] ${e.text}\n');
		}
		return b.toString();
	}

	function refreshDisplay():Void {
		lastRecordedCount = DBEConsoleCapture.totalRecorded;
		var curMod = ModsFolder.currentModFolder != null ? ModsFolder.currentModFolder : "(none)";
		statsBarText.text = 'Mod: $curMod | View: ${FILTER_NAMES[filterMode]} | Total: ${DBEConsoleCapture.totalRecorded} | Errors: ${DBEConsoleCapture.errorCount} | Warnings: ${DBEConsoleCapture.warningCount} | Script Issues: ${DBEConsoleCapture.scriptIssueCount} | Missing Assets: ${DBEConsoleCapture.missingAssetCount}';

		var lines:Array<String> = [];
		if (filterMode == 6) {
			lines = DBEConsoleCapture.buildDiagnosticReport().split("\n");
		} else {
			var filtered = DBEConsoleCapture.getFilteredEntries(filterMode);
			if (filtered.length == 0) {
				lines.push('No entries recorded for filter [${FILTER_NAMES[filterMode]}].');
				lines.push('Press [T] to test & reload the active mod, or [7] to view the full diagnostic report.');
			} else {
				for (e in filtered) {
					lines.push('[#${e.id}][${e.category}] ${e.text}');
				}
			}
		}

		var visibleLinesCount = 28;
		var maxScroll = Std.int(Math.max(0, lines.length - visibleLinesCount));
		if (autoFollowTail && filterMode != 6) {
			scrollOffset = maxScroll;
		} else if (scrollOffset > maxScroll) {
			scrollOffset = maxScroll;
		}
		if (scrollOffset < 0) scrollOffset = 0;

		var endIdx = Std.int(Math.min(lines.length, scrollOffset + visibleLinesCount));
		var slice = lines.slice(scrollOffset, endIdx);
		logDisplay.text = slice.join("\n");
	}

	public override function update(elapsed:Float):Void {
		super.update(elapsed);

		if (DBEConsoleCapture.totalRecorded != lastRecordedCount) {
			refreshDisplay();
		}

		if (FlxG.mouse.justPressed) {
			for (btn in toolbarButtons) {
				if (FlxG.mouse.overlaps(btn.bg)) {
					btn.onClick();
					return;
				}
			}
		}

		if (FlxG.mouse.wheel != 0) {
			autoFollowTail = false;
			scrollOffset -= FlxG.mouse.wheel * 4;
			refreshDisplay();
		}

		if (FlxG.keys.justPressed.UP) {
			autoFollowTail = false;
			scrollOffset -= 2;
			refreshDisplay();
		} else if (FlxG.keys.justPressed.DOWN) {
			autoFollowTail = false;
			scrollOffset += 2;
			refreshDisplay();
		} else if (FlxG.keys.justPressed.PAGEUP) {
			autoFollowTail = false;
			scrollOffset -= 20;
			refreshDisplay();
		} else if (FlxG.keys.justPressed.PAGEDOWN) {
			autoFollowTail = false;
			scrollOffset += 20;
			refreshDisplay();
		} else if (FlxG.keys.justPressed.HOME) {
			autoFollowTail = false;
			scrollOffset = 0;
			refreshDisplay();
		} else if (FlxG.keys.justPressed.END) {
			autoFollowTail = true;
			refreshDisplay();
		}

		if (FlxG.keys.justPressed.TAB) {
			cycleFilter();
		} else if (FlxG.keys.justPressed.ONE) {
			setFilter(0);
		} else if (FlxG.keys.justPressed.TWO) {
			setFilter(1);
		} else if (FlxG.keys.justPressed.THREE) {
			setFilter(2);
		} else if (FlxG.keys.justPressed.FOUR) {
			setFilter(3);
		} else if (FlxG.keys.justPressed.FIVE) {
			setFilter(4);
		} else if (FlxG.keys.justPressed.SIX) {
			setFilter(5);
		} else if (FlxG.keys.justPressed.SEVEN) {
			setFilter(6);
		} else if (FlxG.keys.justPressed.T) {
			testAndCaptureCurrentMod();
		} else if (FlxG.keys.justPressed.C) {
			copyToClipboard();
		} else if (FlxG.keys.justPressed.S) {
			saveFullDump();
		} else if (FlxG.keys.justPressed.X) {
			clearCapturedLogs();
		} else if (FlxG.keys.justPressed.R) {
			openREAInspector();
		} else if (FlxG.keys.justPressed.ESCAPE || controls.BACK) {
			FlxG.switchState(new funkin.menus.MainMenuState());
		}
	}
}
#end
