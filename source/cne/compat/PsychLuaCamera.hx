package cne.compat;

class PsychLuaCamera
{
	public static function resolve(camera:String, gameCamera:Dynamic, hudCamera:Dynamic, otherCamera:Dynamic, fallbackCamera:Dynamic):Dynamic
	{
		return switch (camera == null ? "game" : StringTools.trim(camera).toLowerCase())
		{
			case "hud" | "camhud": hudCamera;
			case "other" | "camother": otherCamera;
			case "game" | "camgame" | "": gameCamera;
			default: fallbackCamera;
		};
	}
}