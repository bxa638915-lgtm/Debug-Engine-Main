local expectedProfile = "1.0.4"

function onCreate()
	local actualProfile = engine and engine.compatibility and engine.compatibility.psychLuaProfile
	if actualProfile ~= expectedProfile then
		print("DBE_PSYCH_LUA_ERROR:expected profile " .. expectedProfile .. ", got " .. tostring(actualProfile))
		return
	end
	print("DBE_PSYCH_PROFILE:" .. actualProfile)
	print("DBE_PSYCH_FIXTURE_PASS:psych-1.0.4-profile-selection")
end
