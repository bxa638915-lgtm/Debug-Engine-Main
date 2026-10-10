local path = 'stages/haben/'
local defY = 200

function onCreate()
    setProperty('gf.visible', false)
    makeItQuick(path .. 'shiro', -300, -50, 0.05, 1.6)
    makeItQuick(path .. 'cloud1', 420, 0, 0.3, 2.2)
    makeItQuick(path .. 'cloud2', 1180, 160, 0.4, 2.2)
    makeItQuick(path .. 'cloud3', 1230, 50, 0.5, 2.2)
    makeItQuick(path .. 'cloud4', 400, 220, 0.6, 2.2)
    makeItQuick(path .. 'cloud5', 600, 0, 0.7, 2.2)
    makeItQuick(path .. 'cloud6', 1000, 250, 0.8, 2.2)
    makeItQuick(path .. 'cloud7', 950, 420, 0.9, 2.2)
    makeItQuick(path .. 'base', -600, -100, 0.95, 2.2)
    makeItQuick(path .. 'bakaneko', 1200, defY, 1.1, 1.6)
    makeItQuick(path .. 'withLight', -680, -80, 1.2, 2.2)
    
    makeLuaSprite('lightLighterYetLighter', '', -300)
    makeGraphic('lightLighterYetLighter', screenWidth + 600, screenHeight, 'white')
    setObjectCamera('lightLighterYetLighter', 'game')
    setScrollFactor('lightLighterYetLighter', 0, 0)
    addLuaSprite('lightLighterYetLighter')
    
    setObjectOrder(path .. 'bakaneko', 13)
    setObjectOrder(path .. 'withLight', 14)
    setObjectOrder('lightLighterYetLighter', 0)
end

function makeItQuick(img, x, y, sf, size)
    makeLuaSprite(img, img, x, y)
    setScrollFactor(img, sf, sf)
    scaleObject(img, size, size)
    addLuaSprite(img)
end

function onUpdate(elapsed)
    setProperty(path .. 'bakaneko.y', defY + (math.sin(getSongPosition() / 1500 * 2) * 50))
end