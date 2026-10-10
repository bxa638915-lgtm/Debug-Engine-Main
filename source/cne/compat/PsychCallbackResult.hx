package cne.compat;

/** Return markers and dispatch rules used by Psych's script callback helpers. */
class PsychCallbackResult
{
	public static inline var FUNCTION_STOP:String = "##PSYCHLUA_FUNCTIONSTOP";
	public static inline var FUNCTION_CONTINUE:String = "##PSYCHLUA_FUNCTIONCONTINUE";
	public static inline var FUNCTION_STOP_LUA:String = "##PSYCHLUA_FUNCTIONSTOPLUA";
	public static inline var FUNCTION_STOP_HSCRIPT:String = "##PSYCHLUA_FUNCTIONSTOPHSCRIPT";
	public static inline var FUNCTION_STOP_ALL:String = "##PSYCHLUA_FUNCTIONSTOPALL";

	public static function shouldStopLua(value:Dynamic, ignoreStops:Bool, excludeValues:Array<Dynamic>):Bool
		return !ignoreStops && (value == FUNCTION_STOP_LUA || value == FUNCTION_STOP_ALL) && !contains(excludeValues, value);

	public static function shouldStopHScript(value:Dynamic, ignoreStops:Bool, excludeValues:Array<Dynamic>):Bool
		return !ignoreStops && (value == FUNCTION_STOP_HSCRIPT || value == FUNCTION_STOP_ALL) && !contains(excludeValues, value);

	public static function shouldCallHScript(luaResult:Dynamic, excludeValues:Array<Dynamic>):Bool
		return luaResult == null || contains(excludeValues, luaResult);

	public static function includeResult(value:Dynamic, excludeValues:Array<Dynamic>):Bool
		return value != null && !contains(excludeValues, value);

	public static function contains(values:Array<Dynamic>, value:Dynamic):Bool
		return values != null && values.indexOf(value) != -1;
}
