package funkin.editors.charter;

typedef CharterPreviewCharacterChange = {
	var target:String;
	var characterName:String;
}

/** Small, engine-independent helpers for dispatching chart preview actions. */
class CharterPreviewTimeline {
	/** Returns whether an action lies in the forward interval (previous, current]. */
	public static inline function crosses(actionTime:Float, previousTime:Float, currentTime:Float):Bool
		return currentTime > previousTime && actionTime > previousTime && actionTime <= currentTime;

	/** Orders actions by time, with gameplay events before note hits at the same time. */
	public static inline function compare(timeA:Float, isEventA:Bool, sequenceA:Int, timeB:Float, isEventB:Bool, sequenceB:Int):Int {
		if (timeA < timeB) return -1;
		if (timeA > timeB) return 1;
		if (isEventA != isEventB) return isEventA ? -1 : 1;
		if (sequenceA < sequenceB) return -1;
		if (sequenceA > sequenceB) return 1;
		return 0;
	}

	/** Resolves the character target used by Psych's Change Character event. */
	public static function parseCharacterChange(eventName:String, params:Array<Dynamic>):Null<CharterPreviewCharacterChange> {
		if (eventName == null || StringTools.trim(eventName).toLowerCase() != "change character" || params == null || params.length < 2)
			return null;

		var target = params[0] == null ? "" : StringTools.trim(Std.string(params[0])).toLowerCase();
		var role:String = switch (target) {
			case "0" | "bf" | "boyfriend" | "player": "player";
			case "1" | "dad" | "opponent": "opponent";
			case "2" | "gf" | "girlfriend": "girlfriend";
			default: return null;
		}

		var characterName = params[1] == null ? "" : StringTools.trim(Std.string(params[1]));
		if (characterName.length == 0) return null;
		return {target: role, characterName: characterName};
	}
}
