local fixtureId = "psych-1.0.4-hscript-interop"
local expectedProfile = "1.0.4"

local function fail(message)
	debugPrint("DBE_PSYCH_LUA_ERROR:" .. fixtureId .. ":" .. message)
	error(fixtureId .. ":" .. message)
end

local function expectEqual(name, actual, expected)
	if actual ~= expected then fail(name .. " expected " .. tostring(expected) .. ", got " .. tostring(actual)) end
end

function onCreatePost()
	local profile = engine and engine.compatibility and engine.compatibility.psychLuaProfile
	if profile ~= expectedProfile then fail("expected profile " .. expectedProfile .. ", got " .. tostring(profile)) end
	debugPrint("DBE_PSYCH_PROFILE:" .. profile)

	addHaxeLibrary("StringTools")
	local result = runHaxeCode([[
function dbeTask6Function(value) {
	return task6Provided * value;
}
task6Provided + 1
]], { task6Provided = 12 }, "dbeTask6Function", { 4 })
	expectEqual("runHaxeCode callback return and injected variables", result, 48)
	expectEqual("runHaxeFunction persistent interpreter", runHaxeFunction("dbeTask6Function", { 3 }), 36)
	expectEqual("addHaxeLibrary binding", runHaxeCode("StringTools.trim('  Psych  ')"), "Psych")

	expectEqual("addHScript void return", addHScript("scripts/dbe_task6_helper.hx"), nil)
	expectEqual("removeHScript", removeHScript("dbe_task6_helper.hx"), true)
	expectEqual("remove missing HScript", removeHScript("dbe_task6_helper.hx"), false)
	debugPrint("DBE_PSYCH_FIXTURE_PASS:" .. fixtureId)
end
