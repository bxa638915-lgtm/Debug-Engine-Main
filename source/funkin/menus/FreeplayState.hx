package funkin.menus;

import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import dbe.compatibility.chart.VSliceChartCodec;
import funkin.backend.chart.Chart;
import funkin.backend.chart.ChartData.ChartMetaData;
import funkin.backend.chart.VSliceParser;
import funkin.backend.scripting.events.menu.MenuChangeEvent;
import funkin.backend.scripting.events.menu.freeplay.*;
import funkin.backend.system.Conductor;
import funkin.game.HealthIcon;
import funkin.savedata.FunkinSave;
import haxe.Json;

using StringTools;

class FreeplayState extends MusicBeatState
{
	/**
	 * Array containing all of the songs' metadata.
	 */
	public var songs:Array<ChartMetaData> = [];

	/**
	 * Current song metadata
	 */
	public var curSong:Null<ChartMetaData>;

	/**
	 * Current song difficulties
	 */
	public var curDifficulties:Array<String>;

	/**
	 * songs[curSelected].metas.get(curDiffMetaIndices[curDifficulty])
	 */
	public var curDiffMetaKeys:Array<String> = [];

	/**
	 * Currently selected song
	 */
	public var curSelected:Int = 0;
	/**
	 * Currently selected difficulty
	 */
	public var curDifficulty:Int = 1;
	/**
	 * Currently selected coop/opponent mode
	 */
	public var curCoopMode:Int = 0;

	/**
	 * Text containing the score info (PERSONAL BEST: 0)
	 */
	public var scoreText:FlxText;

	/**
	 * Text containing the current difficulty (< HARD >)
	 */
	public var diffText:FlxText;

	/**
	 * Text containing the current coop/opponent mode ([KEYBINDS] Co-Op mode)
	 */
	public var coopText:FlxText;

	/**
	 * Currently lerped score. Is updated to go towards `intendedScore`.
	 */
	public var lerpScore:Float = 0;
	/**
	 * Destination for the currently lerped score.
	 */
	public var intendedScore:Int = 0;

	/**
	 * Assigned FreeplaySonglist item.
	 */
	public var songList:FreeplaySonglist;
	/**
	 * Black background around the score, the difficulty text and the co-op text.
	 */
	public var scoreBG:FlxSprite;

	/**
	 * Background.
	 */
	public var bg:FlxSprite;
	public var albumArt:FlxSprite;
	public var artistText:FlxText;
	public var albumText:FlxText;
	public var ostText:FlxText;
	public var charactersText:FlxText;
	public var ratingText:FlxText;
	public var progressText:FlxText;
	private var previewSongName:String = null;
	private var previewStartTime:Float = 0;
	private var previewEndTime:Float = 0;
	private var previewRequestId:Int = 0;
	private var vSlicePreviewTransitioning:Bool = false;
	private var currentAlbumArtAsset:String = null;
	private var freeplayCharacterChoices:Array<String> = [];
	public static var rememberedVSliceCharacter:Null<String> = null;

	/**
	 * Whenever the player can navigate and select
	 */
	public var canSelect:Bool = true;

	/**
	 * Group containing all of the alphabets
	 */
	public var grpSongs:FlxTypedGroup<Alphabet>;
	private var vSliceCapsules:Array<Null<FlxSprite>> = [];

	/**
	 * Whenever the currently selected song is playing.
	 */
	public var curPlaying:Bool = false;

	/**
	 * Array containing all of the icons.
	 */
	public var iconArray:Array<HealthIcon> = [];

	/**
	 * FlxInterpolateColor object for smooth transition between Freeplay colors.
	 */
	public var interpColor:FlxInterpolateColor;


