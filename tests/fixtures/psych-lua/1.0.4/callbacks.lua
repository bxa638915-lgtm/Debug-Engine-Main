local fixtureId = "psych-1.0.4-callbacks"
local expectedProfile = "1.0.4"
local probeIds = {"psych-1.0.4-callbacks", "psych-1.0.4-notes-scheduler", "psych-1.0.4-input-cancellation"}
local task5ManualCallbackNames = {"onEventPushed", "onGameOver", "onGameOverConfirm", "onGameOverStart", "onMoveCamera", "onPause", "onRecalculateRating", "onResume", "onUpdateScore", "preUpdateScore"}
local task5ManualCallbackHits = {}

local function fail(message)
	debugPrint("DBE_PSYCH_LUA_ERROR:" .. fixtureId .. ":" .. message)
	error(fixtureId .. ":" .. message)
end

local function expectEqual(name, actual, expected)
	if actual ~= expected then fail(name .. " expected " .. tostring(expected) .. ", got " .. tostring(actual)) end
end

function dbeTask5DispatchProbe(action, number, profile)
	expectEqual("dispatch action", action, "dispatch")
	expectEqual("dispatch number", number, 17)
	expectEqual("dispatch profile", profile, expectedProfile)
	debugPrint("DBE_PSYCH_CALLBACK:" .. fixtureId .. ":dispatch:" .. fixtureId)
	return fixtureId
end


function eventEarlyTrigger(...)
	local argCount = select("#", ...)
	local name, value1, value2, chartTime = ...
	if type(name) ~= "string" or type(value1) ~= "string" or type(value2) ~= "string" or type(chartTime) ~= "number" then
		fail("1.0.4 eventEarlyTrigger args=" .. argCount .. " types=" .. type(name) .. "," .. type(value1) .. "," .. type(value2) .. "," .. type(chartTime) .. " values=" .. tostring(name) .. "," .. tostring(value1) .. "," .. tostring(value2) .. "," .. tostring(chartTime))
	end
	return Function_Continue
end

function onStartCountdown()
	return Function_Continue
end

function onCreatePost()
	local profile = engine and engine.compatibility and engine.compatibility.psychLuaProfile
	expectEqual("selected profile", profile, expectedProfile)
	expectEqual("Function_Stop", Function_Stop, "##PSYCHLUA_FUNCTIONSTOP")
	expectEqual("Function_Continue", Function_Continue, "##PSYCHLUA_FUNCTIONCONTINUE")
	expectEqual("Function_StopLua", Function_StopLua, "##PSYCHLUA_FUNCTIONSTOPLUA")
	expectEqual("Function_StopHScript", Function_StopHScript, "##PSYCHLUA_FUNCTIONSTOPHSCRIPT")
	expectEqual("Function_StopAll", Function_StopAll, "##PSYCHLUA_FUNCTIONSTOPALL")
	debugPrint("DBE_PSYCH_PROFILE:" .. profile)

	local running = getRunningScripts()
	local expectedLast = nil
	for _, path in ipairs(running) do
		for _, id in ipairs(probeIds) do
			if string.find(string.lower(path), id, 1, true) then expectedLast = id end
		end
	end
	if expectedLast == nil then fail("task 5 fixture scripts were not all loaded") end
	local dispatched = callOnLuas("dbeTask5DispatchProbe", {"dispatch", 17, expectedProfile}, false, false, nil, {Function_Continue})
	expectEqual("last non-continue Lua result follows script order", dispatched, expectedLast)

	local notesId = "psych-1.0.4-notes-scheduler"
	local scriptResult = callScript(notesId, "dbeTask5ScriptProbe", {"callScript", 23, expectedProfile})
	expectEqual("callScript result", scriptResult, notesId)

	local earlyResult = callOnLuas("eventEarlyTrigger", {"DBE Fixture Event", "one", "two", 1200}, false, false, nil, {Function_Continue})
	expectEqual("eventEarlyTrigger continues", earlyResult, Function_Continue)

	local prePressResult = callOnLuas("onKeyPressPre", {1}, false, false, nil, {Function_Continue})
	local preReleaseResult = callOnLuas("onKeyReleasePre", {2}, false, false, nil, {Function_Continue})
	expectEqual("lane 1 press cancellation", prePressResult, Function_Stop)
	expectEqual("lane 2 release cancellation", preReleaseResult, Function_Stop)
	local passThrough = callOnLuas("onKeyPressPre", {0}, false, false, nil, {Function_Continue})
	expectEqual("unrelated lane stays unblocked", passThrough, Function_Continue)

	local pressResult = callOnLuas("onKeyPress", {1}, false, false, nil, {Function_Continue})
	local releaseResult = callOnLuas("onKeyRelease", {1}, false, false, nil, {Function_Continue})
	expectEqual("onKeyPress callback result", pressResult, Function_Continue)
	expectEqual("onKeyRelease callback result", releaseResult, Function_Continue)
	for _, callbackName in ipairs(task5ManualCallbackNames) do
		local callbackResult = callScript(fixtureId, callbackName, {})
		expectEqual("manual callback dispatch " .. callbackName, callbackResult, Function_Continue)
		expectEqual("manual callback reached " .. callbackName, task5ManualCallbackHits[callbackName], true)
	end

	if startCountdown() ~= true then fail("startCountdown should report success") end
	debugPrint("DBE_PSYCH_CALLBACK:" .. fixtureId .. ":onCreatePost")
	debugPrint("DBE_PSYCH_FIXTURE_PASS:" .. fixtureId)
end

function onSongStart() end
function onCountdownStarted() end
function onCountdownTick(tick) if type(tick) ~= "number" then fail("onCountdownTick argument") end end
function onEvent(...)
	if select("#", ...) ~= 4 then fail("1.0.4 onEvent must receive exactly four arguments") end
	local name, value1, value2, strumTime = ...
	if type(name) ~= "string" or type(value1) ~= "string" or type(value2) ~= "string" or type(strumTime) ~= "number" then fail("1.0.4 onEvent argument order") end
end
function onUpdate(elapsed) if type(elapsed) ~= "number" then fail("onUpdate elapsed") end end
function onUpdatePost(elapsed) if type(elapsed) ~= "number" then fail("onUpdatePost elapsed") end end
function onStepHit() end
function onBeatHit() end
function onSectionHit() end
function onEndSong() return Function_Continue end
function onEventPushed() task5ManualCallbackHits.onEventPushed = true; return Function_Continue end
function onGameOver() task5ManualCallbackHits.onGameOver = true; return Function_Continue end
function onGameOverConfirm() task5ManualCallbackHits.onGameOverConfirm = true; return Function_Continue end
function onGameOverStart() task5ManualCallbackHits.onGameOverStart = true; return Function_Continue end
function onMoveCamera() task5ManualCallbackHits.onMoveCamera = true; return Function_Continue end
function onPause() task5ManualCallbackHits.onPause = true; return Function_Continue end
function onRecalculateRating() task5ManualCallbackHits.onRecalculateRating = true; return Function_Continue end
function onResume() task5ManualCallbackHits.onResume = true; return Function_Continue end
function onUpdateScore() task5ManualCallbackHits.onUpdateScore = true; return Function_Continue end
function preUpdateScore() task5ManualCallbackHits.preUpdateScore = true; return Function_Continue end
