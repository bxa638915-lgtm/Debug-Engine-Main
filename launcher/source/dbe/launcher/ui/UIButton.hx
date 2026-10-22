package dbe.launcher.ui;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;
import flixel.util.FlxColor;

class UIButton extends FlxSpriteGroup {
	public var bg:FlxSprite;
	public var border:FlxSprite;
	public var label:FlxText;

	public var normalColor:FlxColor;
	public var hoverColor:FlxColor;
	public var pressedColor:FlxColor;
	public var disabledColor:FlxColor;

	public var normalTextColor:FlxColor = UITheme.TEXT;
	public var hoverTextColor:FlxColor = FlxColor.WHITE;
	public var disabledTextColor:FlxColor = UITheme.TEXT_DARK;

	public var enabled:Bool = true;
	public var onClick:() -> Void;

	var isHovered:Bool = false;
	var isPressed:Bool = false;

	public function new(x:Float, y:Float, width:Int, height:Int, text:String, ?onClick:() -> Void, ?bgColor:FlxColor, ?fontSize:Int = 16) {
		super(x, y);
		this.onClick = onClick;

		var baseCol = bgColor == null ? UITheme.BG_CARD : bgColor;
		normalColor = baseCol;
		hoverColor = baseCol == UITheme.PRIMARY ? UITheme.PRIMARY_HOVER : (baseCol == UITheme.SUCCESS ? UITheme.SUCCESS_HOVER : UITheme.BG_HOVER);
		pressedColor = baseCol == UITheme.PRIMARY ? UITheme.PRIMARY_DARK : UITheme.BG_PANEL;
		disabledColor = UITheme.BG_PANEL;

		border = new FlxSprite(0, 0);
		border.makeGraphic(width, height, UITheme.BORDER);
		add(border);

		bg = new FlxSprite(1, 1);
		bg.makeGraphic(width - 2, height - 2, normalColor);
		add(bg);

		label = new FlxText(4, Math.floor((height - fontSize) / 2) - 2, width - 8, text, fontSize);
		label.font = UITheme.FONT;
		label.alignment = CENTER;
		label.color = normalTextColor;
		add(label);
	}

	override public function update(elapsed:Float) {
		super.update(elapsed);

		if (!visible) return;

		if (!enabled) {
			bg.color = disabledColor;
			border.color = UITheme.BORDER;
			label.color = disabledTextColor;
			return;
		}

		var overlaps = FlxG.mouse.overlaps(bg);
		if (overlaps) {
			if (!isHovered) {
				isHovered = true;
			}

			if (FlxG.mouse.pressed) {
				isPressed = true;
				bg.color = pressedColor;
				border.color = UITheme.PRIMARY;
			} else {
				if (isPressed && FlxG.mouse.justReleased) {
					isPressed = false;
					if (onClick != null) onClick();
				}
				bg.color = hoverColor;
				border.color = UITheme.BORDER_LIGHT;
			}
			label.color = hoverTextColor;
		} else {
			isHovered = false;
			isPressed = false;
			bg.color = normalColor;
			border.color = UITheme.BORDER;
			label.color = normalTextColor;
		}
	}

	public function setText(text:String) {
		label.text = text;
	}
}
