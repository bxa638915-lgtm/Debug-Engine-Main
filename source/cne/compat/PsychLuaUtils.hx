package cne.compat;

import openfl.display.BlendMode;

class PsychLuaUtils
{
	public static function blendModeFromString(blend:String):BlendMode
	{
		if (blend == null) return BlendMode.NORMAL;
		return switch (StringTools.trim(blend).toLowerCase())
		{
			case "add": BlendMode.ADD;
			case "alpha": BlendMode.ALPHA;
			case "darken": BlendMode.DARKEN;
			case "difference": BlendMode.DIFFERENCE;
			case "erase": BlendMode.ERASE;
			case "hardlight": BlendMode.HARDLIGHT;
			case "invert": BlendMode.INVERT;
			case "layer": BlendMode.LAYER;
			case "lighten": BlendMode.LIGHTEN;
			case "multiply": BlendMode.MULTIPLY;
			case "normal": BlendMode.NORMAL;
			case "overlay": BlendMode.OVERLAY;
			case "screen": BlendMode.SCREEN;
			case "shader": BlendMode.SHADER;
			case "subtract": BlendMode.SUBTRACT;
			default: BlendMode.NORMAL;
		};
	}

	public static function getTweenEaseByString(?ease:String = ""):flixel.tweens.FlxEase.EaseFunction
	{
		if (ease == null || ease.length == 0) return flixel.tweens.FlxEase.linear;
		var normalized = StringTools.trim(ease);
		var easing = Reflect.field(flixel.tweens.FlxEase, normalized);
		if (easing == null) easing = Reflect.field(flixel.tweens.FlxEase, normalized.toLowerCase());
		if (easing == null)
		{
			var lower = normalized.toLowerCase();
			for (field in Type.getClassFields(flixel.tweens.FlxEase))
			{
				if (field.toLowerCase() == lower)
				{
					easing = Reflect.field(flixel.tweens.FlxEase, field);
					break;
				}
			}
		}
		return easing == null ? flixel.tweens.FlxEase.linear : cast easing;
	}

	public static function getTweenTypeByString(?type:String = ""):flixel.tweens.FlxTween.FlxTweenType
	{
		if (type == null) return flixel.tweens.FlxTween.FlxTweenType.ONESHOT;
		return switch (StringTools.trim(type).toLowerCase())
		{
			case "backward": flixel.tweens.FlxTween.FlxTweenType.BACKWARD;
			case "looping" | "loop": flixel.tweens.FlxTween.FlxTweenType.LOOPING;
			case "persist": flixel.tweens.FlxTween.FlxTweenType.PERSIST;
			case "pingpong": flixel.tweens.FlxTween.FlxTweenType.PINGPONG;
			default: flixel.tweens.FlxTween.FlxTweenType.ONESHOT;
		};
	}

	public static function cameraFromString(cam:Dynamic):flixel.FlxCamera
	{
		var game = funkin.game.PlayState.instance;
		var fallback:flixel.FlxCamera = (game != null && game.camGame != null) ? game.camGame : flixel.FlxG.camera;
		if (cam == null) return fallback;
		var str = Std.string(cam);
		if (game == null) return flixel.FlxG.camera;
		var resolved:flixel.FlxCamera = PsychLuaCamera.resolve(str, game.camGame, game.camHUD, game.camOther, fallback);
		return resolved != null ? resolved : fallback;
	}
}
