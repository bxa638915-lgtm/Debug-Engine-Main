package funkin.editors.uibuilder;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.text.FlxText;
import funkin.backend.assets.Paths;
import funkin.editors.uibuilder.UIBuilderData;
import funkin.game.Character;
import openfl.utils.Assets;

/** Shared component renderer used by both the UI Builder canvas and generated HScript layouts. */
class UIBuilderRuntimeRenderer {
	public static function renderProject(project:UIProjectData, ?camera:FlxCamera):Array<FlxSprite> {
		var rendered:Array<FlxSprite> = [];
		for (element in UIBuilderData.visibleElementsInRenderOrder(project))
			for (sprite in renderElement(element, camera))
				rendered.push(sprite);
		return rendered;
	}

	/** Creates and adds all visible layout components to a runtime state. */
	public static function createRuntimeElements(project:UIProjectData, targetState:Dynamic, ?defaultCamera:Dynamic, ?namedElements:Map<String, Dynamic>):Array<Dynamic> {
		if (targetState == null) targetState = FlxG.state;
		if (targetState == null)
			throw new haxe.Exception("Cannot render a UI layout without a target state.");

		var state:FlxState = cast targetState;
		var fallbackCamera:FlxCamera = cast defaultCamera;
		if (fallbackCamera == null) fallbackCamera = cast Reflect.field(targetState, "camHUD");
		if (fallbackCamera == null) fallbackCamera = FlxG.camera;

		var result:Array<Dynamic> = [];
		for (element in UIBuilderData.visibleElementsInRenderOrder(project)) {
			var camera:FlxCamera = fallbackCamera;
			if (element.camera != null && element.camera != "") {
				var elementCamera:Dynamic = Reflect.field(targetState, element.camera);
				if (Std.isOfType(elementCamera, FlxCamera)) camera = cast elementCamera;
			}

			var componentSprites = renderElement(element, camera, namedElements);
			for (sprite in componentSprites) {
				state.add(sprite);
				result.push(sprite);
			}
		}
		return result;
	}

	/** Removes and destroys the exact sprites created by createRuntimeElements. */
	public static function destroyRuntimeElements(elements:Array<Dynamic>, ?targetState:Dynamic):Void {
		if (elements == null) return;
		var state:FlxState = targetState == null ? null : cast targetState;
		for (element in elements) {
			if (element == null) continue;
			var sprite:FlxSprite = Std.isOfType(element, FlxSprite) ? cast element : null;
			if (sprite == null) continue;
			if (state != null) state.remove(sprite, false);
			sprite.destroy();
		}
		elements.resize(0);
	}

