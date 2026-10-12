local fixtureId = "psych-0.6.3-objects-rendering"
local expectedProfile = "0.6.3"
local spriteTag = "dbe_fixture.sprite_063"
local duplicateTag = "dbe_fixture_duplicate_063"
local animatedTag = "dbe_fixture_animated_063"
local indexedTag = "dbe_fixture_indexed_063"
local loopTag = "dbe_fixture_loop_063"
local framesTag = "dbe_fixture_frames_063"
local textTag = "dbe_fixture_text_063"
local secondTag = "dbe_fixture_overlap_063"

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
	expectEqual("getColorFromHex", getColorFromHex("FF00FF"), getColorFromHex("0xFFFF00FF"))
	expectEqual("luaSpriteMakeGraphic", luaSpriteMakeGraphic(spriteTag, 20, 12, "00FF00"), true)
	expectEqual("second graphic pixel", getPixelColor(spriteTag, 0, 0), getColorFromHex("00FF00"))

	setPropertyLuaSprite(spriteTag, "x", 35)
	setPropertyLuaSprite(spriteTag, "y", 45)
	expectEqual("sprite x", getPropertyLuaSprite(spriteTag, "x"), 35)
	expectEqual("sprite y", getPropertyLuaSprite(spriteTag, "y"), 45)
	expectEqual("setObjectCamera", setObjectCamera(spriteTag, "hud"), true)
	expectEqual("setLuaSpriteCamera", setLuaSpriteCamera(spriteTag, "game"), true)
	expectEqual("setLuaSpriteScrollFactor", setLuaSpriteScrollFactor(spriteTag, 0.5, 0.75), true)
	expectEqual("setScrollFactor", setScrollFactor(spriteTag, 0.25, 0.5), true)
	expectEqual("scroll factor effect", getPropertyLuaSprite(spriteTag, "scrollFactor.x"), 0.25)
	expectEqual("scaleObject", scaleObject(spriteTag, 1.5, 1.25), true)
	expectEqual("scaleLuaSprite", scaleLuaSprite(spriteTag, 2, 2), true)
	expectEqual("scale effect", getPropertyLuaSprite(spriteTag, "scale.x"), 2)
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

	makeAnimatedLuaSprite(animatedTag, "characters/bf", 50, 50)
	expectEqual("addAnimationByPrefix 0.6.3 return", addAnimationByPrefix(animatedTag, "idle", "BF idle dance", 24, true), nil)
	expectEqual("first registered prefix animation starts", getPropertyLuaSprite(animatedTag, "animation.curAnim.name"), "idle")
	makeAnimatedLuaSprite(indexedTag, "characters/bf", 50, 50)
	expectEqual("addAnimationByIndices first animation return", addAnimationByIndices(indexedTag, "indices", "BF idle dance", "0,1", 24, true), true)
	expectEqual("first registered indexed animation starts", getPropertyLuaSprite(indexedTag, "animation.curAnim.name"), "indices")
	expectEqual("0.6.3 indexed animation default loop", getPropertyLuaSprite(indexedTag, "animation.curAnim.looped"), false)
	makeAnimatedLuaSprite(framesTag, "characters/bf", 50, 50)
	expectEqual("addAnimation 0.6.3 return", addAnimation(framesTag, "frames", {0, 1}, 24, true), nil)
	expectEqual("addAnimation missing tag return", addAnimation("dbe_missing_array_animation_063", "frames", {0, 1}, 24, true), nil)
	expectEqual("first array animation starts", getPropertyLuaSprite(framesTag, "animation.curAnim.name"), "frames")
	expectEqual("array animation loop", getPropertyLuaSprite(framesTag, "animation.curAnim.looped"), true)
	makeAnimatedLuaSprite(loopTag, "characters/bf", 50, 50)
	expectEqual("addAnimationByIndicesLoop return", addAnimationByIndicesLoop(loopTag, "indices_loop", "BF idle dance", "0,1", 24), true)
	expectEqual("addAnimationByIndicesLoop missing tag return", addAnimationByIndicesLoop("dbe_missing_loop_animation_063", "indices_loop", "BF idle dance", "0,1", 24), false)
	expectEqual("first looped indexed animation starts", getPropertyLuaSprite(loopTag, "animation.curAnim.name"), "indices_loop")
	expectEqual("indexed loop animation loops", getPropertyLuaSprite(loopTag, "animation.curAnim.looped"), true)
	expectEqual("luaSpriteAddAnimationByPrefix 0.6.3 return", luaSpriteAddAnimationByPrefix(animatedTag, "idle_alias", "BF idle dance", 24, true), nil)
	expectEqual("addAnimationByIndices", addAnimationByIndices(animatedTag, "indices", "BF idle dance", "0,1", 24, true), true)
	expectEqual("luaSpriteAddAnimationByIndices 0.6.3 return", luaSpriteAddAnimationByIndices(animatedTag, "indices_alias", "BF idle dance", "0,1", 24), nil)
	expectEqual("objectPlayAnimation", objectPlayAnimation(animatedTag, "idle", true), true)
	expectEqual("luaSpritePlayAnimation 0.6.3 return", luaSpritePlayAnimation(animatedTag, "idle_alias", true), nil)
	expectEqual("playAnim", playAnim(animatedTag, "indices", true), true)
	loadFrames(duplicateTag, "characters/bf")
	loadGraphic(duplicateTag, "characters/bf")
	if getPropertyLuaSprite(duplicateTag, "width") == nil then fail("loadGraphic did not set sprite dimensions") end

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
	expectEqual("luaTextExists", luaTextExists(textTag), true)
	addLuaText(textTag)
	if getObjectOrder(textTag) < 0 then fail("addLuaText did not add the text to the state") end

	addLuaSprite(spriteTag, true)
	if getObjectOrder(spriteTag) < 0 then fail("addLuaSprite did not add the sprite to the state") end
	setObjectOrder(spriteTag, 0)
	expectEqual("setObjectOrder effect", getObjectOrder(spriteTag), 0)
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
	removeLuaSprite(animatedTag, true)
	removeLuaSprite(indexedTag, true)
	removeLuaSprite(loopTag, true)
	removeLuaSprite(framesTag, true)
	expectEqual("removed sprite tag", luaSpriteExists(spriteTag), false)
	expectEqual("removed text tag", luaTextExists(textTag), false)

	makeGraphic(duplicateTag, 8, 8, "FF0000")
	addLuaSprite(duplicateTag, true)
	if getObjectOrder(duplicateTag) < 0 then fail("first duplicate tag object was not added") end
	makeLuaSprite(duplicateTag, nil, 11, 12)
	expectEqual("duplicate tag remains registered", luaSpriteExists(duplicateTag), true)
	expectEqual("duplicate tag replaces old display object", getObjectOrder(duplicateTag), -1)
	removeLuaSprite(duplicateTag, true)

	debugPrint("DBE_PSYCH_FIXTURE_PASS:" .. fixtureId)
end
