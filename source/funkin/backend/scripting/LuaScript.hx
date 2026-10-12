package funkin.backend.scripting;
#if LUA_ALLOWED
import cne.compat.LuaCallbackScope;
import cne.compat.PsychLuaObjectRegistry;
import cne.compat.PsychLuaPropertyPath;
import cne.compat.PsychLuaCamera;
import cne.compat.PsychLuaProfile;
import cne.compat.PsychHookMap;
import cne.compat.PsychLuaSubState;
import cne.compat.PsychDialogueConverter;
import cne.compat.PsychTimeBar;
import cne.compat.PsychCallbackResult;
import cne.compat.PsychAchievementStore;
import cne.compat.ScriptCapabilities;
import dbe.diagnostics.ScriptTimingProfiler;
import flixel.FlxSprite;
import flixel.FlxObject;
import flixel.FlxG;
import flixel.text.FlxText;
import flixel.text.FlxText.FlxTextAlign;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxTimer;
import flixel.util.FlxSave;
import flixel.util.FlxAxes;
import flixel.util.FlxColor;
import flixel.sound.FlxSound;
import flixel.input.gamepad.FlxGamepadInputID;
import openfl.display.BlendMode;
import haxe.ds.ObjectMap;
import funkin.backend.system.Conductor;
import funkin.backend.assets.Paths;
import funkin.backend.assets.SongLoadRequest;
import funkin.backend.assets.SongLoader;
import funkin.backend.assets.ModsFolder;
import funkin.backend.shaders.CustomShader;
import funkin.backend.utils.DiscordUtil;
import funkin.backend.utils.TranslationUtil;
import funkin.backend.chart.ChartData.ChartEvent;
import funkin.backend.scripting.events.CancellableEvent;
import funkin.backend.scripting.events.gameplay.CamMoveEvent;
import funkin.backend.scripting.events.gameplay.CountdownEvent;
import funkin.backend.scripting.events.gameplay.EventGameEvent;
import funkin.backend.scripting.events.note.InputSystemEvent;
import funkin.backend.scripting.events.note.NoteHitEvent;
import funkin.backend.scripting.events.note.NoteMissEvent;
import funkin.game.Character;
import funkin.game.Strum;
import funkin.game.PlayState;
import funkin.options.Options;
import llua.Convert;
import llua.Lua;
import llua.LuaL;
import llua.State;
import openfl.Assets;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

/**
	LuaJIT-backed Psych Lua adapter. API helpers and CNE lifecycle/gameplay
	events are translated where both engines expose a compatible contract.
**/
class LuaScript extends Script
{
	private var lua:State;
	private var callbackScope:LuaCallbackScope;
	private static var luaObjects:PsychLuaObjectRegistry<Dynamic> = new PsychLuaObjectRegistry<Dynamic>();
	private static var psychVariables:Map<String, Dynamic> = [];
	private static var luaSaves:Map<String, FlxSave> = [];
	private static var luaShaders:Map<String, Dynamic> = [];
	private static var luaModSettings:Map<String, Map<String, Dynamic>> = [];
	private static var psychTranslationCache:Map<String, Map<String, String>> = [];
	private static var luaHealthBarColors:ObjectMap<flixel.ui.FlxBar, Array<FlxColor>> = new ObjectMap();
	private static var sharedObjectCleanupRegistered:Bool = false;
	private var luaTimers:Map<String, FlxTimer> = [];
	private var luaTweens:Map<String, FlxTween> = [];
	private var luaSounds:Map<String, FlxSound> = [];
	private var luaSoundLoops:Map<String, Bool> = [];
	private static var luaDeletedFiles:Map<String, Bool> = [];
	private var stageLuaObjects:Map<String, FlxSprite> = [];
	private var sourceOverride:String;
	private var luaHScript:Script;
	private var scriptClosed:Bool = false;
	private var rawLuaPath:String;
	private var hasSourceOverride:Bool = false;
	private var unsupportedHooks:Map<String, Bool> = [];
	private var spawnedPsychNotes:Array<Dynamic> = [];

	public function new(path:String, ?source:String)
	{
		super(path);
		rawLuaPath = path;
		hasSourceOverride = source != null;
		sourceOverride = source;
		initializeRuntime();

		#if GLOBAL_SCRIPT
		GlobalScript.call("onScriptCreated", [this, "lua"]);
		#end
	}

	private function initializeRuntime():Void
	{
		lua = LuaL.newstate();
		if (lua == null)
		{
			error("Could not allocate a LuaJIT state.");
			return;
		}

		LuaL.openlibs(lua);
		for (name in ["io", "os", "package", "debug", "require", "dofile", "loadfile", "loadstring", "collectgarbage"])
		{
			Lua.pushnil(lua);
			Lua.setglobal(lua, name);
		}

		callbackScope = new LuaCallbackScope(lua, (callbackError:Dynamic) -> error('Lua API callback failed: ${Std.string(callbackError)}'));
		callbackScope.bind("dbeSafeOsClock", () -> haxe.Timer.stamp());
		LuaL.dostring(lua, "os = { clock = dbeSafeOsClock }; dbeSafeOsClock = nil; if math and not math.lerp then math.lerp = function(from, to, ratio) return from + (to - from) * ratio end end; if not lerp then lerp = math.lerp end");
		bindPsychApi();
		setNumberConstant("screenWidth", FlxG.width);
		setNumberConstant("screenHeight", FlxG.height);
	}

	private function bindPsychApi():Void
	{
		callbackScope.bind("print", function(?a:Dynamic, ?b:Dynamic, ?c:Dynamic, ?d:Dynamic):Void printValues([a, b, c, d]));
		callbackScope.bind("debugPrint", function(?a:Dynamic, ?b:Dynamic, ?c:Dynamic, ?d:Dynamic):Void printValues([a, b, c, d]));
		callbackScope.bind("getProperty", (path:String) -> readPsychProperty(path));
		callbackScope.bind("setProperty", setPsychProperty);
		callbackScope.bind("getPropertyFromClass", (className:String, path:String) -> readPath(resolveClass(className), path));
		callbackScope.bind("setPropertyFromClass", setPsychPropertyFromClass);
		callbackScope.bind("getPropertyFromGroup", (groupName:String, index:Float, path:String) -> readPath(getGroupMember(groupName, Std.int(index)), path));
		callbackScope.bind("setPropertyFromGroup", setPsychPropertyFromGroup);
		callbackScope.bind("getRandomBool", function(?chance:Float):Bool return FlxG.random.bool(chance == null ? 50 : chance));
		callbackScope.bind("characterPlayAnim", function(characterName:String, animation:String, ?force:Bool):Bool
		{
			var character = getCharacter(characterName);
			if (character == null) return false;
			character.playAnim(animation, force == true);
			return true;
		});
		callbackScope.bind("characterDance", function(characterName:String):Bool
		{
			var character = getCharacter(characterName);
			if (character == null) return false;
			character.dance();
			return true;
		});

		bindPsychSpriteApi();
		bindPsychTextApi();
		bindPsychUtilityApi();
		bindPsychGameplayApi();
		bindPsychTimerApi();
		bindPsychTweenApi();
		bindPsychSoundApi();
		bindPsychScriptApi();
		bindPsychInputApi();
		bindPsychBackendApi();
		initializePsychGlobals();
		if (!sharedObjectCleanupRegistered)
		{
			sharedObjectCleanupRegistered = true;
			FlxG.signals.preStateSwitch.add(clearSharedPsychObjects);
		}
	}

	private function bindPsychSpriteApi():Void
	{
		callbackScope.bind("makeLuaSprite", function(tag:String, ?image:String = null, ?x:Float = 0, ?y:Float = 0):Bool
		{
			var sprite = new LuaGraphicSprite(x, y);
			if (image != null && image.length > 0 && image.toLowerCase() != "empty") sprite.loadGraphic(Paths.image(image));
			if (PlayState.instance != null) sprite.cameras = [PlayState.instance.camGame];
			sprite.active = true;
			registerLuaObject(tag, sprite);
			return true;
		});
		callbackScope.bind("makeAnimatedLuaSprite", function(tag:String, ?image:String = null, ?x:Float = 0, ?y:Float = 0, ?spriteType:String = "auto"):Bool
		{
			var sprite = new LuaGraphicSprite(x, y);
			if (image != null && image.length > 0 && image.toLowerCase() != "empty") sprite.frames = Paths.getFrames(image);
			if (PlayState.instance != null) sprite.cameras = [PlayState.instance.camGame];
			sprite.active = true;
			registerLuaObject(tag, sprite);
			return true;
		});
		callbackScope.bind("makeGraphic", function(tag:String, ?width:Int = 256, ?height:Int = 256, ?color:Dynamic = "FFFFFF"):Bool
		{
			var sprite = getOrCreateLuaSprite(tag);
			makeLuaSpriteGraphic(sprite, width, height, parseLuaColor(color));
			return true;
		});
		callbackScope.bind("luaSpriteMakeGraphic", function(tag:String, width:Int, height:Int, ?color:Dynamic = "FFFFFF"):Bool
		{
			var sprite = getLuaSprite(tag);
			if (sprite == null) return false;
			makeLuaSpriteGraphic(sprite, width, height, parseLuaColor(color));
			return true;
		});
		callbackScope.bind("addLuaSprite", addLuaSprite);
		callbackScope.bind("removeLuaSprite", removeLuaSprite);
		callbackScope.bind("luaSpriteExists", (tag:String) -> getLuaSprite(tag) != null);
		callbackScope.bind("luaSpriteAddAnimationByPrefix", function(tag:String, name:String, prefix:String, ?frameRate:Float = 24, ?looped:Bool = true):Dynamic
		{
			addLuaAnimationByPrefix(tag, name, prefix, frameRate, looped);
			return null;
		});
		callbackScope.bind("addAnimationByPrefix", addLuaAnimationByPrefix);
		callbackScope.bind("luaSpriteAddAnimationByIndices", function(tag:String, name:String, prefix:String, indices:Dynamic, ?frameRate:Float = 24):Dynamic
		{
			addLuaAnimationByIndices(tag, name, prefix, indices, frameRate);
			return null;
		});
		callbackScope.bind("addAnimationByIndices", addLuaAnimationByIndices);
		callbackScope.bind("addAnimation", addLuaAnimation);
		callbackScope.bind("addAnimationByIndicesLoop", function(tag:String, name:String, prefix:String, indices:Dynamic, ?frameRate:Float = 24):Bool
			return addLuaAnimationByIndices(tag, name, prefix, indices, frameRate, true));
		callbackScope.bind("objectPlayAnimation", playLuaAnimation);
		callbackScope.bind("luaSpritePlayAnimation", function(tag:String, animation:String, ?force:Bool = false):Dynamic
		{
			playLuaAnimation(tag, animation, force);
			return null;
		});
		callbackScope.bind("playAnim", playLuaAnimation);
		callbackScope.bind("setObjectCamera", setLuaObjectCamera);
		callbackScope.bind("setLuaSpriteCamera", setLuaObjectCamera);
		callbackScope.bind("setLuaSpriteScrollFactor", setLuaScrollFactor);
		callbackScope.bind("setScrollFactor", setLuaScrollFactor);
		callbackScope.bind("scaleObject", scaleLuaObject);
		callbackScope.bind("scaleLuaSprite", scaleLuaObject);
		callbackScope.bind("setGraphicSize", setLuaGraphicSize);
		callbackScope.bind("updateHitbox", updateLuaHitbox);
		callbackScope.bind("screenCenter", centerLuaObject);
		callbackScope.bind("setObjectOrder", setLuaObjectOrder);
		callbackScope.bind("getObjectOrder", getLuaObjectOrder);
		callbackScope.bind("loadGraphic", loadLuaGraphic);
		callbackScope.bind("loadFrames", loadLuaFrames);
		callbackScope.bind("loadMultipleFrames", loadLuaFrames);
		callbackScope.bind("makeFlxAnimateSprite", function(tag:String, ?x:Float = 0, ?y:Float = 0, ?loadFolder:String = null):Dynamic
		{
			makeLuaAnimateSprite(tag, x, y, loadFolder);
			return null;
		});
		callbackScope.bind("loadAnimateAtlas", function(tag:String, folderOrImage:String, ?spriteJson:String = null, ?animationJson:String = null):Dynamic
		{
			loadLuaAnimateAtlas(tag, folderOrImage, spriteJson, animationJson);
			return null;
		});
		callbackScope.bind("addAnimationBySymbol", addLuaSymbolAnimation);
		callbackScope.bind("addAnimationBySymbolIndices", addLuaSymbolIndicesAnimation);
		callbackScope.bind("addToGroup", function(groupName:String, tag:String, ?index:Int = -1):Void addLuaObjectToGroup(groupName, tag, index));
		callbackScope.bind("removeFromGroup", removePsychObjectFromGroup);
		callbackScope.bind("updateHitboxFromGroup", function(groupName:String, index:Int):Void updateLuaHitboxFromGroup(groupName, index));
		callbackScope.bind("getPixelColor", getLuaPixelColor);
	}

	private function bindPsychTextApi():Void
	{
		callbackScope.bind("makeLuaText", function(tag:String, ?text:String = "", ?width:Float = 0, ?x:Float = 0, ?y:Float = 0):Bool
		{
			var field = new FlxText(x, y, width, text, 16);
			field.color = FlxColor.WHITE;
			field.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			field.borderSize = 2;
			field.scrollFactor.set(0, 0);
			field.cameras = [PlayState.instance != null ? PlayState.instance.camHUD : FlxG.camera];
			registerLuaObject(tag, field);
			return true;
		});
		callbackScope.bind("luaTextExists", (tag:String) -> Std.isOfType(luaObjects.get(tag), FlxText));
		callbackScope.bind("addLuaText", (tag:String) -> addLuaObject(tag, true));
		callbackScope.bind("removeLuaText", removeLuaObject);
		callbackScope.bind("setTextString", (tag:String, value:String) -> setLuaTextField(tag, "text", value));
		callbackScope.bind("getTextString", (tag:String) -> getLuaTextField(tag, "text"));
		callbackScope.bind("setTextSize", (tag:String, value:Float) -> setLuaTextField(tag, "size", Std.int(value)));
		callbackScope.bind("getTextSize", (tag:String) -> getLuaTextField(tag, "size"));
		callbackScope.bind("setTextFont", (tag:String, value:String) -> setLuaTextField(tag, "font", Paths.font(value)));
		callbackScope.bind("getTextFont", (tag:String) -> getLuaTextField(tag, "font"));
		callbackScope.bind("setTextColor", (tag:String, value:Dynamic) -> setLuaTextField(tag, "color", parseLuaColor(value)));
		callbackScope.bind("setTextWidth", (tag:String, value:Float) -> setLuaTextField(tag, "fieldWidth", value));
		callbackScope.bind("getTextWidth", (tag:String) -> getLuaTextField(tag, "fieldWidth"));
		callbackScope.bind("setTextHeight", (tag:String, value:Float) -> setLuaTextField(tag, "fieldHeight", value));
		callbackScope.bind("setTextItalic", (tag:String, value:Bool) -> setLuaTextField(tag, "italic", value));
		callbackScope.bind("setTextAlignment", setLuaTextAlignment);
		callbackScope.bind("setTextAutoSize", (tag:String, value:Bool) -> setLuaTextField(tag, "autoSize", value));
		callbackScope.bind("setTextBorder", setLuaTextBorder);
	}

	private function bindPsychUtilityApi():Void
	{
		callbackScope.bind("getPropertyLuaSprite", (tag:String, property:String) -> PsychLuaPropertyPath.read(getLuaObject(tag), property));
		callbackScope.bind("setPropertyLuaSprite", setPsychLuaSpriteProperty);
		callbackScope.bind("getRandomInt", function(min:Float, max:Float, ?exclude:String = ""):Int
		{
			var excluded:Array<Int> = [];
			if (exclude != null && exclude.length > 0)
				for (entry in exclude.split(","))
				{
					var parsed = Std.parseInt(StringTools.trim(entry));
					if (parsed != null) excluded.push(parsed);
				}
			return FlxG.random.int(Std.int(min), Std.int(max), excluded);
		});
		callbackScope.bind("getRandomFloat", function(min:Float, max:Float, ?exclude:String = ""):Float
		{
			var excluded:Array<Float> = [];
			if (exclude != null && exclude.length > 0)
				for (entry in exclude.split(","))
				{
					var parsed = Std.parseFloat(StringTools.trim(entry));
					if (!Math.isNaN(parsed)) excluded.push(parsed);
				}
			return FlxG.random.float(min, max, excluded);
		});
		callbackScope.bind("stringStartsWith", (value:String, prefix:String) -> value != null && prefix != null && StringTools.startsWith(value, prefix));
		callbackScope.bind("stringEndsWith", (value:String, suffix:String) -> value != null && suffix != null && StringTools.endsWith(value, suffix));
		callbackScope.bind("stringSplit", (value:String, separator:String) -> value == null || separator == null ? [] : value.split(separator));
		callbackScope.bind("stringTrim", (value:String) -> value == null ? "" : StringTools.trim(value));
		callbackScope.bind("getMouseX", (?camera:String = "game") -> FlxG.mouse.getViewPosition(getLuaCamera(camera)).x);
		callbackScope.bind("getMouseY", (?camera:String = "game") -> FlxG.mouse.getViewPosition(getLuaCamera(camera)).y);
		callbackScope.bind("keyboardJustPressed", (key:String) -> readInputState(FlxG.keys.justPressed, key));
		callbackScope.bind("keyboardPressed", (key:String) -> readInputState(FlxG.keys.pressed, key));
		callbackScope.bind("keyboardReleased", (key:String) -> readInputState(FlxG.keys.justReleased, key));
		callbackScope.bind("mouseClicked", (?button:String = "left") -> readMouseState(button, 0));
		callbackScope.bind("mousePressed", (?button:String = "left") -> readMouseState(button, 1));
		callbackScope.bind("mouseReleased", (?button:String = "left") -> readMouseState(button, 2));
		callbackScope.bind("addOffset", setLuaOffset);
		callbackScope.bind("setBlendMode", setLuaBlendMode);
		callbackScope.bind("objectsOverlap", (first:String, second:String) -> FlxG.overlap(getLuaObject(first), getLuaObject(second)));
		callbackScope.bind("getMidpointX", (tag:String) -> getLuaObjectPoint(tag, false, false));
		callbackScope.bind("getMidpointY", (tag:String) -> getLuaObjectPoint(tag, false, true));
		callbackScope.bind("getGraphicMidpointX", (tag:String) -> getLuaObjectPoint(tag, true, false));
		callbackScope.bind("getGraphicMidpointY", (tag:String) -> getLuaObjectPoint(tag, true, true));
		callbackScope.bind("getScreenPositionX", (tag:String, ?camera:String = "game") -> getLuaScreenPosition(tag, camera, false));
		callbackScope.bind("getScreenPositionY", (tag:String, ?camera:String = "game") -> getLuaScreenPosition(tag, camera, true));
		if (psychLuaProfileName() != PsychLuaProfile.PSYCH_063)
		{
			callbackScope.bind("callMethod", callLuaMethod);
			callbackScope.bind("callMethodFromClass", callLuaMethodFromClass);
			callbackScope.bind("createInstance", createLuaInstance);
			callbackScope.bind("addInstance", function(tag:String, ?inFront:Bool = false):Void { addLuaInstance(tag, inFront); });
			callbackScope.bind("instanceArg", function(name:String, ?className:String = null):String
				return '##PSYCHLUA_STRINGTOOBJ::$name${className == null ? "" : "::" + className}');
		}
	}

