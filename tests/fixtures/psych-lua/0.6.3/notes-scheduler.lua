local fixtureId = "psych-0.6.3-notes-scheduler"
local expectedProfile = "0.6.3"
local spawnedOnce = false

local function fail(message)
	debugPrint("DBE_PSYCH_LUA_ERROR:" .. fixtureId .. ":" .. message)
	error(fixtureId .. ":" .. message)
end

local function expectEqual(name, actual, expected)
	if actual ~= expected then fail(name .. " expected " .. tostring(expected) .. ", got " .. tostring(actual)) end
end

function dbeTask5ScriptProbe(action, number, profile)
	expectEqual("callScript action", action, "callScript")
	expectEqual("callScript number", number, 23)
	expectEqual("callScript profile", profile, expectedProfile)
	dbeTask5ProbeCalled = true
	return fixtureId
end

function dbeTask5DispatchProbe(action, number, profile)
	if action ~= "dispatch" or number ~= 17 or profile ~= expectedProfile then fail("dispatch callback argument order") end
	debugPrint("DBE_PSYCH_CALLBACK:psych-0.6.3-callbacks:dispatch:" .. fixtureId)
	return fixtureId
end

function onCreatePost()
	dbeTask5Shared = "fixture-initial"
	local hits = getHits()
	local misses = getMisses()
	setHits(hits + 2)
	addHits(3)
	expectEqual("getHits after set/add", getHits(), hits + 5)
	setHits(hits)
	setMisses(misses + 2)
	addMisses(3)
	expectEqual("getMisses after set/add", getMisses(), misses + 5)
	setMisses(misses)

	makeLuaSprite("dbe_task5_hitbox_063", nil, 0, 0)
	if updateHitbox("dbe_task5_hitbox_063") ~= true then fail("updateHitbox must find the created sprite") end
	local x = getPropertyFromGroup("strumLineNotes", 0, "x")
	if type(x) ~= "number" then fail("first receptor x must be numeric") end
	if noteTweenX("dbe_task5_nx_063", 0, x, 0.01) ~= true then fail("noteTweenX failed") end
	local y = getPropertyFromGroup("strumLineNotes", 0, "y")
	if noteTweenY("dbe_task5_ny_063", 0, y, 0.01) ~= true then fail("noteTweenY failed") end
	local angle = getPropertyFromGroup("strumLineNotes", 0, "angle")
	if noteTweenAngle("dbe_task5_na_063", 0, angle, 0.01) ~= true then fail("noteTweenAngle failed") end
	local alpha = getPropertyFromGroup("strumLineNotes", 0, "alpha")
	if noteTweenAlpha("dbe_task5_nalpha_063", 0, alpha, 0.01) ~= true then fail("noteTweenAlpha failed") end
	local direction = getPropertyFromGroup("strumLineNotes", 0, "direction")
	if noteTweenDirection("dbe_task5_ndir_063", 0, direction, 0.01) ~= true then fail("noteTweenDirection failed") end
	debugPrint("DBE_PSYCH_FIXTURE_PASS:" .. fixtureId)
end

function onSpawnNote(noteIndex, noteData, noteType, isSustainNote)
	if type(noteIndex) ~= "number" or noteIndex < 0 then fail("0.6.3 onSpawnNote index") end
	if type(noteData) ~= "number" or type(noteType) ~= "string" or type(isSustainNote) ~= "boolean" then fail("0.6.3 onSpawnNote argument order") end
	if not spawnedOnce then
		spawnedOnce = true
		debugPrint("DBE_PSYCH_NOTE_SPAWN:" .. expectedProfile)
	end
end

function goodNoteHit(noteIndex, direction, noteType, isSustainNote)
	if type(noteIndex) ~= "number" or type(direction) ~= "number" or (noteType ~= nil and type(noteType) ~= "string") or type(isSustainNote) ~= "boolean" then fail("goodNoteHit argument order") end
end
function noteMiss(noteIndex, noteData, noteType, isSustainNote)
	if type(noteIndex) ~= "number" or type(noteData) ~= "number" or (noteType ~= nil and type(noteType) ~= "string") or type(isSustainNote) ~= "boolean" then fail("noteMiss argument order") end
end
function noteMissPress(direction) if type(direction) ~= "number" then fail("noteMissPress direction") end end
function opponentNoteHit(noteIndex, direction, noteType, isSustainNote)
	if type(noteIndex) ~= "number" or type(direction) ~= "number" or (noteType ~= nil and type(noteType) ~= "string") or type(isSustainNote) ~= "boolean" then fail("opponentNoteHit argument order") end
end
