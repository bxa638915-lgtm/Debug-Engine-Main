local fixtureId = "psych-0.6.3-dialogue-substates"
local expectedProfile = "0.6.3"

local function fail(message)
	debugPrint("DBE_PSYCH_LUA_ERROR:" .. fixtureId .. ":" .. message)
	error(fixtureId .. ":" .. message)
end

local function expectEqual(name, actual, expected)
	if actual ~= expected then fail(name .. " expected " .. tostring(expected) .. ", got " .. tostring(actual)) end
end

local function callback(name)
	debugPrint("DBE_PSYCH_CALLBACK:" .. fixtureId .. ":" .. name)
end

function onCreatePost()
	local profile = engine and engine.compatibility and engine.compatibility.psychLuaProfile
	if profile ~= expectedProfile then fail("expected profile " .. expectedProfile .. ", got " .. tostring(profile)) end
	debugPrint("DBE_PSYCH_PROFILE:" .. profile)
	expectEqual("openCustomSubstate is void", openCustomSubstate("dbe_task6_dialogue", true), nil)
end

function onCustomSubstateCreate(name)
	if name ~= "dbe_task6_dialogue" then fail("custom substate create name mismatch") end
	callback("onCustomSubstateCreate")
end

function onCustomSubstateCreatePost(name)
	if name ~= "dbe_task6_dialogue" then fail("custom substate create post name mismatch") end
	expectEqual("custom substate pauses gameplay", getProperty("paused"), true)
	callback("onCustomSubstateCreatePost")
end

function onCustomSubstateUpdate(name, elapsed)
	if name ~= "dbe_task6_dialogue" then fail("custom substate update name mismatch") end
	callback("onCustomSubstateUpdate")
end

function onCustomSubstateUpdatePost(name, elapsed)
	if name ~= "dbe_task6_dialogue" then fail("custom substate update post name mismatch") end
	callback("onCustomSubstateUpdatePost")
	expectEqual("closeCustomSubstate", closeCustomSubstate(), true)
end

function onCustomSubstateDestroy(name)
	if name ~= "dbe_task6_dialogue" then fail("custom substate destroy name mismatch") end
	callback("onCustomSubstateDestroy")
	local started = startDialogue("dialogue")
	expectEqual("startDialogue success return", started, true)
	addHaxeLibrary("DialogueCutscene", "funkin.game.cutscenes")
end

function onNextDialogue(count)
	if count ~= 1 then fail("first onNextDialogue count mismatch") end
	addHaxeLibrary("DialogueCutscene", "funkin.game.cutscenes")
	expectEqual("Psych bf portrait maps to boyfriend", runHaxeCode("DialogueCutscene.cutscene.curLine.char"), "boyfriend")
	expectEqual("Psych portrait is preserved", runHaxeCode("DialogueCutscene.cutscene.dialogueLines[0].char"), "dad")
	callback("onNextDialogue")
	expectEqual("skip the active dialogue line", runHaxeCode("DialogueCutscene.cutscene.skipCurrentDialogue(); true"), true)
	debugPrint("DBE_PSYCH_FIXTURE_PASS:" .. fixtureId)
end

function onSkipDialogue(count)
	if count ~= 1 then fail("onSkipDialogue count mismatch") end
	callback("onSkipDialogue")
end