	private function bindPsychScriptApi():Void
	{
		callbackScope.bind("setVar", (name:String, value:Dynamic) -> { psychVariables.set(name, value); value; });
		callbackScope.bind("getVar", (name:String) -> psychVariables.get(name));
		callbackScope.bind("getRunningScripts", getRunningLuaScripts);
		callbackScope.bind("isRunning", isLuaScriptRunning);
		callbackScope.bind("callScript", callLuaScript);
		if (psychLuaProfileName() == PsychLuaProfile.PSYCH_063)
		{
			callbackScope.bind("getGlobalFromScript", getLuaGlobalFromScript);
			callbackScope.bind("setGlobalFromScript", setLuaGlobalFromScript);
		}
		callbackScope.bind("callOnScripts", function(functionName:String, ?args:Array<Dynamic>, ?ignoreStops:Bool = false, ?ignoreSelf:Bool = true,
			?excludeScripts:Array<String>, ?excludeValues:Array<Dynamic>) return callPsychScripts(functionName, args, ignoreStops, ignoreSelf, excludeScripts, excludeValues));
		callbackScope.bind("callOnLuas", function(functionName:String, ?args:Array<Dynamic>, ?ignoreStops:Bool = false, ?ignoreSelf:Bool = true,
			?excludeScripts:Array<String>, ?excludeValues:Array<Dynamic>)
		{
			var result = callLuaScripts(functionName, args, ignoreStops, ignoreSelf, excludeScripts, excludeValues);
			return psychLuaProfileName() == PsychLuaProfile.PSYCH_063 ? null : result;
		});
		callbackScope.bind("setOnScripts", function(name:String, value:Dynamic, ?ignoreSelf:Bool = false, ?excludeScripts:Array<String>) return setLuaScripts(name, value, ignoreSelf, excludeScripts, false));
		callbackScope.bind("setOnLuas", function(name:String, value:Dynamic, ?ignoreSelf:Bool = false, ?excludeScripts:Array<String>) return setLuaScripts(name, value, ignoreSelf, excludeScripts, true));
		callbackScope.bind("addLuaScript", addLuaScript);
		callbackScope.bind("removeLuaScript", removeLuaScript);
		if (psychLuaProfileName() != PsychLuaProfile.PSYCH_063)
		{
			callbackScope.bind("addHScript", function(name:String, ?ignoreAlreadyRunning:Bool = false):Void { addHScript(name, ignoreAlreadyRunning); });
			callbackScope.bind("removeHScript", removeHScript);
			callbackScope.bind("callOnHScript", function(functionName:String, ?args:Array<Dynamic>, ?ignoreStops:Bool = false, ?ignoreSelf:Bool = true,
				?excludeScripts:Array<String>, ?excludeValues:Array<Dynamic>) return callScripts(functionName, args, ignoreStops, ignoreSelf, excludeScripts, excludeValues, "hscript"));
			callbackScope.bind("setOnHScript", function(name:String, value:Dynamic, ?ignoreSelf:Bool = false, ?excludeScripts:Array<String>) return setScripts(name, value, ignoreSelf, excludeScripts, "hscript"));
			callbackScope.bind("runHaxeFunction", runLuaHScriptFunction);
		}
		callbackScope.bind("runHaxeCode", function(code:String, ?varsToBring:Dynamic, ?functionName:String, ?args:Array<Dynamic>):Dynamic
		{
			return psychLuaProfileName() == PsychLuaProfile.PSYCH_063
				? runLuaHScriptCode(code)
				: runLuaHScriptCode(code, varsToBring, functionName, args);
		});
		callbackScope.bind("addHaxeLibrary", function(library:String, ?packageName:String = ""):Void { addLuaHaxeLibrary(library, packageName); });
		callbackScope.bind("close", closeLuaScript);
	}

	private function bindPsychInputApi():Void
	{
		callbackScope.bind("keyJustPressed", (key:String) -> readControlState(key, 0));
		callbackScope.bind("keyPressed", (key:String) -> readControlState(key, 1));
		callbackScope.bind("keyReleased", (key:String) -> readControlState(key, 2));
		callbackScope.bind("anyGamepadJustPressed", (button:String) -> FlxG.gamepads.anyJustPressed(FlxGamepadInputID.fromString(button.toUpperCase())));
		callbackScope.bind("anyGamepadPressed", (button:String) -> FlxG.gamepads.anyPressed(FlxGamepadInputID.fromString(button.toUpperCase())));
		callbackScope.bind("anyGamepadReleased", (button:String) -> FlxG.gamepads.anyJustReleased(FlxGamepadInputID.fromString(button.toUpperCase())));
		callbackScope.bind("gamepadAnalogX", (id:Int, ?leftStick:Bool = true) -> { var pad = FlxG.gamepads.getByID(id); pad == null ? 0 : pad.getXAxis(leftStick ? FlxGamepadInputID.LEFT_ANALOG_STICK : FlxGamepadInputID.RIGHT_ANALOG_STICK); });
		callbackScope.bind("gamepadAnalogY", (id:Int, ?leftStick:Bool = true) -> { var pad = FlxG.gamepads.getByID(id); pad == null ? 0 : pad.getYAxis(leftStick ? FlxGamepadInputID.LEFT_ANALOG_STICK : FlxGamepadInputID.RIGHT_ANALOG_STICK); });
		callbackScope.bind("gamepadJustPressed", (id:Int, button:String) -> getGamepadButtonState(id, button, 0));
		callbackScope.bind("gamepadPressed", (id:Int, button:String) -> getGamepadButtonState(id, button, 1));
		callbackScope.bind("gamepadReleased", (id:Int, button:String) -> getGamepadButtonState(id, button, 2));
	}

	private static function clearSharedPsychObjects():Void
	{
		var game = PlayState.instance;
		for (tag in luaObjects.keys())
		{
			var object = luaObjects.get(tag);
			if (game != null && object != null && game.members.indexOf(object) >= 0) game.remove(object, true);
			if (Std.isOfType(object, FlxSprite)) (cast object:FlxSprite).destroy();
		}
		luaObjects.clear();
		psychVariables.clear();
		luaShaders.clear();
		luaHealthBarColors.clear();
	}

	private function registerLuaObject(tag:String, object:Dynamic):Void
	{
		var key = PsychLuaObjectRegistry.normalizeTag(tag);
		if (key.length == 0) return;
		if (luaObjects.exists(key)) removeLuaObject(key, true);
		luaObjects.set(key, object);
		var game = PlayState.instance;
		if (game != null && game.variables != null)
		{
			game.variables.set(tag, object);
			game.variables.set(key, object);
		}
	}

	/** Makes XML stage sprites available to Lua property and object helpers without serializing Haxe objects. */
	public function setStageSprites(sprites:Map<String, FlxSprite>):Void
	{
		stageLuaObjects = [];
		if (sprites == null) return;
		for (tag => sprite in sprites)
			if (tag != null && sprite != null) stageLuaObjects.set(PsychLuaObjectRegistry.normalizeTag(tag), sprite);
	}

	private function getRunningLuaScripts():Array<String>
	{
		var result:Array<String> = [];
		var game = PlayState.instance;
		if (game != null && game.scripts != null)
			for (script in game.scripts.scripts)
				if (Std.isOfType(script, LuaScript)) result.push(script.path);
		return result;
	}

	private function findLuaScript(name:String):Script
	{
		var game = PlayState.instance;
		if (game == null || game.scripts == null || name == null) return null;
		var target = StringTools.replace(name.toLowerCase(), "\\", "/");
		var targetWithExtension = StringTools.endsWith(target, ".lua") ? target : target + ".lua";
		var targetWithoutExtension = StringTools.endsWith(target, ".lua") ? target.substring(0, target.length - 4) : target;
		for (script in game.scripts.scripts)
			if (Std.isOfType(script, LuaScript)
				&& (script.path.toLowerCase() == target || script.path.toLowerCase() == targetWithExtension
					|| script.fileName.toLowerCase() == target || script.fileName.toLowerCase() == targetWithoutExtension
					|| StringTools.endsWith(script.path.toLowerCase(), targetWithExtension))) return script;
		return null;
	}

	private function isLuaScriptRunning(name:String):Bool
	{
		return findLuaScript(name) != null;
	}

	private function callLuaScript(name:String, functionName:String, ?args:Array<Dynamic>):Dynamic
	{
		var script = findLuaScript(name);
		if (script == null) return null;
		var result = script.call(functionName, args == null ? [] : args);
		return psychLuaProfileName() == PsychLuaProfile.PSYCH_063 ? null : result;
	}

	private function getLuaGlobalFromScript(name:String, global:String):Dynamic
	{
		var script = findLuaScript(name);
		if (script == null || global == null) return null;
		var value = script.get(global);
		if (Std.isOfType(value, String) || Std.isOfType(value, Bool) || Std.isOfType(value, Int) || Std.isOfType(value, Float)) return value;
		return null;
	}

	private function setLuaGlobalFromScript(name:String, global:String, value:Dynamic):Void
	{
		var script = findLuaScript(name);
		if (script != null && global != null) script.set(global, value);
	}

	private function callLuaScripts(functionName:String, ?args:Array<Dynamic>, ?ignoreStops:Bool = false, ?ignoreSelf:Bool = true,
		?excludeScripts:Array<String>, ?excludeValues:Array<Dynamic>):Dynamic
	{
		var game = PlayState.instance;
		var profile = psychLuaProfileName();
		if (game == null || game.scripts == null) return PsychCallbackResult.continueValueForProfile(profile);
		if (excludeScripts == null) excludeScripts = [];
		if (excludeValues == null) excludeValues = PsychCallbackResult.defaultExcludeValues(profile);
		var callbacks:Array<Array<Dynamic>->Dynamic> = [];
		for (script in game.scripts.scripts)
		{
			if (!Std.isOfType(script, LuaScript)) continue;
			if (ignoreSelf && script == this) continue;
			if (isPsychScriptExcluded(script, excludeScripts)) continue;
			if (!script.active) continue;
			var target:LuaScript = cast script;
			callbacks.push((callbackArgs:Array<Dynamic>) -> target.call(functionName, callbackArgs));
		}
		return PsychCallbackResult.dispatchLuaCallbacks(callbacks, args, profile, ignoreStops, excludeValues);
	}

	private function callPsychScripts(functionName:String, ?args:Array<Dynamic>, ?ignoreStops:Bool = false, ?ignoreSelf:Bool = true,
		?excludeScripts:Array<String>, ?excludeValues:Array<Dynamic>):Dynamic
	{
		if (excludeScripts == null) excludeScripts = [];
		if (excludeValues == null) excludeValues = PsychCallbackResult.defaultExcludeValues(psychLuaProfileName());
		var result = callLuaScripts(functionName, args, ignoreStops, ignoreSelf, excludeScripts, excludeValues);
		if (PsychCallbackResult.shouldCallHScript(result, excludeValues))
			result = callScripts(functionName, args, ignoreStops, ignoreSelf, excludeScripts, excludeValues, "hscript");
		return result;
	}

	private function isPsychScriptExcluded(script:Script, exclusions:Array<String>):Bool
	{
		if (script == null || exclusions == null) return false;
		var scriptPath = StringTools.replace(script.path == null ? "" : script.path.toLowerCase(), "\\", "/");
		var fileName = script.fileName == null ? "" : script.fileName.toLowerCase();
		for (entry in exclusions)
		{
			if (entry == null) continue;
			var target = StringTools.replace(entry.toLowerCase(), "\\", "/");
			if (target == fileName || target == scriptPath || (target.length > 0 && StringTools.endsWith(scriptPath, target))) return true;
		}
		return false;
	}

	private function setLuaScripts(name:String, value:Dynamic, ?ignoreSelf:Bool = false, ?excludeScripts:Array<String>, ?luaOnly:Bool = false):Dynamic
	{
		var game = PlayState.instance;
		if (game == null || game.scripts == null) return null;
		for (script in game.scripts.scripts)
		{
			if (luaOnly && !Std.isOfType(script, LuaScript)) continue;
			if (ignoreSelf && script == this) continue;
			if (excludeScripts != null && excludeScripts.contains(script.fileName)) continue;
			script.set(name, value);
		}
		return value;
	}

	private function addLuaScript(name:String, ?ignoreAlreadyRunning:Bool = false):Bool
	{
		var game = PlayState.instance;
		if (game == null || name == null) return false;
		if (!ignoreAlreadyRunning && findLuaScript(name) != null) return false;
		var scriptPath = Paths.script(name);
		if (!Assets.exists(scriptPath)) return false;
		var script = Script.create(scriptPath);
		if (Std.isOfType(script, DummyScript)) return false;
		game.scripts.add(script);
		script.load();
		return true;
	}

	private function removeLuaScript(name:String):Bool
	{
		var game = PlayState.instance;
		var script = findLuaScript(name);
		if (game == null || script == null) return false;
		game.scripts.remove(script);
		script.destroy();
		return true;
	}

	private function findHScript(name:String):Script
	{
		var game = PlayState.instance;
		if (game == null || game.scripts == null || name == null) return null;
		var target = StringTools.replace(name.toLowerCase(), "\\", "/");
		for (script in game.scripts.scripts)
			if (Std.isOfType(script, HScript) && (script.path.toLowerCase() == target || script.fileName.toLowerCase() == target || StringTools.endsWith(script.path.toLowerCase(), target))) return script;
		return null;
	}

	private function addHScript(name:String, ?ignoreAlreadyRunning:Bool = false):Bool
	{
		var game = PlayState.instance;
		if (game == null || name == null || (!ignoreAlreadyRunning && findHScript(name) != null)) return false;
		var requested = StringTools.endsWith(name.toLowerCase(), ".hx") ? name : name + ".hx";
		var scriptPath = Paths.script(requested);
		if (!Assets.exists(scriptPath)) return false;
		var script = Script.create(scriptPath);
		if (!Std.isOfType(script, HScript)) return false;
		game.scripts.add(script);
		script.load();
		return true;
	}

	private function removeHScript(name:String):Bool
	{
		var game = PlayState.instance;
		var script = findHScript(name);
		if (game == null || script == null) return false;
		game.scripts.remove(script);
		script.destroy();
		return true;
	}

	private function callScripts(functionName:String, ?args:Array<Dynamic>, ?ignoreStops:Bool = false, ?ignoreSelf:Bool = true,
		?excludeScripts:Array<String>, ?excludeValues:Array<Dynamic>, ?language:String = "hscript"):Dynamic
	{
		var game = PlayState.instance;
		var profile = psychLuaProfileName();
		if (game == null || game.scripts == null) return PsychCallbackResult.continueValueForProfile(profile);
		if (excludeScripts == null) excludeScripts = [];
		if (excludeValues == null) excludeValues = PsychCallbackResult.defaultExcludeValues(profile);
		var callbacks:Array<Array<Dynamic>->Dynamic> = [];
		for (script in game.scripts.scripts)
		{
			if (language == "hscript" && !Std.isOfType(script, HScript)) continue;
			if (language == "lua" && !Std.isOfType(script, LuaScript)) continue;
			if (ignoreSelf && script == this) continue;
			if (isPsychScriptExcluded(script, excludeScripts)) continue;
			if (!script.active) continue;
			var target:Script = script;
			callbacks.push((callbackArgs:Array<Dynamic>) -> target.call(functionName, callbackArgs));
		}
		return language == "lua"
			? PsychCallbackResult.dispatchLuaCallbacks(callbacks, args, profile, ignoreStops, excludeValues)
			: PsychCallbackResult.dispatchHScriptCallbacks(callbacks, args, profile, ignoreStops, excludeValues);
	}

	private function setScripts(name:String, value:Dynamic, ?ignoreSelf:Bool = false, ?excludeScripts:Array<String>, ?language:String = "hscript"):Dynamic
	{
		var game = PlayState.instance;
		if (game == null || game.scripts == null) return null;
		for (script in game.scripts.scripts)
		{
			if (language == "hscript" && !Std.isOfType(script, HScript)) continue;
			if (language == "lua" && !Std.isOfType(script, LuaScript)) continue;
			if (ignoreSelf && script == this) continue;
			if (excludeScripts != null && excludeScripts.contains(script.fileName)) continue;
			script.set(name, value);
		}
		return value;
	}

	private function runLuaHScriptCode(code:String, ?varsToBring:Dynamic, ?functionName:String, ?args:Array<Dynamic>):Dynamic
	{
		if (code == null) return null;
		var haxeCodeStartedAt = ScriptTimingProfiler.startTimer();
		var hscript = ensureLuaHScript();
		if (hscript == null) {
			ScriptTimingProfiler.finishRunHaxeCode(path, haxeCodeStartedAt);
			return null;
		}
		hscript.set("game", PlayState.instance);
		hscript.set("PlayState", PlayState);
		hscript.set("FlxG", FlxG);
		if (varsToBring != null)
			for (field in Reflect.fields(varsToBring)) hscript.set(field, Reflect.field(varsToBring, field));

		var result = hscript.executeString(code);
		if (functionName != null && functionName.length > 0)
		{
			var callResult = hscript.call(functionName, args == null ? [] : args);
			if (callResult != null) result = callResult;
		}
		ScriptTimingProfiler.finishRunHaxeCode(path, haxeCodeStartedAt);
		return toPsychLuaValue(result);
	}

	private function runLuaHScriptFunction(functionName:String, ?args:Array<Dynamic>):Dynamic
	{
		if (functionName == null) return null;
		var hscript = ensureLuaHScript();
		return hscript == null ? null : toPsychLuaValue(hscript.call(functionName, args == null ? [] : args));
	}

	private function addLuaHaxeLibrary(library:String, ?packageName:String = ""):Bool
	{
		if (library == null) return false;
		var hscript = ensureLuaHScript();
		if (hscript == null) return false;
		var fullName = packageName == null || packageName.length == 0 ? library : packageName + "." + library;
		var resolved:Dynamic = Type.resolveClass(fullName);
		if (resolved == null && psychLuaProfileName() != PsychLuaProfile.PSYCH_063) resolved = Type.resolveEnum(fullName);
		if (resolved == null) return false;
		hscript.set(library, resolved);
		return true;
	}

	private function ensureLuaHScript():HScript
	{
		var game = PlayState.instance;
		if (game == null) return null;
		if (luaHScript != null && Std.isOfType(luaHScript, HScript)) return cast luaHScript;

		var embedded = Script.fromString("", 'psychlua/${fileName}_embedded.hx');
		if (!Std.isOfType(embedded, HScript)) return null;
		luaHScript = embedded;
		game.scripts.add(embedded);
		embedded.set("game", game);
		embedded.set("PlayState", PlayState);
		embedded.set("FlxG", FlxG);
		embedded.load();
		return cast embedded;
	}

	private static function toPsychLuaValue(value:Dynamic):Dynamic
	{
		if (value == null || Std.isOfType(value, Bool) || Std.isOfType(value, Int) || Std.isOfType(value, Float) || Std.isOfType(value, String)
			|| Std.isOfType(value, Array)) return value;
		return null;
	}

	private function closeLuaScript():Bool
	{
		if (scriptClosed) return true;
		scriptClosed = true;
		active = false;
		for (tag in luaTimers.keys()) cancelLuaTimer(tag);
		for (tag in luaTweens.keys()) cancelLuaTween(tag);
		for (tag in luaSounds.keys()) stopLuaSound(tag);
		return true;
	}

