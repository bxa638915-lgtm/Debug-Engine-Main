package dbe.compatibility.rea;

#if MOD_SUPPORT
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import funkin.backend.assets.ModsFolder;
import funkin.backend.assets.Paths;
import funkin.backend.utils.CoolUtil;
import funkin.backend.MusicBeatSubstate;
import dbe.compatibility.mods.RuntimeModConverter;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

#if lime
import lime.system.Clipboard;
import lime.ui.FileDialog;
import lime.ui.FileDialogFilter;
#end

using StringTools;

/**
 * Interactive substate displayed when a mod cannot be converted purely automatically
 * or when the user wants to associate an original executable (.exe) with a mod.
 * 
 * Extracts RTTI, Haxe classes, file routes, and engine version via REA,
 * saves the association to mods/_dbe_mod_executables.json, and re-converts the mod.
 */
class REAModExePromptSubState extends MusicBeatSubstate {
	var modName:String;
	var conversionReport:Null<Dynamic>;
	var onComplete:Null<Bool->Void>;

	var promptCam:FlxCamera;
	var bgBox:FlxSprite;
	var titleText:FlxText;
	var subtitleText:FlxText;
	var reasonText:FlxText;
	var instructionText:FlxText;
	var statusText:FlxText;
	var hintText:FlxText;

	var btnBrowse:FlxSprite;
	var btnBrowseText:FlxText;
	var btnPaste:FlxSprite;
	var btnPasteText:FlxText;
	var btnCancel:FlxSprite;
	var btnCancelText:FlxText;

	var isProcessing:Bool = false;
	var windowWidth:Int = 760;
	var windowHeight:Int = 470;

	public function new(modName:String, ?conversionReport:Dynamic, ?onComplete:Bool->Void) {
		super();
		this.modName = modName;
		this.conversionReport = conversionReport;
		this.onComplete = onComplete;
	}

	public override function create():Void {
		super.create();

		camera = promptCam = new FlxCamera();
		promptCam.bgColor = 0;
		promptCam.alpha = 0;
		FlxG.cameras.add(promptCam, false);

		// Dark backdrop
		var backdrop = new FlxSprite(0, 0).makeGraphic(FlxG.width, FlxG.height, 0xB8000000);
		backdrop.scrollFactor.set();
		add(backdrop);

		var boxX = (FlxG.width - windowWidth) / 2;
		var boxY = (FlxG.height - windowHeight) / 2;

		// Modal Outer Glow / Border
		var border = new FlxSprite(boxX - 3, boxY - 3).makeGraphic(windowWidth + 6, windowHeight + 6, 0xFF00B4D8);
		border.scrollFactor.set();
		add(border);

		// Modal Window Body
		bgBox = new FlxSprite(boxX, boxY).makeGraphic(windowWidth, windowHeight, 0xFF0F141C);
		bgBox.scrollFactor.set();
		add(bgBox);

		// Header Bar
		var headerBar = new FlxSprite(boxX, boxY).makeGraphic(windowWidth, 54, 0xFF182232);
		headerBar.scrollFactor.set();
		add(headerBar);

		// Title
		titleText = new FlxText(boxX + 20, boxY + 12, windowWidth - 40, "COMPATIBILIDADE REA - EXECUTAVEL ORIGINAL (.EXE)", 18);
		titleText.setFormat(Paths.font("vcr.ttf"), 18, 0xFF00E5FF, LEFT, FlxTextBorderStyle.OUTLINE, 0xFF003344);
		add(titleText);

		// Mod Subtitle
		subtitleText = new FlxText(boxX + 20, boxY + 62, windowWidth - 40, 'Mod: $modName', 16);
		subtitleText.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(subtitleText);

		// Reason / Incompatibility notice
		var reasonMsg = "A conversao automatica pura nao conseguiu mapear todas as classes e arquivos deste mod.";
		if (conversionReport != null) {
			var incomp:Array<Dynamic> = Reflect.field(conversionReport, "incompatibilities");
			if (incomp != null && incomp.length > 0) {
				reasonMsg = "Motivo detectado: " + incomp[0];
			}
		}
		reasonText = new FlxText(boxX + 20, boxY + 92, windowWidth - 40, reasonMsg, 13);
		reasonText.setFormat(Paths.font("vcr.ttf"), 13, 0xFFFFCC00, LEFT);
		reasonText.wordWrap = true;
		add(reasonText);

		// Detailed Instructions
		var inst = "Para que a engine execute este mod sem quebras, forneca o executavel (.exe) original\n"
			+ "onde o mod foi criado ou compilado (ex: PsychEngine.exe, Funkin.exe, ou o proprio .exe do mod).\n"
			+ "O REA ira extrair automaticamente os tipos RTTI, classes compiladas e rotas de arquivos necessarias.";
		instructionText = new FlxText(boxX + 20, boxY + 140, windowWidth - 40, inst, 13);
		instructionText.setFormat(Paths.font("vcr.ttf"), 13, 0xFFCCCCCC, LEFT);
		instructionText.wordWrap = true;
		add(instructionText);

		// Buttons
		var btnY = boxY + 235;

		// Browse Button [SPACE]
		btnBrowse = new FlxSprite(boxX + 30, btnY).makeGraphic(210, 48, 0xFF007ACC);
		add(btnBrowse);
		btnBrowseText = new FlxText(boxX + 30, btnY + 12, 210, "[ESPACO] Buscar .EXE", 13);
		btnBrowseText.setFormat(Paths.font("vcr.ttf"), 13, FlxColor.WHITE, CENTER);
		add(btnBrowseText);

		// Paste Button [CTRL+V]
		btnPaste = new FlxSprite(boxX + 265, btnY).makeGraphic(210, 48, 0xFF2D8A4E);
		add(btnPaste);
		btnPasteText = new FlxText(boxX + 265, btnY + 12, 210, "[Ctrl+V] Colar Caminho", 13);
		btnPasteText.setFormat(Paths.font("vcr.ttf"), 13, FlxColor.WHITE, CENTER);
		add(btnPasteText);

		// Cancel Button [ESC]
		btnCancel = new FlxSprite(boxX + 500, btnY).makeGraphic(220, 48, 0xFF5A2D2D);
		add(btnCancel);
		btnCancelText = new FlxText(boxX + 500, btnY + 12, 220, "[ESC] Ignorar / Voltar", 13);
		btnCancelText.setFormat(Paths.font("vcr.ttf"), 13, FlxColor.WHITE, CENTER);
		add(btnCancelText);

		// Drop hint
		hintText = new FlxText(boxX + 20, boxY + 310, windowWidth - 40, "Dica: Voce tambem pode ARRASTAR E SOLTAR (Drag & Drop) o arquivo .exe diretamente nesta janela!", 12);
		hintText.setFormat(Paths.font("vcr.ttf"), 12, 0xFF88AAFF, CENTER);
		add(hintText);

		// Status Box
		var statusBg = new FlxSprite(boxX + 20, boxY + 350).makeGraphic(windowWidth - 40, 80, 0xFF141A24);
		add(statusBg);

		var associated = REARuntimeBridge.getAssociatedExecutable(modName);
		var initialStatus = associated != null ? 'Executavel atualmente associado: $associated' : "Aguardando selecao do executavel (.exe)...";

		statusText = new FlxText(boxX + 30, boxY + 360, windowWidth - 60, initialStatus, 13);
		statusText.setFormat(Paths.font("vcr.ttf"), 13, 0xFF00FFCC, LEFT);
		statusText.wordWrap = true;
		add(statusText);

		// Register Drag & Drop listener
		#if lime
		try {
			if (FlxG.stage != null && FlxG.stage.window != null) {
				FlxG.stage.window.onDropFile.add(onFileDropped);
			}
		} catch (_:Dynamic) {}
		#end

		FlxTween.tween(promptCam, {alpha: 1}, 0.25, {ease: FlxEase.cubeOut});
		CoolUtil.playMenuSFX(WARNING);
	}

