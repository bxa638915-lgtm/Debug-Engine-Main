local fixtureId = "psych-1.0.4-end-song"
local expectedProfile = "1.0.4"

local function fail(message)
	debugPrint("DBE_PSYCH_LUA_ERROR:" .. fixtureId .. ":" .. message)
	error(fixtureId .. ":" .. message)
end

function onCreatePost()
	local profile = engine and engine.compatibility and engine.compatibility.psychLuaProfile
	if profile ~= expectedProfile then fail("expected profile " .. expectedProfile .. ", got " .. tostring(profile)) end
	debugPrint("DBE_PSYCH_PROFILE:" .. profile)
	local result = endSong()
	if result ~= true then fail("endSong expected true, got " .. tostring(result)) end
	debugPrint("DBE_PSYCH_FIXTURE_PASS:" .. fixtureId)
end
