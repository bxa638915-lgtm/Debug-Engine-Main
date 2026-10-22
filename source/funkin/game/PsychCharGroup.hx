package funkin.game;

import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.util.FlxColor;

/**
 * Compatibility group wrapper for Psych Engine character groups (dadGroup, boyfriendGroup, gfGroup).
 * Keeps track of base stage coordinates and group-level offsets so that Lua scripts querying
 * `dadGroup.x` or tweening `dadGroup` behave exactly as in Psych Engine 1.0.4.
**/
@:keep
class PsychCharGroup extends FlxBasic {
	public var baseX:Float = 0;
	public var baseY:Float = 0;
	public var groupOffsetX:Float = 0;
	public var groupOffsetY:Float = 0;
	public var characters:Array<Character> = [];

	public var x(get, set):Float;
	private inline function get_x():Float return baseX + groupOffsetX;
	private function set_x(value:Float):Float {
		var delta = value - (baseX + groupOffsetX);
		groupOffsetX = value - baseX;
		for (c in characters) {
			if (c != null) c.x += delta;
		}
		return value;
	}

	public var y(get, set):Float;
	private inline function get_y():Float return baseY + groupOffsetY;
	private function set_y(value:Float):Float {
		var delta = value - (baseY + groupOffsetY);
		groupOffsetY = value - baseY;
		for (c in characters) {
			if (c != null) c.y += delta;
		}
		return value;
	}

	public var alpha(get, set):Float;
	private function get_alpha():Float {
		for (c in characters) if (c != null) return c.alpha;
		return 1.0;
	}
	private function set_alpha(value:Float):Float {
		for (c in characters) if (c != null) c.alpha = value;
		return value;
	}

	override function set_visible(value:Bool):Bool {
		for (c in characters) if (c != null) c.visible = value;
		return visible = value;
	}

	public var color(get, set):FlxColor;
	private function get_color():FlxColor {
		for (c in characters) if (c != null) return c.color;
		return FlxColor.WHITE;
	}
	private function set_color(value:FlxColor):FlxColor {
		for (c in characters) if (c != null) c.color = value;
		return value;
	}

	override function get_cameras():Array<FlxCamera> {
		for (c in characters) if (c != null) return c.cameras;
		return super.get_cameras();
	}
	override function set_cameras(value:Array<FlxCamera>):Array<FlxCamera> {
		for (c in characters) if (c != null) c.cameras = value;
		return super.set_cameras(value);
	}

	public var members(get, never):Array<Character>;
	private inline function get_members():Array<Character> return characters;

	public var length(get, never):Int;
	private inline function get_length():Int return characters.length;

	public function new(baseX:Float = 0, baseY:Float = 0) {
		super();
		this.baseX = baseX;
		this.baseY = baseY;
		this.visible = true;
	}

	public function resetBase(x:Float, y:Float):Void {
		this.baseX = x;
		this.baseY = y;
	}

	public function add(char:Character):Character {
		if (char != null && !characters.contains(char)) {
			characters.push(char);
			if (groupOffsetX != 0) char.x += groupOffsetX;
			if (groupOffsetY != 0) char.y += groupOffsetY;
		}
		return char;
	}

	public function remove(char:Character):Character {
		if (char != null) {
			characters.remove(char);
		}
		return char;
	}

	public function clear():Void {
		characters = [];
		groupOffsetX = 0;
		groupOffsetY = 0;
	}

	public inline function iterator():Iterator<Character> {
		return characters.iterator();
	}
}
