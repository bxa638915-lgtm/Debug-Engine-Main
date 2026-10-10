local pastStep = 0
function onEvent(name, v1)
    if name == 'hudBump' then
        cancelTween('zomHud' .. pastStep)
        setProperty('camHUD.zoom', tonumber(v1))
        doTweenZoom('zomHud' .. curStep, 'hud', 1, 2, 'quintOut')
        pastStep = curStep
    end
end