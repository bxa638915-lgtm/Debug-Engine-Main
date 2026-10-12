local fixtureId = "psych-1.0.4-properties-groups"
local expectedProfile = "1.0.4"

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
	local originalZoom = getProperty("defaultCamZoom")
	expectEqual("setProperty 1.0.4 return", setProperty("defaultCamZoom", originalZoom + 0.125), originalZoom + 0.125)
	expectEqual("set/get defaultCamZoom", getProperty("defaultCamZoom"), originalZoom + 0.125)
	setProperty("defaultCamZoom", originalZoom)

	local originalSkip = getProperty("skipCountdown")
	expectEqual("setProperty false return", setProperty("skipCountdown", false), false)
	expectEqual("setProperty false value", getProperty("skipCountdown"), false)
	setProperty("skipCountdown", originalSkip)
	expectEqual("setProperty zero return", setProperty("defaultCamZoom", 0), 0)
	expectEqual("setProperty zero value", getProperty("defaultCamZoom"), 0)
	setProperty("defaultCamZoom", originalZoom)
	local originalOffset = getProperty("opponentCameraOffset[0]")
	expectEqual("indexed property write", setProperty("opponentCameraOffset[0]", 23), 23)
	expectEqual("indexed property read", getProperty("opponentCameraOffset[0]"), 23)
	setProperty("opponentCameraOffset[0]", originalOffset)

	local classZoom = getPropertyFromClass("FlxG", "camera.zoom")
	if classZoom == nil then fail("getPropertyFromClass FlxG.camera.zoom returned nil") end
	expectEqual("setPropertyFromClass return", setPropertyFromClass("FlxG", "camera.zoom", classZoom + 0.05), classZoom + 0.05)
	expectEqual("class property side effect", getPropertyFromClass("FlxG", "camera.zoom"), classZoom + 0.05)
	setPropertyFromClass("FlxG", "camera.zoom", classZoom)

	local strumX = getPropertyFromGroup("playerStrums", 0, "x")
	if strumX == nil then fail("getPropertyFromGroup playerStrums returned nil") end
	expectEqual("setPropertyFromGroup return", setPropertyFromGroup("playerStrums", 0, "x", strumX + 3), strumX + 3)
	expectEqual("group property side effect", getPropertyFromGroup("playerStrums", 0, "x"), strumX + 3)
	setPropertyFromGroup("playerStrums", 0, "x", strumX)
	expectEqual("negative group index", getPropertyFromGroup("playerStrums", -1, "x"), nil)
	expectEqual("out-of-range group index", getPropertyFromGroup("playerStrums", 999999, "x"), nil)
	expectEqual("invalid group write returns input", setPropertyFromGroup("playerStrums", 999999, "x", 0), 0)

	local spriteTag = "dbe_property_sprite_104"
	makeGraphic(spriteTag, 12, 8, "FF00FF")
	expectEqual("setPropertyLuaSprite return", setPropertyLuaSprite(spriteTag, "x", 41), true)
	expectEqual("getPropertyLuaSprite", getPropertyLuaSprite(spriteTag, "x"), 41)
	setPropertyLuaSprite(spriteTag, "visible", false)
	expectEqual("sprite false value", getPropertyLuaSprite(spriteTag, "visible"), false)
	expectEqual("missing sprite tag", getPropertyLuaSprite("dbe-missing-tag", "x"), nil)
	addToGroup("members", spriteTag)
	local order = getObjectOrder(spriteTag)
	if order < 0 then fail("addToGroup did not insert the object") end
	expectEqual("removeFromGroup return", removeFromGroup("members", -1, spriteTag, false), nil)
	expectEqual("removeFromGroup effect", getObjectOrder(spriteTag), -1)
	removeLuaSprite(spriteTag, true)
	updateHitboxFromGroup("playerStrums", 0)

	debugPrint("DBE_PSYCH_FIXTURE_PASS:" .. fixtureId)
end