	override function destroy():Void {
		#if lime
		try {
			if (FlxG.stage != null && FlxG.stage.window != null) {
				FlxG.stage.window.onDropFile.remove(onFileDropped);
			}
		} catch (_:Dynamic) {}
		#end

		if (promptCam != null) {
			FlxG.cameras.remove(promptCam, true);
			promptCam = null;
		}

		super.destroy();
	}

	function onFileDropped(droppedPath:String, type:String, x:Float, y:Float):Void {
		if (isProcessing) return;
		if (droppedPath == null || droppedPath.trim() == "") return;
		var clean = droppedPath.trim().replace('"', '');
		processExecutable(clean);
	}

	public override function update(elapsed:Float):Void {
		super.update(elapsed);

		if (isProcessing) return;

		// Mouse button clicks
		if (FlxG.mouse.justPressed) {
			if (FlxG.mouse.overlaps(btnBrowse, promptCam)) {
				browseExecutable();
				return;
			}
			if (FlxG.mouse.overlaps(btnPaste, promptCam)) {
				pasteClipboardPath();
				return;
			}
			if (FlxG.mouse.overlaps(btnCancel, promptCam)) {
				cancelAndClose();
				return;
			}
		}

		// Keyboard controls
		if (FlxG.keys.justPressed.SPACE || FlxG.keys.justPressed.ENTER) {
			browseExecutable();
		} else if (FlxG.keys.pressed.CONTROL && FlxG.keys.justPressed.V) {
			pasteClipboardPath();
		} else if (FlxG.keys.justPressed.ESCAPE || FlxG.keys.justPressed.BACKSPACE) {
			cancelAndClose();
		}
	}

