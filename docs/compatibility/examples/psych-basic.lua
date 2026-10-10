function onCreate()
	debugPrint("Adaptador Lua carregado")
end

function onBeatHit(beat)
	local zoom = getProperty("camGame.zoom")
	if zoom ~= nil then
		setProperty("camGame.zoom", zoom + 0.01)
	end
end