	override function create()
	{
		CoolUtil.playMenuSong();
		songList = FreeplaySonglist.get();
		songs = songList.songs;
		freeplayCharacterChoices = [];
		for (song in songs) {
			if (song.customValues == null || Reflect.field(song.customValues, "album") == null) continue;
			var characters:Dynamic = song.customValues == null ? null : Reflect.field(song.customValues, "characters");
			var player:Dynamic = characters == null ? null : Reflect.field(characters, "player");
			if (Std.isOfType(player, String) && !freeplayCharacterChoices.contains(cast player)) freeplayCharacterChoices.push(cast player);
		}
		if (rememberedVSliceCharacter == null && freeplayCharacterChoices.length > 0)
			rememberedVSliceCharacter = freeplayCharacterChoices[0];
		VSliceParser.freeplayCharacterOverride = rememberedVSliceCharacter;

		for(k=>s in songs) {
			if (s.name == Options.freeplayLastSong) {
				curSelected = k;
			}
		}

		updateCurDifficulties();
		for(i=>diff in curDifficulties) {
			if (curDiffMetaKeys[i] == Options.freeplayLastVariation && diff == Options.freeplayLastDifficulty)
				curDifficulty = i;
		}

		updateCurSong();

		DiscordUtil.call("onMenuLoaded", ["Freeplay"]);

		super.create();

		// LOAD CHARACTERS

		bg = new FlxSprite(0, 0).loadAnimatedGraphic(Paths.image('menus/menuDesat'));
		if (songs.length > 0)
			bg.color = songs[0].color;
		bg.antialiasing = true;
		add(bg);

		albumArt = new FlxSprite(FlxG.width - 268, 110);
		albumArt.visible = false;
		add(albumArt);
		artistText = new FlxText(FlxG.width - 280, 348, 270, "", 18);
		artistText.setFormat(Paths.font("vcr.ttf"), 18, FlxColor.WHITE, CENTER);
		add(artistText);
		albumText = new FlxText(FlxG.width - 280, 372, 270, "", 16);
		albumText.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, CENTER);
		add(albumText);
		ostText = new FlxText(FlxG.width - 280, 394, 270, "", 14);
		ostText.setFormat(Paths.font("vcr.ttf"), 14, FlxColor.WHITE, CENTER);
		add(ostText);
		charactersText = new FlxText(FlxG.width - 280, 416, 270, "", 14);
		charactersText.setFormat(Paths.font("vcr.ttf"), 14, FlxColor.WHITE, CENTER);
		add(charactersText);
		ratingText = new FlxText(FlxG.width - 280, 438, 270, "", 14);
		ratingText.setFormat(Paths.font("vcr.ttf"), 14, FlxColor.WHITE, CENTER);
		add(ratingText);
		progressText = new FlxText(FlxG.width - 280, 460, 270, "", 12);
		progressText.setFormat(Paths.font("vcr.ttf"), 12, FlxColor.WHITE, CENTER);
		add(progressText);

		// Use the V-Slice capsule atlas for V-Slice songs, with a simple panel fallback when the optional assets are not mounted.
		vSliceCapsules = [];
		for (song in songs) {
			if (song.customValues == null || Reflect.field(song.customValues, "album") == null) {
				vSliceCapsules.push(null);
				continue;
			}
			var capsule = new FlxSprite();
			try {
				capsule.frames = Paths.getSparrowAtlas("freeplay/freeplayCapsule/capsule/freeplayCapsule");
				capsule.animation.addByPrefix("selected", "mp3 capsule w backing0", 24, true);
				capsule.animation.addByPrefix("unselected", "mp3 capsule w backing NOT SELECTED", 24, true);
				capsule.animation.play("unselected", true);
				capsule.scale.set(0.68, 0.68);
				capsule.updateHitbox();
			} catch (_:Dynamic) {
				capsule.makeGraphic(580, 108, 0xCC171729);
				capsule.scale.set(0.68, 0.68);
				capsule.updateHitbox();
			}
			capsule.alpha = 0.35;
			vSliceCapsules.push(capsule);
			add(capsule);
		}

		grpSongs = new FlxTypedGroup<Alphabet>();
		add(grpSongs);

