package funkin.game;

import flixel.math.FlxPoint;
import flixel.math.FlxAngle;
import flixel.math.FlxRect;
import funkin.backend.chart.ChartData;
import funkin.backend.scripting.events.note.NoteCreationEvent;
import funkin.backend.system.Conductor;

using StringTools;

@:allow(funkin.game.PlayState)
class Note extends FlxSprite
{
	public var extra:Map<String, Dynamic> = [];

	public var strumTime:Float = 0;

	public var mustPress(get, set):Bool;
	public var strumLine(default, set):StrumLine;
	private function set_strumLine(strLine:StrumLine) {
		if (this.strumLine != null) {
			if (this.strumLine.notes != null)
				this.strumLine.notes.remove(this, true);
			strLine.notes.add(this);
			strLine.notes.sortNotes();
		}
		if (PlayState.instance != null) {
			PlayState.instance.__psychNotesCacheVersion++;
			PlayState.instance.__psychNotesCachePos = Math.NaN;
		}
		return strumLine = strLine;
	}

	private inline function get_mustPress():Bool {
		return strumLine != null && !strumLine.cpu;
	}
	private function set_mustPress(val:Bool):Bool {
		if (PlayState.instance != null && strumLine != null && (!strumLine.cpu) != val) {
			var targetStrumLine = val ? PlayState.instance.playerStrums : PlayState.instance.cpuStrums;
			if (targetStrumLine != null && targetStrumLine != strumLine) {
				var savedCachePos = PlayState.instance.__psychNotesCachePos;
				strumLine = targetStrumLine;
				PlayState.instance.__psychNotesCachePos = savedCachePos;
			}
		}
		return val;
	}
	public var noteData:Int = 0;
	public var canBeHit:Bool = false;
	public var tooLate:Bool = false;
	public var wasGoodHit:Bool = false;

	/**
	 * Whenever that note should be avoided by Botplay.
	 */
	public var avoid:Bool = false;

	public var noAnimation:Bool = false;
	public var noMissAnimation:Bool = false;
	public var gfNote:Bool = false;
	public var ignoreNote(get, set):Bool;
	private inline function get_ignoreNote():Bool return avoid;
	private inline function set_ignoreNote(v:Bool):Bool return avoid = v;
	public var hitCausesMiss:Bool = false;
	public var lowPriority:Bool = false;
	public var hitHealth:Null<Float> = null;
	public var missHealth:Null<Float> = null;
	public var offsetX:Float = 0;
	public var offsetY:Float = 0;
	public var multSpeed:Float = 1;
	public var noteSplashTexture(get, set):String;
	private inline function get_noteSplashTexture():String return splash;
	private inline function set_noteSplashTexture(v:String):String return splash = v;
	@:isVar public var texture(get, set):String = null;
	private inline function get_texture():String return texture;
	private function set_texture(val:String):String {
		if (val != null && val != "" && val != texture) {
			reloadNoteTexture(val);
		}
		return texture = val;
	}

	/**
	 * The note that comes before this one (sustain and not)
	 */
	public var prevNote:Note;
	/**
	 * The note that comes after this one (sustain and not)
	 */
	public var nextNote:Note;
	/**
	 * The next sustain after this one
	 */
	public var nextSustain:Note;

	/**
	 * The parent of the sustain.
	 * 
	 * If this note is not sustain, this will be null.
	 */
	public var sustainParent:Null<Note>;
	public var __parentWasHit:Bool = false;

	/**
	 * Number of active sustain pieces attached to this note
	 * 
	 * Increases by 1 every time a hold piece is initialized.
	 * 
	 * Decreases by 1 every time a hold piece gets destroyed.
	 */
	public var tailCount:Int = 0;

	/**
	 * Name of the splash.
	 */
	public var splash:String = "default";

	public var strumID(get, never):Int;
	private function get_strumID() {
		return if (noteData < 0) 0; else noteData % strumLine.members.length;
	}

	public var sustainLength:Float = 0;
	public var isSustainNote:Bool = false;
	public var noSustainClip:Bool = false;
	public var flipSustain:Bool = true;

	public var noteTypeID:Int = 0;

	// TO APPLY THOSE ON A SINGLE NOTE
	public var scrollSpeed:Null<Float> = null;
	public var noteAngle:Null<Float> = null;

