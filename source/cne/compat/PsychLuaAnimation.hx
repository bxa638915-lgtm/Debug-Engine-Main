package cne.compat;

import flixel.FlxSprite;

/** Reproduces Psych's rule that the first registered Lua animation starts immediately. */
class PsychLuaAnimation
{
	public static function playIfNeeded(sprite:FlxSprite, name:String, useCharacterHook:Bool):Void
	{
		if (sprite == null || sprite.animation == null || sprite.animation.curAnim != null) return;
		if (useCharacterHook)
		{
			var playAnim = Reflect.field(sprite, "playAnim");
			if (playAnim != null)
			{
				Reflect.callMethod(sprite, playAnim, [name, true]);
				return;
			}
		}
		sprite.animation.play(name, true);
	}
}
