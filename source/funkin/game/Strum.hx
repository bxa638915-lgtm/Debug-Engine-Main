package funkin.game;

import flixel.math.FlxPoint;
import flixel.math.FlxAngle;
import flixel.util.typeLimit.OneOfTwo;
import funkin.backend.system.Conductor;

class Strum extends FlxSprite {
	/**
	 * Extra data that can be added to the strum.
	**/
	public var extra:Map<String, Dynamic> = [];

	/**
	 * Which animation suffix on characters that should be used when hitting notes.
	 */
	public var animSuffix:String = "";

	/**
	 * Whenever the strum should act as a CPU strum.
	 * WARNING: Unused.
	**/
	@:dox(hide) public var cpu:Bool = false; // Unused
	/**
	 * The initial X/Y position of this strum when created.
	**/
	public var initialX:Float = 0;
	public var initialY:Float = 0;
	@:dox(hide) public var __pendingIntroAnim:Bool = false;

	public var defaultX(get, set):Float;
	private inline function get_defaultX():Float return initialX;
	private inline function set_defaultX(v:Float):Float return initialX = v;

	public var defaultY(get, set):Float;
	private inline function get_defaultY():Float return initialY;
	private inline function set_defaultY(v:Float):Float return initialY = v;

	public var direction(get, set):Float;
	private inline function get_direction():Float return (noteAngle == null ? 0 : noteAngle) + 90;
	private inline function set_direction(v:Float):Float {
		noteAngle = v - 90;
		return v;
	}

	public var downScroll(get, set):Bool;
	private inline function get_downScroll():Bool return PlayState.instance != null ? PlayState.instance.downscroll : funkin.options.Options.downscroll;
	private inline function set_downScroll(v:Bool):Bool return v;

	public var sustainReduce:Bool = true;

	public function new(x:Float = 0, y:Float = 0) {
		super(x, y);
		this.initialX = x;
		this.initialY = y;
	}
	/**
	 * The last time the note/confirm animation was hit.
	**/
	public var lastHit:Float = -5000;

	/**
	 * The strum line that this strum belongs to.
	**/
	public var strumLine:StrumLine = null;

	/**
	 * The scroll speed of the notes.
	**/
	public var scrollSpeed:Null<Float> = null; // custom scroll speed per strum
	/**
	 * The direction of the notes.
	 * If you don't want angle of the strum to interfere with the direction the notes are going,
	 * you can set noteAngle to = 0, and then you can use the angle of the strum without it affecting the direction of the notes.
	**/
	public var noteAngle:Null<Float> = null;

	public var lastDrawCameras(default, null):Array<FlxCamera> = [];

	// Copy fields
	public var copyStrumCamera:Bool = true;
	public var copyStrumScrollX:Bool = true;
	public var copyStrumScrollY:Bool = true;
	public var copyStrumAngle:Bool = true;
	public var copyStrumAlpha:Bool = true;
	public var updateNotesPosX:Bool = true;
	public var updateNotesPosY:Bool = true;
	public var extraCopyFields(default, set):Array<String> = [];

	@:noCompletion public var __cachedCopyFields:Array<Array<OneOfTwo<String, Int>>> = null;

	private function set_extraCopyFields(val:Array<String>) {
		extraCopyFields = val == null ? [] : val;
		__cachedCopyFields = null;
		return extraCopyFields;
	}

	private inline function __initCachedCopyFields() {
		if (__cachedCopyFields != null) return;
		__cachedCopyFields = [for (field in extraCopyFields) CoolUtil.parsePropertyString(field)];
	}

	private inline function __applyCopyFields(daNote:Note) {
		for (i in 0...extraCopyFields.length) {
			final parsed = __cachedCopyFields[i];
			final fromProp = CoolUtil.parseProperty(this, parsed);
			final toProp = CoolUtil.parseProperty(daNote, parsed);
			toProp.setValue(fromProp.getValue());
		}
	}

	/**
	 * Whenever the strum is pressed.
	**/
	public var getPressed:StrumLine->Bool = null;
	/**
	 * Whenever the strum was just pressed.
	**/
	public var getJustPressed:StrumLine->Bool = null;
	/**
	 * Whenever the strum was just released.
	**/
	public var getJustReleased:StrumLine->Bool = null;

