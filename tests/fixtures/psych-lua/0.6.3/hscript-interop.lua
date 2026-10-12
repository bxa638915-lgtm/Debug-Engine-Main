local fixtureId = "psych-0.6.3-hscript-interop"
local expectedProfile = "0.6.3"

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
	expectEqual("HScript executes after addHaxeLibrary initializes it", runHaxeCode("StringTools.trim('  Psych  ')"), "Psych")
	expectEqual("first runHaxeCode expression result", runHaxeCode("13 * 3"), 39)
	debugPrint("DBE_PSYCH_FIXTURE_PASS:" .. fixtureId)
end
