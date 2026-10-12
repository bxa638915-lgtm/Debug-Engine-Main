local fixtureId = "psych-0.6.3-timers-tweens-audio"
local expectedProfile = "0.6.3"
local timerCount = 0
local tweenCount = 0
local soundFinished = false
local runFinished = false
local guardCount = 0
local spriteTag = "dbe_task6_services_sprite"
local repeatTag = "dbe_task6_repeat"
local tweenTag = "dbe_task6_move"
local soundTag = "dbe_task6_sound"

local function fail(message)
	runFinished = true
	debugPrint("DBE_PSYCH_LUA_ERROR:" .. fixtureId .. ":" .. message)
	error(fixtureId .. ":" .. message)
end

local function expectEqual(name, actual, expected)
	if actual ~= expected then fail(name .. " expected " .. tostring(expected) .. ", got " .. tostring(actual)) end
end

local function checkProfile()
	local actual = engine and engine.compatibility and engine.compatibility.psychLuaProfile
	if actual ~= expectedProfile then fail("expected profile " .. expectedProfile .. ", got " .. tostring(actual)) end
	debugPrint("DBE_PSYCH_PROFILE:" .. actual)
end

function onCreatePost()
	checkProfile()
	precacheSound("pixel/type")
	precacheMusic("freakyMenu")
	makeLuaSprite(spriteTag, nil, 0, 0)
	makeGraphic(spriteTag, 8, 8, "FFFFFF")
	addLuaSprite(spriteTag, true)

	expectEqual("runTimer void return", runTimer(repeatTag, 0.1, 2), nil)
	expectEqual("canceled timer void return", runTimer("dbe_task6_canceled_timer", 0.6, 1), nil)
	cancelTimer("dbe_task6_canceled_timer")

	expectEqual("doTweenX void return", doTweenX(tweenTag, spriteTag, 20, 0.2, "linear"), nil)
	doTweenY("dbe_task6_y", spriteTag, 20, 0.5, "linear")
	doTweenAngle("dbe_task6_angle", spriteTag, 30, 0.5, "linear")
	doTweenAlpha("dbe_task6_alpha", spriteTag, 0.5, 0.5, "linear")
	doTweenColor("dbe_task6_color", spriteTag, "00FF00", 0.5, "linear")
	doTweenZoom("dbe_task6_zoom", "game", 1, 0.5, "linear")
	cancelTween("dbe_task6_y")
	cancelTween("dbe_task6_angle")
	cancelTween("dbe_task6_alpha")
	cancelTween("dbe_task6_color")
	cancelTween("dbe_task6_zoom")

	playMusic("freakyMenu", 0.1, true)
	musicFadeIn(0.05, 0, 0.1)
	musicFadeOut(0.05, 0.1)
	expectEqual("playSound void return", playSound("pixel/type", 0.1, soundTag), nil)
	expectEqual("tagged sound exists", luaSoundExists(soundTag), true)
	setSoundVolume(soundTag, 0.35)
	expectEqual("sound volume roundtrip", getSoundVolume(soundTag), 0.35)
	setSoundTime(soundTag, 0.01)
	if getSoundTime(soundTag) < 0 then fail("sound time did not update") end
	pauseSound(soundTag)
	resumeSound(soundTag)
	soundFadeIn(soundTag, 0.1, 0, 0.35)
	soundFadeOut(soundTag, 0.1, 0.1)
	soundFadeCancel(soundTag)
	local stopTag = "dbe_task6_stop_sound"
	playSound("pixel/type", 0.1, stopTag)
	stopSound(stopTag)
	expectEqual("stopped sound missing", luaSoundExists(stopTag), false)

	expectEqual("shader init", initLuaShader("coloredVignette", 120), true)
	expectEqual("sprite shader set", setSpriteShader(spriteTag, "coloredVignette"), true)
	setShaderFloat(spriteTag, "amount", 0.25)
	expectEqual("shader float roundtrip", getShaderFloat(spriteTag, "amount"), 0.25)
	setShaderFloatArray(spriteTag, "color", {0.2, 0.4, 0.6})
	if getShaderFloatArray(spriteTag, "color") == nil then fail("shader float array read returned nil") end
	setShaderBool(spriteTag, "missingBool", true)
	setShaderBoolArray(spriteTag, "missingBoolArray", {true, false})
	setShaderInt(spriteTag, "missingInt", 2)
	setShaderIntArray(spriteTag, "missingIntArray", {1, 2})
	setShaderSampler2D(spriteTag, "bitmap", "characters/bf")
	getShaderBool(spriteTag, "missingBool")
	getShaderBoolArray(spriteTag, "missingBoolArray")
	getShaderInt(spriteTag, "missingInt")
	getShaderIntArray(spriteTag, "missingIntArray")
	removeSpriteShader(spriteTag)

	debugPrint("DBE_PSYCH_FIXTURE_PASS:" .. fixtureId)
end

function onTimerCompleted(tag, loops, loopsLeft)
	if tag == repeatTag then
		timerCount = timerCount + 1
		debugPrint("DBE_PSYCH_CALLBACK:" .. fixtureId .. ":timer:" .. timerCount)
		if loops ~= 2 or loopsLeft ~= 2 - timerCount then fail("timer callback arguments") end
	elseif tag == "dbe_task6_canceled_timer" then
		fail("canceled timer callback fired")
	end
end

function onTweenCompleted(tag)
	if tag == tweenTag then tweenCount = tweenCount + 1; debugPrint("DBE_PSYCH_CALLBACK:" .. fixtureId .. ":tween:" .. tweenCount) end
end

function onSoundFinished(tag)
	if tag == soundTag then soundFinished = true; debugPrint("DBE_PSYCH_CALLBACK:" .. fixtureId .. ":sound") end
end

function onUpdatePost(elapsed)
	if runFinished then return end
	if timerCount >= 2 and tweenCount >= 1 and soundFinished then
		runFinished = true
		debugPrint("DBE_PSYCH_CALLBACK:" .. fixtureId .. ":onTimerCompleted")
		debugPrint("DBE_PSYCH_CALLBACK:" .. fixtureId .. ":onTweenCompleted")
		debugPrint("DBE_PSYCH_CALLBACK:" .. fixtureId .. ":onSoundFinished")
		debugPrint("DBE_PSYCH_FIXTURE_ASYNC_PASS:" .. fixtureId)
	elseif guardCount > 700 then
		fail("completion callback missing: timer=" .. timerCount .. ", tween=" .. tweenCount .. ", sound=" .. tostring(soundFinished))
	end
	guardCount = guardCount + 1
end
