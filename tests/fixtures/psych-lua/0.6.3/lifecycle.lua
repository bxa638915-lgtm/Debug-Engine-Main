local fixtureId = "psych-0.6.3-lifecycle"
local expectedProfile = "0.6.3"

local function fail(message)
	debugPrint("DBE_PSYCH_LUA_ERROR:" .. fixtureId .. ":" .. message)
	error(fixtureId .. ":" .. message)
end

local function expectEqual(name, actual, expected)
	if actual ~= expected then
		fail(name .. " expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local function checkProfile()
	local actualProfile = engine and engine.compatibility and engine.compatibility.psychLuaProfile
	if actualProfile ~= expectedProfile then fail("expected profile " .. expectedProfile .. ", got " .. tostring(actualProfile)) end
	debugPrint("DBE_PSYCH_PROFILE:" .. actualProfile)
end

function onCreatePost()
	checkProfile()
	debugPrint("DBE_PSYCH_CALLBACK:" .. fixtureId .. ":onCreatePost")
	expectEqual("stringStartsWith", stringStartsWith("Psych Engine", "Psych"), true)
	expectEqual("stringEndsWith", stringEndsWith("Psych Engine", "Engine"), true)
	expectEqual("stringTrim", stringTrim("  DBE  "), "DBE")
	local pieces = stringSplit("a/b", "/")
	expectEqual("stringSplit length", #pieces, 2)
	expectEqual("getRandomBool 100%", getRandomBool(100), true)
	expectEqual("getRandomFloat fixed range", getRandomFloat(2.5, 2.5), 2.5)
	expectEqual("getRandomInt fixed range", getRandomInt(7, 7), 7)

	local scripts = getRunningScripts()
	local foundSelf = false
	for _, scriptPath in ipairs(scripts) do
		if string.find(scriptPath, fixtureId, 1, true) then foundSelf = true end
	end
	expectEqual("getRunningScripts contains self", foundSelf, true)
	expectEqual("isRunning self", isRunning(fixtureId .. ".lua"), true)
	expectEqual("addLuaScript duplicate", addLuaScript(fixtureId .. ".lua"), false)
	expectEqual("removeLuaScript missing", removeLuaScript("dbe-missing-script.lua"), false)
	expectEqual("isRunning missing", isRunning("dbe-missing-script.lua"), false)

	addCharacterToList("dad", "dad")
	precacheImage("characters/bf")
	local originalX = getCharacterX("dad")
	local originalY = getCharacterY("dad")
	if originalX == nil or originalY == nil then fail("character coordinates returned nil") end
	expectEqual("setCharacterX", setCharacterX("dad", originalX + 2), true)
	expectEqual("character X side effect", getCharacterX("dad"), originalX + 2)
	expectEqual("setCharacterY", setCharacterY("dad", originalY + 2), true)
	expectEqual("character Y side effect", getCharacterY("dad"), originalY + 2)
	setCharacterX("dad", originalX)
	setCharacterY("dad", originalY)
	if getMidpointX("dad") == nil or getMidpointY("dad") == nil then fail("character midpoint returned nil") end
	characterDance("dad")
	characterPlayAnim("dad", "idle", true)

	debugPrint("DBE_PSYCH_FIXTURE_PASS:" .. fixtureId)
	close()
end
