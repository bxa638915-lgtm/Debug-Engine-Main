package funkin.editors.charter;

import flixel.animation.FlxAnimation;
import flixel.math.FlxPoint;
import flixel.math.FlxRect;
import flixel.util.FlxColor;
import flixel.util.FlxDestroyUtil;
import funkin.game.Character;
import funkin.backend.scripting.events.sprite.PlayAnimContext;
import funkin.backend.system.Conductor;

/** A movable, independently closable character preview pane for the chart editor. */
class CharterCharacterPreviewWindow extends UISliceSprite {
	public var isPlayer(default, null):Bool;
	public var previewCamera(default, null):FlxCamera;
	public var chromeCamera(default, null):FlxCamera;
	public var character(default, null):Character;
	public var onClose:Void->Void;
	public var onFocus:CharterCharacterPreviewWindow->Void;

	private var titleText:UIText;
	private var minimizeButton:UIButton;
	private var closeButton:UIButton;
	private var resizeHandle:FlxSprite;
	private var characterName:String = null;
	private var collapsed:Bool = false;
	private var dragging:Bool = false;
	private var resizing:Bool = false;
	private var dragOffset:FlxPoint = FlxPoint.get();
	private var resizeStartSize:FlxPoint = FlxPoint.get();
	private var resizeStartMouse:FlxPoint = FlxPoint.get();
	private var mousePosition:FlxPoint = FlxPoint.get();
	private var titleBounds:FlxRect = new FlxRect();
	private var characterBounds:FlxRect = new FlxRect();
	private var danceTimer:Float = 0;
	private var uiCamera:FlxCamera;
	private var windowWidth:Int;
	private var windowHeight:Int;

	private var savedEnvelope:Array<Float> = null;
	public var userZoom:Float = 1.0;
	public var fitZoom:Float = 1.0;
	private var panning:Bool = false;
	private var panStartMouse:FlxPoint = FlxPoint.get();
	private var panStartScroll:FlxPoint = FlxPoint.get();

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

		chromeCamera = new FlxCamera();
		chromeCamera.bgColor = 0;
		chromeCamera.scroll.set();
		FlxG.cameras.add(chromeCamera, false);

		titleText = new UIText(x + 12, y + 7, width - 76, "", 15, -1);
		members.push(titleText);

		minimizeButton = new UIButton(x + width - 58, y + 3, "-", toggleCollapsed, 25, 24);
		minimizeButton.autoFrames = false;
		members.push(minimizeButton);

		closeButton = new UIButton(x + width - 30, y + 3, "x", closeWindow, 25, 24);
		closeButton.autoFrames = false;
		members.push(closeButton);

		resizeHandle = new FlxSprite(x + width - 14, y + height - 14);
		resizeHandle.makeGraphic(12, 12, FlxColor.TRANSPARENT, true);
		for (dx in 0...10) {
			for (dy in 0...10) {
				if (dx + dy == 4 || dx + dy == 7 || dx + dy == 10)
					resizeHandle.pixels.setPixel32(11 - dx, 11 - dy, 0x88FFFFFF);
			}
		}
		members.push(resizeHandle);
		setChromeCamera(chromeCamera);

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
		if (chromeCamera != null) chromeCamera.visible = value;
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

	public function isMouseOver():Bool {
		if (!visible) return false;
		FlxG.mouse.getWorldPosition(uiCamera, mousePosition);
		return mousePosition.x >= x && mousePosition.x <= x + windowWidth &&
			mousePosition.y >= y && mousePosition.y <= y + (collapsed ? 34 : windowHeight);
	}

	public function setChromeCamera(camera:FlxCamera):Void {
		// Keep the opaque window skin behind the character viewport. Only the
		// title and controls belong on the topmost camera.
		cameras = [uiCamera];
		if (titleText != null) titleText.cameras = [camera];
		if (minimizeButton != null) minimizeButton.cameras = [camera];
		if (closeButton != null) closeButton.cameras = [camera];
		if (resizeHandle != null) resizeHandle.cameras = [camera];
	}

	private function closeWindow():Void {
		setPreviewVisible(false);
		if (onClose != null) onClose();
	}