	private function bindPsychBackendApi():Void
	{
		callbackScope.bind("getAchievementScore", PsychAchievementStore.getScore);
		callbackScope.bind("setAchievementScore", (name:String, ?value:Float = 0, ?saveIfNotUnlocked:Bool = true) -> PsychAchievementStore.setScore(name, value, saveIfNotUnlocked));
		callbackScope.bind("addAchievementScore", (name:String, ?value:Float = 1, ?saveIfNotUnlocked:Bool = true) -> PsychAchievementStore.addScore(name, value, saveIfNotUnlocked));
		callbackScope.bind("unlockAchievement", PsychAchievementStore.unlock);
		callbackScope.bind("isAchievementUnlocked", PsychAchievementStore.isUnlocked);
		callbackScope.bind("achievementExists", PsychAchievementStore.exists);
		callbackScope.bind("changeDiscordPresence", changePsychDiscordPresence);
		callbackScope.bind("changeDiscordClientID", changePsychDiscordClientID);
		if (psychLuaProfileName() == PsychLuaProfile.PSYCH_063)
			callbackScope.bind("changePresence", changePsychDiscordPresence);
		callbackScope.bind("getTranslationPhrase", getPsychTranslationPhrase);
		callbackScope.bind("getFileTranslation", getPsychFileTranslation);
	}

	private function changePsychDiscordPresence(?details:String = "In the Menus", ?state:String, ?smallImageKey:String,
		?hasStartTimestamp:Bool = false, ?endTimestamp:Float = 0, ?largeImageKey:String = "icon"):Void
	{
		var startTimestamp:Float = hasStartTimestamp ? Date.now().getTime() : 0;
		var end:Float = endTimestamp > 0 ? startTimestamp + endTimestamp : 0;
		DiscordUtil.changePresenceAdvanced({
			state: state,
			details: details,
			smallImageKey: smallImageKey,
			largeImageKey: largeImageKey,
			largeImageText: "Codename Engine",
			startTimestamp: Std.int(startTimestamp / 1000),
			endTimestamp: Std.int(end / 1000)
		});
	}

	private function changePsychDiscordClientID(?newID:String):Void
	{
		DiscordUtil.currentID = newID == null || newID.length == 0 ? funkin.backend.system.Flags.DEFAULT_DISCORD_CLIENT_ID : newID;
	}

	private function getPsychTranslationPhrase(key:String, ?defaultPhrase:String, ?values:Array<Dynamic>):String
	{
		if (key == null) return defaultPhrase == null ? "" : defaultPhrase;
		var id = formatPsychTranslationKey(key);
		var phrase = getPsychLanguagePhrases().get(id);
		if (phrase != null)
		{
			if (values != null)
				for (index in 0...values.length)
					phrase = phrase.replace("{" + (index + 1) + "}", Std.string(values[index]));
			return phrase;
		}
		return TranslationUtil.get(id, values, defaultPhrase == null ? key : defaultPhrase);
	}

	private function getPsychFileTranslation(key:String):String
	{
		if (key == null) return null;
		var translated = getPsychLanguagePhrases().get(key.trim().toLowerCase());
		if (translated != null) return translated;
		return TranslationUtil.exists(key) ? TranslationUtil.get(key, null, key) : key;
	}

	private function formatPsychTranslationKey(key:String):String
	{
		var normalized = StringTools.replace(key, " ", "_");
		var hidden = new EReg("[~&\\\\/;:<>#.,'\"%?!]", "g");
		return hidden.replace(normalized, "").toLowerCase().trim();
	}

	private function getPsychLanguagePhrases():Map<String, String>
	{
		var mod = ModsFolder.currentModFolder == null ? "(base)" : ModsFolder.currentModFolder;
		var language = Options.language == null ? "" : Options.language;
		var cacheKey = mod + "/" + language;
		var phrases = psychTranslationCache.get(cacheKey);
		if (phrases != null) return phrases;
		phrases = [];
		var path = Paths.file('data/$language.lang');
		if (Assets.exists(path))
		{
			var lines = Assets.getText(path).split("\n");
			for (index in 0...lines.length)
			{
				var line = StringTools.trim(lines[index]);
				if (index == 0 && line.indexOf(":") < 0)
				{
					phrases.set("language_name", line);
					continue;
				}
				if (line.length < 4 || StringTools.startsWith(line, "//")) continue;
				var separator = line.indexOf(":");
				if (separator < 0) continue;
				var phraseValue = line.substr(separator);
				var quoteStart = phraseValue.indexOf('"');
				var quoteEnd = phraseValue.lastIndexOf('"');
				if (quoteStart < 0 || quoteEnd <= quoteStart) continue;
				var key = StringTools.trim(line.substr(0, separator)).toLowerCase();
				phrases.set(key, phraseValue.substring(quoteStart + 1, quoteEnd).replace("\\n", "\n"));
			}
		}
		psychTranslationCache.set(cacheKey, phrases);
		return phrases;
	}

	private function readControlState(name:String, state:Int):Bool
	{
		var game = PlayState.instance;
		if (game == null || name == null) return false;
		var key = StringTools.trim(name).toUpperCase();
		if (key == "LEFT" || key == "DOWN" || key == "UP" || key == "RIGHT") key = "NOTE_" + key;
		var suffix = state == 0 ? "_P" : (state == 2 ? "_R" : "");
		return Reflect.getProperty(game.controls, key + suffix) == true;
	}

	private function getGamepadButtonState(id:Int, button:String, state:Int):Bool
	{
		var pad = FlxG.gamepads.getByID(id);
		if (pad == null || button == null) return false;
		var inputs = state == 0 ? pad.justPressed : (state == 2 ? pad.justReleased : pad.pressed);
		return Reflect.getProperty(inputs, button.toUpperCase()) == true;
	}

	private function setLuaOffset(tag:String, name:String, ?x:Float = 0, ?y:Float = 0):Bool
	{
		var sprite = getLuaSprite(tag);
		if (sprite == null) return false;
		if (Std.isOfType(sprite, funkin.backend.FunkinSprite))
			(cast sprite:funkin.backend.FunkinSprite).addOffset(name, x, y);
		else
			sprite.offset.set(x, y);
		return true;
	}

	private function setLuaBlendMode(tag:String, ?name:String = "normal"):Bool
	{
		var sprite = getLuaSprite(tag);
		if (sprite == null || name == null) return false;
		var mode:Null<BlendMode> = switch (name.toUpperCase())
		{
			case "ADD": BlendMode.ADD;
			case "ALPHA": BlendMode.ALPHA;
			case "DARKEN": BlendMode.DARKEN;
			case "DIFFERENCE": BlendMode.DIFFERENCE;
			case "ERASE": BlendMode.ERASE;
			case "HARDLIGHT": BlendMode.HARDLIGHT;
			case "INVERT": BlendMode.INVERT;
			case "LAYER": BlendMode.LAYER;
			case "LIGHTEN": BlendMode.LIGHTEN;
			case "MULTIPLY": BlendMode.MULTIPLY;
			case "NORMAL": BlendMode.NORMAL;
			case "OVERLAY": BlendMode.OVERLAY;
			case "SCREEN": BlendMode.SCREEN;
			case "SHADER": BlendMode.SHADER;
			case "SUBTRACT": BlendMode.SUBTRACT;
			default: null;
		};
		if (mode == null) return false;
		sprite.blend = mode;
		return true;
	}

	private function getLuaObjectPoint(tag:String, graphic:Bool, y:Bool):Float
	{
		var object = getLuaObject(tag);
		if (!Std.isOfType(object, FlxObject)) return 0;
		var point = graphic && Std.isOfType(object, FlxSprite) ? (cast object:FlxSprite).getGraphicMidpoint() : (cast object:FlxObject).getMidpoint();
		return y ? point.y : point.x;
	}

	private function getLuaScreenPosition(tag:String, camera:String, y:Bool):Float
	{
		var object = getLuaObject(tag);
		if (!Std.isOfType(object, FlxObject)) return 0;
		var point = (cast object:FlxObject).getScreenPosition(null, getLuaCamera(camera));
		return y ? point.y : point.x;
	}

	private function makeLuaAnimateSprite(tag:String, ?x:Float = 0, ?y:Float = 0, ?loadFolder:String = null):Bool
	{
		var animateClass = Type.resolveClass("animate.FlxAnimate");
		if (animateClass == null) return false;
		var sprite:Dynamic = Type.createInstance(animateClass, [x, y]);
		if (sprite == null) return false;
		sprite.active = true;
		registerLuaObject(tag, sprite);
		if (loadFolder != null && loadFolder.length > 0 && !loadLuaAnimateAtlas(tag, loadFolder))
		{
			removeLuaObject(tag, true);
			return false;
		}
		return true;
	}

	private function loadLuaAnimateAtlas(tag:String, folderOrImage:String, ?spriteJson:String = null, ?animationJson:String = null):Bool
	{
		var sprite = getLuaObject(tag);
		if (!Std.isOfType(sprite, FlxSprite) || folderOrImage == null || folderOrImage.length == 0) return false;
		var frames:Dynamic = null;
		var animateFrames = Type.resolveClass("animate.FlxAnimateFrames");
		var fromAnimate = animateFrames == null ? null : Reflect.field(animateFrames, "fromAnimate");
		if (fromAnimate != null)
		{
			var metadata:Dynamic = null;
			if (spriteJson != null && Assets.exists(spriteJson)) metadata = Assets.getText(spriteJson);
			frames = Reflect.callMethod(animateFrames, fromAnimate, [folderOrImage, null, metadata, animationJson]);
		}
		if (frames == null) frames = Paths.getFrames(folderOrImage);
		if (frames == null) return false;
		(cast sprite:FlxSprite).frames = frames;
		return true;
	}

	private function addLuaSymbolAnimation(tag:String, name:String, symbol:String, ?frameRate:Float = 24, ?looped:Bool = false, ?matX:Float = 0, ?matY:Float = 0):Bool
	{
		var animateController = getLuaAnimateController(tag);
		if (animateController == null) return false;
		var add = Reflect.field(animateController, "addBySymbol");
		if (add == null) return false;
		Reflect.callMethod(animateController, add, [name, symbol, frameRate, looped, matX, matY]);
		playLuaSymbolAnimationIfNeeded(animateController, name);
		return true;
	}

	private function addLuaSymbolIndicesAnimation(tag:String, name:String, symbol:String, ?indices:Dynamic = null, ?frameRate:Float = 24, ?looped:Bool = false, ?matX:Float = 0, ?matY:Float = 0):Bool
	{
		var animateController = getLuaAnimateController(tag);
		if (animateController == null) return false;
		var add = Reflect.field(animateController, "addBySymbolIndices");
		if (add == null) return false;
		var frameIndices:Array<Int> = [];
		if (indices == null)
			frameIndices.push(0);
		else if (Std.isOfType(indices, String))
		{
			for (index in (cast indices:String).trim().split(","))
				frameIndices.push(Std.int(Std.parseFloat(index)));
		}
		else if (Std.isOfType(indices, Array))
		{
			for (index in (cast indices:Array<Dynamic>))
				frameIndices.push(Std.int(Std.parseFloat(Std.string(index))));
		}
		else
			return false;
		Reflect.callMethod(animateController, add, [name, symbol, frameIndices, frameRate, looped, matX, matY]);
		playLuaSymbolAnimationIfNeeded(animateController, name);
		return true;
	}

	private function playLuaSymbolAnimationIfNeeded(animateController:Dynamic, name:String):Void
	{
		if (Reflect.getProperty(animateController, "curAnim") != null) return;
		var play = Reflect.field(animateController, "play");
		if (play != null) Reflect.callMethod(animateController, play, [name, true]);
	}

	private function getLuaAnimateController(tag:String):Dynamic
	{
		var object = getLuaObject(tag);
		return object == null ? null : Reflect.getProperty(object, "anim");
	}

	private function getLuaGroup(groupName:String):Dynamic
	{
		return PlayState.instance == null ? null : readPath(PlayState.instance, groupName);
	}

	private function getLuaGroupMembers(group:Dynamic):Dynamic
	{
		if (Std.isOfType(group, Array)) return group;
		return group == null ? null : Reflect.getProperty(group, "members");
	}

	private function addLuaObjectToGroup(groupName:String, tag:String, ?index:Int = -1):Bool
	{
		var group = getLuaGroup(groupName);
		var object = getLuaObject(tag);
		var members = getLuaGroupMembers(group);
		if (group == null || object == null || !Std.isOfType(members, Array)) return false;
		var list:Array<Dynamic> = cast members;
		if (list.indexOf(object) >= 0) return true;
		if (Std.isOfType(group, Array))
		{
			var groupArray:Array<Dynamic> = cast group;
			if (index < 0 || index >= groupArray.length) groupArray.push(object); else groupArray.insert(index, object);
		}
		else
		{
			var methodName = index < 0 ? "add" : "insert";
			var method = Reflect.field(group, methodName);
			if (method == null) return false;
			if (index < 0) Reflect.callMethod(group, method, [object]); else Reflect.callMethod(group, method, [index, object]);
		}
		return true;
	}

	private function removeLuaObjectFromGroup(groupName:String, ?index:Int = -1, ?tag:String = null, ?destroy:Bool = true):Bool
	{
		var group = getLuaGroup(groupName);
		var object = tag == null ? null : getLuaObject(tag);
		var members = getLuaGroupMembers(group);
		if (group == null || !Std.isOfType(members, Array)) return false;
		var list:Array<Dynamic> = cast members;
		if (object == null && index >= 0 && index < list.length) object = list[index];
		if (object == null) return false;
		if (Std.isOfType(group, Array))
			(cast group:Array<Dynamic>).remove(object);
		else
		{
			var remove = Reflect.field(group, "remove");
			if (remove == null) return false;
			Reflect.callMethod(group, remove, [object, true]);
		}
		if (destroy && Reflect.hasField(object, "destroy")) Reflect.callMethod(object, Reflect.field(object, "destroy"), []);
		return true;
	}

	private function updateLuaHitboxFromGroup(groupName:String, index:Int):Bool
	{
		var object = getGroupMember(groupName, index);
		if (!Std.isOfType(object, FlxSprite)) return false;
		(cast object:FlxSprite).updateHitbox();
		return true;
	}

	private function getLuaPixelColor(tag:String, x:Int, y:Int):Int
	{
		var sprite = getLuaObject(tag);
		if (!Std.isOfType(sprite, FlxSprite) || (cast sprite:FlxSprite).pixels == null) return FlxColor.BLACK;
		if (Std.isOfType(sprite, LuaGraphicSprite))
		{
			var compactColor:Null<Int> = (cast sprite:LuaGraphicSprite).compactPixelColor(x, y);
			if (compactColor != null) return compactColor;
		}
		var bitmap = (cast sprite:FlxSprite).pixels;
		if (x < 0 || y < 0 || x >= bitmap.width || y >= bitmap.height) return FlxColor.BLACK;
		return bitmap.getPixel32(x, y);
	}

	private function setLuaTextBorder(tag:String, size:Float, color:Dynamic, ?style:String = "outline"):Bool
	{
		var object = luaObjects.get(tag);
		if (!Std.isOfType(object, FlxText)) return false;
		var text:FlxText = cast object;
		text.borderStyle = switch (style == null ? "outline" : style.toLowerCase())
		{
			case "shadow": FlxTextBorderStyle.SHADOW;
			case "outline_fast" | "outlinefast": FlxTextBorderStyle.OUTLINE_FAST;
			case "none": FlxTextBorderStyle.NONE;
			default: size > 0 ? FlxTextBorderStyle.OUTLINE : FlxTextBorderStyle.NONE;
		};
		text.borderSize = Math.max(0, size);
		text.borderColor = parseLuaColor(color);
		return true;
	}

	private function callLuaMethod(methodPath:String, ?args:Array<Dynamic>):Dynamic
	{
		if (methodPath == null || methodPath.length == 0) return null;
		var parts = methodPath.split(".");
		var target:Dynamic = PlayState.instance;
		if (luaObjects.exists(parts[0]))
		{
			target = luaObjects.get(parts.shift());
		}
		else if (psychVariables.exists(parts[0]))
		{
			target = psychVariables.get(parts.shift());
		}
		else if (parts.length > 1)
		{
			var possible = readPath(target, parts[0]);
			if (possible != null) { target = possible; parts.shift(); }
		}
		return callLuaMethodOn(target, parts, args);
	}

	private function callLuaMethodFromClass(className:String, methodPath:String, ?args:Array<Dynamic>):Dynamic
	{
		var target = resolveClass(className);
		return callLuaMethodOn(target, methodPath == null ? [] : methodPath.split("."), args);
	}

	private function callLuaMethodOn(target:Dynamic, parts:Array<String>, ?args:Array<Dynamic>):Dynamic
	{
		if (target == null || parts == null || parts.length == 0) return null;
		var methodName = parts.pop();
		for (part in parts) target = Reflect.getProperty(target, part);
		if (target == null) return null;
		var method = Reflect.field(target, methodName);
		if (method == null) return null;
		var parameters = args == null ? [] : [for (arg in args) resolvePsychInstanceArgument(arg)];
		return Reflect.callMethod(target, method, parameters);
	}

	private function resolvePsychInstanceArgument(argument:Dynamic):Dynamic
	{
		if (argument == null || !Std.isOfType(argument, String)) return argument;
		var value:String = cast argument;
		if (!StringTools.startsWith(value, "##PSYCHLUA_STRINGTOOBJ::")) return argument;
		var parts = value.substr("##PSYCHLUA_STRINGTOOBJ::".length).split("::");
		var root:Dynamic = parts.length > 1 ? resolveClass(parts[1]) : PlayState.instance;
		if (parts.length == 0 || parts[0].length == 0) return root;
		for (field in parts[0].split(".")) root = Reflect.getProperty(root, field);
		return root;
	}

	private function createLuaInstance(variableName:String, className:String, ?args:Array<Dynamic>):Bool
	{
		var key = PsychLuaObjectRegistry.normalizeTag(variableName);
		var instanceClass = resolveClass(className);
		if (key.length == 0 || instanceClass == null || luaObjects.exists(key) || psychVariables.exists(key)) return false;
		try
		{
			var instance = Type.createInstance(instanceClass, args == null ? [] : [for (arg in args) resolvePsychInstanceArgument(arg)]);
			if (instance == null) return false;
			registerLuaObject(key, instance);
			return true;
		}
		catch (error:Dynamic)
		{
			return false;
		}
	}

	private function addLuaInstance(tag:String, ?inFront:Bool = false):Bool
	{
		var game = PlayState.instance;
		var object = getLuaObject(tag);
		if (game == null || !Std.isOfType(object, FlxObject)) return false;
		if (game.members.indexOf(object) >= 0) return true;
		if (inFront) game.add(cast object); else game.insert(0, cast object);
		return true;
	}

	private function setPsychRatingPercent(value:Float):Bool
	{
		if (PlayState.instance != null) setGameValue("accuracy", value);
		set("ratingPercent", value);
		psychVariables.set("ratingPercent", value);
		return true;
	}

	private function precachePsychCharacter(name:String, ?characterType:String = "bf"):Bool
	{
		if (name == null || name.length == 0) return false;
		var isPlayer = characterType != null && ["bf", "boyfriend", "player"].contains(characterType.toLowerCase());
		try
		{
			var character = new Character(0, 0, name, isPlayer, true, true);
			character.destroy();
			return true;
		}
		catch (_:Dynamic) return false;
	}