	@:dox(hide) public inline function __getPressed(strumLine:StrumLine):Bool {
		return getPressed != null ? getPressed(strumLine) : strumLine.members.length != 4 ? ControlsUtil.getPressed(strumLine.controls, strumLine.members.length+"k"+ID) : switch(ID) {
			case 0: strumLine.controls.NOTE_LEFT;
			case 1: strumLine.controls.NOTE_DOWN;
			case 2: strumLine.controls.NOTE_UP;
			case 3: strumLine.controls.NOTE_RIGHT;
			default: false;
		}
	}
	@:dox(hide) public inline function __getJustPressed(strumLine:StrumLine) {
		return getJustPressed != null ? getJustPressed(strumLine) : strumLine.members.length != 4 ? ControlsUtil.getJustPressed(strumLine.controls, strumLine.members.length+"k"+ID) : switch(ID) {
			case 0: strumLine.controls.NOTE_LEFT_P;
			case 1: strumLine.controls.NOTE_DOWN_P;
			case 2: strumLine.controls.NOTE_UP_P;
			case 3: strumLine.controls.NOTE_RIGHT_P;
			default: false;
		}
	}
	@:dox(hide) public inline function __getJustReleased(strumLine:StrumLine) {
		return getJustReleased != null ? getJustReleased(strumLine) : strumLine.members.length != 4 ? ControlsUtil.getJustReleased(strumLine.controls, strumLine.members.length+"k"+ID) : switch(ID) {
			case 0: strumLine.controls.NOTE_LEFT_R;
			case 1: strumLine.controls.NOTE_DOWN_R;
			case 2: strumLine.controls.NOTE_UP_R;
			case 3: strumLine.controls.NOTE_RIGHT_R;
			default: false;
		}
	}

	/**
	 * Gets the scroll speed of the notes.
	 * @param note (Optional) The note
	**/
	public inline function getScrollSpeed(?note:Note):Float {
		var speed:Float = 1;
		if (note != null && note.scrollSpeed != null) speed = note.scrollSpeed;
		else if (scrollSpeed != null) speed = scrollSpeed;
		else if (PlayState.instance != null) speed = PlayState.instance.scrollSpeed;
		if (note != null && note.multSpeed != 1) speed *= note.multSpeed;
		return speed;
	}

	/**
	 * Gets the angle of the notes.
	 * If you don't want angle of the strum to interfere with the direction the notes are going,
	 * you can set noteAngle to = 0, and then you can use the angle of the strum without it affecting the direction of the notes.
	 * @param note (Optional) The note
	**/
	public inline function getNotesAngle(?note:Note):Float {
		if (note != null && note.noteAngle != null) return note.noteAngle;
		if (noteAngle != null) return noteAngle;
		return angle;
	}

	public override function update(elapsed:Float) {
		super.update(elapsed);
		if (cpu) {
			if (lastHit + (Conductor.crochet * 0.5) < Conductor.songPosition && getAnim() == "confirm") {
				playAnim("static");
			}
		}
	}

	public override function draw() {
		if (cameras.length == 1) {
			if (lastDrawCameras.length != 1 || lastDrawCameras[0] != cameras[0]) {
				lastDrawCameras = [cameras[0]];
			}
		} else {
			lastDrawCameras = cameras.copy();
		}
		super.draw();
	}

	@:noCompletion public static inline final PIX180:Float = 565.4866776461628; // 180 * Math.PI
	@:noCompletion public static final N_WIDTHDIV2:Float = Note.swagWidth / 2; // DEPRECATED

	static var __lastStrumW:Float = Math.NaN;
	static var __lastStrumH:Float = Math.NaN;
	static var __lastStrumHalfW:Float = 0;
	static var __lastStrumHalfH:Float = 0;
	static var __noteOffset:FlxPoint = FlxPoint.get();
	static var __lastNoteAngle:Float = Math.NaN;
	static var __lastAngleCos:Float = 0;
	static var __lastAngleSin:Float = 0;

	/**
	 * Updates the position of a note.
	 * @param daNote The note
	**/
	public function updateNotePosition(daNote:Note) {
		if (!daNote.exists) return;

		daNote.__strum = this;
		if (copyStrumCamera) daNote.__strumCameras = lastDrawCameras;
		if (copyStrumScrollX) daNote.scrollFactor.x = scrollFactor.x;
		if (copyStrumScrollY) daNote.scrollFactor.y = scrollFactor.y;
		if (copyStrumAngle && daNote.copyStrumAngle) {
			daNote.__noteAngle = getNotesAngle(daNote);
			daNote.angle = daNote.isSustainNote ? daNote.__noteAngle : angle;
		}
		if (copyStrumAlpha && daNote.copyAlpha) {
			daNote.alpha = alpha * daNote.multAlpha;
		}

		updateNotePos(daNote);
		if (extraCopyFields.length > 0) {
			__initCachedCopyFields();
			__applyCopyFields(daNote);
		}
	}

