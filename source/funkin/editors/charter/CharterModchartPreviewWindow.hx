package funkin.editors.charter;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.math.FlxRect;
import flixel.util.FlxColor;
import flixel.util.FlxDestroyUtil;
import funkin.backend.system.Conductor;
import funkin.editors.ui.UIButton;
import funkin.editors.ui.UISliceSprite;
import funkin.editors.ui.UIText;
import dbe.modchart.ModchartSimulator;
import dbe.modchart.ModchartSimulator.ModchartConfig;
import dbe.modchart.ModchartPresetRegistry;

/**
 * Janela flutuante no Chart Editor para pré-visualização em tempo real de Modcharts e Presets.
 */
class CharterModchartPreviewWindow extends UISliceSprite {
	public var previewCamera(default, null):FlxCamera;
	public var chromeCamera(default, null):FlxCamera;
	public var onClose:Void->Void;
	public var onFocus:CharterModchartPreviewWindow->Void;

	public var activeConfig:ModchartConfig;
	public var isPlayingPreview:Bool = true;
	public var previewTime:Float = 0.0;

	private var titleText:UIText;
	private var minimizeButton:UIButton;
	private var closeButton:UIButton;
	private var presetButton:UIButton;
	private var playPauseButton:UIButton;
	private var resizeHandle:FlxSprite;

	private var collapsed:Bool = false;
	private var dragging:Bool = false;
	private var resizing:Bool = false;
	private var dragOffset:FlxPoint = FlxPoint.get();
	private var resizeStartSize:FlxPoint = FlxPoint.get();
	private var resizeStartMouse:FlxPoint = FlxPoint.get();
	private var mousePosition:FlxPoint = FlxPoint.get();
	private var titleBounds:FlxRect = new FlxRect();

	private var uiCamera:FlxCamera;
	private var windowWidth:Int;
	private var windowHeight:Int;

	private var presetKeys:Array<String>;
	private var currentPresetIndex:Int = 0;

	// Sprites dos Receptores (4 do Oponente + 4 do Jogador)
	private var strumsGroup:FlxTypedGroup<FlxSprite>;
	private var opponentStrums:Array<FlxSprite> = [];
	private var playerStrums:Array<FlxSprite> = [];
	private var baseStrumPositions:Array<FlxPoint> = [];

	private static inline var STRUM_SPACING:Float = 52.0;

	public function new(x:Float, y:Float, width:Int, height:Int, uiCamera:FlxCamera, onClose:Void->Void, ?onFocus:CharterModchartPreviewWindow->Void) {
		super(x, y, width, height, "editors/ui/normal-popup");
		this.uiCamera = uiCamera;
		this.onClose = onClose;
		this.onFocus = onFocus;
		this.windowWidth = width;
		this.windowHeight = height;
		this.cameras = [uiCamera];

		presetKeys = ModchartPresetRegistry.getPresetKeys();
		if (presetKeys.length == 0) presetKeys = ["impostor_alert"];
		activeConfig = ModchartPresetRegistry.getPreset(presetKeys[currentPresetIndex]);

		previewCamera = new FlxCamera();
		previewCamera.bgColor = 0xFF14141E;
		previewCamera.scroll.set();
		FlxG.cameras.add(previewCamera, false);

		chromeCamera = new FlxCamera();
		chromeCamera.bgColor = 0;
		chromeCamera.scroll.set();
		FlxG.cameras.add(chromeCamera, false);

		titleText = new UIText(x + 12, y + 7, width - 110, "MODCHART: " + activeConfig.name, 13, -1);
		members.push(titleText);

		playPauseButton = new UIButton(x + width - 90, y + 3, "||", togglePlayPause, 24, 24);
		playPauseButton.autoFrames = false;
		members.push(playPauseButton);

		minimizeButton = new UIButton(x + width - 60, y + 3, "-", toggleCollapsed, 24, 24);
		minimizeButton.autoFrames = false;
		members.push(minimizeButton);

		closeButton = new UIButton(x + width - 30, y + 3, "x", closeWindow, 24, 24);
		closeButton.autoFrames = false;
		members.push(closeButton);

		presetButton = new UIButton(x + 12, y + height - 32, "Preset: " + activeConfig.name, nextPreset, width - 24, 24);
		members.push(presetButton);

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
		_buildStrumSprites();
		updatePreviewCamera();
	}