	function browseExecutable():Void {
		statusText.color = 0xFF00FFCC;
		statusText.text = "Abrindo seletor de arquivos...";

		var opened = false;
		#if lime
		try {
			var win = (FlxG.stage != null && FlxG.stage.window != null) ? FlxG.stage.window : lime.app.Application.current.window;
			FileDialog.openFile(win, "Selecionar Executavel Original (.exe) do Mod", function(files:Array<String>, activeFilter:FileDialogFilter) {
				if (files != null && files.length > 0 && files[0] != null && files[0] != "") {
					processExecutable(files[0]);
				} else {
					statusText.text = "Selecao de arquivo cancelada.";
				}
			}, [
				new FileDialogFilter("Arquivos Executaveis (*.exe)", "exe"),
				new FileDialogFilter("Todos os Arquivos (*.*)", "*")
			]);
			opened = true;
		} catch (_:Dynamic) {
			opened = false;
		}
		#end

		#if windows
		if (!opened) {
			var picked = openWindowsNativeFileDialog();
			if (picked != null) {
				processExecutable(picked);
			} else {
				statusText.text = "Selecao de executavel cancelada.";
			}
		}
		#end
	}

	#if windows
	static function openWindowsNativeFileDialog():Null<String> {
		try {
			var script = "Add-Type -AssemblyName System.Windows.Forms; $f = New-Object System.Windows.Forms.OpenFileDialog; $f.Filter = 'Executable Files (*.exe)|*.exe|All Files (*.*)|*.*'; $f.Title = 'Selecionar Executavel Original do Mod (.exe)'; if($f.ShowDialog() -eq 'OK'){ [Console]::Out.WriteLine($f.FileName) }";
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
			statusText.color = 0xFFFFCC00;
			statusText.text = "A area de transferencia esta vazia.";
			return;
		}

		var clean = text.trim().replace('"', '');
		processExecutable(clean);
	}

	function processExecutable(candidatePath:String):Void {
		if (candidatePath == null || candidatePath == "") return;
		var norm = Path.normalize(candidatePath.replace("\\", "/"));

		if (!FileSystem.exists(norm)) {
			statusText.color = 0xFFFF4444;
			statusText.text = 'Arquivo nao encontrado: $candidatePath';
			return;
		}

		if (FileSystem.isDirectory(norm)) {
			// Check if folder contains an .exe
			var companion = REARuntimeBridge.findCompanionExecutable(norm);
			if (companion != null) {
				norm = companion;
			} else {
				statusText.color = 0xFFFF4444;
				statusText.text = 'O caminho selecionado e uma pasta e nao contem nenhum .exe: $norm';
				return;
			}
		}

		if (Path.extension(norm).toLowerCase() != "exe") {
			statusText.color = 0xFFFF4444;
			statusText.text = 'O arquivo selecionado nao e um executavel (.exe): ' + Path.withoutDirectory(norm);
			return;
		}

		isProcessing = true;
		statusText.color = 0xFF00FFCC;
		statusText.text = 'Analisando executavel com REA: ' + Path.withoutDirectory(norm) + '...';

		new FlxTimer().start(0.05, function(_) {
			try {
				// 1. Analyze target with REA
				var analysis = REAModAnalyzer.analyzeTarget(norm);

				// 2. Learn classes, routes and version
				var rulesLearned = REARuntimeBridge.learnFromAnalysis(analysis);

				// 3. Persist association to mods/_dbe_mod_executables.json and AppData
				REARuntimeBridge.setAssociatedExecutable(modName, norm);
				var engName = (analysis.primaryEngine != null && analysis.primaryEngine != "Unknown") ? analysis.primaryEngine : haxe.io.Path.withoutDirectory(norm);
				var verHint = (analysis.binaryAnalysis != null && analysis.binaryAnalysis.versionHint != null) ? analysis.binaryAnalysis.versionHint : "1.0";
				READecodedEnginesManager.registerDecodedEngine(engName, analysis.primaryEngine, verHint, norm, REARuntimeBridge.activeProfile);
				READecodedEnginesManager.setEngineForMod(modName, engName.toLowerCase().replace(" ", "-"));

				statusText.text = 'Aprendidas $rulesLearned regras do executavel! Reconvertendo mod...';

				// 4. Clear cache and re-run conversion
				var modPath = ModsFolder.modsPath + modName;
				try {
					RuntimeModConverter.clearCacheForSource(modPath);
				} catch (_:Dynamic) {}

				var result = RuntimeModConverter.prepare(modPath, RuntimeModConverter.defaultManagedRoot());

				if (result != null && result.blocked != true) {
					statusText.color = 0xFF00FF88;
					statusText.text = 'SUCESSO! O mod foi adaptado com as regras do executavel original. Carregando...';
					CoolUtil.playMenuSFX(CONFIRM);

					new FlxTimer().start(0.7, function(_) {
						close();
						if (onComplete != null) onComplete(true);
					});
				} else {
					isProcessing = false;
					statusText.color = 0xFFFF4444;
					var details = "";
					if (result != null && result.report != null) {
						var incomp:Array<Dynamic> = Reflect.field(result.report, "incompatibilities");
						if (incomp != null && incomp.length > 0) details = ": " + incomp.join("; ");
					}
					statusText.text = 'A conversao ainda encontrou problemas' + details;
				}
			} catch (e:Dynamic) {
				isProcessing = false;
				statusText.color = 0xFFFF4444;
				statusText.text = 'Erro ao processar executavel: ' + Std.string(e);
			}
		});
	}

	function cancelAndClose():Void {
		close();
		if (onComplete != null) onComplete(false);
	}
}
#end
