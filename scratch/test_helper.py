with open('source/funkin/backend/scripting/LuaScript.hx', 'r', encoding='utf-8') as f:
    text = f.read()

idx = text.find('function playLuaAnimation')
print(text[idx:idx+1500])
