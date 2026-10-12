local fixtureId = "psych-1.0.4-objects-rendering"
local expectedProfile = "1.0.4"
local spriteTag = "dbe_fixture_sprite_104"
local duplicateTag = "dbe_fixture_duplicate_104"
local animatedTag = "dbe_fixture_animated_104"
local indexedTag = "dbe_fixture_indexed_104"
local loopTag = "dbe_fixture_loop_104"
local animateTag = "dbe_fixture_flxanimate_104"
local framesTag = "dbe_fixture_frames_104"
local textTag = "dbe_fixture_text_104"
local secondTag = "dbe_fixture_overlap_104"

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
	makeLuaSprite(spriteTag, nil, 20, 30)
	makeGraphic(spriteTag, 24, 16, "FF00FF")
	expectEqual("luaSpriteExists", luaSpriteExists(spriteTag), true)
	expectEqual("set graphic pixel", getPixelColor(spriteTag, 0, 0), getColorFromHex("FF00FF"))
	expectEqual("getColorFromHex", getColorFromHex("FF00FF"), FlxColor("FF00FF"))
	if getColorFromName("red") == nil or getColorFromString("#FF0000") == nil then fail("color conversion returned nil") end
	expectEqual("luaSpriteMakeGraphic", luaSpriteMakeGraphic(spriteTag, 20, 12, "00FF00"), true)
	expectEqual("second graphic pixel", getPixelColor(spriteTag, 0, 0), getColorFromHex("00FF00"))

	setPropertyLuaSprite(spriteTag, "x", 35)
	setPropertyLuaSprite(spriteTag, "y", 45)
	expectEqual("sprite x", getPropertyLuaSprite(spriteTag, "x"), 35)
	expectEqual("sprite y", getPropertyLuaSprite(spriteTag, "y"), 45)
	expectEqual("setObjectCamera", setObjectCamera(spriteTag, "other"), true)
	expectEqual("setLuaSpriteCamera", setLuaSpriteCamera(spriteTag, "game"), true)
	expectEqual("setScrollFactor", setScrollFactor(spriteTag, 0.25, 0.5), true)
	expectEqual("setLuaSpriteScrollFactor", setLuaSpriteScrollFactor(spriteTag, 0.5, 0.75), true)
	expectEqual("scroll factor effect", getPropertyLuaSprite(spriteTag, "scrollFactor.x"), 0.5)
	expectEqual("scaleObject", scaleObject(spriteTag, 1.5, 1.25), true)
	expectEqual("scaleLuaSprite", scaleLuaSprite(spriteTag, 2, 2), true)
	expectEqual("setGraphicSize", setGraphicSize(spriteTag, 48, 32, true), true)
	expectEqual("graphic width", getPropertyLuaSprite(spriteTag, "width"), 48)
	setBlendMode(spriteTag, "add")
	addOffset(spriteTag, "fixture", 3, 4)
	expectEqual("offset x", getPropertyLuaSprite(spriteTag, "offset.x"), 3)
	if getGraphicMidpointX(spriteTag) == nil or getGraphicMidpointY(spriteTag) == nil then fail("graphic midpoint returned nil") end
	if getScreenPositionX(spriteTag, "hud") == nil or getScreenPositionY(spriteTag, "hud") == nil then fail("screen position returned nil") end
	screenCenter(spriteTag, "xy")
	if getPropertyLuaSprite(spriteTag, "x") == nil then fail("screenCenter lost the sprite position") end

	makeGraphic(secondTag, 24, 16, "00FF00")
	setPropertyLuaSprite(secondTag, "x", getPropertyLuaSprite(spriteTag, "x"))
	setPropertyLuaSprite(secondTag, "y", getPropertyLuaSprite(spriteTag, "y"))
	expectEqual("objectsOverlap", objectsOverlap(spriteTag, secondTag), true)

	expectEqual("makeFlxAnimateSprite return", makeFlxAnimateSprite(animateTag, 50, 50), nil)
	expectEqual("makeFlxAnimateSprite effect", luaSpriteExists(animateTag), true)
	expectEqual("loadAnimateAtlas return", loadAnimateAtlas(animateTag, "game/cutscenes/tank/ugh-tankman"), nil)
	if getPropertyLuaSprite(animateTag, "width") <= 0 then fail("loadAnimateAtlas did not set sprite dimensions") end
	expectEqual("addAnimationBySymbol", addAnimationBySymbol(animateTag, "tank_talk", "TANK TALK 1 EXPORT", 24, false, 0, 0), true)
	expectEqual("playAnim symbol", playAnim(animateTag, "tank_talk", true), true)
	expectEqual("current symbol animation", getPropertyLuaSprite(animateTag, "anim.curAnim.name"), "tank_talk")
	expectEqual("addAnimationBySymbolIndices", addAnimationBySymbolIndices(animateTag, "tank_talk_frames", "TANK TALK 1 EXPORT", {0, 1}, 24, false, 0, 0), true)
	expectEqual("playAnim symbol indices", playAnim(animateTag, "tank_talk_frames", true), true)

	makeAnimatedLuaSprite(animatedTag, "characters/bf", 50, 50)
	expectEqual("addAnimationByPrefix", addAnimationByPrefix(animatedTag, "idle", "BF idle dance", 24, true), true)
	expectEqual("first registered prefix animation starts", getPropertyLuaSprite(animatedTag, "animation.curAnim.name"), "idle")
	makeAnimatedLuaSprite(indexedTag, "characters/bf", 50, 50)
	expectEqual("addAnimationByIndices first animation return", addAnimationByIndices(indexedTag, "indices", "BF idle dance", "0,1", 24), true)
	expectEqual("first registered indexed animation starts", getPropertyLuaSprite(indexedTag, "animation.curAnim.name"), "indices")
	expectEqual("1.0.4 indexed animation default loop", getPropertyLuaSprite(indexedTag, "animation.curAnim.looped"), false)
	makeAnimatedLuaSprite(framesTag, "characters/bf", 50, 50)
	expectEqual("addAnimation return", addAnimation(framesTag, "frames", {0, 1}, 24, true), true)
	expectEqual("addAnimation missing tag return", addAnimation("dbe_missing_array_animation_104", "frames", {0, 1}, 24, true), false)
	expectEqual("first array animation starts", getPropertyLuaSprite(framesTag, "animation.curAnim.name"), "frames")
	expectEqual("array animation loop", getPropertyLuaSprite(framesTag, "animation.curAnim.looped"), true)
	makeAnimatedLuaSprite(loopTag, "characters/bf", 50, 50)
	expectEqual("addAnimationByIndicesLoop return", addAnimationByIndicesLoop(loopTag, "indices_loop", "BF idle dance", "0,1", 24), true)
	expectEqual("addAnimationByIndicesLoop missing tag return", addAnimationByIndicesLoop("dbe_missing_loop_animation_104", "indices_loop", "BF idle dance", "0,1", 24), false)
	expectEqual("first looped indexed animation starts", getPropertyLuaSprite(loopTag, "animation.curAnim.name"), "indices_loop")
	expectEqual("indexed loop animation loops", getPropertyLuaSprite(loopTag, "animation.curAnim.looped"), true)
	expectEqual("luaSpriteAddAnimationByPrefix return", luaSpriteAddAnimationByPrefix(animatedTag, "idle_alias", "BF idle dance", 24, true), nil)
	expectEqual("addAnimationByIndices", addAnimationByIndices(animatedTag, "indices", "BF idle dance", "0,1", 24, false), true)
	expectEqual("luaSpriteAddAnimationByIndices return", luaSpriteAddAnimationByIndices(animatedTag, "indices_alias", "BF idle dance", "0,1", 24), nil)
	expectEqual("objectPlayAnimation", objectPlayAnimation(animatedTag, "idle", true), true)
	expectEqual("luaSpritePlayAnimation return", luaSpritePlayAnimation(animatedTag, "idle_alias", true), nil)
	expectEqual("playAnim", playAnim(animatedTag, "indices", true), true)
	loadFrames(framesTag, "characters/bf")
	loadMultipleFrames(framesTag, "characters/bf")
	loadGraphic(framesTag, "characters/bf")
	if getPropertyLuaSprite(framesTag, "width") == nil then fail("loadGraphic did not set sprite dimensions") end

	makeLuaText(textTag, "before", 180, 0, 0)
	expectEqual("empty text string write", setTextString(textTag, ""), true)
	expectEqual("empty text string read", getTextString(textTag), "")
	expectEqual("setTextString", setTextString(textTag, "after"), true)
	expectEqual("getTextString", getTextString(textTag), "after")
	expectEqual("setTextSize", setTextSize(textTag, 18), true)
	expectEqual("getTextSize", getTextSize(textTag), 18)
	expectEqual("setTextWidth", setTextWidth(textTag, 200), true)
	expectEqual("getTextWidth", getTextWidth(textTag), 200)
	expectEqual("setTextFont", setTextFont(textTag, "vcr.ttf"), true)
	if getTextFont(textTag) == nil then fail("getTextFont returned nil") end
	expectEqual("setTextColor", setTextColor(textTag, "00FF00"), true)
	expectEqual("setTextItalic", setTextItalic(textTag, true), true)
	expectEqual("text italic effect", getPropertyLuaSprite(textTag, "italic"), true)
	expectEqual("setTextAlignment", setTextAlignment(textTag, "center"), true)
	expectEqual("text alignment effect", getPropertyLuaSprite(textTag, "alignment"), "center")
	expectEqual("setTextBorder", setTextBorder(textTag, 2, "FFFFFF", "outline"), true)
	expectEqual("text border effect", getPropertyLuaSprite(textTag, "borderSize"), 2)
	expectEqual("setTextHeight", setTextHeight(textTag, 48), true)
	expectEqual("text height effect", getPropertyLuaSprite(textTag, "fieldHeight"), 48)
	expectEqual("setTextAutoSize", setTextAutoSize(textTag, false), true)
	expectEqual("text autosize effect", getPropertyLuaSprite(textTag, "autoSize"), false)
	expectEqual("luaTextExists", luaTextExists(textTag), true)
	addLuaText(textTag)
	if getObjectOrder(textTag) < 0 then fail("addLuaText did not add the text to the state") end

	addLuaSprite(spriteTag, true)
	if getObjectOrder(spriteTag) < 0 then fail("addLuaSprite did not add the sprite to the state") end
	setObjectOrder(spriteTag, 0)
	expectEqual("setObjectOrder effect", getObjectOrder(spriteTag), 0)

	local followX = getCameraFollowX()
	local followY = getCameraFollowY()
	setCameraFollowPoint(followX + 2, followY + 3)
	expectEqual("set camera follow X", getCameraFollowX(), followX + 2)
	expectEqual("set camera follow Y", getCameraFollowY(), followY + 3)
	addCameraFollowPoint(2, 3)
	expectEqual("add camera follow X", getCameraFollowX(), followX + 4)
	expectEqual("add camera follow Y", getCameraFollowY(), followY + 6)
	setCameraFollowPoint(followX, followY)

	local scrollX = getCameraScrollX()
	local scrollY = getCameraScrollY()
	setCameraScroll(scrollX + 4, scrollY + 5)
	expectEqual("set camera scroll X", getCameraScrollX(), scrollX + 4)
	expectEqual("set camera scroll Y", getCameraScrollY(), scrollY + 5)
	addCameraScroll(2, 3)
	expectEqual("add camera scroll X", getCameraScrollX(), scrollX + 6)
	expectEqual("add camera scroll Y", getCameraScrollY(), scrollY + 8)
	setCameraScroll(scrollX, scrollY)

	cameraShake("camGame", 0, 0)
	cameraFlash("camGame", "FFFFFF", 0, true)
	cameraFade("camGame", "000000", 0, true, false)
	cameraFade("camGame", "000000", 0, true, true)
	cameraSetTarget("dad")
	setHealthBarColors("FF00FF", "00FF00")
	setTimeBarColors("FF00FF", "00FF00")

	removeLuaText(textTag, true)
	removeLuaSprite(secondTag, true)
	removeLuaSprite(spriteTag, true)
	removeLuaSprite(animateTag, true)
	removeLuaSprite(animatedTag, true)
	removeLuaSprite(indexedTag, true)
	removeLuaSprite(loopTag, true)
	removeLuaSprite(framesTag, true)
	expectEqual("removed sprite tag", luaSpriteExists(spriteTag), false)
	expectEqual("removed FlxAnimate tag", luaSpriteExists(animateTag), false)
	expectEqual("removed text tag", luaTextExists(textTag), false)

	local instanceTag = "dbe_fixture_created_instance_104"
	expectEqual("createInstance", createInstance(instanceTag, "flixel.FlxSprite"), true)
	expectEqual("instanceArg without class", instanceArg(instanceTag), "##PSYCHLUA_STRINGTOOBJ::" .. instanceTag)
	expectEqual("instanceArg with class", instanceArg("boyfriend", "Character"), "##PSYCHLUA_STRINGTOOBJ::boyfriend::Character")
	expectEqual("callMethodFromClass", callMethodFromClass("StringTools", "trim", {"  psych  "}), "psych")
	callMethod(instanceTag .. ".setPosition", {12, 18})
	expectEqual("callMethod target X", getPropertyLuaSprite(instanceTag, "x"), 12)
	expectEqual("callMethod target Y", getPropertyLuaSprite(instanceTag, "y"), 18)
	expectEqual("addInstance void return", addInstance(instanceTag, true), nil)
	if getObjectOrder(instanceTag) < 0 then fail("addInstance did not add the created object") end
	removeLuaSprite(instanceTag, true)

	makeGraphic(duplicateTag, 8, 8, "FF0000")
	addLuaSprite(duplicateTag, true)
	if getObjectOrder(duplicateTag) < 0 then fail("first duplicate tag object was not added") end
	makeLuaSprite(duplicateTag, nil, 11, 12)
	expectEqual("duplicate tag remains registered", luaSpriteExists(duplicateTag), true)
	expectEqual("duplicate tag replaces old display object", getObjectOrder(duplicateTag), -1)
	removeLuaSprite(duplicateTag, true)

	debugPrint("DBE_PSYCH_FIXTURE_PASS:" .. fixtureId)
end
