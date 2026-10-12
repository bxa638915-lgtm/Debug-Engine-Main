import cne.compat.PsychLuaCamera;

class PsychLuaCameraTest
{
	static function assertSame(actual:Dynamic, expected:Dynamic, message:String):Void
	{
		if (actual != expected) throw message;
	}

	static function main():Void
	{
		var gameCamera:Dynamic = {name: "game"};
		var hudCamera:Dynamic = {name: "hud"};
		var otherCamera:Dynamic = {name: "other"};
		var fallbackCamera:Dynamic = {name: "fallback"};

		assertSame(PsychLuaCamera.resolve("other", gameCamera, hudCamera, otherCamera, fallbackCamera), otherCamera,
			"Psych 'other' camera must resolve to CNE camOther");
		assertSame(PsychLuaCamera.resolve("camother", gameCamera, hudCamera, otherCamera, fallbackCamera), otherCamera,
			"Psych 'camother' camera alias must resolve to CNE camOther");
		assertSame(PsychLuaCamera.resolve("game", gameCamera, hudCamera, otherCamera, fallbackCamera), gameCamera,
			"Psych 'game' camera must remain mapped to CNE camGame");
		assertSame(PsychLuaCamera.resolve("camHUD", gameCamera, hudCamera, otherCamera, fallbackCamera), hudCamera,
			"Psych 'camHUD' camera alias must resolve to CNE camHUD");
		assertSame(PsychLuaCamera.resolve("unknown", gameCamera, hudCamera, otherCamera, fallbackCamera), fallbackCamera,
			"Unknown camera names must preserve the existing fallback");
		Sys.println("PsychLuaCameraTest: PASS");
	}
}