	public var copyStrumAngle:Bool = true;
	public var updateNotesPosX:Bool = true;
	public var updateNotesPosY:Bool = true;
	public var updateFlipY:Bool = true;

	public var copyX(get, set):Bool;
	private inline function get_copyX():Bool return updateNotesPosX;
	private inline function set_copyX(v:Bool):Bool return updateNotesPosX = v;

	public var copyY(get, set):Bool;
	private inline function get_copyY():Bool return updateNotesPosY;
	private inline function set_copyY(v:Bool):Bool return updateNotesPosY = v;

	public var copyAngle(get, set):Bool;
	private inline function get_copyAngle():Bool return copyStrumAngle;
	private inline function set_copyAngle(v:Bool):Bool return copyStrumAngle = v;

	public var copyAlpha:Bool = true;
	public var multAlpha:Float = 1.0;
	public var distance:Float = 2000;

	public var noteType(get, never):String;

	@:dox(hide) public var __strumCameras:Array<FlxCamera> = null;
	@:dox(hide) public var __strum:Strum = null;
	@:dox(hide) public var __noteAngle:Float = 0;

	private function get_noteType() {
		if (PlayState.instance == null) return null;
		return PlayState.instance.getNoteType(noteTypeID);
	}

	public static var swagWidth:Float = 160 * 0.7; // TODO: remove this

	private static var __customNoteTypeExists:Map<String, Bool> = [];
	private static var __customNoteTypeConfigs:Map<String, Map<String, String>> = [];

	public var animSuffix:String = null;

	// Deprecated?
	@:dox(hide) public var tripTimer:Float = 0; // ranges from 0 to 1

	private static function customTypePathExists(path:String) {
		if (__customNoteTypeExists.exists(path))
			return __customNoteTypeExists[path];
		return __customNoteTypeExists[path] = Assets.exists(path);
	}

	private static function getCustomTypeConfig(typeName:String):Map<String, String> {
		if (typeName == null || typeName == "" || typeName == "default") return null;
		if (__customNoteTypeConfigs.exists(typeName))
			return __customNoteTypeConfigs.get(typeName);
		var cfg:Map<String, String> = null;
		var txtPath = Paths.file('custom_notetypes/$typeName.txt');
		if (!Assets.exists(txtPath))
			txtPath = Paths.file('data/notes/$typeName.txt');
		if (Assets.exists(txtPath)) {
			cfg = [];
			var raw = Assets.getText(txtPath);
			if (raw != null) {
				for (line in raw.split("\n")) {
					var trimmed = line.trim();
					if (trimmed == "" || trimmed.startsWith("#") || trimmed.startsWith("//")) continue;
					var eqIdx = trimmed.indexOf("=");
					if (eqIdx > 0) {
						var k = trimmed.substr(0, eqIdx).trim();
						var v = trimmed.substr(eqIdx + 1).trim();
						if (v.length >= 2 && ((v.startsWith("'") && v.endsWith("'")) || (v.startsWith('"') && v.endsWith('"'))))
							v = v.substr(1, v.length - 2);
						cfg.set(k, v);
					}
				}
			}
		}
		__customNoteTypeConfigs.set(typeName, cfg);
		return cfg;
	}

	public function reloadNoteTexture(tex:String) {
		if (tex == null || tex == "") return;
		var skinPath = PlayState.getNoteSkinPath(tex);
		var newFrames = Paths.getFrames(skinPath);
		if (newFrames == null || newFrames.frames == null || newFrames.frames.length == 0) return;
		frames = newFrames;
		switch(strumID % 4) {
			case 0:
				animation.addByPrefix('scroll', 'purple0');
				animation.addByPrefix('hold', 'purple hold piece');
				animation.addByPrefix("holdend", "pruple end hold");
				if (animation.exists("holdend") != true)
					animation.addByPrefix('holdend', 'purple hold end');
			case 1:
				animation.addByPrefix('scroll', 'blue0');
				animation.addByPrefix('hold', 'blue hold piece');
				animation.addByPrefix('holdend', 'blue hold end');
			case 2:
				animation.addByPrefix('scroll', 'green0');
				animation.addByPrefix('hold', 'green hold piece');
				animation.addByPrefix('holdend', 'green hold end');
			case 3:
				animation.addByPrefix('scroll', 'red0');
				animation.addByPrefix('hold', 'red hold piece');
				animation.addByPrefix('holdend', 'red hold end');
		}
		var scaleVal = (strumLine != null ? @:privateAccess strumLine.strumScale : 1.0) * Flags.DEFAULT_NOTE_SCALE;
		scale.set(scaleVal, scaleVal);
		lastScrollSpeed = null;
		if (isSustainNote) {
			var targetAnim = nextSustain != null ? 'hold' : 'holdend';
			if (animation.exists(targetAnim))
				animation.play(targetAnim);
			else
				animation.play('scroll');
			if (nextSustain != null) {
				var sp = __strum != null ? __strum.getScrollSpeed(this) : (PlayState.instance != null ? PlayState.instance.scrollSpeed : 1.0);
				scale.y = (sustainLength * 0.45 * Math.abs(sp)) / frameHeight;
				updateHitbox();
				scale.y += gapFix / frameHeight;
			} else {
				updateHitbox();
			}
		} else {
			animation.play('scroll');
			updateHitbox();
		}
	}

