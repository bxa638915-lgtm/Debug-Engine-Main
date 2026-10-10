import llua.Lua;
import llua.LuaL;
import llua.LuaOpen;
import llua.State;
import cne.compat.LuaCallbackScope;

class LuaRuntimeTest
{
	static function assertTrue(value:Bool, message:String):Void
	{
		if (!value) throw message;
	}

	static function main():Void
	{
		var state:State = LuaL.newstate();
		assertTrue(state != null, "LuaJIT must allocate a state");
		LuaOpen.base(state);
		LuaOpen.math(state);
		LuaOpen.string(state);
		LuaOpen.table(state);
		Lua.init_callbacks(state);
		Lua.register(state, "bridgeAdd", (left:Float, right:Float) -> left + right);

		var loadStatus = LuaL.dostring(state, "function runAdapterCheck() return bridgeAdd(math.floor(2.5), tonumber('40')) end");
		assertTrue(loadStatus == Lua.LUA_OK, "Lua source must load successfully");
		Lua.getglobal(state, "runAdapterCheck");
		var callStatus = Lua.pcall(state, 0, 1, 0);
		assertTrue(callStatus == Lua.LUA_OK, "Lua callback and standard libraries must execute");
		assertTrue(Lua.tonumber(state, -1) == 42, "Haxe callbacks must round-trip a numeric return value");
		Lua.settop(state, 0);
		Lua.close(state);

		var firstState:State = LuaL.newstate();
		var secondState:State = LuaL.newstate();
		LuaL.openlibs(firstState);
		LuaL.openlibs(secondState);
		var callbackErrors = 0;
		var firstScope = new LuaCallbackScope(firstState, (error:Dynamic) -> callbackErrors++);
		var secondScope = new LuaCallbackScope(secondState);
		firstScope.bind("getInstanceValue", () -> 11);
		secondScope.bind("getInstanceValue", () -> 22);
		firstScope.bind("returnNil", () -> null);
		firstScope.bind("returnUnsupported", () -> Date.now());
		firstScope.bind("throwFromHaxe", () -> throw "expected callback failure");
		assertTrue(LuaL.dostring(firstState, "function readValue() return getInstanceValue() end") == Lua.LUA_OK, "First Lua state must load its callback test");
		assertTrue(LuaL.dostring(secondState, "function readValue() return getInstanceValue() end") == Lua.LUA_OK, "Second Lua state must load its callback test");
		Lua.getglobal(firstState, "readValue");
		assertTrue(Lua.pcall(firstState, 0, 1, 0) == Lua.LUA_OK && Lua.tonumber(firstState, -1) == 11, "First script must call its own Haxe callback");
		Lua.settop(firstState, 0);
		Lua.getglobal(secondState, "readValue");
		assertTrue(Lua.pcall(secondState, 0, 1, 0) == Lua.LUA_OK && Lua.tonumber(secondState, -1) == 22, "Second script must call its own Haxe callback");
		Lua.settop(secondState, 0);
		assertTrue(LuaL.dostring(firstState, "function readNil() return returnNil() end; function readUnsupported() return returnUnsupported() end; function readFailure() return throwFromHaxe() end") == Lua.LUA_OK, "Lua nil and error callbacks must load");
		Lua.getglobal(firstState, "readNil");
		assertTrue(Lua.pcall(firstState, 0, 1, 0) == Lua.LUA_OK && Lua.isnil(firstState, -1) != 0, "Void Haxe callbacks must return Lua nil");
		Lua.settop(firstState, 0);
		Lua.getglobal(firstState, "readUnsupported");
		assertTrue(Lua.pcall(firstState, 0, 1, 0) == Lua.LUA_OK && Lua.isnil(firstState, -1) != 0, "Unsupported Haxe values must return Lua nil");
		Lua.settop(firstState, 0);
		Lua.getglobal(firstState, "readFailure");
		assertTrue(Lua.pcall(firstState, 0, 1, 0) == Lua.LUA_OK && Lua.isnil(firstState, -1) != 0, "Haxe callback exceptions must not cross the native Lua boundary");
		assertTrue(callbackErrors == 1, "Callback exceptions must be reported to the owning adapter");
		Lua.settop(firstState, 0);
		firstScope.dispose();
		secondScope.dispose();
		Lua.close(firstState);
		Lua.close(secondState);

		state = LuaL.newstate();
		LuaL.openlibs(state);
		var syntaxStatus = LuaL.dostring(state, "function broken( {");
		assertTrue(syntaxStatus != Lua.LUA_OK, "Invalid Lua source must return an error status");
		Lua.close(state);
		Sys.println("LuaRuntimeTest: PASS");
	}
}
