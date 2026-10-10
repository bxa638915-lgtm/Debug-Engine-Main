package cne.compat;

import flixel.ui.FlxBar;
import flixel.util.FlxColor;
import funkin.game.PlayState;

/** FlxBar wrapper exposing the Psych Engine `setColors(left, right)` method. */
class PsychTimeBar extends FlxBar
{
	var leftColor:FlxColor = FlxColor.WHITE;
	var rightColor:FlxColor = FlxColor.BLACK;

	public function new(game:PlayState, x:Float, y:Float, width:Int, height:Int)
	{
		super(x, y, LEFT_TO_RIGHT, width, height, game, "psychSongPercent", 0, 1);
		createFilledBar(rightColor, leftColor);
		numDivisions = width;
		continuous = true;
	}

	public function setColors(left:Null<FlxColor> = null, right:Null<FlxColor> = null):Void
	{
		if (left != null) leftColor = left;
		if (right != null) rightColor = right;
		createFilledBar(rightColor, leftColor);
	}
}