	static var DEFAULT_FIELDS:Array<String> = ["time", "id", "type", "sLen"];

	public function new(strumLine:StrumLine, noteData:ChartNote, sustain:Bool = false, sustainLength:Float = 0, sustainOffset:Float = 0, ?prev:Note) {
		super();

		moves = false;

		if(prev != null)
			this.prevNote = prev;
		else
			this.prevNote = strumLine.notes.members.last();

		if (this.prevNote != null) this.prevNote.nextNote = this;
		this.noteTypeID = noteData.type.getDefault(0);
		this.isSustainNote = sustain;
		this.sustainLength = sustainLength;
		this.strumLine = strumLine;
		for(field in Reflect.fields(noteData)) if(!DEFAULT_FIELDS.contains(field))
			this.extra.set(field, Reflect.field(noteData, field));

		// work around to set the `sustainParent`
		if (isSustainNote)
			sustainParent = prevNote.isSustainNote ? prevNote.sustainParent : prevNote;

		x += 50;
		// MAKE SURE ITS DEFINITELY OFF SCREEN?
		y -= 2000;

		this.strumTime = noteData.time.getDefault(0) + sustainOffset;
		this.noteData = noteData.id.getDefault(0);

		if (PlayState.instance != null && PlayState.instance.splashSkin != null && PlayState.instance.splashSkin != "")
			this.splash = PlayState.instance.splashSkin;

		var defaultSkin = (PlayState.instance != null && PlayState.instance.arrowSkin != null)
			? PlayState.getNoteSkinPath(PlayState.instance.arrowSkin)
			: 'game/notes/default';

		var noteSprite = defaultSkin;
		if (this.noteType != null && this.noteType != "" && this.noteType != "default") {
			var customType = Paths.image('game/notes/${this.noteType}');
			if (customTypePathExists(customType))
				noteSprite = 'game/notes/${this.noteType}';
			else if (customTypePathExists(Paths.image(this.noteType)))
				noteSprite = this.noteType;
			else if (customTypePathExists(Paths.image('noteSkins/${this.noteType}')))
				noteSprite = 'noteSkins/${this.noteType}';

			switch (this.noteType.toLowerCase()) {
				case "alt animation":
					if (animSuffix == null || animSuffix == "") animSuffix = Flags.DEFAULT_ALT_ANIM_SUFFIX;
				case "no animation":
					noAnimation = true;
					noMissAnimation = true;
				case "gf sing":
					gfNote = true;
				case "hurt note":
					avoid = true;
					hitCausesMiss = true;
					lowPriority = true;
			}

			var cfg = getCustomTypeConfig(this.noteType);
			if (cfg != null) {
				if (cfg.exists("texture") && cfg.get("texture") != "") {
					@:bypassAccessor this.texture = cfg.get("texture");
					noteSprite = PlayState.getNoteSkinPath(this.texture);
				}
				if (cfg.exists("noteSplashTexture") && cfg.get("noteSplashTexture") != "")
					this.splash = cfg.get("noteSplashTexture");
				if (cfg.exists("animSuffix"))
					this.animSuffix = cfg.get("animSuffix");
				if (cfg.exists("noAnimation"))
					this.noAnimation = cfg.get("noAnimation").toLowerCase() == "true";
				if (cfg.exists("noMissAnimation"))
					this.noMissAnimation = cfg.get("noMissAnimation").toLowerCase() == "true";
				if (cfg.exists("gfNote"))
					this.gfNote = cfg.get("gfNote").toLowerCase() == "true";
				if (cfg.exists("ignoreNote"))
					this.avoid = cfg.get("ignoreNote").toLowerCase() == "true";
				if (cfg.exists("hitCausesMiss"))
					this.hitCausesMiss = cfg.get("hitCausesMiss").toLowerCase() == "true";
				if (cfg.exists("lowPriority"))
					this.lowPriority = cfg.get("lowPriority").toLowerCase() == "true";
			}
		}

		var event = EventManager.get(NoteCreationEvent).recycle(this, strumID, this.noteType, noteTypeID, PlayState.instance.strumLines.members.indexOf(strumLine), mustPress,
			noteSprite, @:privateAccess strumLine.strumScale * Flags.DEFAULT_NOTE_SCALE, animSuffix);

		if (PlayState.instance != null)
			event = PlayState.instance.gameAndCharsEvent("onNoteCreation", event);

		this.animSuffix = event.animSuffix;
		if (!event.cancelled) {
			switch (event.noteType)
			{
				// case "My Custom Note Type": // hardcoding note types
				default:
					frames = Paths.getFrames(event.noteSprite);

					switch(event.strumID % 4) {
						case 0:
							animation.addByPrefix('scroll', 'purple0');
							animation.addByPrefix('hold', 'purple hold piece');
							animation.addByPrefix("holdend", "pruple end hold");
							if (animation.exists("holdend") != true) // null or false
								animation.addByPrefix('holdend', 'purple hold end');
						case 1:
							animation.addByPrefix('scroll', 'blue0');
							animation.addByPrefix('hold', 'blue hold piece');
							animation.addByPrefix('holdend', 'blue hold end');
						case 2:
							animation.addByPrefix('scroll', 'green0');
							animation.addByPrefix('hold', 'green hold piece');
							animation.addByPrefix('holdend', 'green hold end');
						case 3:
							animation.addByPrefix('scroll', 'red0');
							animation.addByPrefix('hold', 'red hold piece');
							animation.addByPrefix('holdend', 'red hold end');
					}

					scale.set(event.noteScale, event.noteScale);
					antialiasing = true;
			}
		}

		if (isSustainNote && prevNote != null)
		{
			alpha = 0.6;
			multAlpha = 0.6;
			animation.play('holdend');

			if (prevNote.isSustainNote)
			{
				prevNote.nextSustain = this;
				prevNote.animation.play('hold');
				prevNote.updateHitbox();
			}
		} else {
			animation.play("scroll");
		}
		updateHitbox();

		if (PlayState.instance != null) {
			PlayState.instance.splashHandler.getSplashGroup(splash);
			PlayState.instance.gameAndCharsEvent("onPostNoteCreation", event);
		}
	}