	private inline function updateNotePos(daNote:Note) {
		var shouldX = updateNotesPosX && daNote.updateNotesPosX;
		var shouldY = updateNotesPosY && daNote.updateNotesPosY;

		if (shouldX || shouldY) {
			if (daNote.strumRelativePos) {
				if (shouldX) daNote.x = 0;
				if (shouldY) {
					daNote.y = ((daNote.strumTime - Conductor.songPosition) * 0.45 * getScrollSpeed(daNote));
					if (daNote.isSustainNote) daNote.y += daNote.height * 0.5;
				}
			} else {
				if (width != __lastStrumW || height != __lastStrumH) {
					__lastStrumW = width;
					__lastStrumH = height;
					__lastStrumHalfW = width * 0.5;
					__lastStrumHalfH = height * 0.5;
				}

				if (daNote.__noteAngle != __lastNoteAngle) {
					__lastNoteAngle = daNote.__noteAngle;
					final result = FlxMath.fastSinCos((__lastNoteAngle + 90) * FlxAngle.TO_RAD);
					__lastAngleCos = result.cos;
					__lastAngleSin = result.sin;
				}

				final speed = getScrollSpeed(daNote);
				final distance = (daNote.strumTime - Conductor.songPosition) * 0.45 * speed;
				__noteOffset.set(__lastAngleCos * distance, __lastAngleSin * distance);
				var offX:Float = daNote.offsetX;
				var offY:Float = daNote.offsetY;
				if (offX != 0) offX += daNote.origin.x - __lastStrumHalfW;
				if (offY != 0) offY += daNote.origin.y - __lastStrumHalfH;
				__noteOffset.x += -daNote.origin.x + daNote.offset.x + offX;
				__noteOffset.y += -daNote.origin.y + daNote.offset.y + offY;
				if (daNote.isSustainNote) {
					final m = (daNote.height * 0.5 * (speed < 0 ? -1 : 1));
					__noteOffset.x += __lastAngleCos * m;
					__noteOffset.y += __lastAngleSin * m;
				}
				__noteOffset.x += x + __lastStrumHalfW;
				__noteOffset.y += y + __lastStrumHalfH;
				if (shouldX) daNote.x = __noteOffset.x;
				if (shouldY) daNote.y = __noteOffset.y;
			}
		}
	}

	/**
	 * Updates a sustain note.
	 * @param daNote The note
	**/
	public inline function updateSustain(daNote:Note) {
		if (!daNote.isSustainNote) return;
		daNote.updateSustain(this);
	}

	/**
	 * Updates the animation state based on the player input.
	 * @param pressed Whenever the player is pressing the button
	 * @param justPressed Whenever the player just pressed the button
	 * @param justReleased Whenever the player just released the button
	**/
	public function updatePlayerInput(pressed:Bool, justPressed:Bool, justReleased:Bool) {
		switch(getAnim()) {
			case "confirm":
				if (justReleased || !pressed)
					playAnim("static");
			case "pressed":
				if (justReleased || !pressed)
					playAnim("static");
			case "static":
				if (justPressed || pressed)
					playAnim("pressed");
			case null:
				playAnim("static");
		}
	}

	/**
	 * Plays the confirm animation.
	 * @param time The time
	**/
	public inline function press(time:Float) {
		lastHit = time;
		playAnim("confirm");
	}

	/**
	 * Plays an animation.
	 * @param anim The animation name
	 * @param force Whenever the animation should be forced to play
	**/
	public function playAnim(anim:String, force:Bool = true) {
		animation.play(anim, force);
		centerOffsets();
		centerOrigin();
	}

	/**
	 * Gets the current animation name.
	**/
	public inline function getAnim() {
		return animation.name;
	}

	override public function destroy():Void {
		flixel.tweens.FlxTween.cancelTweensOf(this);
		if (extra != null) {
			extra.clear();
			extra = null;
		}
		strumLine = null;
		super.destroy();
	}

	public function reloadNote(?customSkin:String = ""):Void {
		// Psych compatibility
	}
}
