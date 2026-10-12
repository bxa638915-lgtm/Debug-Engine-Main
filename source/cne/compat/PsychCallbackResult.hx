package cne.compat;

/** Return markers and dispatch rules used by Psych's script callback helpers. */
class PsychCallbackResult
{
	public static inline var FUNCTION_STOP:String = "##PSYCHLUA_FUNCTIONSTOP";
	public static inline var FUNCTION_CONTINUE:String = "##PSYCHLUA_FUNCTIONCONTINUE";
	public static inline var FUNCTION_STOP_LUA:String = "##PSYCHLUA_FUNCTIONSTOPLUA";
	public static inline var FUNCTION_STOP_HSCRIPT:String = "##PSYCHLUA_FUNCTIONSTOPHSCRIPT";
	public static inline var FUNCTION_STOP_ALL:String = "##PSYCHLUA_FUNCTIONSTOPALL";

	/** Return constants exposed by the selected upstream Psych Lua profile. */
	public static function constantsForProfile(profile:String):Dynamic
	{
		if (profile == "0.6.3")
			return {stop: 1, continueValue: 0, stopLua: 2, stopHScript: null, stopAll: null};
		return {
			stop: FUNCTION_STOP,
			continueValue: FUNCTION_CONTINUE,
			stopLua: FUNCTION_STOP_LUA,
			stopHScript: FUNCTION_STOP_HSCRIPT,
			stopAll: FUNCTION_STOP_ALL
		};
	}

	public static function continueValueForProfile(profile:String):Dynamic
		return profile == "0.6.3" ? 0 : FUNCTION_CONTINUE;

	public static function stopValueForProfile(profile:String):Dynamic
		return profile == "0.6.3" ? 1 : FUNCTION_STOP;

	public static function stopLuaValueForProfile(profile:String):Dynamic
		return profile == "0.6.3" ? 2 : FUNCTION_STOP_LUA;

	public static function defaultExcludeValues(profile:String):Array<Dynamic>
		return [continueValueForProfile(profile)];

	public static function shouldStopLua(value:Dynamic, ignoreStops:Bool, excludeValues:Array<Dynamic>, ?profile:String):Bool
		return !ignoreStops && (value == stopLuaValueForProfile(profile) || (profile != "0.6.3" && value == FUNCTION_STOP_ALL)) && !contains(excludeValues, value);

	public static function shouldStopHScript(value:Dynamic, ignoreStops:Bool, excludeValues:Array<Dynamic>, ?profile:String):Bool
		return profile != "0.6.3" && !ignoreStops && value != null && (value == FUNCTION_STOP_HSCRIPT || value == FUNCTION_STOP_ALL) && !contains(excludeValues, value);

	public static function shouldCallHScript(luaResult:Dynamic, excludeValues:Array<Dynamic>):Bool
		return luaResult == null || contains(excludeValues, luaResult);

	public static function includeResult(value:Dynamic, excludeValues:Array<Dynamic>):Bool
		return value != null && !contains(excludeValues, value);

	/** Dispatches callbacks in load order, retaining the last included value and source stop behavior. */
	public static function dispatchLuaCallbacks(callbacks:Array<Array<Dynamic>->Dynamic>, args:Array<Dynamic>, profile:String, ?ignoreStops:Bool = false,
		?excludeValues:Array<Dynamic>, ?onError:Dynamic->Void):Dynamic
	{
		if (excludeValues == null) excludeValues = defaultExcludeValues(profile);
		var result:Dynamic = continueValueForProfile(profile);
		if (callbacks == null) return result;
		for (callback in callbacks)
		{
			var value:Dynamic;
			try
			{
				value = callback == null ? null : callback(args == null ? [] : args);
			}
			catch (error:Dynamic)
			{
				if (onError != null) onError(error);
				value = continueValueForProfile(profile);
			}

			if (shouldStopLua(value, ignoreStops, excludeValues, profile))
			{
				result = value;
				break;
			}
			if (includeResult(value, excludeValues)) result = value;
		}
		return result;
	}

	/** Dispatches HScript callbacks using Psych 1.0.4's separate HScript stop markers. */
	public static function dispatchHScriptCallbacks(callbacks:Array<Array<Dynamic>->Dynamic>, args:Array<Dynamic>, profile:String, ?ignoreStops:Bool = false,
		?excludeValues:Array<Dynamic>, ?onError:Dynamic->Void):Dynamic
	{
		if (excludeValues == null) excludeValues = defaultExcludeValues(profile);
		var result:Dynamic = continueValueForProfile(profile);
		if (callbacks == null) return result;
		for (callback in callbacks)
		{
			var value:Dynamic;
			try
			{
				value = callback == null ? null : callback(args == null ? [] : args);
			}
			catch (error:Dynamic)
			{
				if (onError != null) onError(error);
				value = continueValueForProfile(profile);
			}

			if (shouldStopHScript(value, ignoreStops, excludeValues, profile))
			{
				result = value;
				break;
			}
			if (includeResult(value, excludeValues)) result = value;
		}
		return result;
	}

	public static function contains(values:Array<Dynamic>, value:Dynamic):Bool
		return values != null && values.indexOf(value) != -1;
}
