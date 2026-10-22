package funkin.menus;

import flixel.sound.FlxSound;
import funkin.backend.FunkinText;
import funkin.backend.assets.SongLoadRequest;
import funkin.backend.assets.SongLoader;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import funkin.backend.FunkinText;
import funkin.backend.scripting.Script;
import funkin.backend.scripting.events.NameEvent;
import funkin.backend.scripting.events.menu.MenuChangeEvent;
import funkin.backend.scripting.events.menu.pause.*;
import funkin.backend.system.Conductor;
import funkin.backend.utils.FunkinParentDisabler;
import funkin.backend.utils.FunkinParentDisabler.ParentDisableable;
import funkin.editors.charter.Charter;
import funkin.menus.StoryMenuState;
import funkin.options.OptionsMenu;
import funkin.options.keybinds.KeybindsOptions;

class PauseSubState extends MusicBeatSubstate
{
	public static var script:String = Flags.DEFAULT_PAUSE_SCRIPT;

	var grpMenuShit:FlxTypedGroup<Alphabet>;

	var levelInfo:FunkinText;
	var levelDifficulty:FunkinText;
	var deathCounter:FunkinText;
	var multiplayerText:FunkinText;

	var parentDisablerExcludeList:Array<ParentDisableable>;
	var menuItems:Array<String>;

	var curSelected:Int = 0;

	var pauseMusic:FlxSound;

	public var pauseScript:Script;
	public var selectCall:NameEvent->Void;  // Mainly for extern stuff that aren't scripts  - Nex

	public var game:PlayState = PlayState.instance; // shortcut

	private var __cancelDefault:Bool = false;
	private var skipTimeSelected:Float = 0;
	private var songLength:Float = 0;
	private var hasChangedSkipTime:Bool = false;

	public function new(?items:Array<String>, ?selectCall:NameEvent->Void, ?excludeList:Array<ParentDisableable>) {
		super();

		parentDisablerExcludeList = excludeList != null ? excludeList : [];
		menuItems = items != null ? items : Flags.DEFAULT_PAUSE_ITEMS.copy();
		this.selectCall = selectCall;
	}

	var parentDisabler:FunkinParentDisabler;
	override function create()
	{
		super.create();

		songLength = (game != null && game.inst != null && game.inst.length > 0) ? game.inst.length : (FlxG.sound.music != null ? FlxG.sound.music.length : 0);
		skipTimeSelected = Conductor.songPosition > 0 ? Conductor.songPosition : 0;

		if (menuItems.contains("Exit to charter") && !PlayState.chartingMode)
			menuItems.remove("Exit to charter");

		add(parentDisabler = new FunkinParentDisabler(parentDisablerExcludeList));

		pauseScript = Script.create(Paths.script(script));
		pauseScript.setParent(this);
		pauseScript.load();

		var event = EventManager.get(PauseCreationEvent).recycle(Flags.DEFAULT_PAUSE_MENU_MUSIC, menuItems);
		pauseScript.call('create', [event]);

		menuItems = event.options;

		if (Assets.exists(Paths.music(event.music))) {
			pauseMusic = FlxG.sound.load(Assets.getMusic(Paths.music(event.music)), 0, true);
			pauseMusic.persist = false;
			pauseMusic.group = FlxG.sound.defaultMusicGroup;
			pauseMusic.play(false, FlxG.random.int(0, Std.int(pauseMusic.length / 2)));
		}

		if (__cancelDefault = event.cancelled) return;

		var bg:FlxSprite = new FlxSprite().makeSolid(FlxG.width + 100, FlxG.height + 100, FlxColor.BLACK);
		bg.updateHitbox();
		bg.alpha = 0;
		bg.screenCenter();
		bg.scrollFactor.set();
		add(bg);

		var multiplayerInfo:String = PlayState.opponentMode ? 'pause.opponentMode' :
									 PlayState.coopMode ? 'pause.coopMode' :
									 null;

		levelInfo = new FunkinText(20, 15, 0, PlayState.SONG.meta.displayName, 32, false);
		levelDifficulty = new FunkinText(20, 15, 0, TU.translateDiff(PlayState.difficulty).toUpperCase(), 32, false);
		deathCounter = new FunkinText(20, 15, 0, TU.translate("pause.deathCounter", [PlayState.deathCounter]), 32, false);
		multiplayerText = null;
		if(multiplayerInfo != null)
			multiplayerText = new FunkinText(20, 15, 0, TU.translate(multiplayerInfo), 32, false);

		for(k=>label in [levelInfo, levelDifficulty, deathCounter, multiplayerText]) {
			if(label == null) continue;
			label.scrollFactor.set();
			label.alpha = 0;
			label.x = FlxG.width - (label.width + 20);
			label.y = 15 + (32 * k);
			FlxTween.tween(label, {alpha: 1, y: label.y + 5}, 0.4, {ease: FlxEase.quartInOut, startDelay: 0.3 * (k+1)});
			add(label);
		}

		FlxTween.tween(bg, {alpha: 0.6}, 0.4, {ease: FlxEase.quartInOut});

		grpMenuShit = new FlxTypedGroup<Alphabet>();
		add(grpMenuShit);

		for (i in 0...menuItems.length)
		{
			var pauseId = "pause." + TU.raw2Id(menuItems[i]);
			var songText:Alphabet = new Alphabet(0, (70 * i) + 30, TU.translate(pauseId, null, menuItems[i]), "bold");
			songText.isMenuItem = true;
			songText.targetY = i;
			grpMenuShit.add(songText);
		}

		changeSelection();

		camera = new FlxCamera();
		camera.bgColor = 0;
		FlxG.cameras.add(camera, false);
	}

