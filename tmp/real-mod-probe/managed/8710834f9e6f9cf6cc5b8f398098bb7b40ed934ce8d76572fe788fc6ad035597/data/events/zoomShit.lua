local pastStep = 0
function onEvent(name, v1, v2)

    local johnson = stringSplit(v1, ',')
    local zom = tonumber(johnson[1])
    local duration = tonumber(johnson[2])
    local ease = johnson[3]

    if name == 'zoomShit' then
    cancelTween('zom' .. pastStep)
        if v2 == 'move' then
            if duration > 0 then
                doTweenZoom('zom' .. curStep, 'game', zom, duration, ease)
                setProperty('defaultCamZoom', zom)
                pastStep = curStep
            else
                setProperty('defaultCamZoom', zom)
                setProperty('camGame.zoom', zom)
            end
        elseif v2 == 'bump' then
            local origZom = getProperty('camGame.zoom')
            setProperty('camGame.zoom', zom)
            doTweenZoom('zom' .. curStep, 'game', origZom, duration, ease)
            pastStep = curStep
        end
    end
end