	public var lastScrollSpeed:Null<Float> = null;
	public var gapFix:SingleOrFloat = 0;
	public var useAntialiasingFix(get, set):Bool;

	inline function set_useAntialiasingFix(v:Bool) {
		if(v != useAntialiasingFix) {
			gapFix = v ? 1 : 0;
		}
		return v;
	}
	inline function get_useAntialiasingFix() {
		return gapFix > 0;
	}

	/**
	 * Whenever the position of the note should be relative to the strum position or not.
	 * For example, if this is true, a note at the position 0; 0 will be on the strum, instead of at the top left of the screen.
	 */
	public var strumRelativePos:Bool = true;

	@:dox(hide) static var __lastAngle:Float = Math.NaN;
	@:dox(hide) static var __lastAngleSin:Float = 0;
	@:dox(hide) static var __lastAngleCos:Float = 0;
	@:dox(hide) static var __lastStrumW:Float = Math.NaN;
	@:dox(hide) static var __lastStrumH:Float = Math.NaN;
	@:dox(hide) static var __lastStrumHalfW:Float = 0;
	@:dox(hide) static var __lastStrumHalfH:Float = 0;

	override function draw() {
		@:privateAccess var oldDefaultCameras = FlxCamera._defaultCameras;
		@:privateAccess if (__strumCameras != null) FlxCamera._defaultCameras = __strumCameras;

		var negativeScroll = isSustainNote && strumRelativePos && lastScrollSpeed < 0;
		if (negativeScroll) y -= height;
		if (__strum != null && strumRelativePos) {
			final originalX = x;
			final originalY = y;

			if (__noteAngle != __lastAngle) {
				__lastAngle = __noteAngle;
				final result = FlxMath.fastSinCos((__noteAngle + 90) * FlxAngle.TO_RAD);
				__lastAngleSin = result.sin;
				__lastAngleCos = result.cos;
			}

			if (__strum.width != __lastStrumW || __strum.height != __lastStrumH) {
				__lastStrumW = __strum.width;
				__lastStrumH = __strum.height;
				__lastStrumHalfW = __strum.width * 0.5;
				__lastStrumHalfH = __strum.height * 0.5;
			}

			var offX:Float = offsetX;
			var offY:Float = offsetY;
			if (offX != 0) offX += (width - __lastStrumW) * 0.5;
			if (offY != 0) offY += (height - __lastStrumH) * 0.5;

			x = -origin.x + offset.x + offX + (originalY * __lastAngleCos) + __strum.x + __lastStrumHalfW;
			y = -origin.y + offset.y + offY + (originalY * __lastAngleSin) + __strum.y + __lastStrumHalfH;
			super.draw();
			x = originalX;
			y = originalY;
		} else {
			super.draw();
		}
		if (negativeScroll) y += height;

		@:privateAccess FlxCamera._defaultCameras = oldDefaultCameras;
	}