	override function createPost() {
		super.createPost();
		pauseScript.call("postCreate");
		if (game != null) game.updateDiscordPresence();
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (pauseMusic != null && pauseMusic.volume < 0.5)
			pauseMusic.volume += 0.01 * elapsed;

		pauseScript.call("update", [elapsed]);

		if (__cancelDefault) return;

		var upP = controls.UP_P;
		var downP = controls.DOWN_P;
		var scroll = FlxG.mouse.wheel;

		if (upP || downP || scroll != 0)  // like this we wont break mods that expect a 0 change event when calling sometimes  - Nex
			changeSelection((upP ? -1 : 0) + (downP ? 1 : 0) - scroll);

		if (menuItems[curSelected] == "Skip Time")
		{
			var left = controls.LEFT_P;
			var right = controls.RIGHT_P;
			if (left || right)
			{
				hasChangedSkipTime = true;
				var step:Float = FlxG.keys.pressed.SHIFT ? 20000 : 5000;
				if (left) skipTimeSelected -= step;
				if (right) skipTimeSelected += step;

				if (skipTimeSelected < 0) skipTimeSelected = 0;
				if (songLength > 0 && skipTimeSelected > songLength - 1000)
					skipTimeSelected = songLength - 1000;

				FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
				updateSkipTimeLabel();
			}
		}

		if (controls.ACCEPT)
			selectOption();
	}

	public function selectOption() {
		var event = EventManager.get(NameEvent).recycle(menuItems[curSelected]);
		if (selectCall != null) selectCall(event);
		pauseScript.call("onSelectOption", [event]);
		if (event.cancelled) return;

		switch (event.name)
		{
			case "Resume":
				close();
			case "Skip Time":
				var target = skipTimeSelected;
				if (!hasChangedSkipTime) {
					if (Conductor.songPosition <= 0) {
						var firstNote = game.getFirstNoteTime();
						target = firstNote > 2000 ? (firstNote - 1200) : 5000;
					} else {
						target += 5000;
					}
				}

				if (target < Conductor.songPosition) {
					// Ao retroceder, reinicia o estado do zero e salta até o target
					// (exatamente como a Psych Engine faz), garantindo que personagens,
					// eventos, estágios, shaders e variáveis voltem ao estado correto daquele instante!
					PlayState.startOnTime = target <= 100 ? 0 : target;
					parentDisabler.reset();
					game.registerSmoothTransition();
					var request = SongLoadRequest.fromPlayState("retry");
					SongLoader.start(request, () -> PlayState.SONG);
					return;
				}

				game.skipTime(target);
				close();
			case "Restart Song":
				parentDisabler.reset();
				game.registerSmoothTransition();
				var request = SongLoadRequest.fromPlayState("retry");
				SongLoader.start(request, () -> PlayState.SONG);
			case "Change Controls":
				persistentDraw = false;
				openSubState(new KeybindsOptions());
			case "Change Options":
				var request = SongLoadRequest.fromPlayState("optionsReturn");
				FlxG.switchState(new OptionsMenu((_) -> {
					SongLoader.start(request, () -> PlayState.SONG);
				}));
			case "Exit to charter":
				FlxG.switchState(new Charter(PlayState.SONG.meta.name, PlayState.difficulty, PlayState.variation, false));
			case "Exit to menu":
				if (PlayState.chartingMode && Charter.undos.unsaved)
					game.saveWarn(false);
				else {
					if (Charter.instance != null) Charter.instance.__clearStatics();

					// prevents certain notes to disappear early when exiting  - Nex
					game.strumLines.forEachAlive(function(grp) grp.notes.__forcedSongPos = Conductor.songPosition);

					CoolUtil.playMenuSong();
					FlxG.switchState(PlayState.isStoryMode ? new StoryMenuState() : new FreeplayState());
				}

		}
	}
	override function destroy()
	{
		if(camera != FlxG.camera && _cameras != null) {
			if(FlxG.cameras.list.contains(camera))
				FlxG.cameras.remove(camera, true);
		}
		pauseScript.call("destroy");
		pauseScript.destroy();

		if(pauseMusic != null) {
			@:privateAccess
			FlxG.sound.destroySound(pauseMusic);
		}
		super.destroy();
	}

	function changeSelection(change:Int = 0):Void
	{
		var event = EventManager.get(MenuChangeEvent).recycle(curSelected, FlxMath.wrap(curSelected + change, 0, menuItems.length-1), change, change != 0);
		pauseScript.call("onChangeItem", [event]);
		if (event.cancelled) return;

		curSelected = event.value;

		for (i=>item in grpMenuShit.members)
		{
			item.targetY = i - curSelected;

			item.alpha = (item.targetY == 0) ? 1 : 0.6;
		}

		updateSkipTimeLabel();
	}

	private function formatTime(ms:Float):String {
		if (ms < 0) ms = 0;
		var totalSeconds = Math.floor(ms / 1000);
		var minutes = Math.floor(totalSeconds / 60);
		var seconds = totalSeconds % 60;
		var secStr = seconds < 10 ? "0" + seconds : "" + seconds;
		var minStr = minutes < 10 ? "0" + minutes : "" + minutes;
		return '$minStr:$secStr';
	}

	private function updateSkipTimeLabel():Void {
		var idx = menuItems.indexOf("Skip Time");
		if (idx != -1 && grpMenuShit != null && idx < grpMenuShit.members.length) {
			var item = grpMenuShit.members[idx];
			if (item != null) {
				var baseText = TU.translate("pause.skipTime", null, "Skip Time");
				if (curSelected == idx) {
					item.text = '< $baseText: ${formatTime(skipTimeSelected)} / ${formatTime(songLength)} >';
				} else {
					item.text = baseText;
				}
			}
		}
	}
}