	private function setPsychHealthBarColors(left:Dynamic, right:Dynamic):Bool
	{
		var game = PlayState.instance;
		if (game == null || game.healthBar == null) return false;
		var colors = luaHealthBarColors.get(game.healthBar);
		if (colors == null)
		{
			colors = [
				game.dad != null && game.dad.iconColor != null && Options.colorHealthBar ? game.dad.iconColor : (PlayState.opponentMode ? 0xFF66FF33 : 0xFFFF0000),
				game.boyfriend != null && game.boyfriend.iconColor != null && Options.colorHealthBar ? game.boyfriend.iconColor : (PlayState.opponentMode ? 0xFFFF0000 : 0xFF66FF33)
			];
		}
		if (left != null && Std.string(left).length > 0) colors[0] = parseLuaColor(left);
		if (right != null && Std.string(right).length > 0) colors[1] = parseLuaColor(right);
		game.healthBar.createFilledBar(colors[0], colors[1]);
		luaHealthBarColors.set(game.healthBar, colors);
		return true;
	}

	private function setPsychTimeBarColors(left:Dynamic, right:Dynamic):Bool
	{
		var game = PlayState.instance;
		if (game == null) return false;
		var leftColor:Null<FlxColor> = left == null || Std.string(left).length == 0 ? null : parseLuaColor(left);
		var rightColor:Null<FlxColor> = right == null || Std.string(right).length == 0 ? null : parseLuaColor(right);
		game.ensurePsychTimeBar().setColors(leftColor, rightColor);
		return true;
	}

	private function loadPsychSong(?name:String = null, ?difficulty:Dynamic = null):Bool
	{
		var song = name == null || name.length == 0 ? (PlayState.instance == null ? null : PlayState.instance.curSong) : name;
		if (song == null || song.length == 0) return false;
		var diff = difficulty == null || (Std.isOfType(difficulty, Int) && difficulty == -1)
			? PlayState.difficulty : Std.string(difficulty);
		var request = SongLoadRequest.forSong(song, diff, null, false, false, "psychLua");
		if (FlxG.sound.music != null)
		{
			FlxG.sound.music.pause();
			FlxG.sound.music.volume = 0;
		}
		SongLoader.start(request, () -> {
			PlayState.loadSong(song, diff);
			return PlayState.SONG;
		});
		return true;
	}

	private function exitPsychSong(?skipTransition:Bool = false):Bool
	{
		var stateName = PlayState.isStoryMode ? "funkin.menus.StoryMenuState" : "funkin.menus.FreeplayState";
		var stateClass = Type.resolveClass(stateName);
		if (stateClass == null) return false;
		FlxG.switchState(cast Type.createInstance(stateClass, []));
		return true;
	}

	private function startPsychDialogue(dialogueFile:String, ?music:String = null):Bool
	{
		var game = PlayState.instance;
		if (game == null || dialogueFile == null || dialogueFile.length == 0) return false;
		var inputPath = dialogueFile;
		var extension = haxe.io.Path.extension(inputPath).toLowerCase();
		var songId = game.curSongID;
		var jsonPath:String = null;
		var jsonSource:String = null;
		if (extension != "xml")
		{
			if (extension == "json" && Assets.exists(inputPath))
			{
				jsonPath = inputPath;
				jsonSource = Assets.getText(jsonPath);
			}
			else
			{
				var dialogueName = haxe.io.Path.withoutExtension(inputPath);
				var relativeName = StringTools.startsWith(dialogueName, "data/") ? dialogueName.substr(5) : null;
				var candidates:Array<String> = [];
				if (relativeName != null)
				{
					candidates.push(Paths.file('data/${relativeName}_${Options.language}.json'));
					candidates.push(Paths.file('data/$relativeName.json'));
				}
				else
				{
					candidates.push(Paths.file('data/$songId/${dialogueName}_${Options.language}.json'));
					candidates.push(Paths.file('data/$songId/$dialogueName.json'));
				}
				for (candidate in candidates)
					if (Assets.exists(candidate))
					{
						jsonPath = candidate;
						jsonSource = Assets.getText(candidate);
						break;
					}
			}
		}

		var path:String = null;
		var source:String = null;
		if (jsonSource != null)
		{
			source = PsychDialogueConverter.toCneXml(jsonSource);
			if (source == null)
			{
				Logs.trace('startDialogue: Psych dialogue JSON is malformed: $jsonPath', WARNING, YELLOW);
				return false;
			}
			path = jsonPath;
		}
		else
		{
			path = inputPath;
			if (!Assets.exists(path))
			{
				path = Paths.file('songs/$songId/$inputPath');
				if (!Assets.exists(path) && !StringTools.endsWith(inputPath.toLowerCase(), ".xml"))
					path = Paths.file('songs/$songId/$inputPath.xml');
			}
			if (!Assets.exists(path) || !StringTools.endsWith(path.toLowerCase(), ".xml"))
			{
				Logs.trace('startDialogue: Dialogue file not found: $dialogueFile', WARNING, YELLOW);
				if (game.endingSong) game.endSong(); else game.startCountdown();
				return false;
			}
		}
		var dialogueClass = Type.resolveClass("funkin.game.cutscenes.DialogueCutscene");
		if (dialogueClass == null) return false;
		var substate = Type.createInstance(dialogueClass, [path, () -> { game.inCutscene = false; game.startCountdown(); }, source, music]);
		game.inCutscene = true;
		game.openSubState(cast substate);
		return true;
	}

	private function startPsychVideo(videoFile:String, ?canSkip:Bool = true, ?forMidSong:Bool = false, ?shouldLoop:Bool = false, ?playOnLoad:Bool = true):Bool
	{
		var game = PlayState.instance;
		if (game == null || videoFile == null || videoFile.length == 0) return false;
		var path = Paths.video(videoFile);
		if (!Assets.exists(path)) return false;
		var videoClass = Type.resolveClass("funkin.game.cutscenes.VideoCutscene");
		if (videoClass == null) return false;
		var substate = Type.createInstance(videoClass, [path, () -> { if (!forMidSong && game.startedCountdown == false) game.startCountdown(); }]);
		if (Reflect.hasField(substate, "skippable")) Reflect.setProperty(substate, "skippable", canSkip);
		game.inCutscene = true;
		game.openSubState(cast substate);
		return true;
	}

	private function openPsychCustomSubstate(name:String, ?pauseGame:Bool = false):Bool
	{
		var game = PlayState.instance;
		if (game == null) return false;
		PsychLuaSubState.currentName = name == null ? "unnamed" : name;
		game.openSubState(new PsychLuaSubState(name, pauseGame));
		return true;
	}

	private function closePsychCustomSubstate():Bool
	{
		if (PsychLuaSubState.instance == null || PlayState.instance == null) return false;
		PlayState.instance.closeSubState();
		return true;
	}

	private function insertPsychCustomSubstate(tag:String, ?position:Int = -1):Bool
	{
		var substate = PsychLuaSubState.instance;
		var object = getLuaObject(tag);
		if (substate == null || object == null || !Std.isOfType(object, FlxObject)) return false;
		if (position < 0) substate.add(cast object); else substate.insert(position, cast object);
		return true;
	}

	private function getPsychModSetting(saveTag:String, ?modName:String = null):Dynamic
	{
		var mod = modName == null || modName.length == 0 ? ModsFolder.currentModFolder : modName;
		if (mod == null || mod.length == 0 || saveTag == null) return null;
		var settings = luaModSettings.get(mod);
		if (settings == null)
		{
			settings = [];
			var filePath = haxe.io.Path.join([ModsFolder.modsPath, mod, "data", "settings.json"]);
			var jsonText:String = null;
			#if sys
			if (FileSystem.exists(filePath) && !FileSystem.isDirectory(filePath))
				try jsonText = File.getContent(filePath) catch (_:Dynamic) {}
			#end
			if (jsonText == null)
			{
				var assetPath = Paths.getPath('mods/$mod/data/settings.json');
				if (Assets.exists(assetPath)) jsonText = Assets.getText(assetPath);
			}
			if (jsonText != null)
				try
				{
					var entries:Dynamic = haxe.Json.parse(jsonText);
					if (Std.isOfType(entries, Array))
						for (entry in (cast entries:Array<Dynamic>))
							if (entry != null && Reflect.field(entry, "save") != null)
							{
								var key:String = Std.string(Reflect.field(entry, "save"));
								if (Reflect.field(entry, "type") == "key" || Reflect.field(entry, "type") == "keybind")
									settings.set(key, {keyboard: Reflect.field(entry, "keyboard") ?? "NONE", gamepad: Reflect.field(entry, "gamepad") ?? "NONE"});
								else if (Reflect.field(entry, "value") != null) settings.set(key, Reflect.field(entry, "value"));
							}
				}
				catch (_:Dynamic) {}
			luaModSettings.set(mod, settings);
		}
		return settings.get(saveTag);
	}

	private function bindPsychGameplayApi():Void
	{
		callbackScope.bind("getHealth", () -> PlayState.instance == null ? 0 : PlayState.instance.health);
		callbackScope.bind("setHealth", (value:Float) -> setGameValue("health", value));
		callbackScope.bind("addHealth", (value:Float) -> setGameValue("health", PlayState.instance == null ? value : PlayState.instance.health + value));
		callbackScope.bind("setScore", (value:Int) -> setGameValue("songScore", value));
		callbackScope.bind("addScore", (value:Int) -> setGameValue("songScore", PlayState.instance == null ? value : PlayState.instance.songScore + value));
		callbackScope.bind("setMisses", function(?value:Int = 0) return setGameValue("misses", value));
		callbackScope.bind("addMisses", function(?value:Int = 0) return setGameValue("misses", PlayState.instance == null ? value : PlayState.instance.misses + value));
		callbackScope.bind("setHits", function(?value:Int = 0) return setGameValue("ratingNum", value));
		callbackScope.bind("addHits", function(?value:Int = 0) return setGameValue("ratingNum", PlayState.instance == null ? value : PlayState.instance.ratingNum + value));
		if (psychLuaProfileName() == PsychLuaProfile.PSYCH_063)
		{
			callbackScope.bind("getScore", () -> PlayState.instance.songScore);
			callbackScope.bind("getHits", () -> PlayState.instance == null ? 0 : PlayState.instance.ratingNum);
			callbackScope.bind("getMisses", () -> PlayState.instance == null ? 0 : PlayState.instance.misses);
		}
		callbackScope.bind("setRatingPercent", setPsychRatingPercent);
		callbackScope.bind("setRatingName", (value:String) -> { set("ratingName", value); psychVariables.set("ratingName", value); true; });
		callbackScope.bind("setRatingFC", (value:String) -> { set("ratingFC", value); psychVariables.set("ratingFC", value); true; });
		callbackScope.bind("getSongPosition", () -> Conductor.songPosition);
		callbackScope.bind("getCharacterX", (name:String) -> { var c = getCharacter(name); c == null ? 0 : c.x; });
		callbackScope.bind("getCharacterY", (name:String) -> { var c = getCharacter(name); c == null ? 0 : c.y; });
		callbackScope.bind("setCharacterX", (name:String, value:Float) -> { var c = getCharacter(name); if (c == null) false else { c.x = value; true; } });
		callbackScope.bind("setCharacterY", (name:String, value:Float) -> { var c = getCharacter(name); if (c == null) false else { c.y = value; true; } });
		callbackScope.bind("setCameraFollowPoint", (x:Float, y:Float) -> { var game = PlayState.instance; if (game == null) false else { game.camFollow.setPosition(x, y); true; } });
		callbackScope.bind("addCameraFollowPoint", function(?x:Float = 0, ?y:Float = 0):Bool
		{
			var game = PlayState.instance;
			if (game == null) return false;
			game.camFollow.x += x;
			game.camFollow.y += y;
			return true;
		});
		callbackScope.bind("getCameraFollowX", () -> PlayState.instance == null ? 0 : PlayState.instance.camFollow.x);
		callbackScope.bind("getCameraFollowY", () -> PlayState.instance == null ? 0 : PlayState.instance.camFollow.y);
		callbackScope.bind("setCameraScroll", (x:Float, y:Float) -> { FlxG.camera.scroll.set(x - FlxG.width * 0.5, y - FlxG.height * 0.5); true; });
		callbackScope.bind("addCameraScroll", function(?x:Float = 0, ?y:Float = 0):Bool { FlxG.camera.scroll.add(x, y); return true; });
		callbackScope.bind("getCameraScrollX", () -> FlxG.camera.scroll.x + FlxG.width * 0.5);
		callbackScope.bind("getCameraScrollY", () -> FlxG.camera.scroll.y + FlxG.height * 0.5);
		callbackScope.bind("cameraShake", (camera:String, intensity:Float, duration:Float) -> { getLuaCamera(camera).shake(intensity, duration); true; });
		callbackScope.bind("cameraFlash", function(camera:String, ?color:Dynamic = "FFFFFF", ?duration:Float = 1, ?forced:Bool = false):Bool
		{
			getLuaCamera(camera).flash(parseLuaColor(color), duration, null, forced);
			return true;
		});
		callbackScope.bind("cameraFade", function(camera:String, ?color:Dynamic = "000000", ?duration:Float = 1, ?forced:Bool = false, ?fadeOut:Bool = false):Bool
		{
			getLuaCamera(camera).fade(parseLuaColor(color), duration, fadeOut, null, forced);
			return true;
		});
		callbackScope.bind("cameraSetTarget", (name:String) -> {
			var game = PlayState.instance;
			var character = getCharacter(name);
			if (game == null || character == null) false else { game.camFollow.setPosition(character.getCameraPosition().x, character.getCameraPosition().y); true; }
		});
		callbackScope.bind("triggerEvent", triggerPsychEvent);
		callbackScope.bind("startCountdown", () -> { if (PlayState.instance != null) PlayState.instance.startCountdown(); true; });
		callbackScope.bind("endSong", () -> { if (PlayState.instance != null) PlayState.instance.endSong(); true; });
		callbackScope.bind("updateScoreText", () -> { var game = PlayState.instance; if (game != null) @:privateAccess if (game.updateRatingStuff != null) game.updateRatingStuff(); true; });
		callbackScope.bind("getColorFromHex", (hex:String) -> parseLuaColor(hex));
		callbackScope.bind("getColorFromString", (color:String) -> parseLuaColor(color));
		callbackScope.bind("getColorFromName", (color:String) -> parseLuaColor(color));
		callbackScope.bind("FlxColor", (color:String) -> parseLuaColor(color));
		callbackScope.bind("precacheImage", (image:String) -> { Paths.image(image); true; });
		callbackScope.bind("precacheSound", (sound:String) -> { Paths.sound(sound); true; });
		callbackScope.bind("precacheMusic", (music:String) -> { Paths.music(music); true; });
		callbackScope.bind("addCharacterToList", precachePsychCharacter);
		callbackScope.bind("setHealthBarColors", setPsychHealthBarColors);
		callbackScope.bind("setTimeBarColors", setPsychTimeBarColors);
		callbackScope.bind("restartSong", (?skipTransition:Bool = false) -> { if (PlayState.instance == null) false else { FlxG.resetState(); true; } });
		callbackScope.bind("exitSong", exitPsychSong);
		callbackScope.bind("loadSong", function(?name:String = null, ?difficulty:Dynamic = null):Void { loadPsychSong(name, difficulty); });
		callbackScope.bind("startDialogue", function(dialogueFile:String, ?music:String = null):Dynamic
		{
			var started = startPsychDialogue(dialogueFile, music);
			return psychLuaProfileName() == PsychLuaProfile.PSYCH_063 ? started : null;
		});
		callbackScope.bind("startVideo", startPsychVideo);
		callbackScope.bind("openCustomSubstate", function(name:String, ?pauseGame:Bool = false):Void { openPsychCustomSubstate(name, pauseGame); });
		callbackScope.bind("closeCustomSubstate", closePsychCustomSubstate);
		if (psychLuaProfileName() != PsychLuaProfile.PSYCH_063)
			callbackScope.bind("insertToCustomSubstate", insertPsychCustomSubstate);
		callbackScope.bind("getModSetting", getPsychModSetting);
	}

	private function bindPsychTimerApi():Void
	{
		callbackScope.bind("runTimer", function(tag:String, ?time:Float = 1, ?loops:Int = 1):Dynamic
		{
			var result = runLuaTimer(tag, time, loops);
			return result == null || psychLuaProfileName() == PsychLuaProfile.PSYCH_063 ? null : psychTaggedValue("timer", tag);
		});
		callbackScope.bind("cancelTimer", function(tag:String):Void { cancelLuaTimer(tag); });
	}

	private inline function psychTaggedValue(kind:String, tag:String):String
	{
		var normalized = StringTools.replace(StringTools.trim(tag), " ", "_");
		normalized = StringTools.replace(normalized, ".", "");
		return kind + "_" + normalized;
	}

	private function psychTweenReturn(tag:String, started:Bool):Dynamic
	{
		if (!started || tag == null) return null;
		return psychLuaProfileName() == PsychLuaProfile.PSYCH_063 ? null : psychTaggedValue("tween", tag);
	}

	private static function parsePsychTweenNumber(value:Dynamic):Float
	{
		if (value == null) return Math.NaN;
		return Std.parseFloat(StringTools.trim(Std.string(value)));
	}

	private function bindPsychTweenApi():Void
	{
		callbackScope.bind("doTweenX", (tag:String, object:String, value:Float, duration:Float, ?ease:String = "linear") -> psychTweenReturn(tag, tweenLuaProperty(tag, object, "x", value, duration, ease)));
		callbackScope.bind("doTweenY", (tag:String, object:String, value:Float, duration:Float, ?ease:String = "linear") -> psychTweenReturn(tag, tweenLuaProperty(tag, object, "y", value, duration, ease)));
		callbackScope.bind("doTweenAngle", (tag:String, object:String, value:Float, duration:Float, ?ease:String = "linear") -> psychTweenReturn(tag, tweenLuaProperty(tag, object, "angle", value, duration, ease)));
		callbackScope.bind("doTweenAlpha", function(tag:String, object:String, value:Dynamic, duration:Dynamic, ?ease:String = "linear"):Dynamic
		{
			var alpha = parsePsychTweenNumber(value);
			var seconds = parsePsychTweenNumber(duration);
			if (Math.isNaN(alpha) || Math.isNaN(seconds))
			{
				trace('Psych doTweenAlpha could not parse values: tag=$tag, object=$object, alpha=$value, duration=$duration');
				return psychTweenReturn(tag, false);
			}
			var started = tweenLuaProperty(tag, object, "alpha", alpha, seconds, ease);
			return psychTweenReturn(tag, started);
		});
		callbackScope.bind("doTweenColor", function(tag:String, object:String, color:Dynamic, duration:Float, ?ease:String = "linear"):Dynamic
			return psychTweenReturn(tag, tweenLuaColor(tag, object, color, duration, ease)));
		callbackScope.bind("doTweenZoom", (tag:String, camera:String, value:Float, duration:Float, ?ease:String = "linear") -> psychTweenReturn(tag, tweenLuaTarget(tag, getLuaCamera(camera), camera, "zoom", value, duration, ease)));
		callbackScope.bind("noteTweenX", (tag:String, note:Int, value:Float, duration:Float, ?ease:String = "linear") -> tweenLuaNote(tag, note, "x", value, duration, ease));
		callbackScope.bind("noteTweenY", (tag:String, note:Int, value:Float, duration:Float, ?ease:String = "linear") -> tweenLuaNote(tag, note, "y", value, duration, ease));
		callbackScope.bind("noteTweenAngle", (tag:String, note:Int, value:Float, duration:Float, ?ease:String = "linear") -> tweenLuaNote(tag, note, "angle", value, duration, ease));
		callbackScope.bind("noteTweenAlpha", (tag:String, note:Int, value:Float, duration:Float, ?ease:String = "linear") -> tweenLuaNote(tag, note, "alpha", value, duration, ease));
		callbackScope.bind("noteTweenDirection", (tag:String, note:Int, value:Float, duration:Float, ?ease:String = "linear") -> tweenLuaNote(tag, note, "direction", value, duration, ease));
		if (psychLuaProfileName() != PsychLuaProfile.PSYCH_063) callbackScope.bind("startTween", startLuaTween);
		callbackScope.bind("cancelTween", function(tag:String):Void { cancelLuaTween(tag); });
	}