	private function _buildStrumSprites():Void {
		strumsGroup = new FlxTypedGroup<FlxSprite>();
		members.push(strumsGroup);

		var colors = [0xFFC24B99, 0xFF00FFFF, 0xFF12FA05, 0xFFF9393F]; // Esquerda, Baixo, Cima, Direita

		// 4 Receptores do Oponente
		for (i in 0...4) {
			var spr = new FlxSprite();
			spr.makeGraphic(42, 42, colors[i % 4]);
			spr.cameras = [previewCamera];
			opponentStrums.push(spr);
			strumsGroup.add(spr);
			baseStrumPositions.push(FlxPoint.get(40 + (i * STRUM_SPACING), 80));
		}

		// 4 Receptores do Jogador
		for (i in 0...4) {
			var spr = new FlxSprite();
			spr.makeGraphic(42, 42, colors[i % 4]);
			spr.cameras = [previewCamera];
			playerStrums.push(spr);
			strumsGroup.add(spr);
			baseStrumPositions.push(FlxPoint.get(280 + (i * STRUM_SPACING), 80));
		}
	}

	public function setChromeCamera(cam:FlxCamera):Void {
		this.cameras = [cam];
		titleText.cameras = [cam];
		minimizeButton.cameras = [cam];
		closeButton.cameras = [cam];
		presetButton.cameras = [cam];
		playPauseButton.cameras = [cam];
		resizeHandle.cameras = [cam];
	}

	private function updatePreviewCamera():Void {
		if (previewCamera == null) return;
		var inset = 6;
		var topBar = 32;
		var bottomBar = 38;
		previewCamera.x = Std.int(x + inset);
		previewCamera.y = Std.int(y + topBar);
		previewCamera.width = Std.int(Math.max(10, windowWidth - (inset * 2)));
		previewCamera.height = Std.int(Math.max(10, windowHeight - topBar - bottomBar));
	}

	public function nextPreset():Void {
		if (presetKeys.length == 0) return;
		currentPresetIndex = (currentPresetIndex + 1) % presetKeys.length;
		activeConfig = ModchartPresetRegistry.getPreset(presetKeys[currentPresetIndex]);
		titleText.text = "MODCHART: " + activeConfig.name;
		if (presetButton.field != null) presetButton.field.text = "Preset: " + activeConfig.name;
	}

	public function togglePlayPause():Void {
		isPlayingPreview = !isPlayingPreview;
		if (playPauseButton.field != null) playPauseButton.field.text = isPlayingPreview ? "||" : ">";
	}

	public function toggleCollapsed():Void {
		collapsed = !collapsed;
		previewCamera.visible = !collapsed;
		presetButton.visible = !collapsed;
		if (collapsed) {
			bHeight = 34;
		} else {
			bHeight = windowHeight;
			updatePreviewCamera();
		}
	}

	public function closeWindow():Void {
		visible = false;
		active = false;
		if (previewCamera != null) previewCamera.visible = false;
		if (chromeCamera != null) chromeCamera.visible = false;
		if (onClose != null) onClose();
	}