	var __lastDownscrollCam:Bool = false;
	var __lastX:Float = 0;

	@:noCompletion @:dox(hide) override function isOnScreen(?camera:FlxCamera):Bool {
		var downscrollCam = (Std.isOfType(camera, HudCamera) ? cast(camera, HudCamera).downscroll : false);
		if (updateFlipY) {
			flipY = (isSustainNote && flipSustain) && (downscrollCam != (lastScrollSpeed < 0));
		}
		if (downscrollCam == __lastDownscrollCam)
			return super.isOnScreen(camera);
		else {
			__lastDownscrollCam = downscrollCam;
			__lastX = x;
		}

		if (downscrollCam && __strum != null && __strum.updateNotesPosX && updateNotesPosX) {
			x = -x + 2 * (__strum.x - origin.x + offset.x) + __strum.width;
		}
		final isOnScreen = super.isOnScreen(camera);
		return isOnScreen;
	}

	override function drawComplex(camera:FlxCamera):Void {
		super.drawComplex(camera);

		if (__lastDownscrollCam) {
			__lastDownscrollCam = false;
			x = __lastX;
		}
	}

	public function isOnScreenOriginal(?camera:FlxCamera):Bool {
    	return super.isOnScreen(camera);
	}

	public var earlyPressWindow:Float = Flags.EARLY_HIT_WINDOW_RANGE;
	public var latePressWindow:Float = Flags.LATE_HIT_WINDOW_RANGE;

	public function updateSustain(strum:Strum) {
		var scrollSpeed = strum.getScrollSpeed(this);

		if (lastScrollSpeed != scrollSpeed) {
			lastScrollSpeed = scrollSpeed;
			if (nextSustain != null) {
				scale.y = (sustainLength * 0.45 * Math.abs(scrollSpeed)) / frameHeight;
				updateHitbox();
				scale.y += gapFix / frameHeight;
			}
		}

		updateSustainClip();
	}

	public function updateSustainClip() if (wasGoodHit && !noSustainClip) {
		var t = CoolUtil.bound((Conductor.songPosition - strumTime) / height * 0.45 * Math.abs(lastScrollSpeed), 0, 1);
		@:bypassAccessor {
			if (clipRect == null) clipRect = FlxRect.get();
			clipRect.set(0, frameHeight * t, frameWidth, frameHeight * (1 - t));
		}
		@:privateAccess {
			if (frame != null && _frame != null)
				_frame = frame.clipTo(clipRect, _frame);
		}
	}

	@:noCompletion
	override function set_clipRect(rect:FlxRect):FlxRect {
		@:bypassAccessor clipRect = rect;

		@:privateAccess if (frame != null) {
			if (rect != null && _frame != null)
				_frame = frame.clipTo(rect, _frame);
			else if (_frame != null)
				_frame = frame.copyTo(_frame);
			dirty = true;
		}

		return rect;
	}

	public override function destroy() {
		super.destroy();

		clipRect = FlxDestroyUtil.put(clipRect);
	}
}