	private function bindPsychSoundApi():Void
	{
		callbackScope.bind("playMusic", function(name:String, ?volume:Float = 1, ?loop:Bool = false):Void
		{
			FlxG.sound.playMusic(Paths.music(name), volume, loop);
		});
		callbackScope.bind("playSound", function(name:String, ?volume:Float = 1, ?tag:String = null, ?loop:Bool = false):Dynamic
		{
			var result = playLuaSound(name, volume, tag, loop);
			return result == null || psychLuaProfileName() == PsychLuaProfile.PSYCH_063 ? null : psychTaggedValue("sound", tag);
		});
		callbackScope.bind("stopSound", function(tag:String):Void { stopLuaSound(tag); });
		callbackScope.bind("pauseSound", function(tag:String):Void { pauseLuaSound(tag); });
		callbackScope.bind("resumeSound", function(tag:String):Void { resumeLuaSound(tag); });
		callbackScope.bind("luaSoundExists", (tag:String) -> luaSounds.exists(tag));
		callbackScope.bind("getSoundVolume", getLuaSoundVolume);
		callbackScope.bind("setSoundVolume", function(tag:String, value:Float):Void { setLuaSoundVolume(tag, value); });
		callbackScope.bind("getSoundTime", getLuaSoundTime);
		callbackScope.bind("setSoundTime", function(tag:String, value:Float):Void { setLuaSoundTime(tag, value); });
		if (psychLuaProfileName() != PsychLuaProfile.PSYCH_063)
		{
			callbackScope.bind("getSoundPitch", getLuaSoundPitch);
			callbackScope.bind("setSoundPitch", function(tag:String, value:Float, ?doPause:Bool = false):Void { setLuaSoundPitch(tag, value, doPause); });
		}
		callbackScope.bind("soundFadeOut", function(tag:String, duration:Float, ?to:Float = 0):Void { fadeLuaSound(tag, duration, to, false); });
		callbackScope.bind("soundFadeIn", function(tag:String, duration:Float, ?from:Float = 0, ?to:Float = 1):Void { fadeLuaSound(tag, duration, to, true, from); });
		callbackScope.bind("soundFadeCancel", function(tag:String):Void { cancelLuaSoundFade(tag); });
		callbackScope.bind("musicFadeOut", function(duration:Float, ?to:Float = 0):Void { if (FlxG.sound.music != null) FlxG.sound.music.fadeOut(duration, to); });
		callbackScope.bind("musicFadeIn", function(duration:Float, ?from:Float = 0, ?to:Float = 1):Void { if (FlxG.sound.music != null) FlxG.sound.music.fadeIn(duration, from, to); });
		callbackScope.bind("initSaveData", function(name:String, ?folder:String = "psychenginemods"):Void { initLuaSaveData(name, folder); });
		callbackScope.bind("flushSaveData", function(name:String):Void { flushLuaSaveData(name); });
		callbackScope.bind("getDataFromSave", getLuaSaveData);
		callbackScope.bind("setDataFromSave", function(name:String, field:String, value:Dynamic):Void { setLuaSaveData(name, field, value); });
		if (psychLuaProfileName() != PsychLuaProfile.PSYCH_063)
			callbackScope.bind("eraseSaveData", function(name:String):Void { eraseLuaSaveData(name); });
		callbackScope.bind("checkFileExists", checkLuaFileExists);
		callbackScope.bind("saveFile", saveLuaFile);
		callbackScope.bind("deleteFile", deleteLuaFile);
		callbackScope.bind("getTextFromFile", getLuaTextFromFile);
		callbackScope.bind("directoryFileList", listLuaDirectoryFiles);
		callbackScope.bind("initLuaShader", initLuaShader);
		callbackScope.bind("setSpriteShader", setLuaSpriteShader);
		callbackScope.bind("removeSpriteShader", removeLuaSpriteShader);
		callbackScope.bind("setShaderBool", (tag:String, field:String, value:Bool) -> setLuaShaderValue(tag, field, value, "Bool"));
		callbackScope.bind("setShaderInt", (tag:String, field:String, value:Int) -> setLuaShaderValue(tag, field, value, "Int"));
		callbackScope.bind("setShaderFloat", (tag:String, field:String, value:Float) -> setLuaShaderValue(tag, field, value, "Float"));
		callbackScope.bind("setShaderBoolArray", (tag:String, field:String, value:Array<Dynamic>) -> setLuaShaderValue(tag, field, value, "BoolArray"));
		callbackScope.bind("setShaderIntArray", (tag:String, field:String, value:Array<Dynamic>) -> setLuaShaderValue(tag, field, value, "IntArray"));
		callbackScope.bind("setShaderFloatArray", (tag:String, field:String, value:Array<Dynamic>) -> setLuaShaderValue(tag, field, value, "FloatArray"));
		callbackScope.bind("setShaderSampler2D", setLuaShaderSampler);
		callbackScope.bind("getShaderBool", (tag:String, field:String) -> getLuaShaderValue(tag, field, "getBool"));
		callbackScope.bind("getShaderInt", (tag:String, field:String) -> getLuaShaderValue(tag, field, "getInt"));
		callbackScope.bind("getShaderFloat", (tag:String, field:String) -> getLuaShaderValue(tag, field, "getFloat"));
		callbackScope.bind("getShaderBoolArray", (tag:String, field:String) -> getLuaShaderValue(tag, field, "getBoolArray"));
		callbackScope.bind("getShaderIntArray", (tag:String, field:String) -> getLuaShaderValue(tag, field, "getIntArray"));
		callbackScope.bind("getShaderFloatArray", (tag:String, field:String) -> getLuaShaderValue(tag, field, "getFloatArray"));
	}

	private function initializePsychGlobals():Void
	{
		set("engine", {
			commit: Flags.COMMIT_NUMBER,
			hash: Flags.COMMIT_HASH,
			build: 2675,
			name: "Codename Engine",
			displayName: "DBE (Debug Engine)",
			modApiVersion: Flags.CURRENT_API_VERSION,
			compatibility: ScriptCapabilities.getLuaCompatibilityInfo()
		});
		var callbackConstants = PsychCallbackResult.constantsForProfile(psychLuaProfileName());
		set("Function_Stop", callbackConstants.stop);
		set("Function_Continue", callbackConstants.continueValue);
		set("Function_StopLua", callbackConstants.stopLua);
		if (callbackConstants.stopHScript != null) set("Function_StopHScript", callbackConstants.stopHScript);
		if (callbackConstants.stopAll != null) set("Function_StopAll", callbackConstants.stopAll);
		set("scriptName", path);
		set("screenWidth", FlxG.width);
		set("screenHeight", FlxG.height);
		updatePsychGlobals();
	}

	private function updatePsychGlobals():Void
	{
		var game = PlayState.instance;
		set("songPosition", Conductor.songPosition);
		set("curBeat", Conductor.curBeat);
		set("curStep", Conductor.curStep);
		set("curDecBeat", Conductor.curBeatFloat);
		set("curDecStep", Conductor.curStepFloat);
		set("bpm", Conductor.bpm);
		set("curBpm", Conductor.bpm);
		set("crochet", Conductor.crochet);
		set("stepCrochet", Conductor.stepCrochet);
		if (game == null) return;
		set("songName", game.curSong);
		set("songPath", game.curSongID);
		set("curStage", game.curStage);
		set("difficulty", PlayState.difficulty);
		set("health", game.health);
		set("score", game.songScore);
		set("misses", game.misses);
		set("combo", game.combo);
		set("downscroll", game.downscroll);
		set("defaultCamZoom", game.defaultCamZoom);
		set("cameraZoomOnBeat", game.camZooming);
		set("isStoryMode", PlayState.isStoryMode);
		set("mustHitSection", game.curCameraTarget != 0);
		set("boyfriendName", game.boyfriend == null ? "" : game.boyfriend.curCharacter);
		set("dadName", game.dad == null ? "" : game.dad.curCharacter);
		set("gfName", game.gf == null ? "" : game.gf.curCharacter);
		set("defaultBoyfriendX", game.boyfriend == null ? 0 : game.boyfriend.x);
		set("defaultBoyfriendY", game.boyfriend == null ? 0 : game.boyfriend.y);
		set("defaultOpponentX", game.dad == null ? 0 : game.dad.x);
		set("defaultOpponentY", game.dad == null ? 0 : game.dad.y);
		set("defaultGirlfriendX", game.gf == null ? 0 : game.gf.x);
		set("defaultGirlfriendY", game.gf == null ? 0 : game.gf.y);
	}

	private function setGameValue(field:String, value:Dynamic):Dynamic
	{
		var game = PlayState.instance;
		if (game == null) return null;
		Reflect.setProperty(game, field, value);
		if (field == "songScore" || field == "misses" || field == "ratingNum") @:privateAccess if (game.updateRatingStuff != null) game.updateRatingStuff();
		return value;
	}

	private function triggerPsychEvent(name:String, ?value1:String = "", ?value2:String = ""):Bool
	{
		var game = PlayState.instance;
		if (game == null || name == null) return false;
		var first = value1 == null ? "" : value1;
		var second = value2 == null ? "" : value2;
		switch (name.toLowerCase())
		{
			case "camera follow pos":
				var x = Std.parseFloat(first);
				var y = Std.parseFloat(second);
				if (!Math.isNaN(x) && !Math.isNaN(y)) game.camFollow.setPosition(x, y);
			case "add camera zoom":
				var amount = Std.parseFloat(first);
				if (!Math.isNaN(amount)) game.camGame.zoom += amount;
			case "change scroll speed":
				var speed = Std.parseFloat(second);
				if (Math.isNaN(speed)) speed = Std.parseFloat(first);
				if (!Math.isNaN(speed)) game.scrollSpeed = speed;
			case "play animation":
				var character = getCharacter(first);
				if (character != null) character.playAnim(second, true);
			default:
				var event:ChartEvent = {name: name, time: Conductor.songPosition, params: [first, second]};
			game.executeEvent(event);
		}
		return true;
	}

	private function readInputState(state:Dynamic, key:String):Bool
	{
		if (state == null || key == null) return false;
		var normalized = StringTools.replace(StringTools.trim(key), " ", "_").toUpperCase();
		return Reflect.getProperty(state, normalized) == true;
	}

	private function readMouseState(button:String, state:Int):Bool
	{
		var normalized = button == null ? "left" : StringTools.trim(button).toLowerCase();
		return switch (state)
		{
			case 1: normalized == "middle" ? FlxG.mouse.pressedMiddle : (normalized == "right" ? FlxG.mouse.pressedRight : FlxG.mouse.pressed);
			case 2: normalized == "middle" ? FlxG.mouse.justReleasedMiddle : (normalized == "right" ? FlxG.mouse.justReleasedRight : FlxG.mouse.justReleased);
			default: normalized == "middle" ? FlxG.mouse.justPressedMiddle : (normalized == "right" ? FlxG.mouse.justPressedRight : FlxG.mouse.justPressed);
		};
	}

	private function runLuaTimer(tag:String, ?time:Float = 1, ?loops:Int = 1):String
	{
		if (tag == null || tag.length == 0 || PlayState.instance == null) return null;
		cancelLuaTimer(tag);
		var timer = new FlxTimer();
		luaTimers.set(tag, timer);
		timer.start(time, (finished:FlxTimer) -> {
			if (finished.finished) luaTimers.remove(tag);
			callLua("onTimerCompleted", [tag, finished.loops, finished.loopsLeft]);
		}, loops);
		return tag;
	}

	private function cancelLuaTimer(tag:String):Bool
	{
		var timer = luaTimers.get(tag);
		if (timer == null) return false;
		timer.cancel();
		timer.destroy();
		luaTimers.remove(tag);
		return true;
	}

	private function tweenLuaProperty(tag:String, objectName:String, property:String, value:Dynamic, duration:Float, ?ease:String = "linear"):Bool
	{
		return tweenLuaTarget(tag, getLuaObject(objectName), objectName, property, value, duration, ease);
	}

	private function tweenLuaNote(tag:String, noteIndex:Int, property:String, value:Float, duration:Float, ?ease:String = "linear"):Bool
	{
		var strum:Dynamic = getGroupMember("strumLineNotes", noteIndex);
		if (property == "direction")
		{
			if (!Std.isOfType(strum, Strum)) return false;
			var receptor:Strum = cast strum;
			if (receptor.noteAngle == null) receptor.noteAngle = receptor.getNotesAngle();
			property = "noteAngle";
			value -= 90;
		}
		return tweenLuaTarget(tag, strum, 'strumLineNotes[$noteIndex]', property, value, duration, ease);
	}

	private function tweenLuaColor(tag:String, objectName:String, color:Dynamic, duration:Float, ?ease:String = "linear"):Bool
	{
		var target = getLuaObject(objectName);
		if (tag == null || target == null || Reflect.getProperty(target, "color") == null || duration < 0) return false;
		cancelLuaTween(tag);
		var startColor:FlxColor = cast Reflect.getProperty(target, "color");
		var endColor = parseLuaColor(color);
		luaTweens.set(tag, FlxTween.color(target, duration, startColor, endColor, {
			ease: resolveLuaEase(ease),
			onComplete: function(_:FlxTween)
			{
				luaTweens.remove(tag);
				callLua("onTweenCompleted", PsychHookMap.makeTweenCompletedArguments(psychLuaProfileName(), tag, objectName, true));
			}
		}));
		return true;
	}

	private function startLuaTween(tag:String, objectName:String, values:Dynamic, duration:Float, ?options:Dynamic):Dynamic
	{
		var target = getLuaObject(objectName);
		if (tag == null || target == null || values == null || duration < 0) return null;
		var properties:Dynamic = {};
		for (field in Reflect.fields(values)) Reflect.setField(properties, field, Reflect.field(values, field));
		cancelLuaTween(tag);
		var easeName = options == null ? "linear" : Std.string(Reflect.getProperty(options, "ease"));
		var tweenOptions:Dynamic = {
			ease: resolveLuaEase(easeName),
			onComplete: function(_:FlxTween)
			{
				luaTweens.remove(tag);
				callLua("onTweenCompleted", PsychHookMap.makeTweenCompletedArguments(psychLuaProfileName(), tag, objectName));
			}
		};
		if (options != null)
			for (field in ["startDelay", "loopDelay", "loops", "type"])
				if (Reflect.hasField(options, field)) Reflect.setField(tweenOptions, field, Reflect.field(options, field));
		luaTweens.set(tag, FlxTween.tween(target, properties, duration, tweenOptions));
		return tag;
	}

	private function tweenLuaTarget(tag:String, target:Dynamic, objectName:String, property:String, value:Dynamic, duration:Float, ?ease:String = "linear"):Bool
	{
		if (tag == null || target == null || duration < 0) return false;
		cancelLuaTween(tag);
		var properties:Dynamic = {};
		Reflect.setField(properties, property, value);
		var options:Dynamic = {
			ease: resolveLuaEase(ease),
			onComplete: function(_:FlxTween)
			{
				luaTweens.remove(tag);
				callLua("onTweenCompleted", PsychHookMap.makeTweenCompletedArguments(psychLuaProfileName(), tag, objectName));
			}
		};
		luaTweens.set(tag, FlxTween.tween(target, properties, duration, options));
		return true;
	}

	private function resolveLuaEase(name:String):Dynamic
	{
		if (name == null || name.length == 0) return FlxEase.linear;
		var normalized = StringTools.trim(name);
		var easing = Reflect.field(FlxEase, normalized);
		if (easing == null) easing = Reflect.field(FlxEase, normalized.toLowerCase());
		return easing == null ? FlxEase.linear : easing;
	}

	private function cancelLuaTween(tag:String):Bool
	{
		var tween = luaTweens.get(tag);
		if (tween == null) return false;
		tween.cancel();
		luaTweens.remove(tag);
		return true;
	}

	private function cancelLuaSoundFade(tag:String):Bool
	{
		var sound = tag == null || tag.length == 0 ? FlxG.sound.music : luaSounds.get(tag);
		if (sound == null) return false;
		var fadeTween = Reflect.getProperty(sound, "fadeTween");
		if (fadeTween == null) fadeTween = Reflect.getProperty(sound, "_fadeTween");
		if (fadeTween != null && Reflect.field(fadeTween, "cancel") != null)
		{
			Reflect.callMethod(fadeTween, Reflect.field(fadeTween, "cancel"), []);
			return true;
		}
		return false;
	}

	private function playLuaSound(name:String, ?volume:Float = 1, ?tag:String = null, ?loop:Bool = false):Dynamic
	{
		if (name == null || name.length == 0) return null;
		if (tag == null || tag.length == 0)
		{
			FlxG.sound.play(Paths.sound(name), volume, loop);
			return null;
		}
		stopLuaSound(tag);
		var sound = FlxG.sound.play(Paths.sound(name), volume, loop, null, true, () -> {
			if (!luaSoundLoops.exists(tag) || !luaSoundLoops.get(tag))
			{
				luaSounds.remove(tag);
				luaSoundLoops.remove(tag);
			}
			callLua("onSoundFinished", [tag]);
		});
		luaSounds.set(tag, sound);
		luaSoundLoops.set(tag, loop);
		return tag;
	}

	private function stopLuaSound(tag:String):Bool
	{
		if (tag == null || tag.length == 0)
		{
			if (FlxG.sound.music != null) FlxG.sound.music.stop();
			return true;
		}
		var sound = luaSounds.get(tag);
		if (sound == null) return false;
		sound.stop();
		luaSounds.remove(tag);
		luaSoundLoops.remove(tag);
		return true;
	}

	private inline function getLuaSound(tag:String):FlxSound
		return tag == null || tag.length == 0 ? FlxG.sound.music : luaSounds.get(tag);

	private function getLuaSoundVolume(tag:String):Float
	{
		var sound = getLuaSound(tag);
		return sound == null ? 0 : sound.volume;
	}

	private function setLuaSoundVolume(tag:String, value:Float):Void
	{
		var sound = getLuaSound(tag);
		if (sound != null) sound.volume = value;
	}

	private function getLuaSoundTime(tag:String):Float
	{
		var sound = getLuaSound(tag);
		return sound == null ? 0 : sound.time;
	}

	private function setLuaSoundTime(tag:String, value:Float):Void
	{
		var sound = getLuaSound(tag);
		if (sound != null) sound.time = value;
	}

	private function getLuaSoundPitch(tag:String):Float
	{
		var sound = getLuaSound(tag);
		return sound == null ? 1 : sound.pitch;
	}

