package funkin.editors.charter;

import flixel.animation.FlxAnimation;
import flixel.math.FlxPoint;
import flixel.math.FlxRect;
import funkin.game.Character;
import funkin.backend.scripting.events.sprite.PlayAnimContext;
import funkin.backend.system.Conductor;

/** A movable, independently closable character preview pane for the chart editor. */
class CharterCharacterPreviewWindow extends UISliceSprite {
	public var isPlayer(default, null):Bool;
	public var previewCamera(default, null):FlxCamera;
	public var character(default, null):Character;
	public var onClose:Void->Void;
	public var onFocus:CharterCharacterPreviewWindow->Void;

	private var titleText:UIText;
	private var minimizeButton:UIButton;
	private var closeButton:UIButton;
	private var characterName:String = null;
	private var collapsed:Bool = false;
	private var dragging:Bool = false;
	private var dragOffset:FlxPoint = FlxPoint.get();
	private var mousePosition:FlxPoint = FlxPoint.get();
	private var titleBounds:FlxRect = new FlxRect();
	private var characterBounds:FlxRect = new FlxRect();
	private var danceTimer:Float = 0;
	private var uiCamera:FlxCamera;
	private var windowWidth:Int;
	private var windowHeight:Int;

	public function new(x:Float, y:Float, width:Int, height:Int, isPlayer:Bool, uiCamera:FlxCamera, onClose:Void->Void, ?onFocus:CharterCharacterPreviewWindow->Void) {
		super(x, y, width, height, "editors/ui/normal-popup");
		this.isPlayer = isPlayer;
		this.uiCamera = uiCamera;
		this.onClose = onClose;
		this.onFocus = onFocus;
		this.windowWidth = width;
		this.windowHeight = height;
		this.cameras = [uiCamera];

		previewCamera = new FlxCamera();
		previewCamera.bgColor = 0xFF292D2E;
		previewCamera.scroll.set();
		FlxG.cameras.add(previewCamera, false);

		titleText = new UIText(x + 12, y + 7, width - 76, "", 15, -1);
		members.push(titleText);

		minimizeButton = new UIButton(x + width - 58, y + 3, "-", toggleCollapsed, 25, 24);
		minimizeButton.autoFrames = false;
		members.push(minimizeButton);

		closeButton = new UIButton(x + width - 30, y + 3, "x", closeWindow, 25, 24);
		closeButton.autoFrames = false;
		members.push(closeButton);

		updatePreviewCamera();
	}

	public function setCharacter(name:String):Void {
		if (name == null || name.length == 0) name = isPlayer ? Flags.DEFAULT_CHARACTER : Flags.DEFAULT_OPPONENT;
		if (characterName == name) return;
		characterName = name;

		if (character != null) {
			members.remove(character);
			character.destroy();
			character = null;
		}

		character = new Character(0, 0, name, isPlayer, true, true);
		character.danceOnBeat = false;
		// Character animation offsets are intended for the stage and can move a sprite
		// outside this cropped preview camera.
		character.forceIsOnScreen = true;
		character.cameras = [previewCamera];
		character.scrollFactor.set();
		members.push(character);
		titleText.text = '${TU.translate(isPlayer ? "charter.view.playerPreview" : "charter.view.opponentPreview")}: ${character.curCharacter}';
		danceTimer = 0;
		fitCharacter();
	}

	public function setPreviewVisible(value:Bool):Void {
		visible = value;
		active = value;
		previewCamera.visible = value && !collapsed;
	}

	public inline function canPlayTimelineAnimation():Bool
		return visible && !collapsed && character != null;

	public function playSingAnimation(direction:Int, suffix:String, singEndTime:Float):Void {
		if (character != null) {
			danceTimer = 0;
			character.playSingAnim(direction, suffix);
			// Gameplay refreshes lastHit as sustain pieces are hit. Position it at
			// the chart's tail so Character.tryDance waits through the whole hold,
			// using the character's configured holdTime after that point.
			character.lastHit = singEndTime;
		}
	}

	public function playPreviewAnimation(animationName:String, force:Null<Bool>, context:PlayAnimContext):Void {
		if (character != null && character.hasAnim(animationName)) {
			danceTimer = 0;
			character.playAnim(animationName, force, context);
		}
	}

	public function setPreviewIdleSuffix(suffix:String):Void {
		if (character != null) character.idleSuffix = suffix;
	}

	public function resetTimelineAnimation(idleSuffix:String):Void {
		if (character == null) return;
		character.idleSuffix = idleSuffix;
		character.dance();
		danceTimer = 0;
	}

	public function setChromeCamera(camera:FlxCamera):Void {
		// Keep the opaque window skin behind the character viewport. Only the
		// title and controls belong on the topmost camera.
		cameras = [uiCamera];
		titleText.cameras = [camera];
		minimizeButton.cameras = [camera];
		closeButton.cameras = [camera];
	}

	private function closeWindow():Void {
		setPreviewVisible(false);
		if (onClose != null) onClose();
	}

	private function toggleCollapsed():Void {
		collapsed = !collapsed;
		resize(windowWidth, collapsed ? 34 : windowHeight);
		previewCamera.visible = visible && !collapsed;
		updatePreviewCamera();
	}