	public function updateSimulation(songPos:Float, curBeat:Float, elapsed:Float):Void {
		if (!visible || collapsed) return;

		var curTime = isPlayingPreview ? songPos : previewTime;
		if (isPlayingPreview && songPos <= 0) {
			previewTime += elapsed * 1000.0;
			curTime = previewTime;
		}

		// Atualiza Receptores do Oponente
		for (i in 0...opponentStrums.length) {
			var base = baseStrumPositions[i];
			var trans = ModchartSimulator.calculateReceptorTransform(i, 4, false, base.x, base.y, curTime, curBeat, activeConfig);
			var spr = opponentStrums[i];
			spr.x = trans.x;
			spr.y = trans.y;
			spr.angle = trans.angle;
			spr.scale.set(trans.scaleX, trans.scaleY);
			spr.alpha = trans.alpha;
		}

		// Atualiza Receptores do Jogador
		for (i in 0...playerStrums.length) {
			var base = baseStrumPositions[4 + i];
			var trans = ModchartSimulator.calculateReceptorTransform(i, 4, true, base.x, base.y, curTime, curBeat, activeConfig);
			var spr = playerStrums[i];
			spr.x = trans.x;
			spr.y = trans.y;
			spr.angle = trans.angle;
			spr.scale.set(trans.scaleX, trans.scaleY);
			spr.alpha = trans.alpha;
		}
	}

	override public function update(elapsed:Float):Void {
		super.update(elapsed);

		if (!visible) return;

		mousePosition.set(FlxG.mouse.screenX, FlxG.mouse.screenY);
		titleBounds.set(x, y, windowWidth - 95, 30);

		if (FlxG.mouse.justPressed) {
			if (titleBounds.containsPoint(mousePosition)) {
				dragging = true;
				dragOffset.set(mousePosition.x - x, mousePosition.y - y);
				if (onFocus != null) onFocus(this);
			} else if (mousePosition.x >= x + windowWidth - 16 && mousePosition.y >= y + windowHeight - 16 && !collapsed) {
				resizing = true;
				resizeStartSize.set(windowWidth, windowHeight);
				resizeStartMouse.set(mousePosition.x, mousePosition.y);
				if (onFocus != null) onFocus(this);
			}
		}

		if (dragging) {
			x = Std.int(mousePosition.x - dragOffset.x);
			y = Std.int(mousePosition.y - dragOffset.y);
			_syncWindowPositions();
		}

		if (resizing) {
			var newW = Std.int(Math.max(280, resizeStartSize.x + (mousePosition.x - resizeStartMouse.x)));
			var newH = Std.int(Math.max(180, resizeStartSize.y + (mousePosition.y - resizeStartMouse.y)));
			windowWidth = newW;
			windowHeight = newH;
			bWidth = newW;
			bHeight = newH;
			_syncWindowPositions();
		}

		if (FlxG.mouse.justReleased) {
			dragging = false;
			resizing = false;
		}

		updateSimulation(Conductor.songPosition, (Conductor.songPosition / 1000.0) * (Conductor.bpm / 60.0), elapsed);
	}

	private function _syncWindowPositions():Void {
		titleText.x = x + 12;
		titleText.y = y + 7;
		playPauseButton.x = x + windowWidth - 90;
		playPauseButton.y = y + 3;
		minimizeButton.x = x + windowWidth - 60;
		minimizeButton.y = y + 3;
		closeButton.x = x + windowWidth - 30;
		closeButton.y = y + 3;
		presetButton.x = x + 12;
		presetButton.y = y + windowHeight - 32;
		presetButton.bWidth = windowWidth - 24;
		resizeHandle.x = x + windowWidth - 14;
		resizeHandle.y = y + windowHeight - 14;
		updatePreviewCamera();
	}

	override public function destroy():Void {
		if (previewCamera != null) {
			FlxG.cameras.remove(previewCamera, false);
			previewCamera.destroy();
			previewCamera = null;
		}
		if (chromeCamera != null) {
			FlxG.cameras.remove(chromeCamera, false);
			chromeCamera.destroy();
			chromeCamera = null;
		}

		dragOffset = FlxDestroyUtil.put(dragOffset);
		resizeStartSize = FlxDestroyUtil.put(resizeStartSize);
		resizeStartMouse = FlxDestroyUtil.put(resizeStartMouse);
		mousePosition = FlxDestroyUtil.put(mousePosition);

		for (p in baseStrumPositions) FlxDestroyUtil.put(p);
		baseStrumPositions = [];

		super.destroy();
	}
}