	private function setLuaSoundPitch(tag:String, value:Float, ?doPause:Bool = false):Void
	{
		var sound = getLuaSound(tag);
		if (sound == null) return;
		var wasPlaying = sound.playing;
		if (doPause) sound.pause();
		sound.pitch = value;
		if (doPause && wasPlaying) sound.play();
	}

	private function pauseLuaSound(tag:String):Bool
	{
		var sound = tag == null || tag.length == 0 ? FlxG.sound.music : luaSounds.get(tag);
		if (sound == null) return false;
		sound.pause();
		return true;
	}

	private function resumeLuaSound(tag:String):Bool
	{
		var sound = tag == null || tag.length == 0 ? FlxG.sound.music : luaSounds.get(tag);
		if (sound == null) return false;
		sound.play();
		return true;
	}

	private function fadeLuaSound(tag:String, duration:Float, to:Float, fadeIn:Bool, ?from:Float = 0):Bool
	{
		var sound = tag == null || tag.length == 0 ? FlxG.sound.music : luaSounds.get(tag);
		if (sound == null) return false;
		if (fadeIn) sound.fadeIn(duration, from, to); else sound.fadeOut(duration, to);
		return true;
	}

	private function getLuaSaveKey(name:String, folder:String):String
	{
		return '${folder == null ? "psychenginemods" : folder}/$name';
	}

	private function initLuaSaveData(name:String, ?folder:String = "psychenginemods"):Bool
	{
		if (name == null || name.length == 0) return false;
		var key = getLuaSaveKey(name, folder);
		if (luaSaves.exists(key)) return true;
		var save = new FlxSave();
		if (!save.bind(name, folder == null ? "psychenginemods" : folder)) return false;
		luaSaves.set(key, save);
		return true;
	}

	private function flushLuaSaveData(name:String):Bool
	{
		var save = findLuaSave(name);
		if (save == null) return false;
		save.flush();
		return true;
	}

	private function getLuaSaveData(name:String, field:String, ?defaultValue:Dynamic):Dynamic
	{
		var save = findLuaSave(name);
		if (save == null || save.data == null) return defaultValue;
		if (!Reflect.hasField(save.data, field))
			return psychLuaProfileName() == PsychLuaProfile.PSYCH_063 ? null : defaultValue;
		return Reflect.field(save.data, field);
	}

	private function setLuaSaveData(name:String, field:String, value:Dynamic):Bool
	{
		var save = findLuaSave(name);
		if (save == null || field == null || field.length == 0) return false;
		Reflect.setField(save.data, field, value);
		return true;
	}

	private function eraseLuaSaveData(name:String):Bool
	{
		var save = findLuaSave(name);
		if (save == null) return false;
		save.erase();
		return true;
	}

	private function findLuaSave(name:String):FlxSave
	{
		if (name == null) return null;
		for (key => save in luaSaves)
			if (StringTools.endsWith(key, '/$name')) return save;
		return null;
	}

	private function resolveLuaFilePath(path:String, absolute:Bool, writing:Bool):String
	{
		if (path == null || path.length == 0 || absolute) return path;
		if (!writing) return Paths.getPath(path);
		var modPath = ModsFolder.modsPath;
		if (ModsFolder.currentModFolder != null && ModsFolder.currentModFolder.length > 0)
			modPath = haxe.io.Path.join([modPath, ModsFolder.currentModFolder]);
		return haxe.io.Path.join([modPath, path]);
	}

	private function checkLuaFileExists(path:String, ?absolute:Bool = false):Bool
	{
		if (path == null || path.length == 0) return false;
		var deletedKey = getLuaFileStateKey(path, absolute);
		if (luaDeletedFiles.exists(deletedKey)) return false;
		if (!absolute)
		{
			var assetPath = Paths.getPath(path);
			if (Assets.exists(assetPath)) return true;
		}
		#if sys
		return FileSystem.exists(resolveLuaFilePath(path, absolute, false));
		#else
		return absolute && Assets.exists(path);
		#end
	}

	private function saveLuaFile(path:String, content:String, ?absolute:Bool = false):Bool
	{
		#if sys
		if (path == null || content == null) return false;
		var target:String = null;
		try
		{
			target = resolveLuaFilePath(path, absolute, true);
			var folder = haxe.io.Path.directory(target);
			if (folder != null && folder.length > 0 && !FileSystem.exists(folder)) FileSystem.createDirectory(folder);
			File.saveContent(target, content);
			luaDeletedFiles.remove(getLuaFileStateKey(path, absolute));
			return true;
		}
		catch (error:Dynamic)
		{
			Logs.trace('saveFile: could not write "$target": ${Std.string(error)}', WARNING, YELLOW);
			return false;
		}
		#else
		return false;
		#end
	}

	private function deleteLuaFile(path:String, ?ignoreModFolders:Bool = false, ?absolute:Bool = false):Bool
	{
		#if sys
		if (path == null || path.length == 0) return false;
		try
		{
			var target = absolute ? path : (ignoreModFolders ? Paths.getPath(path) : resolveLuaFilePath(path, false, true));
			if (!FileSystem.exists(target) || FileSystem.isDirectory(target)) return false;
			FileSystem.deleteFile(target);
			luaDeletedFiles.set(getLuaFileStateKey(path, absolute), true);
			return true;
		}
		catch (_:Dynamic) return false;
		#else
		return false;
		#end
	}

	private function getLuaTextFromFile(path:String, ?ignoreModFolders:Bool = false):String
	{
		if (path == null || path.length == 0) return null;
		if (luaDeletedFiles.exists(getLuaFileStateKey(path, false))) return null;
		var assetPath = ignoreModFolders ? Paths.getPath(path) : Paths.getPath(path);
		if (Assets.exists(assetPath)) return Assets.getText(assetPath);
		#if sys
		var filePath = resolveLuaFilePath(path, false, false);
		if (FileSystem.exists(filePath) && !FileSystem.isDirectory(filePath))
			try return File.getContent(filePath) catch (_:Dynamic) return null;
		#end
		return null;
	}

	private static function getLuaFileStateKey(path:String, absolute:Bool):String
	{
		var normalized = StringTools.replace(path, "\\", "/");
		var modName = ModsFolder.currentModFolder == null ? "(default)" : ModsFolder.currentModFolder;
		return (absolute ? "absolute:" : 'mod:$modName:') + normalized;
	}

	private function listLuaDirectoryFiles(folder:String):Array<String>
	{
		var result:Array<String> = [];
		#if sys
		if (folder == null || !FileSystem.exists(folder) || !FileSystem.isDirectory(folder)) return result;
		try result = FileSystem.readDirectory(folder) catch (_:Dynamic) {}
		#end
		return result;
	}

	private function initLuaShader(name:String):Bool
	{
		if (name == null || name.length == 0) return false;
		if (luaShaders.exists(name)) return true;
		try
		{
			luaShaders.set(name, new CustomShader(name));
			return true;
		}
		catch (_:Dynamic) return false;
	}

	private function getLuaShader(tag:String):Dynamic
	{
		var object = getLuaObject(tag);
		var shader = object == null ? null : Reflect.getProperty(object, "shader");
		return shader == null ? luaShaders.get(tag) : shader;
	}

	private function setLuaSpriteShader(tag:String, shaderName:String):Bool
	{
		var object = getLuaObject(tag);
		if (!Std.isOfType(object, FlxSprite) || !initLuaShader(shaderName)) return false;
		(cast object:FlxSprite).shader = luaShaders.get(shaderName);
		return true;
	}

	private function removeLuaSpriteShader(tag:String):Bool
	{
		var object = getLuaObject(tag);
		if (!Std.isOfType(object, FlxSprite)) return false;
		(cast object:FlxSprite).shader = null;
		return true;
	}

	private function setLuaShaderValue(tag:String, field:String, value:Dynamic, kind:String):Bool
	{
		var shader = getLuaShader(tag);
		var setterName = "set" + kind;
		var setter = shader == null ? null : Reflect.field(shader, setterName);
		if (setter == null) return false;
		try { Reflect.callMethod(shader, setter, [field, value]); return true; }
		catch (_:Dynamic) return false;
	}

	private function getLuaShaderValue(tag:String, field:String, getterName:String):Dynamic
	{
		var shader = getLuaShader(tag);
		var getter = shader == null ? null : Reflect.field(shader, getterName);
		if (getter == null) return null;
		try return Reflect.callMethod(shader, getter, [field]) catch (_:Dynamic) return null;
	}

	private function setLuaShaderSampler(tag:String, field:String, image:String):Bool
	{
		var shader = getLuaShader(tag);
		if (shader == null || image == null) return false;
		var setter = Reflect.field(shader, "setSampler2D");
		if (setter == null) return false;
		try
		{
			var graphic = FlxG.bitmap.add(Paths.image(image));
			Reflect.callMethod(shader, setter, [field, graphic.bitmap]);
			return true;
		}
		catch (_:Dynamic) return false;
	}

	private function getLuaObject(tag:String):Dynamic
	{
		var object = luaObjects.get(tag);
		if (object != null) return object;
		object = stageLuaObjects.get(PsychLuaObjectRegistry.normalizeTag(tag));
		if (object != null) return object;
		var char = getCharacter(tag);
		if (char != null) return char;
		return PsychLuaPropertyPath.read(PlayState.instance, tag);
	}

	private function getLuaSprite(tag:String):FlxSprite
	{
		var object = luaObjects.get(tag);
		if (object == null) object = stageLuaObjects.get(PsychLuaObjectRegistry.normalizeTag(tag));
		return Std.isOfType(object, FlxSprite) ? cast object : null;
	}

	private function getOrCreateLuaSprite(tag:String):FlxSprite
	{
		var sprite = getLuaSprite(tag);
		if (sprite == null)
		{
			sprite = new LuaGraphicSprite();
			if (PlayState.instance != null) sprite.cameras = [PlayState.instance.camGame];
			registerLuaObject(tag, sprite);
		}
		return sprite;
	}

	private function makeLuaSpriteGraphic(sprite:FlxSprite, width:Int, height:Int, color:FlxColor):Void
	{
		if (Std.isOfType(sprite, LuaGraphicSprite))
			(cast sprite:LuaGraphicSprite).makeLuaGraphic(width, height, color);
		else
			sprite.makeGraphic(width, height, color);
	}

	private function addLuaSprite(tag:String, ?inFront:Bool = false):Bool
	{
		var game = PlayState.instance;
		var sprite = getLuaSprite(tag);
		if (game == null || sprite == null) return false;
		if (sprite.cameras == null) sprite.cameras = [game.camGame];
		if (game.members.indexOf(sprite) >= 0) return true;
		if (inFront)
			game.add(sprite);
		else
		{
			var firstCharacterIndex = game.members.length;
			for (line in game.strumLines.members)
				if (line != null && line.characters != null)
					for (character in line.characters)
					{
						var index = game.members.indexOf(character);
						if (index >= 0 && index < firstCharacterIndex) firstCharacterIndex = index;
					}
			game.insert(firstCharacterIndex, sprite);
		}
		return true;
	}

	private function addLuaObject(tag:String, ?inFront:Bool = false):Bool
	{
		var game = PlayState.instance;
		var object = luaObjects.get(tag);
		if (game == null || object == null) return false;
		if (Std.isOfType(object, FlxSprite) && (cast object:FlxSprite).cameras == null)
			(cast object:FlxSprite).cameras = [Std.isOfType(object, FlxText) ? game.camHUD : game.camGame];
		if (game.members.indexOf(object) < 0)
		{
			if (inFront) game.add(object); else game.insert(0, object);
		}
		return true;
	}

	private function removeLuaSprite(tag:String, ?destroy:Bool = true):Bool
	{
		return removeLuaObject(tag, destroy);
	}

	private function removeLuaObject(tag:String, ?destroy:Bool = true):Bool
	{
		var game = PlayState.instance;
		var object = luaObjects.get(tag);
		if (object == null) return false;
		if (game != null && game.members.indexOf(object) >= 0) game.remove(object, true);
		if (destroy)
		{
			luaObjects.remove(tag);
			if (Std.isOfType(object, FlxSprite)) (cast object:FlxSprite).destroy();
		}
		return true;
	}

	private function addLuaAnimationByPrefix(tag:String, name:String, prefix:String, ?frameRate:Float = 24, ?looped:Bool = true):Dynamic
	{
		var sprite = getLuaSprite(tag);
		if (sprite == null || sprite.frames == null) return psychLuaProfileName() == PsychLuaProfile.PSYCH_063 ? null : false;
		sprite.animation.addByPrefix(name, prefix, frameRate, looped);
		cne.compat.PsychLuaAnimation.playIfNeeded(sprite, name, psychLuaProfileName() != PsychLuaProfile.PSYCH_063);
		return psychLuaProfileName() == PsychLuaProfile.PSYCH_063 ? null : true;
	}

	private function addLuaAnimation(tag:String, name:String, frames:Array<Dynamic>, ?frameRate:Float = 24, ?looped:Bool = true):Dynamic
	{
		var sprite = getLuaSprite(tag);
		if (sprite == null || sprite.frames == null || frames == null) return false;
		var frameIndices:Array<Int> = [for (index in frames) Std.int(Std.parseFloat(Std.string(index)))];
		sprite.animation.add(name, frameIndices, frameRate, looped);
		cne.compat.PsychLuaAnimation.playIfNeeded(sprite, name, psychLuaProfileName() != PsychLuaProfile.PSYCH_063);
		return psychLuaProfileName() == PsychLuaProfile.PSYCH_063 ? null : true;
	}

	private function addLuaAnimationByIndices(tag:String, name:String, prefix:String, indices:Dynamic, ?frameRate:Float = 24, ?looped:Bool = false):Bool
	{
		var sprite = getLuaSprite(tag);
		if (sprite == null || sprite.frames == null) return false;
		var frameIndices:Array<Int> = [];
		if (Std.isOfType(indices, String))
		{
			for (index in (cast indices:String).trim().split(","))
				frameIndices.push(Std.int(Std.parseFloat(index)));
		}
		else if (Std.isOfType(indices, Array))
		{
			for (index in (cast indices:Array<Dynamic>))
				frameIndices.push(Std.int(Std.parseFloat(Std.string(index))));
		}
		else if (indices == null && psychLuaProfileName() != PsychLuaProfile.PSYCH_063)
			frameIndices.push(0);
		else
			return false;
		var effectiveLooped = psychLuaProfileName() == PsychLuaProfile.PSYCH_063 ? false : looped;
		sprite.animation.addByIndices(name, prefix, frameIndices, "", frameRate, effectiveLooped);
		cne.compat.PsychLuaAnimation.playIfNeeded(sprite, name, psychLuaProfileName() != PsychLuaProfile.PSYCH_063);
		return true;
	}

	private function playLuaAnimation(tag:String, animation:String, ?force:Bool = false, ?reverse:Bool = false, ?startFrame:Int = 0):Bool
	{
		var animateController = getLuaAnimateController(tag);
		if (animateController != null)
		{
			var exists = Reflect.field(animateController, "exists");
			var play = Reflect.field(animateController, "play");
			if (exists == null || play == null || !Reflect.callMethod(animateController, exists, [animation])) return false;
			Reflect.callMethod(animateController, play, [animation, force, reverse, startFrame]);
			return true;
		}
		var sprite = getLuaSprite(tag);
		if (sprite == null || !sprite.animation.exists(animation)) return false;
		sprite.animation.play(animation, force, reverse, startFrame);
		return true;
	}

	private function setLuaObjectCamera(tag:String, ?camera:String = "game"):Bool
	{
		var object = getLuaObject(tag);
		if (object == null) return false;
		Reflect.setProperty(object, "cameras", [getLuaCamera(camera)]);
		return true;
	}

	private function getLuaCamera(?camera:String = "game"):Dynamic
	{
		var game = PlayState.instance;
		if (game == null) return FlxG.camera;
		return PsychLuaCamera.resolve(camera, game.camGame, game.camHUD, game.camOther, FlxG.camera);
	}

	private function setLuaScrollFactor(tag:String, x:Float, ?y:Float):Bool
	{
		var object = getLuaObject(tag);
		if (object == null) return false;
		var factor = Reflect.getProperty(object, "scrollFactor");
		if (factor == null) return false;
		Reflect.setProperty(factor, "x", x);
		Reflect.setProperty(factor, "y", y == null ? x : y);
		return true;
	}

	private function scaleLuaObject(tag:String, x:Float, ?y:Float):Bool
	{
		var object = getLuaObject(tag);
		if (object == null) return false;
		var scale = Reflect.getProperty(object, "scale");
		if (scale == null) return false;
		Reflect.setProperty(scale, "x", x);
		Reflect.setProperty(scale, "y", y == null ? x : y);
		if (Reflect.hasField(object, "updateHitbox")) Reflect.callMethod(object, Reflect.field(object, "updateHitbox"), []);
		return true;
	}

	private function setLuaGraphicSize(tag:String, width:Float, ?height:Float = 0, ?updateHitbox:Bool = true):Bool
	{
		var sprite = getLuaSprite(tag);
		if (sprite == null) return false;
		sprite.setGraphicSize(Std.int(width), Std.int(height));
		if (updateHitbox) sprite.updateHitbox();
		return true;
	}

	private function updateLuaHitbox(tag:String):Bool
	{
		var sprite = getLuaSprite(tag);
		if (sprite == null) return false;
		sprite.updateHitbox();
		return true;
	}

	private function centerLuaObject(tag:String, ?axes:String = "xy"):Bool
	{
		var object = getLuaObject(tag);
		if (!Std.isOfType(object, FlxSprite)) return false;
		var mode = axes == null ? "xy" : axes.toLowerCase();
		(cast object:FlxSprite).screenCenter(FlxAxes.fromString(mode));
		return true;
	}

	private function setLuaObjectOrder(tag:String, order:Int):Bool
	{
		var game = PlayState.instance;
		var object = getLuaObject(tag);
		if (game == null || object == null) return false;
		var current = game.members.indexOf(object);
		if (current < 0) return false;
		game.remove(object, false);
		game.insert(Std.int(Math.max(0, Math.min(order, game.members.length))), object);
		return true;
	}

	private function getLuaObjectOrder(tag:String):Int
	{
		var game = PlayState.instance;
		return game == null ? -1 : game.members.indexOf(getLuaObject(tag));
	}

	private function loadLuaGraphic(tag:String, image:String, ?animated:Bool = false, ?frameWidth:Int = 0, ?frameHeight:Int = 0):Bool
	{
		var sprite = getOrCreateLuaSprite(tag);
		sprite.loadGraphic(Paths.image(image), animated, frameWidth, frameHeight);
		return true;
	}

	private function loadLuaFrames(tag:String, image:String, ?spriteType:String = "auto"):Bool
	{
		var sprite = getOrCreateLuaSprite(tag);
		sprite.frames = Paths.getFrames(image);
		return sprite.frames != null;
	}

	private function setLuaTextField(tag:String, field:String, value:Dynamic):Bool
	{
		var object = luaObjects.get(tag);
		if (!Std.isOfType(object, FlxText)) return false;
		Reflect.setProperty(object, field, value);
		return true;
	}

	private function getLuaTextField(tag:String, field:String):Dynamic
	{
		var object = luaObjects.get(tag);
		return Std.isOfType(object, FlxText) ? Reflect.getProperty(object, field) : null;
	}

