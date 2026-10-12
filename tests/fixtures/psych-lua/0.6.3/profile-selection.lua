local expectedProfile = "0.6.3"

function onCreate()
	local actualProfile = engine and engine.compatibility and engine.compatibility.psychLuaProfile
	if actualProfile ~= expectedProfile then
		print("DBE_PSYCH_LUA_ERROR:expected profile " .. expectedProfile .. ", got " .. tostring(actualProfile))
		return
	end
	print("DBE_PSYCH_PROFILE:" .. actualProfile)
	print("DBE_PSYCH_FIXTURE_PASS:psych-0.6.3-profile-selection")
end
