local fixtureId = "psych-0.6.3-saves-settings-achievements"
local expectedProfile = "0.6.3"
local modName = "__DBE_TEMP_MOD__"
local saveName = "dbe_task6_" .. modName

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

	expectEqual("initSaveData void return", initSaveData(saveName), nil)
	local stage = getDataFromSave(saveName, "stage", 0)
	local initialSave = (expectedProfile == "0.6.3" and stage == nil) or stage == 0
	if initialSave then
		local initialValue = getDataFromSave(saveName, "value", 0)
		if expectedProfile == "0.6.3" then
			expectEqual("0.6.3 missing field ignores default", initialValue, nil)
		else
			expectEqual("1.0.4 missing field uses default", initialValue, 0)
		end
		setDataFromSave(saveName, "value", 73)
		setDataFromSave(saveName, "stage", 1)
		expectEqual("flushSaveData void return", flushSaveData(saveName), nil)
		restartSong()
		return
	end
	if stage ~= 1 then fail("unexpected persistence stage " .. tostring(stage)) end
	expectEqual("value persisted through state restart", getDataFromSave(saveName, "value", 0), 73)

	expectEqual("configured mod setting", getModSetting("dbeTask6Setting"), "loaded-from-mod")
	local settingsText = getTextFromFile("data/settings.json")
	if type(settingsText) ~= "string" or not string.find(settingsText, "dbeTask6Setting", 1, true) then fail("mod settings file was not readable") end
	local filePath = "data/dbe-task6.txt"
	expectEqual("saveFile", saveFile(filePath, "psych-lua-persistence"), true)
	expectEqual("checkFileExists after write", checkFileExists(filePath), true)
	expectEqual("getTextFromFile after write", getTextFromFile(filePath), "psych-lua-persistence")
	local files = directoryFileList("mods")
	if type(files) ~= "table" then fail("directoryFileList did not return an array") end
	expectEqual("deleteFile", deleteFile(filePath), true)
	expectEqual("checkFileExists after delete", checkFileExists(filePath), false)
	expectEqual("getTextFromFile after delete", getTextFromFile(filePath), nil)

	setHealth(1.5)
	expectEqual("setHealth", getHealth(), 1.5)
	addHealth(-0.25)
	expectEqual("addHealth", getHealth(), 1.25)
	setScore(18)
	addScore(4)
	expectEqual("getScore", getScore(), 22)
	if type(getSongPosition()) ~= "number" then fail("getSongPosition did not return a number") end
	expectEqual("triggerEvent return", triggerEvent("camera follow pos", "", ""), true)
	expectEqual("missing startVideo", startVideo("dbe_task6_missing_video"), false)
	setRatingPercent(0.75)
	setRatingName("Fixture")
	setRatingFC("SFC")
	updateScoreText()
	expectEqual("score update", getProperty("songScore"), 22)
	expectEqual("changePresence void return", changePresence("In the Menus", nil, nil, false, 0), nil)
	setDataFromSave(saveName, "stage", nil)
	setDataFromSave(saveName, "value", nil)
	flushSaveData(saveName)
	debugPrint("DBE_PSYCH_FIXTURE_PASS:" .. fixtureId)
end