	private function toggleCollapsed():Void {
		collapsed = !collapsed;
		resize(windowWidth, collapsed ? 34 : windowHeight);
		previewCamera.visible = visible && !collapsed;
		if (chromeCamera != null) chromeCamera.visible = visible;
		updatePositions();
		updatePreviewCamera();
		if (!collapsed) updateCharacterPlacement();
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

		var nameList = character.getNameList();
		if (nameList != null) {
			for (animationName in nameList) {
				var animData = character.getAnim(animationName);
				if (animData == null) continue;
				if (Std.isOfType(animData, FlxAnimation)) {
					var animation:FlxAnimation = cast animData;
					if (animation.numFrames <= 0) continue;
					for (frameIndex in 0...animation.numFrames) {
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

		savedEnvelope = envelope;

		var rawW = CharterCharacterPreviewLayout.getWindowWidth(envelope[2] - envelope[0]);
		var rawH = CharterCharacterPreviewLayout.getWindowHeight(envelope[3] - envelope[1]);

		// Limit initial window size so large characters don't blow up the window
		windowWidth = CharterCharacterPreviewLayout.clampWindowWidth(rawW);
		windowHeight = CharterCharacterPreviewLayout.clampWindowHeight(rawH);

		// Character changes can alter the auto-sized window; keep it reachable.
		x = FlxMath.bound(x, 0, Math.max(FlxG.width - windowWidth, 0));
		y = FlxMath.bound(y, 0, Math.max(FlxG.height - (collapsed ? 34 : windowHeight), 0));

		resize(windowWidth, collapsed ? 34 : windowHeight);
		updatePositions();
		updatePreviewCamera();
		updateCharacterPlacement();
	}

	public function updateCharacterPlacement():Void {
		if (character == null || previewCamera == null || savedEnvelope == null) return;

		var viewportW = previewCamera.width;
		var viewportH = previewCamera.height;
		var envW = Math.max(savedEnvelope[2] - savedEnvelope[0], 1);
		var envH = Math.max(savedEnvelope[3] - savedEnvelope[1], 1);

		var availW = Math.max(viewportW - (CharterCharacterPreviewLayout.VIEWPORT_PADDING_X * 2), 1);
		var availH = Math.max(viewportH - (CharterCharacterPreviewLayout.VIEWPORT_PADDING_Y * 2), 1);

		if (envW > availW || envH > availH) {
			fitZoom = Math.min(availW / envW, availH / envH);
		} else {
			fitZoom = 1.0;
		}

		// Center the character envelope inside the camera viewport
		var envelopeCenterX = (savedEnvelope[0] + savedEnvelope[2]) / 2;
		var envelopeCenterY = (savedEnvelope[1] + savedEnvelope[3]) / 2;
		character.x = (viewportW / 2) - envelopeCenterX;
		character.y = (viewportH / 2) - envelopeCenterY;

		previewCamera.zoom = fitZoom * userZoom;
	}

	public function resizeWindow(newWidth:Int, newHeight:Int):Void {
		windowWidth = Std.int(Math.max(CharterCharacterPreviewLayout.MIN_WINDOW_WIDTH, Math.min(FlxG.width - x, newWidth)));
		windowHeight = Std.int(Math.max(CharterCharacterPreviewLayout.MIN_WINDOW_HEIGHT, Math.min(FlxG.height - y, newHeight)));
		resize(windowWidth, collapsed ? 34 : windowHeight);
		updatePositions();
		updatePreviewCamera();
		updateCharacterPlacement();
	}

	private function updatePositions():Void {
		titleText.x = x + 12;
		titleText.y = y + 7;
		titleText.fieldWidth = windowWidth - 76;
		minimizeButton.x = x + windowWidth - 58;
		minimizeButton.y = y + 3;
		closeButton.x = x + windowWidth - 30;
		closeButton.y = y + 3;
		if (resizeHandle != null) {
			resizeHandle.x = x + windowWidth - 14;
			resizeHandle.y = y + (collapsed ? 34 : windowHeight) - 14;
			resizeHandle.visible = !collapsed && visible;
		}
	}

	private function updatePreviewCamera():Void {
		if (previewCamera == null) return;
		previewCamera.setPosition(x + 4, y + 33);
		previewCamera.setSize(Std.int(Math.max(windowWidth - 8, 1)), Std.int(Math.max((collapsed ? 34 : windowHeight) - 37, 1)));
		previewCamera.visible = visible && !collapsed;
	}

	public override function update(elapsed:Float):Void {
		super.update(elapsed);
		if (!visible) return;

		var titlePrefix = TU.translate(isPlayer ? "charter.view.playerPreview" : "charter.view.opponentPreview");
		if (character != null) titleText.text = '$titlePrefix: ${character.curCharacter}';
		updatePositions();

		FlxG.mouse.getWorldPosition(uiCamera, mousePosition);

		// Handle window resizing via mouse drag on bottom-right corner
		var inResizeZone = !collapsed && (mousePosition.x >= x + windowWidth - 18 && mousePosition.x <= x + windowWidth &&
										 mousePosition.y >= y + windowHeight - 18 && mousePosition.y <= y + windowHeight);

		if (!collapsed && FlxG.mouse.justPressed && inResizeZone) {
			resizing = true;
			resizeStartSize.set(windowWidth, windowHeight);
			resizeStartMouse.set(mousePosition.x, mousePosition.y);
			if (onFocus != null) onFocus(this);
		}

		if (resizing) {
			if (FlxG.mouse.pressed) {
				var deltaX = mousePosition.x - resizeStartMouse.x;
				var deltaY = mousePosition.y - resizeStartMouse.y;
				resizeWindow(Std.int(resizeStartSize.x + deltaX), Std.int(resizeStartSize.y + deltaY));
			} else {
				resizing = false;
			}
		}

		// Handle window dragging via title bar
		if (!resizing && !closeButton.hovered && !minimizeButton.hovered) {
			titleBounds.set(x, y, windowWidth, 31);
			if (FlxG.mouse.justPressed && UIState.state.isOverlapping(this, titleBounds)) {
				dragging = true;
				dragOffset.set(mousePosition.x - x, mousePosition.y - y);
				if (onFocus != null) onFocus(this);
			}
		}

		if (dragging) {
			if (FlxG.mouse.pressed) {
				x = FlxMath.bound(mousePosition.x - dragOffset.x, 0, Math.max(FlxG.width - windowWidth, 0));
				y = FlxMath.bound(mousePosition.y - dragOffset.y, 0, Math.max(FlxG.height - 34, 0));
			} else {
				dragging = false;
			}
		}

		// Handle mouse wheel zoom & right-click/middle-click pan inside preview window
		if (!collapsed && isMouseOver()) {
			if (FlxG.mouse.wheel != 0) {
				userZoom += FlxG.mouse.wheel * 0.1;
				userZoom = CoolUtil.bound(userZoom, 0.2, 5.0);
				previewCamera.zoom = fitZoom * userZoom;
			}

			if (FlxG.mouse.justPressedMiddle) {
				userZoom = 1.0;
				previewCamera.scroll.set(0, 0);
				previewCamera.zoom = fitZoom * userZoom;
			}

			if (FlxG.mouse.justPressedRight) {
				panning = true;
				panStartMouse.set(mousePosition.x, mousePosition.y);
				panStartScroll.set(previewCamera.scroll.x, previewCamera.scroll.y);
			}
		}

		if (panning) {
			if (FlxG.mouse.pressedRight) {
				var dx = (mousePosition.x - panStartMouse.x) / previewCamera.zoom;
				var dy = (mousePosition.y - panStartMouse.y) / previewCamera.zoom;
				previewCamera.scroll.x = panStartScroll.x - dx;
				previewCamera.scroll.y = panStartScroll.y - dy;
			} else {
				panning = false;
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
		if (previewCamera != null) {
			FlxG.cameras.remove(previewCamera);
			previewCamera = null;
		}
		if (chromeCamera != null) {
			FlxG.cameras.remove(chromeCamera);
			chromeCamera = null;
		}
		dragOffset = FlxDestroyUtil.put(dragOffset);
		resizeStartSize = FlxDestroyUtil.put(resizeStartSize);
		resizeStartMouse = FlxDestroyUtil.put(resizeStartMouse);
		panStartMouse = FlxDestroyUtil.put(panStartMouse);
		panStartScroll = FlxDestroyUtil.put(panStartScroll);
		mousePosition = FlxDestroyUtil.put(mousePosition);
	}
}