	private function setLuaTextAlignment(tag:String, ?alignment:String = "left"):Bool
	{
		var object = luaObjects.get(tag);
		if (!Std.isOfType(object, FlxText)) return false;
		var text:FlxText = cast object;
		text.alignment = switch (alignment == null ? "left" : alignment.toLowerCase())
		{
			case "center": FlxTextAlign.CENTER;
			case "right": FlxTextAlign.RIGHT;
			case "justify": FlxTextAlign.JUSTIFY;
			default: FlxTextAlign.LEFT;
		};
		return true;
	}

	private function parseLuaColor(value:Dynamic):FlxColor
	{
		if (value == null) return FlxColor.WHITE;
		if (Std.isOfType(value, Int)) return cast value;
		if (Std.isOfType(value, Float)) return cast Std.int(value);
		var color = StringTools.trim(Std.string(value));
		if (StringTools.startsWith(color, "#")) color = color.substr(1);
		if (StringTools.startsWith(color.toLowerCase(), "0x")) color = color.substr(2);
		if (color.length == 6) color = "FF" + color;
		var parsed = Std.parseInt("0x" + color);
		return parsed == null ? FlxColor.WHITE : cast parsed;
	}

	private function readPsychProperty(path:String):Dynamic
	{
		if (path == null) return null;
		var game = PlayState.instance;

		switch (path)
		{
			case "skipCountdown": return game != null ? game.skipCountdown : false;
			case "health": return game != null ? game.health : 1.0;
			case "defaultCamZoom": return game != null ? game.defaultCamZoom : 1.0;
			case "cameraSpeed": return game != null ? game.cameraSpeed : 1.0;
			case "isCameraOnForcedPos": return game != null ? game.isCameraOnForcedPos : false;
			case "camFollow.x": return game != null && game.camFollow != null ? game.camFollow.x : (FlxG.camera.scroll.x + FlxG.camera.width * 0.5);
			case "camFollow.y": return game != null && game.camFollow != null ? game.camFollow.y : (FlxG.camera.scroll.y + FlxG.camera.height * 0.5);
			case "camFollowPos.x": return game != null && game.camFollowPos != null ? game.camFollowPos.x : (FlxG.camera.scroll.x + FlxG.camera.width * 0.5);
			case "camFollowPos.y": return game != null && game.camFollowPos != null ? game.camFollowPos.y : (FlxG.camera.scroll.y + FlxG.camera.height * 0.5);
			case "camGame.zoom" | "camera.zoom": return FlxG.camera.zoom;
			case "camGame.scroll.x" | "camera.scroll.x": return FlxG.camera.scroll.x;
			case "camGame.scroll.y" | "camera.scroll.y": return FlxG.camera.scroll.y;
			case "curBeat": return Conductor.curBeat;
			case "curStep": return Conductor.curStep;
			case "songPosition": return Conductor.songPosition;
			case "bpm" | "curBpm": return Conductor.bpm;
			case "crochet": return Conductor.crochet;
			case "stepCrochet": return Conductor.stepCrochet;
			case "score": return game != null ? game.songScore : 0;
			case "misses": return game != null ? game.misses : 0;
			case "combo": return game != null ? game.combo : 0;
			case "downscroll": return game != null ? game.downscroll : false;
			case "mustHitSection": return game != null ? (game.curCameraTarget != 0) : false;
			case "gfSection": return false;
			case "opponentCameraOffset[0]": return PsychLuaPropertyPath.cameraOffsets.get("opponentCameraOffset")[0];
			case "opponentCameraOffset[1]": return PsychLuaPropertyPath.cameraOffsets.get("opponentCameraOffset")[1];
			case "boyfriendCameraOffset[0]": return PsychLuaPropertyPath.cameraOffsets.get("boyfriendCameraOffset")[0];
			case "boyfriendCameraOffset[1]": return PsychLuaPropertyPath.cameraOffsets.get("boyfriendCameraOffset")[1];
			case "girlfriendCameraOffset[0]": return PsychLuaPropertyPath.cameraOffsets.get("girlfriendCameraOffset")[0];
			case "girlfriendCameraOffset[1]": return PsychLuaPropertyPath.cameraOffsets.get("girlfriendCameraOffset")[1];
			case "opponentCameraOffset": return PsychLuaPropertyPath.cameraOffsets.get("opponentCameraOffset");
			case "boyfriendCameraOffset": return PsychLuaPropertyPath.cameraOffsets.get("boyfriendCameraOffset");
			case "girlfriendCameraOffset": return PsychLuaPropertyPath.cameraOffsets.get("girlfriendCameraOffset");
			case "dad.cameraPosition[0]":
				var c = getCharacter("dad");
				return c != null && c.cameraOffset != null ? c.cameraOffset.x : 0.0;
			case "dad.cameraPosition[1]":
				var c = getCharacter("dad");
				return c != null && c.cameraOffset != null ? c.cameraOffset.y : 0.0;
			case "boyfriend.cameraPosition[0]":
				var c = getCharacter("boyfriend");
				return c != null && c.cameraOffset != null ? c.cameraOffset.x : 0.0;
			case "boyfriend.cameraPosition[1]":
				var c = getCharacter("boyfriend");
				return c != null && c.cameraOffset != null ? c.cameraOffset.y : 0.0;
			case "gf.cameraPosition[0]":
				var c = getCharacter("gf");
				return c != null && c.cameraOffset != null ? c.cameraOffset.x : 0.0;
			case "gf.cameraPosition[1]":
				var c = getCharacter("gf");
				return c != null && c.cameraOffset != null ? c.cameraOffset.y : 0.0;
		}

		if (psychVariables.exists(path)) return psychVariables.get(path);
		if (game != null && game.variables != null && game.variables.exists(path)) return game.variables.get(path);

		var normalized = StringTools.replace(path, "[", ".");
		var rootName = normalized.split(".")[0];
		var root:Dynamic = luaObjects.get(rootName);
		if (root == null) root = stageLuaObjects.get(PsychLuaObjectRegistry.normalizeTag(rootName));
		if (root == null && ["notes", "unspawnNotes", "strumLineNotes", "playerStrums", "opponentStrums", "eventNotes"].contains(rootName))
			root = getPsychGroupMembers(rootName);
		else if (root == null && game != null)
		{
			root = switch (rootName)
			{
				case "camGame" | "camera": game.camGame;
				case "camHUD": game.camHUD;
				case "camOther": game.camOther;
				case "camFollow": game.camFollow;
				case "camFollowPos": game.camFollowPos;
				case "iconP1": game.iconP1;
				case "iconP2": game.iconP2;
				case "healthBar": game.healthBar;
				case "healthBarBG": game.healthBarBG;
				case "scoreTxt": game.scoreTxt;
				default: getCharacter(rootName);
			};
		}
		var targetPath = path;
		if (root != null && normalized.indexOf(".") >= 0 && rootName == normalized.substr(0, rootName.length))
		{
			var dotIdx = path.indexOf(".");
			if (dotIdx >= 0) targetPath = path.substr(dotIdx + 1);
		}

		if (root != null)
		{
			if (Std.isOfType(root, FlxCamera))
			{
				var cam:FlxCamera = cast root;
				switch (targetPath)
				{
					case "x": return cam.x;
					case "y": return cam.y;
					case "width": return cam.width;
					case "height": return cam.height;
					case "zoom": return cam.zoom;
					case "alpha": return cam.alpha;
					case "angle": return cam.angle;
					case "visible": return cam.visible;
					case "bgColor": return cam.bgColor;
				}
			}
			if (Std.isOfType(root, FlxObject))
			{
				var obj:FlxObject = cast root;
				switch (targetPath)
				{
					case "x": return obj.x;
					case "y": return obj.y;
					case "width": return obj.width;
					case "height": return obj.height;
					case "visible": return obj.visible;
					case "alpha" if (Std.isOfType(root, FlxSprite)): return (cast root:FlxSprite).alpha;
					case "angle" if (Std.isOfType(root, FlxSprite)): return (cast root:FlxSprite).angle;
				}
			}
		}

		return PsychLuaPropertyPath.read(root != null ? root : PlayState.instance, targetPath);
	}

	private function psychLuaProfileName():String
	{
		return ModsFolder.currentPsychLuaProfile == null ? PsychLuaProfile.UNSPECIFIED : ModsFolder.currentPsychLuaProfile.profile;
	}

	private function setPsychProperty(path:String, value:Dynamic):Dynamic
	{
		writePsychProperty(path, value);
		return switch (psychLuaProfileName())
		{
			case PsychLuaProfile.PSYCH_063: true;
			case PsychLuaProfile.PSYCH_104: value;
			default:
				// These DBE camera aliases already translate to camera.scroll.
				// Returning null here makes Lua `a or b` fall through and write the
				// same position again as raw scroll, accumulating a viewport offset.
				(path == "camFollowPos.x" || path == "camFollowPos.y") ? value : null;
		};
	}

	private function setPsychPropertyFromClass(className:String, path:String, value:Dynamic):Dynamic
	{
		writePath(resolveClass(className), path, value);
		return switch (psychLuaProfileName())
		{
			case PsychLuaProfile.PSYCH_063: true;
			case PsychLuaProfile.PSYCH_104: value;
			default: null;
		};
	}

	private function setPsychPropertyFromGroup(groupName:String, index:Float, path:String, value:Dynamic):Dynamic
	{
		writePath(getGroupMember(groupName, Std.int(index)), path, value);
		return psychLuaProfileName() == PsychLuaProfile.PSYCH_104 ? value : null;
	}

	private function setPsychLuaSpriteProperty(tag:String, property:String, value:Dynamic):Bool
	{
		var object = getLuaObject(tag);
		if (object == null) return false;
		PsychLuaPropertyPath.write(object, property, value);
		return true;
	}

	private function removePsychObjectFromGroup(groupName:String, ?index:Int = -1, ?tagOrDontDestroy:Dynamic = null, ?destroy:Dynamic = null):Dynamic
	{
		if (psychLuaProfileName() == PsychLuaProfile.PSYCH_063)
		{
			removeLegacyPsychGroupMember(groupName, index, tagOrDontDestroy == true);
			return null;
		}

		var tag:String = tagOrDontDestroy == null || Std.isOfType(tagOrDontDestroy, Bool) ? null : Std.string(tagOrDontDestroy);
		var shouldDestroy = destroy == null ? true : destroy == true;
		removeLuaObjectFromGroup(groupName, index, tag, shouldDestroy);
		return null;
	}

	private function removeLegacyPsychGroupMember(groupName:String, index:Int, dontDestroy:Bool):Void
	{
		var group = getLuaGroup(groupName);
		var members:Dynamic = getLuaGroupMembers(group);
		if (!Std.isOfType(members, Array)) return;
		var list:Array<Dynamic> = cast members;
		if (index < 0 || index >= list.length) return;
		var object = list[index];
		if (object == null) return;

		if (Std.isOfType(group, Array))
			list.remove(object);
		else
		{
			if (!dontDestroy)
			{
				var kill = Reflect.field(object, "kill");
				if (kill != null) Reflect.callMethod(object, kill, []);
			}
			var remove = Reflect.field(group, "remove");
			if (remove == null) return;
			Reflect.callMethod(group, remove, [object, true]);
			if (!dontDestroy)
			{
				var dispose = Reflect.field(object, "destroy");
				if (dispose != null) Reflect.callMethod(object, dispose, []);
			}
		}
	}

	private function writePsychProperty(path:String, value:Dynamic):Dynamic
	{
		if (path == null) return null;
		var game = PlayState.instance;

		switch (path)
		{
			case "skipCountdown":
				var b = value == true || value == 1 || value == "true";
				if (game != null) game.skipCountdown = b;
				psychVariables.set(path, b);
				if (game != null && game.variables != null) game.variables.set(path, b);
				return value;
			case "health":
				if (game != null) game.health = Std.parseFloat(Std.string(value));
				return value;
			case "defaultCamZoom":
				if (game != null) game.defaultCamZoom = Std.parseFloat(Std.string(value));
				return value;
			case "camFollow.x":
				var v = Std.parseFloat(Std.string(value));
				if (!Math.isNaN(v) && game != null && game.camFollow != null) game.camFollow.x = v;
				return value;
			case "camFollow.y":
				var v = Std.parseFloat(Std.string(value));
				if (!Math.isNaN(v) && game != null && game.camFollow != null) game.camFollow.y = v;
				return value;
			case "camFollowPos.x":
				var v = Std.parseFloat(Std.string(value));
				if (!Math.isNaN(v)) {
					if (game != null && game.camFollowPos != null) game.camFollowPos.x = v;
					FlxG.camera.scroll.x = v - FlxG.camera.width * 0.5;
				}
				return value;
			case "camFollowPos.y":
				var v = Std.parseFloat(Std.string(value));
				if (!Math.isNaN(v)) {
					if (game != null && game.camFollowPos != null) game.camFollowPos.y = v;
					FlxG.camera.scroll.y = v - FlxG.camera.height * 0.5;
				}
				return value;
			case "cameraSpeed":
				var v = Std.parseFloat(Std.string(value));
				if (!Math.isNaN(v) && game != null) game.cameraSpeed = v;
				return value;
			case "isCameraOnForcedPos":
				var forced = value == true || value == 1 || Std.string(value).toLowerCase() == "true";
				if (game != null) game.isCameraOnForcedPos = forced;
				psychVariables.set(path, forced);
				if (game != null && game.variables != null) game.variables.set(path, forced);
				return value;
			case "camGame.zoom" | "camera.zoom":
				var v = Std.parseFloat(Std.string(value));
				if (!Math.isNaN(v)) FlxG.camera.zoom = v;
				return value;
			case "camGame.scroll.x" | "camera.scroll.x":
				var v = Std.parseFloat(Std.string(value));
				if (!Math.isNaN(v)) FlxG.camera.scroll.x = v;
				return value;
			case "camGame.scroll.y" | "camera.scroll.y":
				var v = Std.parseFloat(Std.string(value));
				if (!Math.isNaN(v)) FlxG.camera.scroll.y = v;
				return value;
			case "opponentCameraOffset[0]":
				PsychLuaPropertyPath.cameraOffsets.get("opponentCameraOffset")[0] = Std.parseFloat(Std.string(value));
				return value;
			case "opponentCameraOffset[1]":
				PsychLuaPropertyPath.cameraOffsets.get("opponentCameraOffset")[1] = Std.parseFloat(Std.string(value));
				return value;
			case "boyfriendCameraOffset[0]":
				PsychLuaPropertyPath.cameraOffsets.get("boyfriendCameraOffset")[0] = Std.parseFloat(Std.string(value));
				return value;
			case "boyfriendCameraOffset[1]":
				PsychLuaPropertyPath.cameraOffsets.get("boyfriendCameraOffset")[1] = Std.parseFloat(Std.string(value));
				return value;
			case "girlfriendCameraOffset[0]":
				PsychLuaPropertyPath.cameraOffsets.get("girlfriendCameraOffset")[0] = Std.parseFloat(Std.string(value));
				return value;
			case "girlfriendCameraOffset[1]":
				PsychLuaPropertyPath.cameraOffsets.get("girlfriendCameraOffset")[1] = Std.parseFloat(Std.string(value));
				return value;
			case "dad.cameraPosition[0]":
				var c = getCharacter("dad");
				if (c != null && c.cameraOffset != null) c.cameraOffset.x = Std.parseFloat(Std.string(value));
				return value;
			case "dad.cameraPosition[1]":
				var c = getCharacter("dad");
				if (c != null && c.cameraOffset != null) c.cameraOffset.y = Std.parseFloat(Std.string(value));
				return value;
			case "boyfriend.cameraPosition[0]":
				var c = getCharacter("boyfriend");
				if (c != null && c.cameraOffset != null) c.cameraOffset.x = Std.parseFloat(Std.string(value));
				return value;
			case "boyfriend.cameraPosition[1]":
				var c = getCharacter("boyfriend");
				if (c != null && c.cameraOffset != null) c.cameraOffset.y = Std.parseFloat(Std.string(value));
				return value;
		}

		if (psychVariables.exists(path))
		{
			psychVariables.set(path, value);
			return value;
		}

		var normalized = StringTools.replace(path, "[", ".");
		var rootName = normalized.split(".")[0];
		var root:Dynamic = luaObjects.get(rootName);
		if (root == null) root = stageLuaObjects.get(PsychLuaObjectRegistry.normalizeTag(rootName));
		if (root == null && ["notes", "unspawnNotes", "strumLineNotes", "playerStrums", "opponentStrums"].contains(rootName))
			root = getPsychGroupMembers(rootName);
		else if (root == null && game != null)
		{
			root = switch (rootName)
			{
				case "camGame" | "camera": game.camGame;
				case "camHUD": game.camHUD;
				case "camOther": game.camOther;
				case "camFollow": game.camFollow;
				case "camFollowPos": game.camFollowPos;
				case "iconP1": game.iconP1;
				case "iconP2": game.iconP2;
				case "healthBar": game.healthBar;
				case "healthBarBG": game.healthBarBG;
				case "scoreTxt": game.scoreTxt;
				default: getCharacter(rootName);
			};
		}
		var targetPath = path;
		if (root != null && normalized.indexOf(".") >= 0 && rootName == normalized.substr(0, rootName.length))
		{
			var dotIdx = path.indexOf(".");
			if (dotIdx >= 0) targetPath = path.substr(dotIdx + 1);
		}

		if (root != null)
		{
			if (Std.isOfType(root, FlxCamera))
			{
				var cam:FlxCamera = cast root;
				switch (targetPath)
				{
					case "x": cam.x = Std.parseFloat(Std.string(value)); return value;
					case "y": cam.y = Std.parseFloat(Std.string(value)); return value;
					case "width": cam.width = Std.int(Std.parseFloat(Std.string(value))); return value;
					case "height": cam.height = Std.int(Std.parseFloat(Std.string(value))); return value;
					case "zoom": cam.zoom = Std.parseFloat(Std.string(value)); return value;
					case "alpha": cam.alpha = Std.parseFloat(Std.string(value)); return value;
					case "angle": cam.angle = Std.parseFloat(Std.string(value)); return value;
					case "visible": cam.visible = value == true; return value;
					case "bgColor":
						cam.bgColor = Std.isOfType(value, Int) ? cast value : parseLuaColor(value);
						return value;
				}
			}
			if (Std.isOfType(root, FlxObject))
			{
				var obj:FlxObject = cast root;
				switch (targetPath)
				{
					case "x": obj.x = Std.parseFloat(Std.string(value)); return value;
					case "y": obj.y = Std.parseFloat(Std.string(value)); return value;
					case "visible": obj.visible = value == true; return value;
					case "alpha" if (Std.isOfType(root, FlxSprite)): (cast root:FlxSprite).alpha = Std.parseFloat(Std.string(value)); return value;
					case "angle" if (Std.isOfType(root, FlxSprite)): (cast root:FlxSprite).angle = Std.parseFloat(Std.string(value)); return value;
				}
			}
		}
		try
		{
			var res = PsychLuaPropertyPath.write(root != null ? root : PlayState.instance, targetPath, value);
			if (res != null) return res;
		}
		catch (_:Dynamic) {}

		if (targetPath.indexOf(".") < 0 && targetPath.indexOf("[") < 0)
		{
			psychVariables.set(targetPath, value);
			if (game != null && game.variables != null) game.variables.set(targetPath, value);
		}
		return value;
	}

	private function setNumberConstant(name:String, value:Float):Void
	{
		Lua.pushnumber(lua, value);
		Lua.setglobal(lua, name);
	}