		for (i in 0...songs.length)
		{
			var songText:Alphabet = new Alphabet(0, (70 * i) + 30, songs[i].displayName, "bold");
			songText.isMenuItem = true;
			songText.targetY = i;
			grpSongs.add(songText);

			var icon:HealthIcon = new HealthIcon(songs[i].icon);
			icon.sprTracker = songText;
			if (Math.max(icon.width, icon.height) > 150) icon.setUnstretchedGraphicSize(150, 150);

			// using a FlxGroup is too much fuss!
			iconArray.push(icon);
			add(icon);

			// songText.x += 40;
			// DON'T PUT X IN THE FIRST PARAMETER OF new ALPHABET() !!
			// songText.screenCenter(X);
		}

		scoreText = new FlxText(FlxG.width * 0.7, 5, 0, "", 32);
		scoreText.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, RIGHT);

		scoreBG = new FlxSprite(scoreText.x - 6, 0).makeGraphic(1, 1, 0xFF000000);
		scoreBG.alpha = 0.6;
		add(scoreBG);

		diffText = new FlxText(scoreText.x, scoreText.y + 36, 0, "", 24);
		diffText.font = scoreText.font;
		add(diffText);

		coopText = new FlxText(diffText.x, diffText.y + diffText.height + 2, 0, "", 24);
		coopText.font = scoreText.font;
		add(coopText);

		add(scoreText);

		changeSelection(0, true);
		changeCoopMode(0, true);

		interpColor = new FlxInterpolateColor(bg.color);
		updateVSlicePresentation();
		startVSlicePreview();
	}

	private var TEXT_FREEPLAY_SCORE = TU.getRaw("freeplay.score");

	override function update(elapsed:Float)
	{
		super.update(elapsed);
		updateVSliceCapsules();

		if (!vSlicePreviewTransitioning && previewSongName == null && FlxG.sound.music != null && FlxG.sound.music.volume < 0.7)
		{
			FlxG.sound.music.volume += 0.5 * elapsed;
		}

		lerpScore = lerp(lerpScore, intendedScore, 0.4);
		updateVSlicePreviewLoop();

		if (Math.abs(lerpScore - intendedScore) <= 10)
			lerpScore = intendedScore;

		var selectedAnotherSong:Bool = false;
		if (canSelect) {
			changeSelection((controls.UP_P ? -1 : 0) + (controls.DOWN_P ? 1 : 0) - FlxG.mouse.wheel);
			changeDiff((controls.LEFT_P ? -1 : 0) + (controls.RIGHT_P ? 1 : 0));
			changeCoopMode((controls.CHANGE_MODE ? 1 : 0)); // TODO: make this configurable
			if (FlxG.keys.justPressed.Q) cycleVSliceCharacter(-1);
			if (FlxG.keys.justPressed.E) cycleVSliceCharacter(1);
			// putting it before so that its actually smooth

			if (FlxG.mouse.justPressed && grpSongs != null) {
				for (index => sprite in grpSongs.members) {
					if (curSelected != index && FlxG.mouse.overlaps(sprite)) {
						changeSelection(index - curSelected);
						selectedAnotherSong = true;
						break;
					}
				}
			}

			updateOptionsAlpha();
		}

		scoreText.text = TEXT_FREEPLAY_SCORE.format([Math.round(lerpScore)]);
		scoreBG.scale.set(MathUtil.maxSmart(diffText.width, scoreText.width, coopText.width) + 8, (coopText.visible ? coopText.y + coopText.height : 66));
		scoreBG.updateHitbox();
		scoreBG.x = FlxG.width - scoreBG.width;

		scoreText.x = coopText.x = scoreBG.x + 4;
		diffText.x = Std.int(scoreBG.x + ((scoreBG.width - diffText.width) / 2));

		interpColor.fpsLerpTo(curSong.color, 0.0625);
		bg.color = interpColor.color;

		if (controls.BACK || FlxG.mouse.justPressedRight)
		{
			cancelVSlicePreview();
			CoolUtil.playMenuSFX(CANCEL, 0.7);
			FlxG.switchState(new MainMenuState());
		}

		#if sys
		if (FlxG.keys.justPressed.EIGHT && Sys.args().contains("-livereload"))
			convertChart();
		#end

		if ((controls.ACCEPT || (!selectedAnotherSong && FlxG.mouse.justPressed && grpSongs?.members[curSelected] != null
			&& FlxG.mouse.overlaps(grpSongs.members[curSelected]))))
		{
			select();
		}
	}

	/** Keep the optional V-Slice capsule animations aligned with the existing song selector. */
	function updateVSliceCapsules():Void {
		if (grpSongs == null || vSliceCapsules == null) return;
		for (i in 0...vSliceCapsules.length) {
			var capsule = vSliceCapsules[i];
			var songItem = i < grpSongs.members.length ? grpSongs.members[i] : null;
			if (capsule == null || songItem == null) continue;
			var selected = i == curSelected;
			capsule.x = songItem.x - 156;
			capsule.y = songItem.y - 22;
			capsule.alpha = lerp(capsule.alpha, selected ? 0.95 : 0.35, 0.2);
			var animationName = selected ? "selected" : "unselected";
			if (capsule.animation.exists(animationName) && (capsule.animation.curAnim == null || capsule.animation.curAnim.name != animationName))
				capsule.animation.play(animationName, true);
		}
	}

	var __opponentMode:Bool = false;
	var __coopMode:Bool = false;

	function updateCoopModes() {
		__opponentMode = false;
		__coopMode = false;
		if (curSong.coopAllowed && curSong.opponentModeAllowed) {
			__opponentMode = curCoopMode % 2 == 1;
			__coopMode = curCoopMode >= 2;
		} else if (curSong.coopAllowed) {
			__coopMode = curCoopMode == 1;
		} else if (curSong.opponentModeAllowed) {
			__opponentMode = curCoopMode == 1;
		}
	}

	/**
	 * Selects the current song.
	 */
	public function select() {
		updateCoopModes();

		if (curDifficulties.length == 0) return;

		var event = event("onSelect", EventManager.get(FreeplaySongSelectEvent).recycle(curSong.name, curDifficulties[curDifficulty], curSong.variant, __opponentMode, __coopMode));

		if (event.cancelled) return;

		cancelVSlicePreview();
		Options.freeplayLastSong = curSong.name;
		Options.freeplayLastDifficulty = curDifficulties[curDifficulty];
		Options.freeplayLastVariation = curSong.variant;

		PlayState.loadSong(event.song, event.difficulty, event.variant, event.opponentMode, event.coopMode);
		FlxG.switchState(new PlayState());
	}

	public function convertChart() {
		trace('Converting ${curSong.name} ${curDifficulties[curDifficulty]} ${curSong.variant} to Codename format...');
		var chart = Chart.parse(curSong.name, curDifficulties[curDifficulty], curSong.variant);
		Chart.save(chart, curDifficulties[curDifficulty], curSong.variant);
	}

	/**
	 * Changes the current difficulty
	 * @param change How much to change.
	 * @param force Force the change if `change` is equal to 0
	 */
	public function changeDiff(change:Int = 0, force:Bool = false) {
		if (change == 0 && !force) return;

		var validDifficulties = curDifficulties.length > 0;
		var event = event("onChangeDiff", EventManager.get(MenuChangeEvent).recycle(curDifficulty, validDifficulties ? FlxMath.wrap(curDifficulty + change, 0, curDifficulties.length-1) : 0, change));

		if (event.cancelled) {
			if (force) updateCurSong();
			return;
		}

		var prevSong = curSong;
		curDifficulty = event.value;
		updateCurSong();
		updateScore();

		var text = validDifficulties ? curDifficulties[curDifficulty].toUpperCase() + (curSong != songs[curSelected] ? ' (${curSong.variant.toUpperCase()})' : '') : '-';
		diffText.text = curDifficulties.length > 1 ? '< $text >' : text;
		updateVSlicePresentation();
		startVSlicePreview();
	}

	function updateScore() {
		if (curDifficulties.length == 0) {
			intendedScore = 0;
			if (progressText != null) progressText.text = "";
			return;
		}
		updateCoopModes();
		var changes:Array<HighscoreChange> = [];
		if (__coopMode) changes.push(CCoopMode);
		if (__opponentMode) changes.push(COpponentMode);
		var saveData = FunkinSave.getSongHighscore(curSong.name, curDifficulties[curDifficulty], curSong.variant, changes);
		intendedScore = saveData.score;
		if (progressText != null && curSong.customValues != null && Reflect.field(curSong.customValues, "album") != null) {
			var progress = VSliceChartCodec.summarizeFreeplayScore(saveData);
			progressText.text = 'BEST: ${progress.rank}  ${progress.accuracy}%  ${progress.misses} MISS';
		} else if (progressText != null) {
			progressText.text = "";
		}
	}

	/**
	 * Array containing all labels for Co-Op / Opponent modes.
	 */
	public var coopLabels:Array<String> = [
		TU.translate("freeplay.solo"),
		TU.translate("freeplay.opponentMode"),
		TU.translate("freeplay.coopMode"),
		TU.translate("freeplay.coopModeSwitched")
	];

	/**
	 * Change the current coop mode context.
	 * @param change How much to change
	 * @param force Force the change, even if `change` is equal to 0.
	 */
	public function changeCoopMode(change:Int = 0, force:Bool = false) {
		if (change == 0 && !force) return;
		if (!curSong.coopAllowed && !curSong.opponentModeAllowed) return;

		var bothEnabled = curSong.coopAllowed && curSong.opponentModeAllowed;
		var event = event("onChangeCoopMode", EventManager.get(MenuChangeEvent).recycle(curCoopMode, FlxMath.wrap(curCoopMode + change, 0, bothEnabled ? 3 : 1), change));

		if (event.cancelled) return;

		curCoopMode = event.value;

		updateScore();

		var coopBinds = [CoolUtil.keyToString(Options.P1_CHANGE_MODE[0]), CoolUtil.keyToString(Options.P2_CHANGE_MODE[0])].filter(x -> x != "---");
		if (coopBinds.length == 2 && coopBinds[1] == coopBinds[0]) coopBinds.pop();
		else if (coopBinds.length == 0) coopBinds.push("---");

		var key = '[${coopBinds.join(" / ")}] ';

		if (bothEnabled) {
			coopText.text = key + coopLabels[curCoopMode];
		} else {
			coopText.text = key + coopLabels[curCoopMode * (curSong.coopAllowed ? 2 : 1)];
		}
	}

	/**
	 * Change the current selection.
	 * @param change How much to change
	 * @param force Force the change, even if `change` is equal to 0.
	 */
	public function changeSelection(change:Int = 0, force:Bool = false) {
		if (change == 0 && !force) return;

		var event = event("onChangeSelection", EventManager.get(MenuChangeEvent).recycle(curSelected, FlxMath.wrap(curSelected + change, 0, songs.length-1), change));
		if (event.cancelled) return;

		curSelected = event.value;
		if (event.playMenuSFX) CoolUtil.playMenuSFX(SCROLL, 0.7);

		var prevDiff = curDifficulties[curDifficulty], prevVariant = curDiffMetaKeys[curDifficulty];
		updateCurDifficulties();

		for (i => diff in curDifficulties) if (diff == prevDiff && curDiffMetaKeys[i] == prevVariant) {
			curDifficulty = i;
			break;
		}

		changeDiff(0, true);
		updateVSlicePresentation();
		startVSlicePreview();

		coopText.visible = curSong.coopAllowed || curSong.opponentModeAllowed;
	}

	function updateOptionsAlpha() {
		var event = event("onUpdateOptionsAlpha", EventManager.get(FreeplayAlphaUpdateEvent).recycle(0.6, 0.45, 1, 1, 0.25));
		if (event.cancelled) return;

		final idleAlpha = event.idleAlpha;
		final selectedAlpha = event.selectedAlpha;

		for (i in 0...iconArray.length)
			iconArray[i].alpha = lerp(iconArray[i].alpha, idleAlpha, event.lerp);

		iconArray[curSelected].alpha = selectedAlpha;

		for (i=>item in grpSongs.members)
		{
			item.targetY = i - curSelected;

			item.alpha = lerp(item.alpha, idleAlpha, event.lerp);

			if (item.targetY == 0)
				item.alpha = selectedAlpha;
		}
	}

	function updateCurDifficulties() {
		curDiffMetaKeys.resize(0);
		curDifficulties = songs[curSelected].difficulties.copy();
		for (i in 0...curDifficulties.length) curDiffMetaKeys.push(null);
		
		if (songs[curSelected].variants != null) {
			var meta:ChartMetaData;
			for (variant in songs[curSelected].variants) if ((meta = songs[curSelected].metas.get(variant)) != null) {
				curDifficulties = curDifficulties.concat(meta.difficulties);
				for (i in 0...meta.difficulties.length) curDiffMetaKeys.push(variant);
			}
		}
	}

	function updateCurSong() {
		var song = songs[curSelected];
		if (song == null) curSong = null;
		else if ((curSong = song.metas.get(curDiffMetaKeys[curDifficulty])) == null)
			curSong = song;
	}

	/** Show V-Slice album and play-data fields when they are available. */
	function updateVSlicePresentation():Void {
		if (albumArt == null) return;
		if (curSong == null || curSong.customValues == null || Reflect.field(curSong.customValues, "album") == null) {
			albumArt.visible = false;
			currentAlbumArtAsset = null;
			artistText.text = albumText.text = ostText.text = charactersText.text = ratingText.text = "";
			return;
		}
		var values:Dynamic = curSong.customValues;
		var albumId:Dynamic = Reflect.field(values, "album");
		var artist:Dynamic = Reflect.field(values, "artist");
		artistText.text = Std.isOfType(artist, String) ? cast artist : "";
		albumText.text = Std.isOfType(albumId, String) ? cast albumId : "";
		ostText.text = "";
		albumArt.visible = false;

		if (Std.isOfType(albumId, String) && cast(albumId, String).length > 0) {
			var albumPath = Paths.json('ui/freeplay/albums/${cast albumId}');
			if (Assets.exists(albumPath)) try {
				var albumData:Dynamic = Json.parse(Assets.getText(albumPath));
				var albumName:Dynamic = Reflect.field(albumData, "name");
				var artAsset:Dynamic = Reflect.field(albumData, "albumArtAsset");
				var ostName:Dynamic = Reflect.field(albumData, "albumOSTName");
				if (Std.isOfType(albumName, String)) albumText.text = cast albumName;
				if (Std.isOfType(ostName, String)) ostText.text = 'OST: ${Std.string(ostName)}';
				if (Std.isOfType(artAsset, String)) {
					var artPath = Paths.image(cast artAsset, null, false);
					if (Assets.exists(artPath)) {
						if (currentAlbumArtAsset != artPath) {
							FlxTween.cancelTweensOf(albumArt);
							albumArt.loadGraphic(artPath);
							var scale = Math.min(232 / Math.max(albumArt.width, 1), 232 / Math.max(albumArt.height, 1));
							albumArt.scale.set(scale, scale);
							albumArt.updateHitbox();
							albumArt.x = FlxG.width - 268 + (232 - albumArt.width) * 0.5;
							albumArt.y = 110 + (232 - albumArt.height) * 0.5;
							albumArt.alpha = 0;
							albumArt.visible = true;
							currentAlbumArtAsset = artPath;
							FlxTween.tween(albumArt, {alpha: 1}, 0.24, {ease: FlxEase.quadOut});
						} else {
							albumArt.visible = true;
						}
					}
				}
			} catch (e:Dynamic) {
				Logs.warn('Could not load V-Slice album "$albumId": ${Std.string(e)}');
			}
		}

		var characters:Dynamic = Reflect.field(values, "characters");
		var player:Dynamic = characters == null ? null : Reflect.field(characters, "player");
		var opponent:Dynamic = characters == null ? null : Reflect.field(characters, "opponent");
		var selectedPlayer = rememberedVSliceCharacter == null ? player : rememberedVSliceCharacter;
		charactersText.text = (Std.isOfType(selectedPlayer, String) || Std.isOfType(opponent, String))
			? 'Q/E CHARACTER: ${selectedPlayer == null ? "-" : selectedPlayer}    OPPONENT: ${opponent == null ? "-" : opponent}' : "";
		var ratings:Dynamic = Reflect.field(values, "ratings");
		var rating:Dynamic = ratings == null || curDifficulty >= curDifficulties.length ? null : Reflect.field(ratings, curDifficulties[curDifficulty]);
		ratingText.text = rating == null ? "" : 'DIFFICULTY RATING: ${rating}';
	}

	function cycleVSliceCharacter(change:Int):Void {
		if (curSong == null || curSong.customValues == null || Reflect.field(curSong.customValues, "album") == null
			|| freeplayCharacterChoices.length < 2) return;
		var current = rememberedVSliceCharacter;
		if (current == null) {
			var characters:Dynamic = Reflect.field(curSong.customValues, "characters");
			current = characters == null ? freeplayCharacterChoices[0] : Reflect.field(characters, "player");
		}
		var index = freeplayCharacterChoices.indexOf(current);
		if (index < 0) index = 0;
		index = FlxMath.wrap(index + change, 0, freeplayCharacterChoices.length - 1);
		rememberedVSliceCharacter = freeplayCharacterChoices[index];
		VSliceParser.freeplayCharacterOverride = rememberedVSliceCharacter;
		updateVSlicePresentation();
	}

	/** Start the selected V-Slice song's configured preview window when its audio is installed. */
	function startVSlicePreview():Void {
		if (curSong == null || curSong.customValues == null || Reflect.field(curSong.customValues, "album") == null) {
			var hadPreview = previewSongName != null || vSlicePreviewTransitioning;
			previewRequestId++;
			vSlicePreviewTransitioning = false;
			if (hadPreview) CoolUtil.playMenuSong();
			previewSongName = null;
			return;
		}
		if (previewSongName == curSong.name || curDifficulties == null || curDifficulties.length == 0) return;

		var paths = [
			Paths.file('songs/${curSong.name}/Inst.ogg'),
			Paths.file('songs/${curSong.name}/song/Inst.ogg'),
			Paths.music('${curSong.name}/${curSong.name}')
		];
		var audioPath:String = null;
		for (path in paths) if (Assets.exists(path)) {
			audioPath = path;
			break;
		}
		if (audioPath == null) {
			var hadPreview = previewSongName != null || vSlicePreviewTransitioning;
			previewRequestId++;
			vSlicePreviewTransitioning = false;
			if (hadPreview) CoolUtil.playMenuSong();
			previewSongName = null;
			return;
		}

		var start:Float = cast Reflect.field(curSong.customValues, "previewStart");
		var end:Float = cast Reflect.field(curSong.customValues, "previewEnd");
		if (Math.isNaN(start) || Math.isNaN(end) || start < 0 || start >= end || end > 1) {
			start = 0;
			end = 0.2;
		}
		var requestedSong = curSong.name;
		var requestId = ++previewRequestId;
		previewSongName = null;
		vSlicePreviewTransitioning = true;
		var playPreview = function() {
			if (requestId != previewRequestId || curSong == null || curSong.name != requestedSong) return;
			vSlicePreviewTransitioning = false;
			FlxG.sound.playMusic(audioPath, 0, false);
			if (FlxG.sound.music == null) return;
			previewSongName = requestedSong;
			previewStartTime = start * FlxG.sound.music.length;
			previewEndTime = end * FlxG.sound.music.length;
			FlxG.sound.music.time = previewStartTime;
			FlxG.sound.music.fadeIn(0.35, 0, 0.7);
		};
		var previousMusic = FlxG.sound.music;
		if (previousMusic != null && previousMusic.playing && previousMusic.volume > 0) {
			FlxTween.cancelTweensOf(previousMusic);
			FlxTween.tween(previousMusic, {volume: 0}, 0.18, {ease: FlxEase.quadOut, onComplete: function(_) { playPreview(); }});
		} else {
			playPreview();
		}
	}

	function updateVSlicePreviewLoop():Void {
		if (previewSongName == null || FlxG.sound.music == null || previewEndTime <= previewStartTime) return;
		if (FlxG.sound.music.time >= previewEndTime) FlxG.sound.music.time = previewStartTime;
	}

	function cancelVSlicePreview():Void {
		previewRequestId++;
		vSlicePreviewTransitioning = false;
		if (FlxG.sound.music != null) FlxTween.cancelTweensOf(FlxG.sound.music);
		previewSongName = null;
	}
}

