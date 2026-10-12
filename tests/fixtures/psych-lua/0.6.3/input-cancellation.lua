local fixtureId = "psych-0.6.3-input-cancellation"
local expectedProfile = "0.6.3"

local function fail(message)
	debugPrint("DBE_PSYCH_LUA_ERROR:" .. fixtureId .. ":" .. message)
	error(fixtureId .. ":" .. message)
end

local function expectType(name, value, expected)
	if type(value) ~= expected then fail(name .. " expected type " .. expected .. ", got " .. type(value)) end
end

function dbeTask5DispatchProbe(action, number, profile)
	if action ~= "dispatch" or number ~= 17 or profile ~= expectedProfile then fail("dispatch callback argument order") end
	debugPrint("DBE_PSYCH_CALLBACK:psych-0.6.3-callbacks:dispatch:" .. fixtureId)
	return fixtureId
end

function onCreatePost()
	expectType("keyJustPressed", keyJustPressed("NOTE_LEFT"), "boolean")
	expectType("keyPressed", keyPressed("NOTE_LEFT"), "boolean")
	expectType("keyReleased", keyReleased("NOTE_LEFT"), "boolean")
	expectType("keyboardJustPressed", keyboardJustPressed("A"), "boolean")
	expectType("keyboardPressed", keyboardPressed("A"), "boolean")
	expectType("keyboardReleased", keyboardReleased("A"), "boolean")
	expectType("mouseClicked", mouseClicked("left"), "boolean")
	expectType("mousePressed", mousePressed("left"), "boolean")
	expectType("mouseReleased", mouseReleased("left"), "boolean")
	expectType("getMouseX", getMouseX("game"), "number")
	expectType("getMouseY", getMouseY("game"), "number")
	expectType("anyGamepadJustPressed", anyGamepadJustPressed("A"), "boolean")
	expectType("anyGamepadPressed", anyGamepadPressed("A"), "boolean")
	expectType("anyGamepadReleased", anyGamepadReleased("A"), "boolean")
	expectType("gamepadAnalogX", gamepadAnalogX(999), "number")
	expectType("gamepadAnalogY", gamepadAnalogY(999), "number")
	expectType("gamepadJustPressed", gamepadJustPressed(999, "A"), "boolean")
	expectType("gamepadPressed", gamepadPressed(999, "A"), "boolean")
	expectType("gamepadReleased", gamepadReleased(999, "A"), "boolean")
	debugPrint("DBE_PSYCH_FIXTURE_PASS:" .. fixtureId)
end

function onKeyPress(key) if type(key) ~= "number" then fail("onKeyPress lane") end end
function onKeyRelease(key) if type(key) ~= "number" then fail("onKeyRelease lane") end end
function onGhostTap(key) if type(key) ~= "number" then fail("onGhostTap lane") end end
