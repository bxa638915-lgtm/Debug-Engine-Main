import cne.compat.PsychCallbackResult;

class PsychCallbackResultTest
{
	static function main():Void
	{
		var defaults:Array<Dynamic> = [PsychCallbackResult.FUNCTION_CONTINUE];
		if (!PsychCallbackResult.shouldStopLua(PsychCallbackResult.FUNCTION_STOP_LUA, false, defaults)) throw "Function_StopLua must stop the remaining Lua callbacks";
		if (!PsychCallbackResult.shouldStopLua(PsychCallbackResult.FUNCTION_STOP_ALL, false, defaults)) throw "Function_StopAll must stop the remaining Lua callbacks";
		if (PsychCallbackResult.shouldStopLua(PsychCallbackResult.FUNCTION_STOP_HSCRIPT, false, defaults)) throw "Function_StopHScript must not stop Lua callbacks";
		if (PsychCallbackResult.shouldStopLua(PsychCallbackResult.FUNCTION_STOP_LUA, true, defaults)) throw "ignoreStops must allow the remaining Lua callbacks";
		if (PsychCallbackResult.shouldStopLua(PsychCallbackResult.FUNCTION_STOP_LUA, false, [PsychCallbackResult.FUNCTION_STOP_LUA])) throw "Excluded stop values must not stop Lua callbacks";

		if (!PsychCallbackResult.shouldStopHScript(PsychCallbackResult.FUNCTION_STOP_HSCRIPT, false, defaults)) throw "Function_StopHScript must stop the remaining HScript callbacks";
		if (!PsychCallbackResult.shouldStopHScript(PsychCallbackResult.FUNCTION_STOP_ALL, false, defaults)) throw "Function_StopAll must stop the remaining HScript callbacks";
		if (PsychCallbackResult.shouldStopHScript(PsychCallbackResult.FUNCTION_STOP_LUA, false, defaults)) throw "Function_StopLua must not stop HScript callbacks";
		if (PsychCallbackResult.shouldStopHScript(PsychCallbackResult.FUNCTION_STOP_HSCRIPT, true, defaults)) throw "ignoreStops must allow the remaining HScript callbacks";

		if (!PsychCallbackResult.shouldCallHScript(PsychCallbackResult.FUNCTION_CONTINUE, defaults)) throw "callOnScripts must continue to HScript when Lua only returns Function_Continue";
		if (PsychCallbackResult.shouldCallHScript("lua-result", defaults)) throw "callOnScripts must preserve a non-excluded Lua result";
		if (!PsychCallbackResult.includeResult("lua-result", defaults) || PsychCallbackResult.includeResult(PsychCallbackResult.FUNCTION_CONTINUE, defaults))
			throw "Callback results must honor excludeValues";

		Sys.println("PsychCallbackResultTest: PASS");
	}
}