class FreeplaySonglist {
	public var songs:Array<ChartMetaData> = [];
	public static final EXCLUDE_SUBFOLDERS:Array<String> = ['charts', 'scripts', 'song'];

	public function new() {}

	public static function isSubSongDirectory(subs:Array<String>):Bool {
		for (i in EXCLUDE_SUBFOLDERS) {
			if (subs.contains(i)) return false;
		}
		return true;
	}

	public function getSongsFromSource(source:funkin.backend.assets.AssetSource, useTxt:Bool = true, ?startDir:String = 'songs/', ?flatten:Bool = true) {
		var songsFound:Array<String> = null;
		if (useTxt) {
			var oldPath = Paths.txt('freeplaySonglist');
			var newPath = Paths.txt('config/freeplaySonglist');
			if (Paths.assetsTree.existsSpecific(newPath, "TEXT", source)) songsFound = CoolUtil.coolTextFile(newPath);
			else if (Paths.assetsTree.existsSpecific(oldPath, "TEXT", source)) {
				Logs.warn("data/freeplaySonglist.txt is deprecated and will be removed in the future. Please move the file to data/config/", DARKYELLOW, "FreeplaySonglist");
				songsFound = CoolUtil.coolTextFile(oldPath);
			}
		}
		// todo: make this better
		if (songsFound == null) {
			songsFound = [];
			var songDirs = Paths.getFolderDirectories(startDir, false, source);
			if (!flatten) {
				for (i in songDirs) {
					var subs = Paths.getFolderDirectories('$startDir$i', false, source);
					songsFound.push(isSubSongDirectory(subs) ? '$i/' : i);
				}
			} else {
				function poop(a:Array<Dynamic>, startDir:String) {
					for (i in a) {
						var subs = Paths.getFolderDirectories('$startDir$i', false, source);
						if (isSubSongDirectory(subs)) poop(subs, '$startDir$i/');
						else songsFound.push(startDir.substr('songs/'.length) + i);
					}
				}
				poop(songDirs, startDir);
			}
			// put folders at the top
			songsFound = songsFound.filter(a -> a.endsWith('/'))
				.concat(songsFound.filter(a -> !a.endsWith('/')));
		}
		if (songsFound.length > 0) {
			for (s in songsFound) songs.push(Chart.loadChartMeta(startDir.substr('songs/'.length) + s, source == MODS));
		}

		var foundVSlice = false;
		for (songID in Paths.getFolderDirectories('data/songs/', false, source)) {
			if (!VSliceParser.hasMetadata(songID, source)) continue;
			var metadata = Chart.loadChartMeta(songID, null, null, source == MODS);
			var duplicate = false;
			for (existing in songs) if (existing.name == metadata.name && existing.variant == metadata.variant) {
				duplicate = true;
				break;
			}
			if (!duplicate) songs.push(metadata);
			foundVSlice = true;
		}
		return songsFound.length == 0 && !foundVSlice;
	}

	public static function get(useTxt:Bool = true, ?startDir:String = 'songs/', ?flatten:Bool = true) {
		var songList = new FreeplaySonglist();

		switch(Flags.SONGS_LIST_MOD_MODE) {
			case 'prepend':
				songList.getSongsFromSource(MODS, useTxt, startDir, flatten);
				songList.getSongsFromSource(SOURCE, useTxt, startDir, flatten);
			case 'append':
				songList.getSongsFromSource(SOURCE, useTxt, startDir, flatten);
				songList.getSongsFromSource(MODS, useTxt, startDir, flatten);
			default /*case 'override'*/:
				if (songList.getSongsFromSource(MODS, useTxt, startDir, flatten))
					songList.getSongsFromSource(SOURCE, useTxt, startDir, flatten);
		}

		return songList;
	}
}
