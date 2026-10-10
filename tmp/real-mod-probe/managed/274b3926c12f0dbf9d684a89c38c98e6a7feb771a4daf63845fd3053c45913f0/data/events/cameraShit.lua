local tweenXDone = false
local tweenYDone = false

function onEvent(name, value1, value2)
    if name == 'cameraShit' then
        if value1 == 'reset' then
            setProperty('isCameraOnForcedPos', false)
            setProperty('cameraSpeed', 1)
            return
        end

        setProperty('isCameraOnForcedPos', true)

        local penus = stringSplit(value1, ',')
        local x = tonumber(penus[1]) or 0
        local y = tonumber(penus[2]) or 0
        local dur = tonumber(penus[3]) or 0.5
        local ease = value2 ~= '' and value2 or 'linear'
        
        setProperty('cameraSpeed', 99999)
        cancelTween('camX')
        cancelTween('camY')
        if dur > 0 then
            doTweenX('camX', 'camFollow', x, dur, ease)
            doTweenY('camY', 'camFollow', y, dur, ease)
        else
            setProperty('camFollow.x', x)
            setProperty('camFollow.y', y)
        end
    end
end

function onTweenCompleted(tag)
    if tag == 'camX' then
        setProperty('cameraSpeed', 1)
    end
end