-- Choose "0.6.3" or "1.0.4" in data/config/dbe-compat.json for the target mod.
-- These common calls are an example, not a claim of complete Psych API parity.
function onCreate()
	debugPrint("Adaptador Lua carregado")
end

function onBeatHit(beat)
	local zoom = getProperty("camGame.zoom")
	if zoom ~= nil then
		setProperty("camGame.zoom", zoom + 0.01)
	end
end
