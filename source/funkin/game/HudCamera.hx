package funkin.game;

import flixel.math.FlxPoint;
import haxe.ds.ObjectMap;

/**
 * Camera meant for PlayState hud, allows for flipping the camera.
**/
class HudCamera extends FlxCamera {
	/**
	 * Whenever the camera should flip the y axis.
	 * Keeps the sprites not flipped, but the positions are flipped.
	 */
	public var downscroll:Bool = false;

	public static var bypassedObjects:ObjectMap<FlxObject, Bool> = new ObjectMap<FlxObject, Bool>();
	public static var bypassedXObjects:ObjectMap<FlxObject, Bool> = new ObjectMap<FlxObject, Bool>();

	public static inline function bypassDownscroll(obj:FlxObject):Void {
		if (obj != null) bypassedObjects.set(obj, true);
	}

	public static inline function shouldBypassDownscroll(spr:FlxObject):Bool {
		if (spr == null) return false;
		return bypassedObjects.exists(spr);
	}

	public static inline function bypassX(obj:FlxObject):Void {
		if (obj != null) bypassedXObjects.set(obj, true);
	}

	public static inline function shouldBypassX(spr:FlxObject):Bool {
		if (spr == null) return false;
		return bypassedXObjects.exists(spr);
	}

	public static function resetBypasses():Void {
		bypassedObjects = new ObjectMap<FlxObject, Bool>();
		bypassedXObjects = new ObjectMap<FlxObject, Bool>();
	}

	public override function alterScreenPosition(spr:FlxObject, pos:FlxPoint) {
		if (downscroll && !shouldBypassDownscroll(spr)) {
			pos.set(pos.x, height - pos.y - spr.height);
		}
		return pos;
	}
}