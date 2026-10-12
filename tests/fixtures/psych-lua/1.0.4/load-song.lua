local fixtureId = "psych-1.0.4-load-song"
local expectedProfile = "1.0.4"
local modName = "__DBE_TEMP_MOD__"
local saveName = "dbe_task6_load_song_" .. modName

local function fail(message)
	debugPrint("DBE_PSYCH_LUA_ERROR:" .. fixtureId .. ":" .. message)
	error(fixtureId .. ":" .. message)
end

function onCreatePost()
	local profile = engine and engine.compatibility and engine.compatibility.psychLuaProfile
	if profile ~= expectedProfile then fail("expected profile " .. expectedProfile .. ", got " .. tostring(profile)) end
	debugPrint("DBE_PSYCH_PROFILE:" .. profile)
	initSaveData(saveName)
	local stage = getDataFromSave(saveName, "requested", 0)
	local firstRun = (expectedProfile == "0.6.3" and stage == nil) or stage == 0
	if firstRun then
		setDataFromSave(saveName, "requested", 1)
		flushSaveData(saveName)
		local result = loadSong("bopeebo", "normal")
		if result ~= nil then fail("loadSong expected nil, got " .. tostring(result)) end
		return
	end
	if stage ~= 1 then fail("unexpected loadSong fixture stage " .. tostring(stage)) end
	setDataFromSave(saveName, "requested", nil)
	flushSaveData(saveName)
	debugPrint("DBE_PSYCH_FIXTURE_PASS:" .. fixtureId)
end
