function onCreate()
	local actualProfile = engine and engine.compatibility and engine.compatibility.psychLuaProfile
	if actualProfile ~= "unspecified" then
		print("DBE_PSYCH_LUA_ERROR:expected unspecified profile, got " .. tostring(actualProfile))
		return
	end
	print("DBE_PSYCH_PROFILE:unspecified")
	print("DBE_PSYCH_FIXTURE_PASS:psych-profile-unspecified-malformed")
end
