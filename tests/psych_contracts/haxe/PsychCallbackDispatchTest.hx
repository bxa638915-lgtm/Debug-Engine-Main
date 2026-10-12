package;

import cne.compat.PsychCallbackResult;

class PsychCallbackDispatchTest
{
	static function main():Void
	{
		var oldConstants = PsychCallbackResult.constantsForProfile("0.6.3");
		assertEquals(1, oldConstants.stop, "Psych 0.6.3 Function_Stop");
		assertEquals(0, oldConstants.continueValue, "Psych 0.6.3 Function_Continue");
		assertEquals(2, oldConstants.stopLua, "Psych 0.6.3 Function_StopLua");
		assertEquals(null, oldConstants.stopHScript, "Psych 0.6.3 has no Function_StopHScript");
		assertEquals(null, oldConstants.stopAll, "Psych 0.6.3 has no Function_StopAll");

		var newConstants = PsychCallbackResult.constantsForProfile("1.0.4");
		assertEquals("##PSYCHLUA_FUNCTIONSTOP", newConstants.stop, "Psych 1.0.4 Function_Stop");
		assertEquals("##PSYCHLUA_FUNCTIONCONTINUE", newConstants.continueValue, "Psych 1.0.4 Function_Continue");
		assertEquals("##PSYCHLUA_FUNCTIONSTOPLUA", newConstants.stopLua, "Psych 1.0.4 Function_StopLua");
		assertEquals("##PSYCHLUA_FUNCTIONSTOPHSCRIPT", newConstants.stopHScript, "Psych 1.0.4 Function_StopHScript");
		assertEquals("##PSYCHLUA_FUNCTIONSTOPALL", newConstants.stopAll, "Psych 1.0.4 Function_StopAll");

		var order:Array<String> = [];
		var received:Array<Dynamic> = [];
		var callbacks:Array<Array<Dynamic>->Dynamic> = [];
		callbacks.push(function(args:Array<Dynamic>):Dynamic { order.push("lua-1"); received = args.copy(); return null; });
		callbacks.push(function(args:Array<Dynamic>):Dynamic { order.push("lua-2"); return "first-value"; });
		callbacks.push(function(args:Array<Dynamic>):Dynamic { order.push("lua-3"); return "last-value"; });
		var callbackArgs:Array<Dynamic> = [7, "player", true, "Hurt"];
		assertEquals("last-value", PsychCallbackResult.dispatchLuaCallbacks(callbacks, callbackArgs, "1.0.4"), "last included Lua result");
		assertArrayEquals(["lua-1", "lua-2", "lua-3"], order, "Lua callback order");
		var expectedArgs:Array<Dynamic> = [7, "player", true, "Hurt"];
		assertArrayEquals(expectedArgs, received, "callback argument order and conversions");

		assertDispatchStops("0.6.3", 2, false, "old Lua stop marker", true);
		assertDispatchStops("1.0.4", newConstants.stopLua, false, "Lua stop marker", true);
		assertDispatchStops("1.0.4", newConstants.stopAll, false, "all stop marker stops Lua", true);
		assertDispatchStops("1.0.4", newConstants.stop, false, "Function_Stop does not stop later Lua callbacks", false);
		assertDispatchStops("1.0.4", newConstants.stopLua, true, "ignoreStops continues Lua dispatch", false);

		var excludedCalls:Array<String> = [];
		var excludedCallbacks:Array<Array<Dynamic>->Dynamic> = [
			(args:Array<Dynamic>) -> { excludedCalls.push("stop"); return newConstants.stopLua; },
			(args:Array<Dynamic>) -> { excludedCalls.push("after"); return "included"; }
		];
		assertEquals("included", PsychCallbackResult.dispatchLuaCallbacks(excludedCallbacks, [], "1.0.4", false, [newConstants.stopLua]), "excluded stop value does not stop or replace result");
		assertArrayEquals(["stop", "after"], excludedCalls, "excludeValues keeps later Lua callbacks running");
		assertTrue(PsychCallbackResult.shouldCallHScript(0, [0]), "0.6.3 Function_Continue permits HScript fallback");
		assertFalse(PsychCallbackResult.shouldCallHScript(2, [0]), "0.6.3 Function_StopLua suppresses HScript fallback");

		var hscriptCalls:Array<String> = [];
		var hscriptCallbacks:Array<Array<Dynamic>->Dynamic> = [
			(args:Array<Dynamic>) -> { hscriptCalls.push("hscript-1"); return newConstants.stopHScript; },
			(args:Array<Dynamic>) -> { hscriptCalls.push("hscript-2"); return "unreached"; }
		];
		assertEquals(newConstants.stopHScript, PsychCallbackResult.dispatchHScriptCallbacks(hscriptCallbacks, [], "1.0.4"), "StopHScript result");
		assertArrayEquals(["hscript-1"], hscriptCalls, "StopHScript stops later HScript callbacks");

		var errors:Array<String> = [];
		var exceptionCallbacks:Array<Array<Dynamic>->Dynamic> = [
			(args:Array<Dynamic>) -> throw "fixture exception",
			(args:Array<Dynamic>) -> "after-exception"
		];
		assertEquals("after-exception", PsychCallbackResult.dispatchLuaCallbacks(exceptionCallbacks, [], "1.0.4", false, null, (error:Dynamic) -> errors.push(Std.string(error))), "exception does not stop subsequent callbacks");
		assertArrayEquals(["fixture exception"], errors, "callback exception reported once");

		trace("PsychCallbackDispatchTest passed");
	}

	static function assertDispatchStops(profile:String, marker:Dynamic, ignoreStops:Bool, label:String, expectStop:Bool):Void
	{
		var calls:Array<String> = [];
		var callbacks:Array<Array<Dynamic>->Dynamic> = [
			(args:Array<Dynamic>) -> { calls.push("first"); return marker; },
			(args:Array<Dynamic>) -> { calls.push("second"); return "after-stop"; }
		];
		var result = PsychCallbackResult.dispatchLuaCallbacks(callbacks, [], profile, ignoreStops);
		assertEquals(expectStop ? 1 : 2, calls.length, '$label call count');
		assertEquals(expectStop ? marker : "after-stop", result, '$label result');
	}

	static function assertTrue(value:Bool, label:String):Void
	{
		if (!value) throw '$label: expected true';
	}

	static function assertFalse(value:Bool, label:String):Void
	{
		if (value) throw '$label: expected false';
	}

	static function assertEquals<T>(expected:T, actual:T, label:String):Void
	{
		if (expected != actual) throw '$label: expected $expected, got $actual';
	}

	static function assertArrayEquals(expected:Array<Dynamic>, actual:Array<Dynamic>, label:String):Void
	{
		if (actual == null || expected.length != actual.length) throw '$label: expected $expected, got $actual';
		for (index in 0...expected.length)
			if (expected[index] != actual[index]) throw '$label: mismatch at $index, expected ${expected[index]}, got ${actual[index]}';
	}
}