	static function renderElement(element:UIElementData, ?camera:FlxCamera, ?namedElements:Map<String, Dynamic>):Array<FlxSprite> {
		var sprites:Array<FlxSprite> = [];
		var primary:FlxSprite = null;
		var panelLabel:FlxText = null;

		switch (element.type) {
			case PANEL:
				primary = _graphic(element.x, element.y, element.width, element.height, element.bgColor, element);
				sprites.push(primary);
				_solidBorder(sprites, element.x, element.y, element.width, element.height, element.borderColor, 2, element, camera);
				if (element.text != "") {
					panelLabel = _text(element.x + 8, element.y + 4, element.width - 16, element.text, element.fontSize, element, camera);
					panelLabel.color = element.borderColor;
					sprites.push(panelLabel);
				}

			case BUTTON:
				primary = _graphic(element.x, element.y, element.width, element.height, element.bgColor, element);
				sprites.push(primary);
				_solidBorder(sprites, element.x, element.y, element.width, element.height, element.borderColor, 2, element, camera);
				if (element.text != "") {
					var label = _text(element.x, element.y + (element.height - element.fontSize) * 0.5 - 2, element.width, element.text, element.fontSize, element, camera);
					label.alignment = "center";
					label.color = element.color;
					sprites.push(label);
				}

			case TEXT:
				primary = _text(element.x, element.y, element.width, element.text, element.fontSize, element, camera);
				primary.color = element.color;
				(cast primary:FlxText).alignment = element.alignment;
				sprites.push(primary);

			case PROGRESS_BAR:
				primary = _graphic(element.x, element.y, element.width, element.height, element.bgColor, element);
				primary.origin.x = 0;
				sprites.push(primary);
				var fill = _graphic(element.x, element.y, Std.int(Math.max(1, element.width * 0.65)), element.height, element.color, element);
				sprites.push(fill);
				_solidBorder(sprites, element.x, element.y, element.width, element.height, element.borderColor, 1, element, camera);
				var progressLabel = _text(element.x, element.y + (element.height - 14) * 0.5, element.width, element.text, 12, element, camera);
				progressLabel.alignment = "center";
				progressLabel.color = 0xFFFFFFFF;
				sprites.push(progressLabel);

			case CHECKBOX:
				var boxY = element.y + (element.height - 20) * 0.5;
				primary = _graphic(element.x, boxY, 20, 20, element.bgColor, element);
				sprites.push(primary);
				_solidBorder(sprites, element.x, boxY, 20, 20, element.borderColor, 2, element, camera);
				var checkboxLabel = _text(element.x + 28, element.y + (element.height - element.fontSize) * 0.5, element.width - 28, element.text, element.fontSize, element, camera);
				checkboxLabel.color = element.color;
				sprites.push(checkboxLabel);

			case IMAGE:
				var image = new FlxSprite(element.x, element.y);
				var loaded = false;
				if (element.imagePath != null && element.imagePath != "") {
					try {
						var assetPath = Paths.image(element.imagePath);
						if (assetPath != null && Assets.exists(assetPath)) {
							image.loadGraphic(assetPath);
							image.setGraphicSize(element.width, element.height);
							image.updateHitbox();
							loaded = true;
						}
					} catch (_:Dynamic) {}
				}
				if (!loaded) {
					image.makeGraphic(element.width, element.height, 0xFF222238);
					image.alpha = element.alpha;
					_applyComponentState(image, element, camera);
					sprites.push(image);
					_solidBorder(sprites, element.x, element.y, element.width, element.height, 0xFF555577, 1, element, camera);
					var imageLabel = _text(element.x, element.y + (element.height - 14) * 0.5, element.width, '[Image: ${element.imagePath != "" ? element.imagePath : "none"}]', 12, element, camera);
					imageLabel.alignment = "center";
					imageLabel.color = 0xFF9999BB;
					sprites.push(imageLabel);
				} else {
					_applyComponentState(image, element, camera);
					sprites.push(image);
				}
				primary = image;

			case CHARACTER:
				var charName = element.text != null && element.text != "" ? element.text : "bf";
				var isPlayer = element.extra != null && Reflect.field(element.extra, "isPlayer") == true;
				var anim:Dynamic = element.extra == null ? null : Reflect.field(element.extra, "anim");
				if (anim == null || anim == "") anim = "idle";
				try {
					var character = new Character(element.x, element.y, charName, isPlayer);
					character.playAnim(Std.string(anim));
					_applyComponentState(character, element, camera);
					primary = character;
					sprites.push(character);
				} catch (_:Dynamic) {
					primary = _graphic(element.x, element.y, element.width, element.height, 0xFF352240, element);
					sprites.push(primary);
					_solidBorder(sprites, element.x, element.y, element.width, element.height, 0xFFFF00C8, 1, element, camera);
					var characterLabel = _text(element.x, element.y + (element.height - 14) * 0.5, element.width, '[Character: $charName]', 12, element, camera);
					characterLabel.alignment = "center";
					characterLabel.color = 0xFFFF88EE;
					sprites.push(characterLabel);
				}

			case INPUT_BOX:
				primary = _graphic(element.x, element.y, element.width, element.height, element.bgColor, element);
				sprites.push(primary);
				_solidBorder(sprites, element.x, element.y, element.width, element.height, element.borderColor, 1, element, camera);
				var inputLabel = _text(element.x + 6, element.y + (element.height - element.fontSize) * 0.5, element.width - 12, element.text, element.fontSize, element, camera);
				inputLabel.color = 0xFF888888;
				sprites.push(inputLabel);
		}

		if (camera != null)
			for (sprite in sprites) sprite.cameras = [camera];

		if (namedElements != null && primary != null) {
			namedElements.set(element.id, primary);
			if (panelLabel != null) namedElements.set(element.id + "_label", panelLabel);
		}
		return sprites;
	}

	static function _graphic(x:Float, y:Float, width:Int, height:Int, color:Int, element:UIElementData):FlxSprite {
		var sprite = new FlxSprite(x, y);
		sprite.makeGraphic(width, height, color);
		_applyComponentState(sprite, element, null);
		return sprite;
	}

	static function _text(x:Float, y:Float, width:Float, text:String, size:Int, element:UIElementData, camera:FlxCamera):FlxText {
		var sprite = new FlxText(x, y, width, text, size);
		_applyComponentState(sprite, element, camera);
		return sprite;
	}

	static function _solidBorder(target:Array<FlxSprite>, x:Float, y:Float, width:Int, height:Int, color:Int, thickness:Int, element:UIElementData, camera:FlxCamera):Void {
		var sprite = new FlxSprite(x, y);
		sprite.makeGraphic(width, height, 0x00000000, true);
		var bitmap = sprite.graphic.bitmap;
		for (t in 0...thickness) {
			for (px in 0...width) {
				bitmap.setPixel32(px, t, color);
				bitmap.setPixel32(px, height - 1 - t, color);
			}
			for (py in 0...height) {
				bitmap.setPixel32(t, py, color);
				bitmap.setPixel32(width - 1 - t, py, color);
			}
		}
		_applyComponentState(sprite, element, camera);
		target.push(sprite);
	}

	static function _applyComponentState(sprite:FlxSprite, element:UIElementData, camera:FlxCamera):Void {
		sprite.alpha = element.alpha;
		sprite.visible = element.visible;
		sprite.active = element.active;
		sprite.scrollFactor.set(element.scrollFactorX, element.scrollFactorY);
		if (camera != null) sprite.cameras = [camera];
	}
}
