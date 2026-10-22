package dbe.compatibility.rea;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxSubState;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import funkin.backend.MusicBeatSubstate;
import funkin.backend.assets.ModsFolder;
import funkin.backend.assets.Paths;
import funkin.backend.FunkinText;
import funkin.backend.utils.CoolUtil;

using StringTools;

/**
 * Screen displayed immediately after decoding/transforming an engine with REA.
 * Asks the user which mod to attach and load with the newly decoded engine rules.
 */
class REAModSelectTargetSubState extends MusicBeatSubstate {
	var engineName:String;
	var engineId:String;
	var onComplete:Null<String->Void>;

	var bg:FlxSprite;
	var box:FlxSprite;
	var titleText:FlxText;
	var subtitleText:FlxText;
	var questionText:FlxText;
	var footerHint:FlxText;

	var modList:Array<String> = [];
	var modTexts:FlxTypedGroup<FlxText>;
	var curSelected:Int = 0;

	public function new(engineName:String, ?engineId:String, ?onComplete:String->Void) {
		super();
		this.engineName = engineName != null ? engineName : "Engine Desconhecida";
		this.engineId = engineId != null ? engineId : this.engineName.toLowerCase().replace(" ", "-");
		this.onComplete = onComplete;
	}

	override function create():Void {
		super.create();

		// Dim background
		bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0xFF000000);
		bg.alpha = 0;
		add(bg);
		FlxTween.tween(bg, {alpha: 0.75}, 0.25, {ease: FlxEase.cubeOut});

		var winW = 860;
		var winH = 540;
		var winX = (FlxG.width - winW) / 2;
		var winY = (FlxG.height - winH) / 2;

		// Main Panel
		box = new FlxSprite(winX, winY).makeGraphic(winW, winH, 0xFF141824);
		box.alpha = 0;
		add(box);
		FlxTween.tween(box, {alpha: 1.0}, 0.25, {ease: FlxEase.cubeOut});

		// Header border line
		var headerBar = new FlxSprite(winX, winY).makeGraphic(winW, 4, 0xFF00FFCC);
		add(headerBar);

		// Title
		titleText = new FlxText(winX + 20, winY + 16, winW - 40, 'ENGINE DECODIFICADA: $engineName', 22);
		titleText.setFormat(Paths.font("vcr.ttf"), 22, 0xFF00FFCC, CENTER);
		add(titleText);

		// Subtitle
		subtitleText = new FlxText(winX + 20, winY + 48, winW - 40, "As classes, rotas de arquivos e regras da engine foram salvas no AppData!", 14);
		subtitleText.setFormat(Paths.font("vcr.ttf"), 14, 0xFF88AAFF, CENTER);
		add(subtitleText);

		// Prompt Question
		questionText = new FlxText(winX + 20, winY + 80, winW - 40, "Em qual mod voce deseja carregar esta engine agora?", 18);
		questionText.setFormat(Paths.font("vcr.ttf"), 18, 0xFFFFDD44, CENTER);
		add(questionText);

		// Mod list background container
		var listBg = new FlxSprite(winX + 40, winY + 120).makeGraphic(winW - 80, 330, 0xFF0A0D14);
		add(listBg);

		// Populate available mods
		var rawMods = ModsFolder.getModsList({
			descending: false,
			mode: CLEAN
		});
		modList = [];
		for (m in rawMods) {
			if (m != null && m.trim() != "") modList.push(m);
		}

		modTexts = new FlxTypedGroup<FlxText>();
		add(modTexts);

		if (modList.length == 0) {
			var emptyTxt = new FlxText(winX + 60, winY + 240, winW - 120, "Nenhum mod encontrado na pasta mods/. Pressione [ESC] para continuar.", 16);
			emptyTxt.setFormat(Paths.font("vcr.ttf"), 16, 0xFF888888, CENTER);
			add(emptyTxt);
		} else {
			for (i in 0...modList.length) {
				var t = new FlxText(winX + 60, winY + 140 + (i * 32), winW - 120, modList[i], 18);
				t.setFormat(Paths.font("vcr.ttf"), 18, FlxColor.WHITE, LEFT);
				modTexts.add(t);
			}
		}

		// Footer Hints
		footerHint = new FlxText(winX + 20, winY + winH - 45, winW - 40, "[CIMA / BAIXO] Selecionar Mod   |   [ENTER] Vincular e Carregar Agora   |   [ESC] Salvar apenas", 13);
		footerHint.setFormat(Paths.font("vcr.ttf"), 13, 0xFF888888, CENTER);
		add(footerHint);

		updateSelection();
	}

	function updateSelection(change:Int = 0):Void {
		if (modList.length == 0) return;

		curSelected += change;
		if (curSelected < 0) curSelected = modList.length - 1;
		if (curSelected >= modList.length) curSelected = 0;

		var winX = (FlxG.width - 860) / 2;
		var winY = (FlxG.height - 540) / 2;
		var startY = winY + 135;

		var visibleSlots = 8;
		var scrollOffset = Std.int(Math.max(0, curSelected - Std.int(visibleSlots / 2)));
		if (scrollOffset > modList.length - visibleSlots) {
			scrollOffset = Std.int(Math.max(0, modList.length - visibleSlots));
		}

		for (i in 0...modTexts.members.length) {
			var txt = modTexts.members[i];
			var slot = i - scrollOffset;

			if (slot >= 0 && slot < visibleSlots) {
				txt.visible = true;
				txt.y = startY + (slot * 38);
				if (i == curSelected) {
					txt.text = '>  ' + modList[i] + '   [VINCULAR A ' + engineName.toUpperCase() + ']';
					txt.color = 0xFF00FFCC;
					txt.alpha = 1.0;
				} else {
					txt.text = '   ' + modList[i];
					txt.color = FlxColor.WHITE;
					txt.alpha = 0.6;
				}
			} else {
				txt.visible = false;
			}
		}

		if (change != 0) {
			CoolUtil.playMenuSFX(SCROLL, 0.7);
		}
	}

	override function update(elapsed:Float):Void {
		super.update(elapsed);

		if (controls.UP_P || (FlxG.mouse.wheel > 0)) {
			updateSelection(-1);
		} else if (controls.DOWN_P || (FlxG.mouse.wheel < 0)) {
			updateSelection(1);
		}

		if (controls.ACCEPT && modList.length > 0) {
			var chosenMod = modList[curSelected];
			CoolUtil.playMenuSFX(CONFIRM);

			// Link the decoded engine to this mod in AppData
			READecodedEnginesManager.setEngineForMod(chosenMod, engineId);

			close();
			if (onComplete != null) {
				onComplete(chosenMod);
			} else {
				// Switch directly to the selected mod!
				ModsFolder.switchMod(chosenMod);
			}
		}

		if (controls.BACK) {
			CoolUtil.playMenuSFX(CANCEL);
			close();
			if (onComplete != null) {
				onComplete(null);
			}
		}
	}
}
