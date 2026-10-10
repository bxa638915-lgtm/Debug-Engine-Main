import cne.compat.PsychLuaPropertyPath;

class PsychLuaPropertyPathTest
{
	static function assertTrue(value:Bool, message:String):Void
	{
		if (!value) throw message;
	}

	static function main():Void
	{
		var root:Dynamic = {members: [{alpha: 0.25}, {alpha: 0.75}], nested: {value: 10}};
		assertTrue(PsychLuaPropertyPath.read(root, "members[1].alpha") == 0.75, "Psych property paths must index group member arrays");
		assertTrue(PsychLuaPropertyPath.read(root, "nested.value") == 10, "Psych property paths must read nested fields");
		assertTrue(PsychLuaPropertyPath.write(root, "members[0].alpha", 0.5) == 0.5, "Psych property paths must return the assigned value");
		assertTrue(root.members[0].alpha == 0.5, "Psych property paths must write indexed nested fields");
		var strum:Dynamic = {noteAngle: 0.0, angle: 0.0};
		assertTrue(PsychLuaPropertyPath.read(strum, "direction") == 90.0, "Psych strum direction reads must expose CNE's note movement angle in Psych degrees");
		assertTrue(PsychLuaPropertyPath.write(strum, "direction", 180.0) == 180.0 && strum.noteAngle == 90.0,
			"Psych strum direction writes must change note movement without rotating the receptor");
		var character:Dynamic = {cameraOffset: {x: 15.0, y: -25.0}};
		assertTrue(PsychLuaPropertyPath.read(character, "cameraPosition[0]") == 15.0, "character.cameraPosition[0] must fallback to cameraOffset.x");
		assertTrue(PsychLuaPropertyPath.read(character, "cameraPosition[1]") == -25.0, "character.cameraPosition[1] must fallback to cameraOffset.y");
		var playState:Dynamic = {};
		assertTrue(PsychLuaPropertyPath.read(playState, "opponentCameraOffset[0]") == 0.0, "opponentCameraOffset[0] must fallback to 0");
		PsychLuaPropertyPath.write(playState, "opponentCameraOffset[0]", 45.0);
		assertTrue(PsychLuaPropertyPath.read(playState, "opponentCameraOffset[0]") == 45.0, "opponentCameraOffset[0] write must persist in cameraOffsets map");
		assertTrue(PsychLuaPropertyPath.read(playState, "girlfriendCameraOffset[1]") == 0.0, "girlfriendCameraOffset[1] must fallback to 0");
		assertTrue(PsychLuaPropertyPath.read(null, "cameraPosition[0]") == 0.0, "null target cameraPosition[0] must safely return 0.0");
		var spriteClip:Dynamic = {frame: {frame: {width: 100.0}}};
		var readVal:Dynamic = PsychLuaPropertyPath.read(spriteClip, "_frame.frame.width");
		assertTrue(readVal == 100.0, "_frame.frame fallback must resolve sprite frame");
		PsychLuaPropertyPath.write(spriteClip, "_frame.frame.width", 50.0);
		assertTrue(spriteClip.frame.frame.width == 50.0, "writing _frame.frame.width must update underlying frame");
		assertTrue(PsychLuaPropertyPath.read(root, "members[9].alpha") == null, "Out-of-range property paths on arrays must return safe null");
		Sys.println("PsychLuaPropertyPathTest: PASS");
	}
}
