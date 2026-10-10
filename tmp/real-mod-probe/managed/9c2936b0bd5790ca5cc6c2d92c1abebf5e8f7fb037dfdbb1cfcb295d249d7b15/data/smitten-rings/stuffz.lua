local BGs = {'shiro', 'base', 'cloud1', 'cloud2', 'cloud3', 'cloud4', 'cloud5', 'cloud6', 'cloud7', 'withLight'}
local silhouettes = {'boyfriend', 'dad', 'stages/haben/bakaneko'}

function onCreate()
    setProperty('skipCountdown', true)
end

function onCreatePost()
    setProperty('camHUD.alpha', 0)
    setProperty('camZoomingMult', 0)
    
    makeLuaText('songName', '', 0, 260, -100)
    setTextSize('songName', 160)
    setTextFont('songName', 'darkella.ttf')
    setTextAlignment('songName', 'center')
    setObjectCamera('songName', 'game')
    setScrollFactor('songName', 0.65, 0.65)
    setObjectOrder('songName', 7)
    addLuaText('songName')
    
    makeLuaSprite('leLight', '', -2, -2)
    makeGraphic('leLight', screenWidth + 2, screenHeight + 2, 'white')
    setObjectCamera('leLight', 'other')
    screenCenter('leLight', 'xy')
    setProperty('leLight.alpha', 0)
    addLuaSprite('leLight')
    
    makeLuaSprite('frameUp', '', -2, -2)
    makeGraphic('frameUp', screenWidth + 4, screenHeight / 2 + 4, 'black')
    setObjectCamera('frameUp', 'other')
    addLuaSprite('frameUp')
    
    makeLuaSprite('frameDown', '', -2, screenHeight / 2 - 2)
    makeGraphic('frameDown', screenWidth + 4, screenHeight / 2 + 4, 'black')
    setObjectCamera('frameDown', 'other')
    addLuaSprite('frameDown')
    
    setProperty('isCameraOnForcedPos', true)
    setProperty('camFollow.x', 550)
    setProperty('camFollow.y', -400)
    setProperty('camGame.zoom', 2)
    
    for _, img in ipairs(BGs) do
        setProperty('stages/haben/' .. img .. '.visible', false)
    end
    for _, chars in ipairs(silhouettes) do
        setProperty(chars .. '.color', getColorFromHex('000000'))
    end
end

function onBeatHit()
    if curBeat == 1 then
        doTweenY('openSesame', 'frameUp', 120 - screenHeight / 2 - 2, 13, 'quintInOut')
        doTweenY('openingSesame', 'frameDown', screenHeight - 120, 13, 'quintInOut')
    end
    if curBeat == 30 then
        doTweenAlpha('notFlashBang', 'leLight', 0.7, 0.8, 'quadIn')
    end
    if curBeat == 32 then
        cancelTween('notFlashBang')
        setProperty('leLight.alpha', 1)
        setTextString('songName', '\nSmitten         \nRings')
        doTweenY('nameGoesDown', 'songName', 30, 4, 'quintOut')
        for _, img in ipairs(BGs) do
            setProperty('stages/haben/' .. img .. '.visible', true)
        end
        for _, chars in ipairs(silhouettes) do
            setProperty(chars .. '.color', getColorFromHex('FFFFFF'))
        end
        doTweenAlpha('flashBang', 'leLight', 0, 1.5, 'quadOut')
    end
    if curBeat == 46 then
        setProperty('songName.visible', false)
    end
    if curBeat == 48 then
        setTextString('songName', '\nOpponent:\nElmeena')
        setTextSize('songName', 120)
        setProperty('songName.x', 380)
        setProperty('songName.y', 130)
        setTextAlignment('songName', 'left')
        setProperty('songName.visible', true)
    end
    if curBeat == 55 then
        setProperty('songName.visible', false)
        setProperty('songName.x', 420)
    end
    if curBeat == 56 then
        setTextString('songName', '\nPlayer:\nTear')
        setTextAlignment('songName', 'right')
        setProperty('songName.visible', true)
    end
    if curBeat == 60 then
        doTweenY('openMore', 'frameUp', 0 - screenHeight / 2 - 2, 0.8, 'quintIn')
        doTweenY('openingMore', 'frameDown', screenHeight, 0.8, 'quintIn')
        doTweenY('diappear', 'songName', 450, 2, 'quintIn')
    end
    if curBeat == 62 then
        doTweenAlpha('pear', 'camHUD', 1, 0.8, 'quadOut')
    end
    if curBeat== 314 then
        setObjectCamera('frameUp', 'hud')
        setObjectCamera('frameDown', 'hud')
        doTweenY('notClosenSesame', 'frameUp', 120 - screenHeight / 2 - 2, 2, 'quintOut')
        doTweenY('notCloseningSesame', 'frameDown', screenHeight - 120, 2, 'quintOut')
    end
    if curBeat == 380 then
        doTweenY('openMore', 'frameUp', 0 - screenHeight / 2 - 2, 2, 'quintOut')
        doTweenY('openingMore', 'frameDown', screenHeight, 2, 'quintOut')    
    end
    if curBeat == 444 then
        setObjectCamera('frameUp', 'other')
        setObjectCamera('frameDown', 'other')
        doTweenAlpha('ded', 'camHUD', 0, 3, 'quintOut')
        doTweenY('closenSesame', 'frameUp', 150 - screenHeight / 2 - 2, 10, 'expoOut')
        doTweenY('closeningSesame', 'frameDown', screenHeight - 150, 10, 'expoOut')
    end
    if curBeat == 468 then
        cancelTween('closenSesame')
        cancelTween('closeningSesame')
        doTweenY('closenSesame', 'frameUp', 200 - screenHeight / 2 - 2, 1, 'quintOut')
        doTweenY('closeningSesame', 'frameDown', screenHeight - 200, 1, 'quintOut')
    end
    if curBeat == 471 then
        cancelTween('closenSesame')
        cancelTween('closeningSesame')
        doTweenY('closenSesame', 'frameUp', -2, 1, 'quintOut')
        doTweenY('closeningSesame', 'frameDown', screenHeight / 2 - 2, 1, 'quintOut')
    end
end

-- omfg bro why do I have to write ts
function onStepHit()
    if curStep == 1878 then
        cancelTween('closenSesame')
        cancelTween('closeningSesame')
        doTweenY('closenSesame', 'frameUp', 300 - screenHeight / 2 - 2, 1, 'quintOut')
        doTweenY('closeningSesame', 'frameDown', screenHeight - 300, 1, 'quintOut')
    end
end
        