	// Measure every animation frame using Character's own animation path so the
	// envelope includes DBE offsets and Animate timelines without changing scale.
	private function fitCharacter():Void {
		if (character == null || previewCamera == null) return;

		// Keep the scale supplied by the character data adapter, like CharacterPlayer.
		character.updateHitbox();
		character.setPosition(0, 0);

		var originalAnimation = character.getAnimName();
		var originalFrame = character.globalCurFrame;
		var originalReversed = character.isAnimReversed();
		var originalContext = character.lastAnimContext;
		var originalFinished = character.isAnimFinished();
		var envelope:Array<Float> = null;

		for (animationName in character.getNameList()) {
			var animation:FlxAnimation = cast character.getAnim(animationName);
			if (animation == null) continue;

			for (frameIndex in 0...animation.numFrames) {
				// The preview character has scripts disabled; using its normal play
				// path here reproduces Character offsets and FlxAnimate frame bounds.
				character.playAnim(animationName, true, PlayAnimContext.NONE, false, frameIndex);
				character.getScreenBounds(characterBounds, previewCamera);
				envelope = CharterCharacterPreviewLayout.includeBounds(
					envelope,
					characterBounds.x,
					characterBounds.y,
					characterBounds.width,
					characterBounds.height);
			}
		}

		// Measuring should not leave the pane on the last frame scanned.
		if (originalAnimation != null && character.hasAnim(originalAnimation)) {
			var originalAnimationData:FlxAnimation = cast character.getAnim(originalAnimation);
			var restoreFrame = originalReversed && originalAnimationData != null ? originalAnimationData.numFrames - 1 - originalFrame : originalFrame;
			character.playAnim(originalAnimation, true, originalContext, originalReversed, restoreFrame);
			if (originalFinished && character.animation.curAnim != null)
				character.animation.curAnim.finish();
		} else {
			character.dance();
		}

		if (envelope == null) {
			character.getScreenBounds(characterBounds, previewCamera);
			envelope = CharterCharacterPreviewLayout.includeBounds(
				envelope,
				characterBounds.x,
				characterBounds.y,
				characterBounds.width,
				characterBounds.height);
		}

		character.setPosition(
			CharterCharacterPreviewLayout.getCharacterPositionX(envelope[0]),
			CharterCharacterPreviewLayout.getCharacterPositionY(envelope[1]));

		windowWidth = CharterCharacterPreviewLayout.getWindowWidth(envelope[2] - envelope[0]);
		windowHeight = CharterCharacterPreviewLayout.getWindowHeight(envelope[3] - envelope[1]);
		resize(windowWidth, collapsed ? 34 : windowHeight);
		updatePreviewCamera();

		// Character changes can alter the auto-sized window; keep it reachable.
		x = FlxMath.bound(x, 0, Math.max(FlxG.width - windowWidth, 0));
		y = FlxMath.bound(y, 0, Math.max(FlxG.height - (collapsed ? 34 : windowHeight), 0));
	}

	private function updatePreviewCamera():Void {
		if (previewCamera == null) return;
		previewCamera.setPosition(x + 4, y + 33);
		previewCamera.setSize(Std.int(Math.max(windowWidth - 8, 1)), Std.int(Math.max((collapsed ? 34 : windowHeight) - 37, 1)));
		previewCamera.visible = visible && !collapsed;
		previewCamera.scroll.set();
	}

	public override function update(elapsed:Float):Void {
		super.update(elapsed);
		if (!visible) return;

		var titlePrefix = TU.translate(isPlayer ? "charter.view.playerPreview" : "charter.view.opponentPreview");
		if (character != null) titleText.text = '$titlePrefix: ${character.curCharacter}';
		titleText.x = x + 12;
		titleText.y = y + 7;
		minimizeButton.x = x + windowWidth - 58;
		minimizeButton.y = y + 3;
		closeButton.x = x + windowWidth - 30;
		closeButton.y = y + 3;

		if (!closeButton.hovered && !minimizeButton.hovered) {
			FlxG.mouse.getWorldPosition(uiCamera, mousePosition);
			titleBounds.set(x, y, windowWidth, 31);
			if (FlxG.mouse.justPressed && UIState.state.isOverlapping(this, titleBounds)) {
				dragging = true;
				dragOffset.set(mousePosition.x - x, mousePosition.y - y);
				if (onFocus != null) onFocus(this);
			}
		}

		if (dragging) {
			if (FlxG.mouse.pressed) {
				FlxG.mouse.getWorldPosition(uiCamera, mousePosition);
				x = FlxMath.bound(mousePosition.x - dragOffset.x, 0, Math.max(FlxG.width - windowWidth, 0));
				y = FlxMath.bound(mousePosition.y - dragOffset.y, 0, Math.max(FlxG.height - 34, 0));
			} else {
				dragging = false;
			}
		}

		updatePreviewCamera();
		danceTimer += elapsed;
		var danceInterval:Float = Conductor.bpm > 0 ? 60 / Conductor.bpm : 0.5;
		danceInterval = Math.max(0.25, Math.min(1.5, danceInterval));
		if (character != null && character.lastAnimContext == PlayAnimContext.DANCE && danceTimer >= danceInterval && character.isAnimFinished()) {
			danceTimer = 0;
			character.dance();
			var currentAnimation = character.getAnimName();
			if (currentAnimation != null && character.isAnimFinished())
				character.playAnim(currentAnimation, true, character.lastAnimContext);
		}
	}

	public override function destroy():Void {
		super.destroy();
		FlxG.cameras.remove(previewCamera);
		dragOffset.put();
		mousePosition.put();
		characterBounds.put();
	}
}
