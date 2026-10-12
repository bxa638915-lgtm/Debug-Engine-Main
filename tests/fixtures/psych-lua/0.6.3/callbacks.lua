local fixtureId = "psych-0.6.3-callbacks"
local expectedProfile = "0.6.3"
local probeIds = {"psych-0.6.3-callbacks", "psych-0.6.3-notes-scheduler", "psych-0.6.3-input-cancellation"}
local task5ManualCallbackNames = {"onGameOver", "onGameOverConfirm", "onGameOverStart", "onMoveCamera", "onPause", "onRecalculateRating", "onResume", "onUpdateScore"}
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

function eventEarlyTrigger(name)
	if type(name) ~= "string" then fail("eventEarlyTrigger name must be a string") end
	return Function_Continue
end

function onStartCountdown()
	return Function_Continue
end

function onCreatePost()
	local profile = engine and engine.compatibility and engine.compatibility.psychLuaProfile
	expectEqual("selected profile", profile, expectedProfile)
	expectEqual("Function_Stop", Function_Stop, 1)
	expectEqual("Function_Continue", Function_Continue, 0)
	expectEqual("Function_StopLua", Function_StopLua, 2)
	expectEqual("Function_StopHScript absent", Function_StopHScript, nil)
	expectEqual("Function_StopAll absent", Function_StopAll, nil)
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
	expectEqual("0.6.3 callOnLuas returns nil", dispatched, nil)

	local notesId = "psych-0.6.3-notes-scheduler"
	local scriptResult = callScript(notesId, "dbeTask5ScriptProbe", {"callScript", 23, expectedProfile})
	expectEqual("0.6.3 callScript returns nil", scriptResult, nil)
	expectEqual("callScript invoked target", getGlobalFromScript(notesId, "dbeTask5ProbeCalled"), true)
	setGlobalFromScript(notesId, "dbeTask5Shared", "cross-script-write")
	expectEqual("setGlobalFromScript/getGlobalFromScript", getGlobalFromScript(notesId, "dbeTask5Shared"), "cross-script-write")

	local earlyResult = callOnLuas("eventEarlyTrigger", {"DBE Fixture Event", "one", "two", 1200}, false, false, nil, {Function_Continue})
	expectEqual("0.6.3 callOnLuas returns nil for eventEarlyTrigger", earlyResult, nil)

	local pressResult = callOnLuas("onKeyPress", {1}, false, false, nil, {Function_Continue})
	local releaseResult = callOnLuas("onKeyRelease", {1}, false, false, nil, {Function_Continue})
	expectEqual("0.6.3 callOnLuas returns nil for onKeyPress", pressResult, nil)
	expectEqual("0.6.3 callOnLuas returns nil for onKeyRelease", releaseResult, nil)
	for _, callbackName in ipairs(task5ManualCallbackNames) do
		callScript(fixtureId, callbackName, {})
		expectEqual("manual callback dispatch " .. callbackName, task5ManualCallbackHits[callbackName], true)
	end

	if startCountdown() ~= true then fail("startCountdown should report success") end
	debugPrint("DBE_PSYCH_CALLBACK:" .. fixtureId .. ":onCreatePost")
	debugPrint("DBE_PSYCH_FIXTURE_PASS:" .. fixtureId)
end

function onSongStart() end
function onCountdownStarted() end
function onCountdownTick(tick) if type(tick) ~= "number" then fail("onCountdownTick argument") end end
function onEvent(...)
	if select("#", ...) ~= 3 then fail("0.6.3 onEvent must receive exactly three arguments") end
	local name, value1, value2 = ...
	if type(name) ~= "string" or type(value1) ~= "string" or type(value2) ~= "string" then fail("0.6.3 onEvent argument order") end
end
function onUpdate(elapsed) if type(elapsed) ~= "number" then fail("onUpdate elapsed") end end
function onUpdatePost(elapsed) if type(elapsed) ~= "number" then fail("onUpdatePost elapsed") end end
function onStepHit() end
function onBeatHit() end
function onSectionHit() end
function onEndSong() return Function_Continue end
function onGameOver() task5ManualCallbackHits.onGameOver = true; return Function_Continue end
function onGameOverConfirm() task5ManualCallbackHits.onGameOverConfirm = true; return Function_Continue end
function onGameOverStart() task5ManualCallbackHits.onGameOverStart = true; return Function_Continue end
function onMoveCamera() task5ManualCallbackHits.onMoveCamera = true; return Function_Continue end
function onPause() task5ManualCallbackHits.onPause = true; return Function_Continue end
function onRecalculateRating() task5ManualCallbackHits.onRecalculateRating = true; return Function_Continue end
function onResume() task5ManualCallbackHits.onResume = true; return Function_Continue end
function onUpdateScore() task5ManualCallbackHits.onUpdateScore = true; return Function_Continue end