	private function printValues(values:Array<Dynamic>):Void
	{
		var output:Array<String> = [];
		for (value in values)
			if (value != null) output.push(Std.string(value));
		if (output.length > 0) trace(output.join("\t"));
	}

	private function resolveClass(className:String):Dynamic
	{
		if (className == null) return null;
		return switch (className)
		{
			case "PlayState": PlayState;
			case "FlxG" | "flixel.FlxG": FlxG;
			case "Conductor" | "backend.Conductor": Conductor;
			case "Paths" | "backend.Paths": Paths;
			case "ClientPrefs" | "backend.ClientPrefs": Options;
			default: Type.resolveClass(className);
		}
	}

	private function getCharacter(characterName:String):Character
	{
		var game = PlayState.instance;
		if (game == null || characterName == null) return null;
		return switch (StringTools.trim(characterName).toLowerCase())
		{
			case "boyfriend" | "bf" | "player": game.boyfriend;
			case "dad" | "opponent": game.dad;
			case "gf" | "girlfriend": game.gf;
			default: cast readPath(game, characterName);
		}
	}

	private function getGroupMember(groupName:String, index:Int):Dynamic
	{
		if (index < 0) return null;
		var list = getPsychGroupMembers(groupName);
		if (list == null) return null;
		return index < list.length ? list[index] : null;
	}

	private function getPsychChartEventNotes():Array<Dynamic>
	{
		var chart = PlayState.SONG;
		if (chart == null || chart.events == null) return [];

		var eventNotes:Array<Dynamic> = [];
		for (event in chart.events)
		{
			if (event == null) continue;
			var params = event.params == null ? [] : event.params;
			eventNotes.push({
				strumTime: event.time,
				event: event.name,
				value1: params.length > 0 && params[0] != null ? params[0] : "",
				value2: params.length > 1 && params[1] != null ? params[1] : ""
			});
		}
		return eventNotes;
	}

	private function getPsychGroupMembers(groupName:String):Array<Dynamic>
	{
		var game = PlayState.instance;
		if (game == null || groupName == null) return null;
		switch (groupName)
		{
			case "eventNotes":
				return getPsychChartEventNotes();
			case "notes" | "unspawnNotes":
				var notesByStrumline:Array<Array<Dynamic>> = [];
				for (line in game.strumLines.members)
				{
					if (line == null || line.notes == null || line.notes.members == null) continue;
					var lineNotes:Array<Dynamic> = [];
					for (note in line.notes.members)
					{
						if (note == null || !note.exists || !note.alive) continue;
						var noteSpeed:Float = 1;
						var sourceNoteSpeed:Dynamic = Reflect.field(note, "multSpeed");
						if (Std.isOfType(sourceNoteSpeed, Int) || Std.isOfType(sourceNoteSpeed, Float)) noteSpeed = cast sourceNoteSpeed;
						var songSpeed:Float = game.scrollSpeed <= 0 ? 1 : game.scrollSpeed;
						var spawned = PsychHookMap.isPsychNoteSpawned(note.strumTime, Conductor.songPosition, songSpeed, noteSpeed);
						if ((groupName == "notes") == spawned) lineNotes.push(note);
					}
					notesByStrumline.push(lineNotes);
				}
				return PsychHookMap.combinePsychNotes(notesByStrumline, groupName == "notes");
			case "strumLineNotes" | "playerStrums" | "opponentStrums":
				var strums:Array<Dynamic> = [];
				for (line in game.strumLines.members)
				{
					if (line == null || line.members == null) continue;
					var isOpponent = line.opponentSide;
					if (groupName == "playerStrums" && isOpponent) continue;
					if (groupName == "opponentStrums" && !isOpponent) continue;
					for (strum in line.members) if (strum != null) strums.push(strum);
				}
				return strums;
			default:
				var group = readPath(game, groupName);
				if (group == null) return null;
				var members:Dynamic = Std.isOfType(group, Array) ? group : Reflect.getProperty(group, "members");
				return Std.isOfType(members, Array) ? cast members : null;
		}
	}

	private function readPath(root:Dynamic, path:String):Dynamic
	{
		return PsychLuaPropertyPath.read(root, path);
	}

	private function writePath(root:Dynamic, path:String, newValue:Dynamic):Dynamic
	{
		return PsychLuaPropertyPath.write(root, path, newValue);
	}

	public override function onLoad():Void
	{
		if (lua == null || scriptClosed) return;
		updatePsychGlobals();
		var code = hasSourceOverride ? sourceOverride : (Assets.exists(rawLuaPath) ? Assets.getText(rawLuaPath) : null);
		if (code == null)
		{
			error('Could not read Lua source at "${path}".');
			return;
		}

		if (code.length > 0)
		{
			var status = LuaL.dostring(lua, code);
			if (status != Lua.LUA_OK)
			{
				var message = Lua.tostring(lua, -1);
				Lua.settop(lua, 0);
				error('Lua load error: ${message}');
				return;
			}
			Lua.settop(lua, 0);
		}

		#if GLOBAL_SCRIPT
		GlobalScript.call("onScriptSetup", [this, "lua"]);
		#end
	}

	private override function onCall(funcName:String, parameters:Array<Dynamic>):Dynamic
	{
		if (lua == null || scriptClosed) return null;
		updatePsychGlobals();
		if (funcName == "update") dispatchPsychSpawnCallbacks();
		var args = parameters == null ? [] : parameters;
		if ((funcName == "onScriptCreated" || funcName == "onScriptSetup") && args.length > 0 && Std.isOfType(args[0], Script))
		{
			var sourceScript:Script = cast args[0];
			args = args.copy();
			args[0] = {
				fileName: sourceScript.fileName,
				path: sourceScript.path,
				active: sourceScript.active
			};
		}
		if (funcName == "onPlayerHit" || funcName == "onDadHit")
		{
			var psychArgs = getPsychHitArgs(args);
			if (psychArgs == null) return null;
			var hitResult = callLua(PsychHookMap.getHooks(funcName)[0], psychArgs);
			applyPsychStop(args, hitResult);
			return hitResult;
		}
		if (funcName == "onPlayerMiss")
		{
			var missResult = callPsychMiss(args);
			applyPsychStop(args, missResult);
			return missResult;
		}

		switch (funcName)
		{
			case "onStartCountdown": return callPsychCancellable(args, "onStartCountdown");
			case "onSongEnd": return callPsychCancellable(args, "onEndSong");
			case "onGamePause": return callPsychCancellable(args, "onPause");
			case "onGameOver": return callPsychCancellable(args, "onGameOver");
			case "onEvent": return callPsychChartEvent(args);
			case "eventEarlyTrigger": return callPsychEventEarlyTrigger(args);
			case "onCountdown": return callPsychCountdown(args);
			case "onCameraMove": return callPsychCameraMove(args);
			case "onInputUpdate": return callPsychInput(args, false);
			case "onPostInputUpdate": return callPsychInput(args, true);
		}

		var result:Dynamic = null;
		for (hook in PsychHookMap.getHooks(funcName))
		{
			var hookResult = callLua(hook, args);
			if (hookResult != null) result = hookResult;
		}
		return result;
	}

	private function callPsychCancellable(args:Array<Dynamic>, hook:String):Dynamic
	{
		var result = callLua(hook, []);
		applyPsychStop(args, result);
		return result;
	}

	private function applyPsychStop(args:Array<Dynamic>, result:Dynamic):Void
	{
		if (args == null || args.length == 0 || !Std.isOfType(args[0], CancellableEvent)) return;
		var profile = psychLuaProfileName();
		if (!PsychCallbackResult.includeResult(result, PsychCallbackResult.defaultExcludeValues(profile))) return;
		var event:CancellableEvent = cast args[0];
		if (event.psychLuaCancelled) event.cancelled = false;
		event.psychLuaCancelled = false;
		if (result == PsychCallbackResult.stopValueForProfile(profile))
		{
			event.preventDefault(true);
			event.psychLuaCancelled = true;
		}
	}

	private function callPsychChartEvent(args:Array<Dynamic>):Dynamic
	{
		if (args == null || args.length == 0 || !Std.isOfType(args[0], EventGameEvent)) return null;
		var event:EventGameEvent = cast args[0];
		if (event.event == null) return null;
		var params = event.event.params == null ? [] : event.event.params;
		var value1:Dynamic = params.length > 0 && params[0] != null ? params[0] : "";
		var value2:Dynamic = params.length > 1 && params[1] != null ? params[1] : "";
		var normalizedPath = StringTools.replace(rawLuaPath, "\\", "/").toLowerCase();
		if (event.event.name == "BlackFlash" && StringTools.endsWith(normalizedPath, "/custom_events/blackflash.lua"))
			trace('Psych BlackFlash callback: script=$rawLuaPath, v1=$value1, v2=$value2');
		return callLua("onEvent", PsychHookMap.makeEventArguments(psychLuaProfileName(), event.event.name, value1, value2, event.event.time));
	}

	private function callPsychEventEarlyTrigger(args:Array<Dynamic>):Dynamic
	{
		if (args == null || args.length == 0) return null;
		var name:String = cast args[0];
		var value1:Dynamic = args.length > 1 ? args[1] : null;
		var value2:Dynamic = args.length > 2 ? args[2] : null;
		var chartTime:Float = args.length > 3 && (Std.isOfType(args[3], Int) || Std.isOfType(args[3], Float)) ? cast args[3] : 0;
		return callLua("eventEarlyTrigger", PsychHookMap.makeEventEarlyTriggerArguments(psychLuaProfileName(), name, value1, value2, chartTime));
	}

	private function callPsychCountdown(args:Array<Dynamic>):Dynamic
	{
		if (args == null || args.length == 0 || !Std.isOfType(args[0], CountdownEvent)) return null;
		var event:CountdownEvent = cast args[0];
		return callLua("onCountdownTick", [event.swagCounter]);
	}

	private function callPsychCameraMove(args:Array<Dynamic>):Dynamic
	{
		if (args == null || args.length == 0 || !Std.isOfType(args[0], CamMoveEvent)) return null;
		var event:CamMoveEvent = cast args[0];
		if (event.strumLine == null || event.strumLine.data == null) return null;
		var target = switch (Std.int(event.strumLine.data.type))
		{
			case 0: "dad";
			case 1: "boyfriend";
			case 2: "gf";
			default: "dad";
		};
		return callLua("onMoveCamera", [target]);
	}

	private function callPsychInput(args:Array<Dynamic>, postUpdate:Bool):Dynamic
	{
		if (args == null || args.length == 0 || !Std.isOfType(args[0], InputSystemEvent)) return null;
		var profile = psychLuaProfileName();
		// Psych 0.6.3 exposes only post-input key callbacks; pre-input cancellation starts in 1.0.4.
		if (!postUpdate && profile == PsychLuaProfile.PSYCH_063) return null;
		var event:InputSystemEvent = cast args[0];
		if (event.strumLine == null || event.strumLine.cpu) return null;
		var stopValue = PsychCallbackResult.stopValueForProfile(profile);
		var continueValues = PsychCallbackResult.defaultExcludeValues(profile);
		var laneCount = event.strumLine.members == null ? 0 : event.strumLine.members.length;
		var blockedAnyLane = false;
		for (lane in 0...laneCount)
		{
			if (event.justPressed != null && lane < event.justPressed.length && event.justPressed[lane])
			{
				if (postUpdate) callLua("onKeyPress", [lane]);
				else
				{
					var result = callLua("onKeyPressPre", [lane]);
					if (result == stopValue)
						blockedAnyLane = PsychHookMap.blockInputLane(event.psychBlockedPress, event.psychBlockedRelease, lane, true) || blockedAnyLane;
					else if (PsychCallbackResult.includeResult(result, continueValues) && event.psychBlockedPress != null && lane < event.psychBlockedPress.length)
						event.psychBlockedPress[lane] = false;
				}
			}
			if (event.justReleased != null && lane < event.justReleased.length && event.justReleased[lane])
			{
				if (postUpdate) callLua("onKeyRelease", [lane]);
				else
				{
					var result = callLua("onKeyReleasePre", [lane]);
					if (result == stopValue)
						blockedAnyLane = PsychHookMap.blockInputLane(event.psychBlockedPress, event.psychBlockedRelease, lane, false) || blockedAnyLane;
					else if (PsychCallbackResult.includeResult(result, continueValues) && event.psychBlockedRelease != null && lane < event.psychBlockedRelease.length)
						event.psychBlockedRelease[lane] = false;
				}
			}
		}
		return blockedAnyLane ? stopValue : null;
	}

	private function dispatchPsychSpawnCallbacks():Void
	{
		var spawned = getPsychGroupMembers("notes");
		for (note in PsychHookMap.collectNewlySpawnedNotes(spawnedPsychNotes, spawned))
		{
			var noteType:String = note.noteType == null ? "" : note.noteType;
			callLua("onSpawnNote", PsychHookMap.makeSpawnNoteArguments(psychLuaProfileName(), PsychHookMap.indexOfNote(spawned, note), note.noteData, noteType, note.isSustainNote, note.strumTime));
		}
	}

	private function callLua(functionName:String, args:Array<Dynamic>):Dynamic
	{
		if (lua == null || scriptClosed) return null;
		syncPsychStrumY();
		var originalTop = Lua.gettop(lua);
		Lua.getglobal(lua, functionName);
		if (Lua.isfunction(lua, -1) == 0)
		{
			Lua.settop(lua, originalTop);
			return null;
		}

		for (index in 0...args.length)
		{
			var argument = args[index];
			var unsupportedPath = findUnsupportedLuaValue(argument, 'arg[${index + 1}]', 0, new ObjectMap<Dynamic, Bool>());
			if (unsupportedPath != null)
			{
				Lua.settop(lua, originalTop);
				if (!unsupportedHooks.exists(functionName))
				{
					unsupportedHooks.set(functionName, true);
					error('Lua callback "${functionName}" was skipped: unsupported Haxe value at ${unsupportedPath}.');
				}
				return null;
			}
			if (!Convert.toLua(lua, argument))
			{
				Lua.settop(lua, originalTop);
				if (!unsupportedHooks.exists(functionName))
				{
					unsupportedHooks.set(functionName, true);
					error('Lua callback "${functionName}" was skipped because this event contains values the adapter does not map yet.');
				}
				return null;
			}
		}

		var status = Lua.pcall(lua, args.length, 1, 0);
		if (status != Lua.LUA_OK)
		{
			var message = Lua.tostring(lua, -1);
			Lua.settop(lua, originalTop);
			error('Lua callback ${functionName} failed: ${message}');
			return null;
		}

		var result = Convert.fromLua(lua, -1);
		Lua.settop(lua, originalTop);
		return result;
	}

	private function syncPsychStrumY():Void
	{
		var game = PlayState.instance;
		if (game == null || game.strumLines == null) return;

		// Some older Psych custom events use StrumY as a global base position.
		// Keep a value explicitly supplied by a script, but fill the missing
		// compatibility global from the first generated receptor when available.
		Lua.getglobal(lua, "StrumY");
		var hasScriptValue = Lua.type(lua, -1) != Lua.LUA_TNIL;
		Lua.pop(lua, 1);
		if (hasScriptValue) return;

		for (line in game.strumLines.members)
		{
			if (line == null || line.members == null) continue;
			for (strum in line.members)
				if (strum != null)
				{
					setNumberConstant("StrumY", strum.y);
					return;
				}
		}
	}

	private function findUnsupportedLuaValue(value:Dynamic, path:String, depth:Int, seen:ObjectMap<Dynamic, Bool>):String
	{
		if (depth > 32) return '${path} (maximum nesting depth exceeded)';

		return switch (Type.typeof(value))
		{
			case TNull | TBool | TInt | TFloat | TClass(String): null;
			case TClass(Array):
				if (seen.exists(value)) null;
				else
				{
					seen.set(value, true);
					var unsupported:String = null;
					var items:Array<Dynamic> = cast value;
					for (index in 0...items.length)
					{
						unsupported = findUnsupportedLuaValue(items[index], '${path}[${index + 1}]', depth + 1, seen);
						if (unsupported != null) break;
					}
					unsupported;
				}
			case TClass(haxe.ds.StringMap):
				if (seen.exists(value)) null;
				else
				{
					seen.set(value, true);
					var unsupported:String = null;
					var items:haxe.ds.StringMap<Dynamic> = cast value;
					for (key => item in items)
					{
						unsupported = findUnsupportedLuaValue(item, '${path}["${key}"]', depth + 1, seen);
						if (unsupported != null) break;
					}
					unsupported;
				}
			case TObject:
				if (seen.exists(value)) null;
				else
				{
					seen.set(value, true);
					var unsupported:String = null;
					for (field in Reflect.fields(value))
					{
						unsupported = findUnsupportedLuaValue(Reflect.field(value, field), '${path}.${field}', depth + 1, seen);
						if (unsupported != null) break;
					}
					unsupported;
				}
			default: '${path} (${Type.typeof(value)})';
		};
	}

	private function getPsychHitArgs(args:Array<Dynamic>):Array<Dynamic>
	{
		if (args.length == 0 || !Std.isOfType(args[0], NoteHitEvent)) return null;
		var event:NoteHitEvent = cast args[0];
		if (event.note == null) return null;
		var noteIndex = PsychHookMap.indexOfNote(getPsychGroupMembers("notes"), event.note);
		return PsychHookMap.makeNoteHitArguments(noteIndex, PsychHookMap.noteDirectionForHit(event.note.noteData), event.noteType, event.note.isSustainNote);
	}

	private function callPsychMiss(args:Array<Dynamic>):Dynamic
	{
		if (args.length == 0 || !Std.isOfType(args[0], NoteMissEvent)) return null;
		var event:NoteMissEvent = cast args[0];
		if (event.ghostMiss || event.note == null)
			return callLua("noteMissPress", [event.direction]);
		var noteIndex = PsychHookMap.indexOfNote(getPsychGroupMembers("notes"), event.note);
		return callLua("noteMiss", PsychHookMap.makeNoteMissArguments(noteIndex, event.note.noteData, event.noteType, event.note.isSustainNote));
	}

	public override function get(variable:String):Dynamic
	{
		if (lua == null || variable == null) return null;
		Lua.getglobal(lua, variable);
		var value = Convert.fromLua(lua, -1);
		Lua.pop(lua, 1);
		return value;
	}

	public override function set(variable:String, value:Dynamic):Void
	{
		if (lua == null || variable == null) return;
		var unsupportedPath = findUnsupportedLuaValue(value, variable, 0, new ObjectMap<Dynamic, Bool>());
		if (unsupportedPath != null)
		{
			error('Lua global "${variable}" was not set: unsupported Haxe value at ${unsupportedPath}.');
			return;
		}
		var originalTop = Lua.gettop(lua);
		if (Convert.toLua(lua, value)) Lua.setglobal(lua, variable);
		else Lua.settop(lua, originalTop);
	}

	public override function destroy():Void
	{
		var game = PlayState.instance;
		if (luaHScript != null)
		{
			if (game != null && game.scripts != null) game.scripts.remove(luaHScript);
			luaHScript.destroy();
			luaHScript = null;
		}
		for (tag in luaTimers.keys()) cancelLuaTimer(tag);
		for (tag in luaTweens.keys()) cancelLuaTween(tag);
		for (tag in luaSounds.keys()) stopLuaSound(tag);
		if (callbackScope != null)
		{
			callbackScope.dispose();
			callbackScope = null;
		}
		if (lua != null)
		{
			Lua.close(lua);
			lua = null;
		}
		super.destroy();
	}
}
#end
