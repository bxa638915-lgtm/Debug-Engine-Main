local modDir = 'inmu'

function onCreatePost()
    modDir = default(currentModDirectory, 'Lovers Angel Number')
    makeLuaSprite('strumBG', '', (getPropertyFromGroup('playerStrums', 3, 'x') + getPropertyFromGroup('playerStrums', 0, 'x')) / 2 - 199, -2)
    makeGraphic('strumBG', getPropertyFromGroup('playerStrums', 3, 'x') - getPropertyFromGroup('playerStrums', 0, 'x') + 170, screenHeight + 2, 'black')
    setObjectCamera('strumBG', 'hud')
    setProperty('strumBG.alpha', getModSetting("strumBeeGee", modDir) / 100)
    addLuaSprite('strumBG')
end

function onResume()
    setProperty('strumBG.alpha', getModSetting("strumBeeGee", modDir) / 100)
end

function default(value, fallback)
    if value == nil or value == '' then
        return fallback
    end
    return value
end