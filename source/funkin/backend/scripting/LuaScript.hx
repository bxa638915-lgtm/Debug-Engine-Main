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

	public static function setPsychVariable(name:String, value:Dynamic):Void {
		psychVariables.set(name, value);
	}
	public static function getPsychVariable(name:String):Dynamic {
		return psychVariables.get(name);
	}
	public static function removePsychVariable(name:String):Bool {
		return psychVariables.remove(name);
	}
	private static var globalCallbacks:Map<String, Dynamic> = [];
	public static function registerGlobalCallback(name:String, func:Dynamic):Void {
		if (name == null || func == null) return;
		globalCallbacks.set(name, func);
		var game = PlayState.instance;
		if (game != null && game.scripts != null) {
			for (script in game.scripts.scripts) {
				if (Std.isOfType(script, LuaScript)) {
					var ls:LuaScript = cast script;
					if (ls.callbackScope != null)
						ls.callbackScope.bind(name, func);
				}
			}
		}
	}
	public static function resolveSharedLuaObject(tag:String):Dynamic {
		if (tag == null) return null;
		var obj = luaObjects.get(tag);
		if (obj != null) return obj;
		var game = PlayState.instance;
		if (game != null) {
			if (game.stage != null && game.stage.stageSprites != null) {
				var norm = PsychLuaObjectRegistry.normalizeTag(tag);
				for (k => spr in game.stage.stageSprites) {
					if (k != null && spr != null && (k == tag || PsychLuaObjectRegistry.normalizeTag(k) == norm))
						return spr;
				}
			}
			if (game.variables != null && game.variables.exists(tag))
				return game.variables.get(tag);
			if (game.scripts != null) {
				for (script in game.scripts.scripts) {
					if (Std.isOfType(script, LuaScript)) {
						var found = (cast script:LuaScript).getLuaObject(tag);
						if (found != null) return found;
					}
				}
			}
		}
		return null;
	}
	private static var luaSaves:Map<String, FlxSave> = [];
	private static var luaShaders:Map<String, Dynamic> = [];
	private static var luaModSettings:Map<String, Map<String, Dynamic>> = [];
	private static var psychTranslationCache:Map<String, Map<String, String>> = [];
	private static var luaHealthBarColors:ObjectMap<flixel.ui.FlxBar, Array<FlxColor>> = new ObjectMap();
	private static var sharedObjectCleanupRegistered:Bool = false;
	public static var currentDispatchStep:Int = -1;
	public static var currentDispatchBeat:Int = -1;
	public static var currentDispatchSection:Int = -1;
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
	private var callbackErrorCounts:Map<String, Int> = [];
	private var spawnedPsychNotes:ObjectMap<Dynamic, Bool> = new ObjectMap();
	private var strumDefaultsInitialized:Bool = false;

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
		for (name in ["os", "package", "debug", "require", "dofile", "loadfile", "loadstring", "collectgarbage"])
		{
			Lua.pushnil(lua);
			Lua.setglobal(lua, name);
		}

		callbackScope = new LuaCallbackScope(lua, (callbackError:Dynamic) -> error('Lua API callback failed: ${Std.string(callbackError)}'));
		callbackScope.bind("dbeSafeOsClock", () -> haxe.Timer.stamp());
		LuaL.dostring(lua, "os = { clock = dbeSafeOsClock }; dbeSafeOsClock = nil; if math and not math.lerp then math.lerp = function(from, to, ratio) return from + (to - from) * ratio end end; if not lerp then lerp = math.lerp end");
		bindPsychApi();
		for (cbName => cbFunc in globalCallbacks)
			callbackScope.bind(cbName, cbFunc);
		setNumberConstant("screenWidth", FlxG.width);
		setNumberConstant("screenHeight", FlxG.height);
		var isDownscroll:Bool = (PlayState.instance != null) ? PlayState.instance.downscroll : funkin.options.Options.downscroll;
		set("downscroll", isDownscroll);
		set("downScroll", isDownscroll);
		psychVariables.set("downscroll", isDownscroll);
		psychVariables.set("downScroll", isDownscroll);

		var isMiddlescroll:Bool = (PlayState.instance != null) ? (funkin.options.Options.centeredFields && funkin.backend.system.Flags.ALLOW_CENTERED_FIELDS) : funkin.options.Options.centeredFields;
		set("middlescroll", isMiddlescroll);
		set("middleScroll", isMiddlescroll);
		psychVariables.set("middlescroll", isMiddlescroll);
		psychVariables.set("middleScroll", isMiddlescroll);

		set("shadersEnabled", funkin.options.Options.gameplayShaders);
		set("flashingLights", funkin.options.Options.flashingMenu);
		set("lowQuality", funkin.options.Options.lowMemoryMode);
		psychVariables.set("shadersEnabled", funkin.options.Options.gameplayShaders);
		psychVariables.set("flashingLights", funkin.options.Options.flashingMenu);
		psychVariables.set("lowQuality", funkin.options.Options.lowMemoryMode);

		var initStrumY:Float = 50;
		if (PlayState.instance != null && PlayState.instance.strumLines != null && PlayState.instance.strumLines.members != null)
		{
			for (line in PlayState.instance.strumLines.members)
			{
				if (line == null || line.members == null) continue;
				for (strum in line.members)
					if (strum != null)
					{
						initStrumY = strum.y;
						break;
					}
			}
		}
		setNumberConstant("StrumY", initStrumY);
		setNumberConstant("strumY", initStrumY);
		set("StrumY", initStrumY);
		set("strumY", initStrumY);
		psychVariables.set("StrumY", initStrumY);
		psychVariables.set("strumY", initStrumY);

		for (i in 0...4)
		{
			var defOppX:Float = 82 + (i * 112);
			var defPlayerX:Float = 732 + (i * 112);
			setNumberConstant('defaultPlayerStrumX$i', defPlayerX);
			setNumberConstant('defaultPlayerStrumY$i', initStrumY);
			setNumberConstant('defaultOpponentStrumX$i', defOppX);
			setNumberConstant('defaultOpponentStrumY$i', initStrumY);
			set('defaultPlayerStrumX$i', defPlayerX);
			set('defaultPlayerStrumY$i', initStrumY);
			set('defaultOpponentStrumX$i', defOppX);
			set('defaultOpponentStrumY$i', initStrumY);
			psychVariables.set('defaultPlayerStrumX$i', defPlayerX);
			psychVariables.set('defaultPlayerStrumY$i', initStrumY);
			psychVariables.set('defaultOpponentStrumX$i', defOppX);
			psychVariables.set('defaultOpponentStrumY$i', initStrumY);
		}

		var curRate:Float = (PlayState.instance != null) ? PlayState.instance.playbackRate : 1.0;
		set("playbackRate", curRate);
		setNumberConstant("playbackRate", curRate);
		psychVariables.set("playbackRate", curRate);

		for (i in 0...8)
		{
			var defX:Float = (i % 4) * 112 + (i >= 4 ? 732 : 82);
			setNumberConstant('noteX$i', defX);
			setNumberConstant('noteY$i', initStrumY);
			set('noteX$i', defX);
			set('noteY$i', initStrumY);
			psychVariables.set('noteX$i', defX);
			psychVariables.set('noteY$i', initStrumY);
		}

		var songLen:Float = (FlxG.sound.music != null) ? FlxG.sound.music.length : 0;
		set("songPosition", Conductor.songPosition);
		set("songPos", Conductor.songPosition);
		set("songLength", songLen);
		setNumberConstant("songPosition", Conductor.songPosition);
		setNumberConstant("songPos", Conductor.songPosition);
		setNumberConstant("songLength", songLen);
		psychVariables.set("songPosition", Conductor.songPosition);
		psychVariables.set("songPos", Conductor.songPosition);
		psychVariables.set("songLength", songLen);
	}


	private function bindPsychApi():Void
	{
		callbackScope.bind("print", function(?a:Dynamic, ?b:Dynamic, ?c:Dynamic, ?d:Dynamic):Void printValues([a, b, c, d]));
		callbackScope.bind("debugPrint", function(?a:Dynamic, ?b:Dynamic, ?c:Dynamic, ?d:Dynamic):Void printValues([a, b, c, d]));
		callbackScope.bind("getProperty", (path:String) -> readPsychProperty(path));
		callbackScope.bind("setProperty", setPsychProperty);
		callbackScope.bind("getPropertyFromClass", (className:String, path:String) -> readPath(resolveClass(className), path));
		callbackScope.bind("setPropertyFromClass", setPsychPropertyFromClass);
		callbackScope.bind("getPropertyFromGroup", function(groupName:String, index:Float, path:String):Dynamic {
			var member = getGroupMember(groupName, Std.int(index));
			if (member != null) {
				var val:Dynamic = readPath(member, path);
				if (val != null) return val;
			}
			if (groupName == "strumLineNotes") {
				var idx = Std.int(index);
				if (idx >= 0 && idx < 8) {
					if (path == "x") {
						var p:Dynamic = (idx < 4) ? psychVariables.get('defaultOpponentStrumX$idx') : psychVariables.get('defaultPlayerStrumX' + (idx - 4));
						if (p != null) return p;
						var defX:Float = (idx % 4) * 112 + (idx >= 4 ? 732 : 82);
						return defX;
					}
					if (path == "y") {
						var p:Dynamic = (idx < 4) ? psychVariables.get('defaultOpponentStrumY$idx') : psychVariables.get('defaultPlayerStrumY' + (idx - 4));
						if (p != null) return p;
						return 50.0;
					}
					if (path == "angle") return 0.0;
					if (path == "alpha") return 1.0;
					if (path == "visible") return true;
				}
			}
			return null;
		});
		callbackScope.bind("setPropertyFromGroup", setPsychPropertyFromGroup);
		callbackScope.bind("getRandomBool", function(?chance:Float):Bool return FlxG.random.bool(chance == null ? 50 : chance));
		callbackScope.bind("randomBool", function(?chance:Float):Bool return FlxG.random.bool(chance == null ? 50 : chance));
		callbackScope.bind("characterPlayAnim", function(characterName:String, animation:String, ?force:Bool):Bool
		{
			var character = getCharacter(characterName);
			if (character == null) return false;
			var isIdle = (animation == "idle" || StringTools.startsWith(animation, "idle") || animation == "danceLeft" || animation == "danceRight");
			if (isIdle)
			{
				if (character.isHoldingNote()) return false;
				character.specialAnim = false;
				if ((animation == "idle" && character.idleSuffix != "" && character.hasAnim("idle" + character.idleSuffix)) || character.isDanceLeftDanceRight || !character.hasAnim("idle"))
					character.dance();
				else
					character.playAnim(animation, force == true, DANCE);
				return true;
			}
			if (character.hasAnim(animation) || character.animation.exists(animation))
			{
				if (StringTools.startsWith(animation, "sing"))
				{
					character.playAnim(animation, force == true, SING);
					character.__lockAnimThisFrame = true;
				}
				else
				{
					character.playAnim(animation, force == true, LOCK);
					character.specialAnim = true;
				}
				return true;
			}
			return false;
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
			if (image != null && image.length > 0 && image.toLowerCase() != "empty" && image != "0") {
				var graphic = Paths.image(image);
				if ((graphic == null || !openfl.utils.Assets.exists(graphic)) && !image.startsWith("characters/")) {
					var charGraphic = Paths.image('characters/$image');
					if (charGraphic != null && openfl.utils.Assets.exists(charGraphic)) graphic = charGraphic;
				}
				if (graphic != null && openfl.utils.Assets.exists(graphic)) {
					sprite.loadGraphic(graphic);
					if (sprite.frame != null) sprite.frame = sprite.frame.copyTo();
				} else {
					sprite.makeGraphic(1, 1, flixel.util.FlxColor.TRANSPARENT);
				}
			}
			if (PlayState.instance != null) sprite.cameras = [PlayState.instance.camGame];
			sprite.active = true;
			registerLuaObject(tag, sprite);
			return true;
		});
		callbackScope.bind("makeAnimatedLuaSprite", function(tag:String, ?image:String = null, ?x:Float = 0, ?y:Float = 0, ?spriteType:String = "auto"):Bool
		{
			var sprite = new LuaGraphicSprite(x, y);
			if (image != null && image.length > 0 && image.toLowerCase() != "empty") {
				var frames = Paths.getFrames(image);
				if (frames == null && !image.startsWith("characters/"))
					frames = Paths.getFrames('characters/$image');
				if (frames != null)
					sprite.frames = frames;
				else
					sprite.makeGraphic(1, 1, flixel.util.FlxColor.TRANSPARENT);
			}
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
		callbackScope.bind("makeLuaText", function(tag:String, ?text:Dynamic = "", ?width:Float = 0, ?x:Float = 0, ?y:Float = 0):Bool
		{
			var safeText = text == null ? "" : Std.string(text);
			var field = new FlxText(x, y, width, safeText, 16);
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
		callbackScope.bind("setTextString", (tag:String, ?value:Dynamic = "") -> setLuaTextField(tag, "text", value == null ? "" : Std.string(value)));
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
		var randIntFunc = function(min:Float, max:Float, ?exclude:String = ""):Int
		{
			var excluded:Array<Int> = [];
			if (exclude != null && exclude.length > 0)
				for (entry in exclude.split(","))
				{
					var parsed = Std.parseInt(StringTools.trim(entry));
					if (parsed != null) excluded.push(parsed);
				}
			return FlxG.random.int(Std.int(min), Std.int(max), excluded);
		};
		callbackScope.bind("getRandomInt", randIntFunc);
		callbackScope.bind("randomInt", randIntFunc);
		var randFloatFunc = function(min:Float, max:Float, ?exclude:String = ""):Float
		{
			var excluded:Array<Float> = [];
			if (exclude != null && exclude.length > 0)
				for (entry in exclude.split(","))
				{
					var parsed = Std.parseFloat(StringTools.trim(entry));
					if (!Math.isNaN(parsed)) excluded.push(parsed);
				}
			return FlxG.random.float(min, max, excluded);
		};
		callbackScope.bind("getRandomFloat", randFloatFunc);
		callbackScope.bind("randomFloat", randFloatFunc);
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
		callbackScope.bind("callMethod", callLuaMethod);
		callbackScope.bind("callMethodFromClass", callLuaMethodFromClass);
		callbackScope.bind("createInstance", createLuaInstance);
		callbackScope.bind("addInstance", function(tag:String, ?inFront:Bool = false):Void { addLuaInstance(tag, inFront); });
		callbackScope.bind("instanceArg", function(name:String, ?className:String = null):String
			return '##PSYCHLUA_STRINGTOOBJ::$name${className == null ? "" : "::" + className}');
	}

	private function bindPsychScriptApi():Void
	{
		callbackScope.bind("setVar", (name:String, value:Dynamic) -> {
			psychVariables.set(name, value);
			if (PlayState.instance != null && PlayState.instance.variables != null)
				PlayState.instance.variables.set(name, value);
			value;
		});
		callbackScope.bind("getVar", (name:String) -> {
			if (PlayState.instance != null && PlayState.instance.variables != null && PlayState.instance.variables.exists(name))
				return PlayState.instance.variables.get(name);
			return psychVariables.get(name);
		});
		callbackScope.bind("removeVar", (name:String) -> {
			var r1 = psychVariables.remove(name);
			var r2 = (PlayState.instance != null && PlayState.instance.variables != null) ? PlayState.instance.variables.remove(name) : false;
			return r1 || r2;
		});
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
		globalCallbacks.clear();
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

	private function getStageSprite(tag:String):FlxSprite
	{
		if (tag == null) return null;
		var norm = PsychLuaObjectRegistry.normalizeTag(tag);
		var spr = stageLuaObjects.get(norm);
		if (spr != null) return spr;
		var game = PlayState.instance;
		if (game != null && game.stage != null && game.stage.stageSprites != null)
		{
			if (game.stage.stageSprites.exists(tag)) return game.stage.stageSprites.get(tag);
			for (k => s in game.stage.stageSprites)
				if (k != null && s != null && PsychLuaObjectRegistry.normalizeTag(k) == norm)
					return s;
		}
		return null;
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
		{
			if (!Std.isOfType(script, LuaScript)) continue;
			var normPath = script.path != null ? StringTools.replace(script.path.toLowerCase(), "\\", "/") : "";
			var normFile = script.fileName != null ? script.fileName.toLowerCase() : "";
			if (normPath == target || normPath == targetWithExtension
				|| normFile == target || normFile == targetWithoutExtension
				|| StringTools.endsWith(normPath, "/" + targetWithExtension)
				|| StringTools.endsWith(normPath, targetWithExtension)) return script;
		}
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
		var target:LuaScript = cast script;
		target.updatePsychGlobals();
		var value = target.get(global);
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
		if (!Assets.exists(scriptPath)) scriptPath = Paths.script('scripts/$name');
		if (!Assets.exists(scriptPath) && game.curSongID != null) scriptPath = Paths.script('data/${game.curSongID}/$name');
		if (!Assets.exists(scriptPath) && game.curSongID != null) scriptPath = Paths.script('songs/${game.curSongID}/scripts/$name');
		if (!Assets.exists(scriptPath)) scriptPath = Paths.script('_dbe_preserved/$name');
		if (!Assets.exists(scriptPath)) return false;
		var script = Script.create(scriptPath);
		if (Std.isOfType(script, DummyScript)) return false;
		game.scripts.add(script);
		script.load();
		script.call("onCreate");
		if (game.postCreated) {
			script.call("onCreatePost");
			script.call("postCreate");
			if (!game.startingSong) script.call("onSongStart");
		}
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
		{
			if (!Std.isOfType(script, HScript)) continue;
			var normPath = script.path != null ? StringTools.replace(script.path.toLowerCase(), "\\", "/") : "";
			var normFile = script.fileName != null ? script.fileName.toLowerCase() : "";
			if (normPath == target || normFile == target || StringTools.endsWith(normPath, target)) return script;
		}
		return null;
	}

	private function addHScript(name:String, ?ignoreAlreadyRunning:Bool = false):Bool
	{
		var game = PlayState.instance;
		if (game == null || name == null || (!ignoreAlreadyRunning && findHScript(name) != null)) return false;
		var requested = StringTools.endsWith(name.toLowerCase(), ".hx") ? name : name + ".hx";
		var scriptPath = Paths.script(requested);
		if (!Assets.exists(scriptPath)) scriptPath = Paths.script('scripts/$requested');
		if (!Assets.exists(scriptPath) && game.curSongID != null) scriptPath = Paths.script('data/${game.curSongID}/$requested');
		if (!Assets.exists(scriptPath) && game.curSongID != null) scriptPath = Paths.script('songs/${game.curSongID}/scripts/$requested');
		if (!Assets.exists(scriptPath)) scriptPath = Paths.script('_dbe_preserved/$requested');
		if (!Assets.exists(scriptPath)) return false;
		var script = Script.create(scriptPath);
		if (!Std.isOfType(script, HScript)) return false;
		game.scripts.add(script);
		script.load();
		script.call("onCreate");
		if (game.postCreated) {
			script.call("onCreatePost");
			script.call("postCreate");
			if (!game.startingSong) script.call("onSongStart");
		}
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
		embedded.set("camHUD", game.camHUD);
		embedded.set("camGame", game.camGame);
		embedded.set("camOther", game.camOther);
		embedded.set("camera", game.camera);
		embedded.set("PlayState", PlayState);
		embedded.set("FlxG", FlxG);
		embedded.set("OptionsState", funkin.options.OptionsMenu);
		embedded.set("MusicBeatState", funkin.backend.MusicBeatState);
		embedded.set("Paths", funkin.backend.assets.Paths);
		embedded.set("ClientPrefs", funkin.options.Options);
		embedded.set("Conductor", funkin.backend.system.Conductor);
		embedded.set("ShaderFilter", openfl.filters.ShaderFilter);
		embedded.set("BitmapFilter", openfl.filters.BitmapFilter);
		embedded.set("FlxCamera", flixel.FlxCamera);
		embedded.set("FlxSprite", flixel.FlxSprite);
		embedded.set("FlxObject", flixel.FlxObject);
		embedded.set("FlxColor", CoolUtil.getMacroAbstractClass("flixel.util.FlxColor"));
		embedded.set("setVar", function(name:String, value:Dynamic):Dynamic {
			if (game != null && game.variables != null)
				game.variables.set(name, value);
			psychVariables.set(name, value);
			return value;
		});
		embedded.set("getVar", function(name:String):Dynamic {
			if (game != null && game.variables != null && game.variables.exists(name))
				return game.variables.get(name);
			return psychVariables.get(name);
		});
		embedded.set("removeVar", function(name:String):Bool {
			var r1 = (game != null && game.variables != null) ? game.variables.remove(name) : false;
			var r2 = psychVariables.remove(name);
			return r1 || r2;
		});
		embedded.set("debugPrint", Reflect.makeVarArgs((args) -> {
			var parts:Array<String> = [];
			for (a in args) if (a != null) parts.push(Std.string(a));
			trace(parts.join(' '));
		}));
		embedded.set("getLuaObject", function(tag:String):Dynamic return getLuaObject(tag));
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
		switch (key)
		{
			case "ACCEPT":
				return state == 0 ? game.controls.ACCEPT : (state == 2 ? game.controls.ACCEPT_R : game.controls.ACCEPT_HOLD);
			case "BACK":
				return state == 0 ? game.controls.BACK : (state == 2 ? game.controls.BACK_R : game.controls.BACK_HOLD);
			case "PAUSE":
				return state == 0 ? game.controls.PAUSE : (state == 2 ? game.controls.PAUSE_R : game.controls.PAUSE_HOLD);
			case "RESET":
				return state == 0 ? game.controls.RESET : (state == 2 ? game.controls.RESET_R : game.controls.RESET_HOLD);
			case "UP" | "DOWN" | "LEFT" | "RIGHT":
				var suffix = state == 0 ? "_P" : (state == 2 ? "_R" : "");
				var noteVal = Reflect.getProperty(game.controls, "NOTE_" + key + suffix) == true;
				var uiVal = Reflect.getProperty(game.controls, key + suffix) == true;
				return noteVal || uiVal;
			default:
				var suffix = state == 0 ? "_P" : (state == 2 ? "_R" : "");
				return Reflect.getProperty(game.controls, key + suffix) == true;
		}
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
		var frames:Dynamic = Paths.getFrames(folderOrImage);
		if (frames == null && !folderOrImage.startsWith("characters/"))
			frames = Paths.getFrames('characters/$folderOrImage');
		if (frames == null)
		{
			var animateFrames = Type.resolveClass("animate.FlxAnimateFrames");
			var fromAnimate = animateFrames == null ? null : Reflect.field(animateFrames, "fromAnimate");
			if (fromAnimate != null)
			{
				var metadata:Dynamic = null;
				if (spriteJson != null && Assets.exists(spriteJson)) metadata = Assets.getText(spriteJson);
				frames = Reflect.callMethod(animateFrames, fromAnimate, [folderOrImage, null, metadata, animationJson]);
			}
		}
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
		var object = getLuaObject(tag);
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
		if (methodPath == null || (methodPath = StringTools.trim(methodPath)).length == 0) return null;
		var lastDot = methodPath.lastIndexOf(".");
		if (lastDot < 0)
		{
			return callLuaMethodOn(PlayState.instance, [methodPath], args);
		}

		var targetPath = methodPath.substr(0, lastDot);
		var methodName = methodPath.substr(lastDot + 1);

		var target:Dynamic = getLuaObject(targetPath);
		if (target == null)
		{
			if (luaObjects.exists(targetPath))
				target = luaObjects.get(targetPath);
			else if (psychVariables.exists(targetPath))
				target = psychVariables.get(targetPath);
			else
			{
				target = readPath(PlayState.instance, targetPath);
				if (target == null && PlayState.instance != null && PlayState.instance.variables != null && PlayState.instance.variables.exists(targetPath))
					target = PlayState.instance.variables.get(targetPath);
			}
		}

		if (target == null) return null;
		return callLuaMethodOn(target, [methodName], args);
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

		var parameters = args == null ? [] : [for (arg in args) resolvePsychInstanceArgument(arg)];

		if (target == PlayState.instance || Std.isOfType(target, flixel.group.FlxGroup))
		{
			var grp:flixel.group.FlxGroup = (target == PlayState.instance) ? (cast PlayState.instance) : cast target;
			if (methodName == "remove")
			{
				var obj:flixel.FlxBasic = parameters.length > 0 ? cast parameters[0] : null;
				var splice:Bool = parameters.length > 1 ? cast parameters[1] : true;
				if (obj != null)
				{
					if (target == PlayState.instance) return PlayState.instance.remove(obj, splice);
					return grp.remove(obj, splice);
				}
				return null;
			}
			else if (methodName == "insert")
			{
				var pos:Int = parameters.length > 0 ? Std.int(parameters[0]) : 0;
				var obj:flixel.FlxBasic = parameters.length > 1 ? cast parameters[1] : null;
				if (obj != null)
				{
					if (target == PlayState.instance) return PlayState.instance.insert(pos, obj);
					return grp.insert(pos, obj);
				}
				return null;
			}
			else if (methodName == "add")
			{
				var obj:flixel.FlxBasic = parameters.length > 0 ? cast parameters[0] : null;
				if (obj != null)
				{
					if (target == PlayState.instance) return PlayState.instance.add(obj);
					return grp.add(obj);
				}
				return null;
			}
		}

		if ((methodName == "set_camera" || methodName == "set_cameras") && Std.isOfType(target, flixel.FlxBasic))
		{
			var basic:flixel.FlxBasic = cast target;
			var val:Dynamic = parameters.length > 0 ? parameters[0] : null;
			while (Std.isOfType(val, Array))
			{
				var arr:Array<Dynamic> = cast val;
				if (arr.length == 1) val = arr[0];
				else break;
			}
			if (Std.isOfType(val, String))
				val = getLuaCamera(cast val);
			if (Std.isOfType(val, flixel.FlxCamera))
			{
				basic.cameras = [cast val];
				if (Std.isOfType(basic, flixel.FlxObject))
					funkin.game.HudCamera.bypassDownscroll(cast basic);
			}
			else if (Std.isOfType(val, Array))
			{
				var validCams:Array<flixel.FlxCamera> = [];
				for (c in (cast val:Array<Dynamic>))
				{
					var resolved:Dynamic = Std.isOfType(c, String) ? getLuaCamera(cast c) : c;
					if (Std.isOfType(resolved, flixel.FlxCamera)) validCams.push(cast resolved);
				}
				if (validCams.length > 0)
				{
					basic.cameras = validCams;
					if (Std.isOfType(basic, flixel.FlxObject))
						funkin.game.HudCamera.bypassDownscroll(cast basic);
				}
			}
			return val;
		}

		var method = Reflect.field(target, methodName);
		if (method == null)
		{
			if (methodName.length > 4 && StringTools.startsWith(methodName, "set_"))
			{
				var prop = methodName.substr(4);
				var val = parameters.length > 0 ? parameters[0] : null;
				if (prop != "camera" && prop != "cameras")
					Reflect.setProperty(target, prop, val);
				return val;
			}
			else if (methodName.length > 4 && StringTools.startsWith(methodName, "get_"))
			{
				return Reflect.getProperty(target, methodName.substr(4));
			}
			return null;
		}
		return Reflect.callMethod(target, method, parameters);
	}

	private function resolvePsychInstanceArgument(argument:Dynamic):Dynamic
	{
		if (argument == null) return null;
		if (Std.isOfType(argument, Array))
		{
			var arr:Array<Dynamic> = cast argument;
			return [for (item in arr) resolvePsychInstanceArgument(item)];
		}
		if (!Std.isOfType(argument, String)) return argument;
		var value:String = cast argument;
		if (!StringTools.startsWith(value, "##PSYCHLUA_STRINGTOOBJ::"))
		{
			if (PlayState.instance != null)
			{
				if (value == "camHUD") return PlayState.instance.camHUD;
				if (value == "camOther") return PlayState.instance.camOther;
				if (value == "camGame") return PlayState.instance.camGame;
			}
			return argument;
		}
		var parts = value.substr("##PSYCHLUA_STRINGTOOBJ::".length).split("::");
		if (parts.length == 0 || parts[0].length == 0) return PlayState.instance;
		var name = parts[0];
		if (PlayState.instance != null)
		{
			if (name == "camHUD") return PlayState.instance.camHUD;
			if (name == "camGame") return PlayState.instance.camGame;
			if (name == "camOther") return PlayState.instance.camOther;
			if (name == "noteGroup") return PlayState.instance.strumLines;
			if (name == "boyfriendGroup") return PlayState.instance.boyfriendGroup != null ? PlayState.instance.boyfriendGroup : PlayState.instance.boyfriend;
			if (name == "dadGroup") return PlayState.instance.dadGroup != null ? PlayState.instance.dadGroup : PlayState.instance.dad;
			if (name == "gfGroup") return PlayState.instance.gfGroup != null ? PlayState.instance.gfGroup : PlayState.instance.gf;
			var luaObj = getLuaObject(name);
			if (luaObj != null) return luaObj;
			if (PlayState.instance.variables != null && PlayState.instance.variables.exists(name))
				return PlayState.instance.variables.get(name);
		}
		var root:Dynamic = parts.length > 1 ? resolveClass(parts[1]) : PlayState.instance;
		var resolved = PsychLuaPropertyPath.read(root, name);
		if (resolved != null) return resolved;
		for (field in name.split(".")) root = Reflect.getProperty(root, field);
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
		if (inFront && !isGhostTrailTag(tag))
			game.add(cast object);
		else
		{
			var firstCharacterIndex = getFirstCharacterIndex();
			if (firstCharacterIndex >= 0)
				game.insert(firstCharacterIndex, cast object);
			else
				game.insert(0, cast object);
		}
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

		#if VIDEO_CUTSCENES
		var isMidSong:Bool = forMidSong || (game != null && (game.startedCountdown || game.curStep > 0));
		if (isMidSong)
		{
			var localPath = Assets.getPath(path);
			var videoSprite = new hxvlc.flixel.FlxVideoSprite();
			videoSprite.antialiasing = true;
			videoSprite.scrollFactor.set();
			videoSprite.visible = false; // Hide until first frame is formatted to eliminate any green flash!
			videoSprite.cameras = [game.camOther != null ? game.camOther : game.camHUD];
			funkin.game.HudCamera.bypassDownscroll(videoSprite);

			var onFormat = function() {
				if (videoSprite != null && videoSprite.bitmap != null && videoSprite.bitmap.bitmapData != null) {
					final width:Float = videoSprite.bitmap.bitmapData.width;
					final height:Float = videoSprite.bitmap.bitmapData.height;
					if (width > 1 && height > 1) {
						final scale:Float = Math.min(FlxG.width / width, FlxG.height / height);
						videoSprite.setGraphicSize(width * scale, height * scale);
						videoSprite.updateHitbox();
						videoSprite.screenCenter();
						// Safety fallback if onDisplay is slightly delayed
						flixel.util.FlxTimer.wait(0.15, function() {
							if (videoSprite != null) videoSprite.visible = true;
						});
					}
				}
			};
			videoSprite.bitmap.onFormatSetup.add(onFormat);

			var onFirstDisplay:Void->Void = null;
			onFirstDisplay = function() {
				if (videoSprite != null) {
					videoSprite.visible = true;
					if (videoSprite.bitmap != null && onFirstDisplay != null) {
						videoSprite.bitmap.onDisplay.remove(onFirstDisplay);
					}
				}
			};
			videoSprite.bitmap.onDisplay.add(onFirstDisplay);

			videoSprite.bitmap.onEndReached.add(function() {
				if (videoSprite != null && !shouldLoop) {
					if (game.members.contains(videoSprite)) game.remove(videoSprite, true);
					luaObjects.remove("videoCutscene");
					videoSprite.destroy();
					game.inCutscene = false;
				}
			});

			var options:Array<String> = [":file-caching=0", ":network-caching=0", ":clock-jitter=0"];
			if (shouldLoop) options.push(":input-repeat=65535");

			if (videoSprite.load(localPath, options)) {
				if (playOnLoad) videoSprite.play();
			}

			registerLuaObject("videoCutscene", videoSprite);
			game.add(videoSprite);
			return true;
		}
		#end

		var videoClass = Type.resolveClass("funkin.game.cutscenes.VideoCutscene");
		if (videoClass == null) return false;
		var substate = Type.createInstance(videoClass, [path, () -> {
			if (game != null) game.inCutscene = false;
			if (!forMidSong && game.startedCountdown == false) game.startCountdown();
		}]);
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
		callbackScope.bind("getCharacterX", function(name:String):Float {
			var game = PlayState.instance;
			var lower = name != null ? name.toLowerCase() : "";
			switch(lower) {
				case 'dad' | 'opponent':
					return game != null && game.dadGroup != null ? game.dadGroup.x : (game != null && game.dad != null ? game.dad.x : 0);
				case 'gf' | 'girlfriend':
					return game != null && game.gfGroup != null ? game.gfGroup.x : (game != null && game.gf != null ? game.gf.x : 0);
				case 'bf' | 'boyfriend':
					return game != null && game.boyfriendGroup != null ? game.boyfriendGroup.x : (game != null && game.boyfriend != null ? game.boyfriend.x : 0);
				default:
					var c = getCharacter(name);
					return c != null ? c.x : 0;
			}
		});
		callbackScope.bind("getCharacterY", function(name:String):Float {
			var game = PlayState.instance;
			var lower = name != null ? name.toLowerCase() : "";
			switch(lower) {
				case 'dad' | 'opponent':
					return game != null && game.dadGroup != null ? game.dadGroup.y : (game != null && game.dad != null ? game.dad.y : 0);
				case 'gf' | 'girlfriend':
					return game != null && game.gfGroup != null ? game.gfGroup.y : (game != null && game.gf != null ? game.gf.y : 0);
				case 'bf' | 'boyfriend':
					return game != null && game.boyfriendGroup != null ? game.boyfriendGroup.y : (game != null && game.boyfriend != null ? game.boyfriend.y : 0);
				default:
					var c = getCharacter(name);
					return c != null ? c.y : 0;
			}
		});
		callbackScope.bind("setCharacterX", function(name:String, value:Float):Bool {
			var game = PlayState.instance;
			if (game == null) return false;
			var lower = name != null ? name.toLowerCase() : "";
			switch(lower) {
				case 'dad' | 'opponent':
					if (game.dadGroup != null) { game.dadGroup.x = value; return true; }
				case 'gf' | 'girlfriend':
					if (game.gfGroup != null) { game.gfGroup.x = value; return true; }
				case 'bf' | 'boyfriend':
					if (game.boyfriendGroup != null) { game.boyfriendGroup.x = value; return true; }
				default:
					var c = getCharacter(name);
					if (c != null) { c.x = value; return true; }
			}
			return false;
		});
		callbackScope.bind("setCharacterY", function(name:String, value:Float):Bool {
			var game = PlayState.instance;
			if (game == null) return false;
			var lower = name != null ? name.toLowerCase() : "";
			switch(lower) {
				case 'dad' | 'opponent':
					if (game.dadGroup != null) { game.dadGroup.y = value; return true; }
				case 'gf' | 'girlfriend':
					if (game.gfGroup != null) { game.gfGroup.y = value; return true; }
				case 'bf' | 'boyfriend':
					if (game.boyfriendGroup != null) { game.boyfriendGroup.y = value; return true; }
				default:
					var c = getCharacter(name);
					if (c != null) { c.y = value; return true; }
			}
			return false;
		});
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
		callbackScope.bind("cameraShake", (camera:String, intensity:Float, duration:Float) -> {
			var cam = getLuaCamera(camera);
			if (cam != null) cam.shake(intensity, duration);
			return true;
		});
		callbackScope.bind("cameraFlash", function(camera:String, ?color:Dynamic = "FFFFFF", ?duration:Float = 1, ?forced:Bool = false):Bool
		{
			var cam = getLuaCamera(camera);
			if (cam != null) cam.flash(parseLuaColor(color), duration, null, forced);
			return true;
		});
		callbackScope.bind("cameraFade", function(camera:String, ?color:Dynamic = "000000", ?duration:Float = 1, ?forced:Bool = false, ?fadeOut:Bool = false):Bool
		{
			var cam = getLuaCamera(camera);
			if (cam != null) cam.fade(parseLuaColor(color), duration, fadeOut, null, forced);
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
		callbackScope.bind("restartSong", function(?skipTransition:Bool = false):Bool {
			if (PlayState.instance == null) return false;
			if (skipTransition) funkin.backend.MusicBeatState.skipTransOut = true;
			var request = funkin.backend.assets.SongLoadRequest.fromPlayState("retry");
			funkin.backend.assets.SongLoader.start(request, () -> PlayState.SONG);
			return true;
		});
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
		callbackScope.bind("runTimer", function(tag:Dynamic, ?time:Float = 1, ?loops:Int = 1):Dynamic
		{
			var tagStr = tag == null ? null : Std.string(tag);
			var result = runLuaTimer(tagStr, time, loops);
			return result == null || psychLuaProfileName() == PsychLuaProfile.PSYCH_063 ? null : psychTaggedValue("timer", tagStr);
		});
		callbackScope.bind("cancelTimer", function(tag:Dynamic):Void { cancelLuaTimer(tag == null ? null : Std.string(tag)); });
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

	private static function parsePsychTweenNumber(value:Dynamic, defaultValue:Float = 0):Float
	{
		if (value == null) return defaultValue;
		var str = StringTools.trim(Std.string(value));
		if (str.length == 0) return defaultValue;
		var num = Std.parseFloat(str);
		return Math.isNaN(num) ? defaultValue : num;
	}

	private function bindPsychTweenApi():Void
	{
		callbackScope.bind("doTweenX", (tag:Dynamic, object:String, value:Dynamic, duration:Dynamic, ?ease:String = "linear") -> {
			var tagStr = tag == null ? null : Std.string(tag);
			psychTweenReturn(tagStr, tweenLuaProperty(tagStr, object, "x", parsePsychTweenNumber(value, 0), parsePsychTweenNumber(duration, 0), ease));
		});
		callbackScope.bind("doTweenY", (tag:Dynamic, object:String, value:Dynamic, duration:Dynamic, ?ease:String = "linear") -> {
			var tagStr = tag == null ? null : Std.string(tag);
			psychTweenReturn(tagStr, tweenLuaProperty(tagStr, object, "y", parsePsychTweenNumber(value, 0), parsePsychTweenNumber(duration, 0), ease));
		});
		callbackScope.bind("doTweenAngle", (tag:Dynamic, object:String, value:Dynamic, duration:Dynamic, ?ease:String = "linear") -> {
			var tagStr = tag == null ? null : Std.string(tag);
			psychTweenReturn(tagStr, tweenLuaProperty(tagStr, object, "angle", parsePsychTweenNumber(value, 0), parsePsychTweenNumber(duration, 0), ease));
		});
		callbackScope.bind("doTweenAlpha", function(tag:Dynamic, object:String, value:Dynamic, duration:Dynamic, ?ease:String = "linear"):Dynamic
		{
			var tagStr = tag == null ? null : Std.string(tag);
			if (isBetterCinematicsScript() || isBetterCinematicsHudTag(tagStr, object))
				return psychTweenReturn(tagStr, true);

			var alpha = parsePsychTweenNumber(value, 1);
			var seconds = parsePsychTweenNumber(duration, 0);
			var started = tweenLuaProperty(tagStr, object, "alpha", alpha, seconds, ease);
			return psychTweenReturn(tagStr, started);
		});
		callbackScope.bind("doTweenColor", function(tag:Dynamic, object:String, color:Dynamic, duration:Dynamic, ?ease:String = "linear"):Dynamic {
			var tagStr = tag == null ? null : Std.string(tag);
			return psychTweenReturn(tagStr, tweenLuaColor(tagStr, object, color, parsePsychTweenNumber(duration, 0), ease));
		});
		callbackScope.bind("doTweenZoom", (tag:Dynamic, camera:String, value:Dynamic, duration:Dynamic, ?ease:String = "linear") -> {
			var tagStr = tag == null ? null : Std.string(tag);
			psychTweenReturn(tagStr, tweenLuaTarget(tagStr, getLuaCamera(camera), camera, "zoom", Math.max(0.05, parsePsychTweenNumber(value, 1)), parsePsychTweenNumber(duration, 0), ease));
		});
		callbackScope.bind("noteTweenX", function(tag:Dynamic, note:Dynamic, value:Dynamic, duration:Dynamic, ?ease:String = "linear"):Dynamic {
			if (value == null) return false;
			var parsed = parsePsychTweenNumber(value, Math.NaN);
			if (Math.isNaN(parsed)) return false;
			var tagStr = tag == null ? null : Std.string(tag);
			return tweenLuaNote(tagStr, Std.int(parsePsychTweenNumber(note, 0)), "x", parsed, parsePsychTweenNumber(duration, 0), ease);
		});
		callbackScope.bind("noteTweenY", function(tag:Dynamic, note:Dynamic, value:Dynamic, duration:Dynamic, ?ease:String = "linear"):Dynamic {
			if (value == null) return false;
			var parsed = parsePsychTweenNumber(value, Math.NaN);
			if (Math.isNaN(parsed)) return false;
			var tagStr = tag == null ? null : Std.string(tag);
			return tweenLuaNote(tagStr, Std.int(parsePsychTweenNumber(note, 0)), "y", parsed, parsePsychTweenNumber(duration, 0), ease);
		});
		callbackScope.bind("noteTweenAngle", (tag:Dynamic, note:Dynamic, value:Dynamic, duration:Dynamic, ?ease:String = "linear") -> tweenLuaNote(tag == null ? null : Std.string(tag), Std.int(parsePsychTweenNumber(note, 0)), "angle", parsePsychTweenNumber(value, 0), parsePsychTweenNumber(duration, 0), ease));
		callbackScope.bind("noteTweenAlpha", (tag:Dynamic, note:Dynamic, value:Dynamic, duration:Dynamic, ?ease:String = "linear") -> tweenLuaNote(tag == null ? null : Std.string(tag), Std.int(parsePsychTweenNumber(note, 0)), "alpha", parsePsychTweenNumber(value, 0), parsePsychTweenNumber(duration, 0), ease));
		callbackScope.bind("noteTweenDirection", (tag:Dynamic, note:Dynamic, value:Dynamic, duration:Dynamic, ?ease:String = "linear") -> tweenLuaNote(tag == null ? null : Std.string(tag), Std.int(parsePsychTweenNumber(note, 0)), "direction", parsePsychTweenNumber(value, 0), parsePsychTweenNumber(duration, 0), ease));
		if (psychLuaProfileName() != PsychLuaProfile.PSYCH_063) callbackScope.bind("startTween", startLuaTween);
		callbackScope.bind("cancelTween", function(tag:Dynamic):Void { cancelLuaTween(tag == null ? null : Std.string(tag)); });
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
		callbackScope.bind("skipTime", function(time:Float):Void {
			if (funkin.game.PlayState.instance != null) {
				var ms = time < 1000 ? (time * 1000) : time;
				funkin.game.PlayState.instance.skipTime(ms);
			}
		});
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
		var activeStep = currentDispatchStep >= 0 ? currentDispatchStep : Conductor.curStep;
		var activeBeat = currentDispatchBeat >= 0 ? currentDispatchBeat : Conductor.curBeat;
		var activeSection = currentDispatchSection >= 0 ? currentDispatchSection : Conductor.curMeasure;

		var songLen:Float = (FlxG.sound.music != null) ? FlxG.sound.music.length : 0;
		set("songPosition", Conductor.songPosition);
		set("songPos", Conductor.songPosition);
		set("songLength", songLen);
		setNumberConstant("songPosition", Conductor.songPosition);
		setNumberConstant("songPos", Conductor.songPosition);
		setNumberConstant("songLength", songLen);
		psychVariables.set("songPosition", Conductor.songPosition);
		psychVariables.set("songPos", Conductor.songPosition);
		psychVariables.set("songLength", songLen);
		set("curBeat", activeBeat);
		set("curStep", activeStep);
		set("curSection", activeSection);
		setNumberConstant("curBeat", activeBeat);
		setNumberConstant("curStep", activeStep);
		setNumberConstant("curSection", activeSection);
		var decBeat = currentDispatchBeat >= 0 ? (currentDispatchStep >= 0 ? currentDispatchStep / 4.0 : activeBeat) : Conductor.curBeatFloat;
		var decStep = currentDispatchStep >= 0 ? activeStep : Conductor.curStepFloat;
		var decSec = currentDispatchSection >= 0 ? activeSection : Conductor.curMeasureFloat;
		set("curDecBeat", decBeat);
		set("curDecStep", decStep);
		set("curDecSection", decSec);
		setNumberConstant("curDecBeat", decBeat);
		setNumberConstant("curDecStep", decStep);
		setNumberConstant("curDecSection", decSec);
		set("bpm", Conductor.bpm);
		set("curBpm", Conductor.bpm);
		set("crochet", Conductor.crochet);
		set("stepCrochet", Conductor.stepCrochet);
		setNumberConstant("bpm", Conductor.bpm);
		setNumberConstant("curBpm", Conductor.bpm);
		setNumberConstant("crochet", Conductor.crochet);
		setNumberConstant("stepCrochet", Conductor.stepCrochet);
		if (game == null) return;
		set("songName", game.rawSongName != null ? game.rawSongName : game.curSong);
		set("songPath", game.curSongID);
		set("curStage", game.curStage);
		set("gfSection", false);
		set("difficulty", PlayState.difficulty);
		set("health", game.health);
		set("score", game.songScore);
		set("misses", game.misses);
		set("combo", game.combo);
		set("downscroll", game.downscroll);
		set("downScroll", game.downscroll);
		var isBotplay = (game.playerStrums != null && (game.playerStrums.botplay || game.playerStrums.cpu));
		set("botPlay", isBotplay);
		set("botplay", isBotplay);
		set("shadersEnabled", Options.gameplayShaders);
		set("flashingLights", Options.flashingMenu);
		set("lowQuality", Options.lowMemoryMode);
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

		if (game.strumLines != null)
		{
			var oppLine = game.cpuStrums != null ? game.cpuStrums : (game.strumLines.members != null && game.strumLines.members.length > 0 ? game.strumLines.members[0] : null);
			var playerLine = game.playerStrums != null ? game.playerStrums : (game.strumLines.members != null && game.strumLines.members.length > 1 ? game.strumLines.members[1] : null);

			if (!strumDefaultsInitialized && oppLine != null && playerLine != null
				&& oppLine.members != null && oppLine.members.length > 0
				&& playerLine.members != null && playerLine.members.length > 0)
			{
				var foundStrumY:Null<Float> = null;
				for (i in 0...oppLine.members.length)
				{
					var strum = oppLine.members[i];
					if (strum == null) continue;
					var bx = strum.initialX != 0 ? strum.initialX : strum.x;
					var by = strum.initialY != 0 ? strum.initialY : strum.y;
					if (foundStrumY == null) foundStrumY = by;
					setNumberConstant('defaultOpponentStrumX$i', bx);
					setNumberConstant('defaultOpponentStrumY$i', by);
					set('defaultOpponentStrumX$i', bx);
					set('defaultOpponentStrumY$i', by);
					psychVariables.set('defaultOpponentStrumX$i', bx);
					psychVariables.set('defaultOpponentStrumY$i', by);
					setNumberConstant('noteX$i', bx);
					setNumberConstant('noteY$i', by);
					set('noteX$i', bx);
					set('noteY$i', by);
					psychVariables.set('noteX$i', bx);
					psychVariables.set('noteY$i', by);
				}
				for (i in 0...playerLine.members.length)
				{
					var strum = playerLine.members[i];
					if (strum == null) continue;
					var bx = strum.initialX != 0 ? strum.initialX : strum.x;
					var by = strum.initialY != 0 ? strum.initialY : strum.y;
					if (foundStrumY == null) foundStrumY = by;
					setNumberConstant('defaultPlayerStrumX$i', bx);
					setNumberConstant('defaultPlayerStrumY$i', by);
					set('defaultPlayerStrumX$i', bx);
					set('defaultPlayerStrumY$i', by);
					psychVariables.set('defaultPlayerStrumX$i', bx);
					psychVariables.set('defaultPlayerStrumY$i', by);
					var idx = i + 4;
					setNumberConstant('noteX$idx', bx);
					setNumberConstant('noteY$idx', by);
					set('noteX$idx', bx);
					set('noteY$idx', by);
					psychVariables.set('noteX$idx', bx);
					psychVariables.set('noteY$idx', by);
				}
				if (foundStrumY != null)
				{
					setNumberConstant("StrumY", foundStrumY);
					setNumberConstant("strumY", foundStrumY);
					set("StrumY", foundStrumY);
					set("strumY", foundStrumY);
					psychVariables.set("StrumY", foundStrumY);
					psychVariables.set("strumY", foundStrumY);
				}
				strumDefaultsInitialized = true;
			}
		}
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
		if ((isBetterCinematicsScript() || isBetterCinematicsHudTag(tag, objectName)) && property == "alpha")
			return true;
		var res = tweenLuaTarget(tag, getLuaObject(objectName), objectName, property, value, duration, ease);
		if (res && objectName == "scoreTxt" && PlayState.instance != null)
		{
			if (property == "alpha" || property == "y")
			{
				if (PlayState.instance.missesTxt != null)
					tweenLuaTarget(tag + "__missesTxt", PlayState.instance.missesTxt, "missesTxt", property, value, duration, ease);
				if (PlayState.instance.accuracyTxt != null)
					tweenLuaTarget(tag + "__accuracyTxt", PlayState.instance.accuracyTxt, "accuracyTxt", property, value, duration, ease);
			}
		}
		return res;
	}

	private static var activeLongNoteTweens:Map<Int, String> = new Map<Int, String>();

	private static inline function isGlitchNoteTag(tag:String):Bool
	{
		return tag != null && (StringTools.startsWith(tag, "glitchNoteX") || StringTools.startsWith(tag, "glitchNoteY"));
	}

	private static function syncDynamicNotePos(noteIndex:Int, prefix:String, value:Float):Void
	{
		var varName = '$prefix$noteIndex';
		psychVariables.set(varName, value);
		if (PlayState.instance != null && PlayState.instance.scripts != null && PlayState.instance.scripts.scripts != null)
		{
			for (s in PlayState.instance.scripts.scripts)
			{
				if (s != null && (s is LuaScript))
				{
					var ls:LuaScript = cast s;
					ls.setNumberConstant(varName, value);
					ls.set(varName, value);
				}
			}
		}
	}

	private function tweenLuaNote(tag:String, noteIndex:Int, property:String, value:Float, duration:Float, ?ease:String = "linear"):Bool
	{
		if (isBetterCinematicsScript() || isBetterCinematicsNoteTag(tag))
			return true;

		var isGlitch = isGlitchNoteTag(tag);
		if (isGlitch && activeLongNoteTweens.exists(noteIndex))
			return true;

		var strum:Dynamic = getGroupMember("strumLineNotes", noteIndex);
		if (Std.isOfType(strum, Strum))
		{
			var receptor:Strum = cast strum;
			receptor.__pendingIntroAnim = false;
			if (property == "angle" && receptor.noteAngle == null)
				receptor.noteAngle = 0;
		}
		if (property == "direction")
		{
			if (!Std.isOfType(strum, Strum)) return false;
			var receptor:Strum = cast strum;
			if (receptor.noteAngle == null) receptor.noteAngle = receptor.getNotesAngle();
			property = "noteAngle";
			value -= 90;
		}

		if (!isGlitch)
		{
			if (property == "x") syncDynamicNotePos(noteIndex, "noteX", value);
			else if (property == "y") syncDynamicNotePos(noteIndex, "noteY", value);

			if (duration > 0.05)
				activeLongNoteTweens.set(noteIndex, tag);
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
		if (duration <= 0)
		{
			Reflect.setProperty(target, "color", endColor);
			callLua("onTweenCompleted", PsychHookMap.makeTweenCompletedArguments(psychLuaProfileName(), tag, objectName, true));
			return true;
		}
		luaTweens.set(tag, FlxTween.color(target, duration, startColor, endColor, {
			ease: resolveLuaEase(ease),
			onComplete: function(_:FlxTween)
			{
				luaTweens.remove(tag);
				callLua("onTweenCompleted", PsychHookMap.makeTweenCompletedArguments(psychLuaProfileName(), tag, objectName, true));
			}
		}));
		if (objectName == "scoreTxt" && PlayState.instance != null)
		{
			if (PlayState.instance.missesTxt != null)
				FlxTween.color(PlayState.instance.missesTxt, duration, startColor, endColor, {ease: resolveLuaEase(ease)});
			if (PlayState.instance.accuracyTxt != null)
				FlxTween.color(PlayState.instance.accuracyTxt, duration, startColor, endColor, {ease: resolveLuaEase(ease)});
		}
		return true;
	}

	private inline function isCamZoomTarget(target:Dynamic, property:String):Bool
	{
		return property == "zoom" && PlayState.instance != null && (target == PlayState.instance.camGame || target == flixel.FlxG.camera);
	}

	private inline function isHudZoomTarget(target:Dynamic, property:String):Bool
	{
		return property == "zoom" && PlayState.instance != null && target == PlayState.instance.camHUD;
	}

	private function startLuaTween(tag:String, objectName:String, values:Dynamic, duration:Float, ?options:Dynamic):Dynamic
	{
		var target = getLuaObject(objectName);
		if (tag == null || target == null || values == null || duration < 0) return null;
		var properties:Dynamic = {};
		for (field in Reflect.fields(values)) Reflect.setField(properties, field, Reflect.field(values, field));
		cancelLuaTween(tag);
		var easeName = options == null ? "linear" : Std.string(Reflect.getProperty(options, "ease"));
		var hasCamZoom = isCamZoomTarget(target, "zoom") && Reflect.hasField(properties, "zoom");
		var hasHudZoom = isHudZoomTarget(target, "zoom") && Reflect.hasField(properties, "zoom");
		var tweenOptions:Dynamic = {
			ease: resolveLuaEase(easeName),
			onUpdate: function(_:FlxTween)
			{
				if (hasCamZoom && PlayState.instance != null) {
					var curZ:Dynamic = Reflect.getProperty(target, "zoom");
					if (curZ != null) PlayState.instance.defaultCamZoom = curZ;
				} else if (hasHudZoom && PlayState.instance != null) {
					var curZ:Dynamic = Reflect.getProperty(target, "zoom");
					if (curZ != null) PlayState.instance.defaultHudZoom = curZ;
				}
			},
			onComplete: function(_:FlxTween)
			{
				if (hasCamZoom && PlayState.instance != null)
					PlayState.instance.defaultCamZoom = Std.parseFloat(Std.string(Reflect.field(properties, "zoom")));
				else if (hasHudZoom && PlayState.instance != null)
					PlayState.instance.defaultHudZoom = Std.parseFloat(Std.string(Reflect.field(properties, "zoom")));
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
		FlxTween.cancelTweensOf(target, [property]);
		var isCamZoom = isCamZoomTarget(target, property);
		var isHudZoom = isHudZoomTarget(target, property);
		if (duration <= 0)
		{
			PsychLuaPropertyPath.write(target, property, value);
			if (isCamZoom && PlayState.instance != null) PlayState.instance.defaultCamZoom = Std.parseFloat(Std.string(value));
			if (isHudZoom && PlayState.instance != null) PlayState.instance.defaultHudZoom = Std.parseFloat(Std.string(value));
			callLua("onTweenCompleted", PsychHookMap.makeTweenCompletedArguments(psychLuaProfileName(), tag, objectName));
			return true;
		}
		var properties:Dynamic = {};
		Reflect.setField(properties, property, value);
		var options:Dynamic = {
			ease: resolveLuaEase(ease),
			onUpdate: function(_:FlxTween)
			{
				if (isCamZoom && PlayState.instance != null)
				{
					var curZ:Dynamic = Reflect.getProperty(target, "zoom");
					if (curZ != null) PlayState.instance.defaultCamZoom = curZ;
				}
				else if (isHudZoom && PlayState.instance != null)
				{
					var curZ:Dynamic = Reflect.getProperty(target, "zoom");
					if (curZ != null) PlayState.instance.defaultHudZoom = curZ;
				}
			},
			onComplete: function(_:FlxTween)
			{
				if (isCamZoom && PlayState.instance != null)
					PlayState.instance.defaultCamZoom = Std.parseFloat(Std.string(value));
				else if (isHudZoom && PlayState.instance != null)
					PlayState.instance.defaultHudZoom = Std.parseFloat(Std.string(value));
				for (k in activeLongNoteTweens.keys())
					if (activeLongNoteTweens.get(k) == tag)
						activeLongNoteTweens.remove(k);
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
		for (k in activeLongNoteTweens.keys())
			if (activeLongNoteTweens.get(k) == tag)
				activeLongNoteTweens.remove(k);
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
		var cleanName = name;
		if (cleanName.startsWith("shaders/")) cleanName = cleanName.substr(8);
		var dot = cleanName.lastIndexOf(".");
		if (dot != -1) {
			var ext = cleanName.substr(dot + 1).toLowerCase();
			if (ext == "frag" || ext == "vert" || ext == "glsl") cleanName = cleanName.substr(0, dot);
		}
		if (luaShaders.exists(cleanName)) {
			luaShaders.set(name, luaShaders.get(cleanName));
			return true;
		}
		try
		{
			var shader = new CustomShader(cleanName);
			luaShaders.set(name, shader);
			luaShaders.set(cleanName, shader);
			luaShaders.set(cleanName.toLowerCase(), shader);
			return true;
		}
		catch (_:Dynamic) return false;
	}

	private function getLuaShader(tag:String):Dynamic
	{
		var object = getLuaObject(tag);
		var shader = object == null ? null : Reflect.getProperty(object, "shader");
		if (shader != null) return shader;
		if (luaShaders.exists(tag)) return luaShaders.get(tag);
		if (tag != null && luaShaders.exists(tag.toLowerCase())) return luaShaders.get(tag.toLowerCase());
		return null;
	}

	private function setLuaSpriteShader(tag:String, shaderName:String):Bool
	{
		var object = getLuaObject(tag);
		if (!Std.isOfType(object, FlxSprite) || shaderName == null || shaderName.length == 0) return false;
		var spr:FlxSprite = cast object;
		var cleanName = shaderName;
		if (cleanName.startsWith("shaders/")) cleanName = cleanName.substr(8);
		var dot = cleanName.lastIndexOf(".");
		if (dot != -1) {
			var ext = cleanName.substr(dot + 1).toLowerCase();
			if (ext == "frag" || ext == "vert" || ext == "glsl") cleanName = cleanName.substr(0, dot);
		}
		if (Std.isOfType(spr.shader, CustomShader) && (cast spr.shader:CustomShader).path == cleanName)
			return true;
		try
		{
			var shader = new CustomShader(cleanName);
			shader.path = cleanName;
			spr.shader = shader;
			if (!luaShaders.exists(shaderName)) luaShaders.set(shaderName, shader);
			if (!luaShaders.exists(cleanName)) luaShaders.set(cleanName, shader);
			if (!luaShaders.exists(cleanName.toLowerCase())) luaShaders.set(cleanName.toLowerCase(), shader);
			return true;
		}
		catch (_:Dynamic) return false;
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
		if (shader == null || field == null) return false;
		var shaderData = Reflect.getProperty(shader, "data");
		if (shaderData != null && !Reflect.hasField(shaderData, field)) return false;
		var setterName = "set" + kind;
		var setter = Reflect.field(shader, setterName);
		if (setter == null) return false;
		var safeValue:Dynamic = value;
		if (kind == "FloatArray" && (value is Array))
		{
			var arr:Array<Dynamic> = cast value;
			safeValue = [for (v in arr) (v is Float || v is Int ? cast(v, Float) : Std.parseFloat(Std.string(v)))];
		}
		else if (kind == "IntArray" && (value is Array))
		{
			var arr:Array<Dynamic> = cast value;
			safeValue = [for (v in arr) (v is Int ? cast(v, Int) : Std.parseInt(Std.string(v)))];
		}
		else if (kind == "BoolArray" && (value is Array))
		{
			var arr:Array<Dynamic> = cast value;
			safeValue = [for (v in arr) (v is Bool ? cast(v, Bool) : Std.string(v).toLowerCase() == "true")];
		}
		try { Reflect.callMethod(shader, setter, [field, safeValue]); return true; }
		catch (_:Dynamic) return false;
	}

	private function getLuaShaderValue(tag:String, field:String, getterName:String):Dynamic
	{
		var shader = getLuaShader(tag);
		if (shader == null || field == null) return null;
		var shaderData = Reflect.getProperty(shader, "data");
		if (shaderData != null && !Reflect.hasField(shaderData, field)) return null;
		var getter = Reflect.field(shader, getterName);
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

	public function getLuaObject(tag:String):Dynamic
	{
		if (tag != null && tag.indexOf(".") != -1)
		{
			var dotIdx = tag.indexOf(".");
			var rootTag = tag.substring(0, dotIdx);
			var subPath = tag.substring(dotIdx + 1);
			var rootObj = getLuaObject(rootTag);
			if (rootObj != null)
				return PsychLuaPropertyPath.read(rootObj, subPath);
		}
		var object = luaObjects.get(tag);
		if (object != null) return object;
		var game = PlayState.instance;
		if (game != null && game.variables != null && game.variables.exists(tag))
			return game.variables.get(tag);
		object = getStageSprite(tag);
		if (object != null) return object;
		var char = getCharacter(tag);
		if (char != null) return char;
		if (game != null)
		{
			switch (tag)
			{
				case "healthBar": return game.healthBar;
				case "healthBarBG": return game.healthBarBG;
				case "iconP1": return game.iconP1;
				case "iconP2": return game.iconP2;
				case "scoreTxt": return game.scoreTxt;
				case "missesTxt": return game.missesTxt;
				case "accuracyTxt": return game.accuracyTxt;
				case "timeBar": return game.timeBar;
				case "timeBarBG" | "timeBG": return game.timeBarBG != null ? game.timeBarBG : (cast game.timeBar);
				case "timeTxt": return game.timeTxt;
				case "camGame" | "camera": return game.camGame;
				case "camHUD": return game.camHUD;
				case "camOther": return game.camOther;
				case "dadGroup": return game.dadGroup != null ? (cast game.dadGroup:Dynamic) : (cast game.dad:Dynamic);
				case "boyfriendGroup": return game.boyfriendGroup != null ? (cast game.boyfriendGroup:Dynamic) : (cast game.boyfriend:Dynamic);
				case "gfGroup": return game.gfGroup != null ? (cast game.gfGroup:Dynamic) : (cast game.gf:Dynamic);
				case "opponentStrums" | "cpuStrums": return game.cpuStrums != null ? game.cpuStrums : (game.strumLines.members != null && game.strumLines.members.length > 0 ? game.strumLines.members[0] : null);
				case "playerStrums": return game.playerStrums != null ? game.playerStrums : (game.strumLines.members != null && game.strumLines.members.length > 1 ? game.strumLines.members[1] : null);
			}
		}
		return PsychLuaPropertyPath.read(PlayState.instance, tag);
	}

	private function getLuaSprite(tag:String):FlxSprite
	{
		var object = luaObjects.get(tag);
		if (object == null) object = getStageSprite(tag);
		if (object == null) object = getLuaObject(tag);
		return Std.isOfType(object, FlxSprite) ? cast object : null;
	}

	private function getOrCreateLuaSprite(tag:String):FlxSprite
	{
		var sprite = getLuaSprite(tag);
		if (sprite == null)
		{
			sprite = new LuaGraphicSprite();
			if (PlayState.instance != null) sprite.cameras = [PlayState.instance.camGame];
			funkin.game.HudCamera.bypassDownscroll(sprite);
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

	private static inline function isGhostTrailTag(tag:String):Bool
	{
		if (tag == null) return false;
		var lower = tag.toLowerCase();
		return lower.indexOf("trail") >= 0 || lower.indexOf("ghost") >= 0 || lower.indexOf("afterimage") >= 0 || lower.indexOf("fantasma") >= 0;
	}

	private inline function isBetterCinematicsScript():Bool
	{
		if (rawLuaPath == null) return false;
		var normalized = StringTools.replace(rawLuaPath, "\\", "/").toLowerCase();
		return normalized.indexOf("better cinematics") >= 0;
	}

	private static inline function isBetterCinematicsNoteTag(tag:String):Bool
	{
		return tag != null && StringTools.startsWith(tag, "leftBF");
	}

	private static inline function isBetterCinematicsHudTag(tag:String, object:String):Bool
	{
		if (tag == null || !StringTools.startsWith(tag, "Alpha")) return false;
		if (object == null) return false;
		var obj = StringTools.trim(object).toLowerCase();
		return [
			"healthbarbg", "healthbar", "scoretxt", "iconp1", "iconp2", "timebar", "timebarbg", "timebg", "timetxt"
		].contains(obj);
	}

	private function getFirstCharacterIndex():Int
	{
		var game = PlayState.instance;
		if (game == null) return -1;
		var firstIdx = game.members.length;
		if (game.strumLines != null && game.strumLines.members != null)
		{
			for (line in game.strumLines.members)
				if (line != null && line.characters != null)
					for (character in line.characters)
					{
						if (character == null) continue;
						var idx = game.members.indexOf(character);
						if (idx >= 0 && idx < firstIdx) firstIdx = idx;
					}
		}
		if (game.dad != null)
		{
			var idx = game.members.indexOf(game.dad);
			if (idx >= 0 && idx < firstIdx) firstIdx = idx;
		}
		if (game.boyfriend != null)
		{
			var idx = game.members.indexOf(game.boyfriend);
			if (idx >= 0 && idx < firstIdx) firstIdx = idx;
		}
		if (game.gf != null)
		{
			var idx = game.members.indexOf(game.gf);
			if (idx >= 0 && idx < firstIdx) firstIdx = idx;
		}
		return firstIdx < game.members.length ? firstIdx : -1;
	}

	private function getLastCharacterIndex():Int
	{
		var game = PlayState.instance;
		if (game == null) return -1;
		var lastIdx = -1;
		if (game.strumLines != null && game.strumLines.members != null)
		{
			for (line in game.strumLines.members)
				if (line != null && line.characters != null)
					for (character in line.characters)
					{
						if (character == null) continue;
						var idx = game.members.indexOf(character);
						if (idx > lastIdx) lastIdx = idx;
					}
		}
		if (game.dad != null)
		{
			var idx = game.members.indexOf(game.dad);
			if (idx > lastIdx) lastIdx = idx;
		}
		if (game.boyfriend != null)
		{
			var idx = game.members.indexOf(game.boyfriend);
			if (idx > lastIdx) lastIdx = idx;
		}
		if (game.gf != null)
		{
			var idx = game.members.indexOf(game.gf);
			if (idx > lastIdx) lastIdx = idx;
		}
		return lastIdx;
	}

	private inline function isStageScript():Bool
	{
		if (rawLuaPath == null) return false;
		var normalized = StringTools.replace(rawLuaPath, "\\", "/").toLowerCase();
		return normalized.indexOf("/stages/") >= 0 || normalized.indexOf("stages/") == 0;
	}

	private function addLuaSprite(tag:String, ?inFront:Bool = false):Bool
	{
		var game = PlayState.instance;
		var sprite = getLuaSprite(tag);
		if (game == null || sprite == null) return false;
		if (sprite.cameras == null) sprite.cameras = [game.camGame];
		funkin.game.HudCamera.bypassDownscroll(sprite);

		if (cne.compat.PsychLuaSubState.instance != null)
		{
			if (cne.compat.PsychLuaSubState.instance.members.indexOf(sprite) < 0)
			{
				if (inFront)
					cne.compat.PsychLuaSubState.instance.add(sprite);
				else
					cne.compat.PsychLuaSubState.instance.insert(0, sprite);
			}
			return true;
		}

		if (game.members.indexOf(sprite) >= 0) return true;

		var tagLow = tag.toLowerCase();
		var imgLow = (sprite.graphic != null && sprite.graphic.key != null) ? sprite.graphic.key.toLowerCase() : "";
		var imgFile = haxe.io.Path.withoutDirectory(imgLow);
		var isFore = tagLow.indexOf("foreground") >= 0 || tagLow.indexOf("over") >= 0 || tagLow.indexOf("fg") >= 0 || tagLow.indexOf("front") >= 0
			|| imgFile.indexOf("foreground") >= 0 || imgFile.indexOf("over") >= 0 || imgFile.indexOf("fg") >= 0 || imgFile.indexOf("front") >= 0;
		var forceBack = isStageScript() && !isFore && (
			tagLow.indexOf("alley") >= 0 || tagLow.indexOf("bg") >= 0 || tagLow.indexOf("back") >= 0 || tagLow.indexOf("stage") >= 0 || tagLow.indexOf("wall") >= 0 || tagLow.indexOf("sky") >= 0
			|| imgFile.indexOf("alley") >= 0 || imgFile.indexOf("bg") >= 0 || imgFile.indexOf("back") >= 0 || imgFile.indexOf("stage") >= 0 || imgFile.indexOf("wall") >= 0 || imgFile.indexOf("sky") >= 0
		);

		if (inFront && !isGhostTrailTag(tag) && !forceBack)
			game.add(sprite);
		else
		{
			var firstCharacterIndex = getFirstCharacterIndex();
			if (firstCharacterIndex >= 0)
				game.insert(firstCharacterIndex, sprite);
			else
				game.add(sprite);
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
		if (Std.isOfType(object, FlxObject))
			funkin.game.HudCamera.bypassDownscroll(cast object);
		if (game.members.indexOf(object) < 0)
		{
			if (inFront && !isGhostTrailTag(tag))
				game.add(object);
			else
			{
				var firstCharacterIndex = getFirstCharacterIndex();
				if (firstCharacterIndex >= 0)
					game.insert(firstCharacterIndex, object);
				else
					game.insert(0, object);
			}
		}
		return true;
	}

	private function removeLuaSprite(tag:String, ?destroy:Dynamic = true):Bool
	{
		return removeLuaObject(tag, destroy);
	}

	private function removeLuaObject(tag:String, ?destroy:Dynamic = true):Bool
	{
		var shouldDestroy:Bool = destroy == null ? true : (destroy == true || Std.string(destroy).toLowerCase() == "true");
		var game = PlayState.instance;
		var object = luaObjects.get(tag);
		if (object == null) return false;
		if (game != null && game.members.indexOf(object) >= 0) game.remove(object, true);
		if (shouldDestroy)
		{
			luaObjects.remove(tag);
			FlxTween.cancelTweensOf(object);
			if (Std.isOfType(object, FlxSprite)) (cast object:FlxSprite).destroy();
		}
		return true;
	}

	private function addLuaAnimationByPrefix(tag:String, name:String, prefix:String, ?frameRate:Dynamic = 24, ?looped:Dynamic = true):Dynamic
	{
		var sprite = getLuaSprite(tag);
		if (sprite == null || sprite.frames == null) return psychLuaProfileName() == PsychLuaProfile.PSYCH_063 ? null : false;
		var fps:Float = 24;
		var loop:Bool = true;
		if (Std.isOfType(frameRate, Bool))
		{
			loop = frameRate == true;
			fps = 24;
		}
		else if (frameRate != null)
		{
			fps = Std.parseFloat(Std.string(frameRate));
			if (Math.isNaN(fps)) fps = 24;
			if (looped != null) loop = looped == true;
		}
		sprite.animation.addByPrefix(name, prefix, fps, loop);
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

		var char = getCharacter(tag);
		if (char != null)
		{
			var isIdle = (animation == "idle" || StringTools.startsWith(animation, "idle") || animation == "danceLeft" || animation == "danceRight");
			if (isIdle)
			{
				if (char.isHoldingNote()) return false;
				char.specialAnim = false;
				if ((animation == "idle" && char.idleSuffix != "" && char.hasAnim("idle" + char.idleSuffix)) || char.isDanceLeftDanceRight || !char.hasAnim("idle"))
				{
					char.dance();
					return true;
				}
				if (char.hasAnim(animation) || char.animation.exists(animation))
				{
					char.playAnim(animation, force, DANCE, reverse, startFrame != null ? startFrame : 0);
					return true;
				}
			}
			if (char.hasAnim(animation) || char.animation.exists(animation))
			{
				if (StringTools.startsWith(animation, "sing"))
					char.playAnim(animation, force, SING, reverse, startFrame != null ? startFrame : 0);
				else
					char.playAnim(animation, force, NONE, reverse, startFrame != null ? startFrame : 0);
				char.__lockAnimThisFrame = true;
				return true;
			}
			return false;
		}

		var sprite = getLuaSprite(tag);
		if (sprite == null) return false;

		if (Std.isOfType(sprite, Character))
		{
			var c:Character = cast sprite;
			var isIdle = (animation == "idle" || StringTools.startsWith(animation, "idle") || animation == "danceLeft" || animation == "danceRight");
			if (isIdle)
			{
				if (c.isHoldingNote()) return false;
				c.specialAnim = false;
				if ((animation == "idle" && c.idleSuffix != "" && c.hasAnim("idle" + c.idleSuffix)) || c.isDanceLeftDanceRight || !c.hasAnim("idle"))
				{
					c.dance();
					return true;
				}
				if (c.hasAnim(animation) || c.animation.exists(animation))
				{
					c.playAnim(animation, force, DANCE, reverse, startFrame != null ? startFrame : 0);
					return true;
				}
			}
			if (c.hasAnim(animation) || c.animation.exists(animation))
			{
				if (StringTools.startsWith(animation, "sing"))
					c.playAnim(animation, force, SING, reverse, startFrame != null ? startFrame : 0);
				else
					c.playAnim(animation, force, NONE, reverse, startFrame != null ? startFrame : 0);
				c.__lockAnimThisFrame = true;
				return true;
			}
			return false;
		}

		if (Std.isOfType(sprite, funkin.backend.FunkinSprite))
		{
			var fs:funkin.backend.FunkinSprite = cast sprite;
			if (fs.hasAnim(animation) || fs.animation.exists(animation))
			{
				fs.playAnim(animation, force, NONE, reverse, startFrame != null ? startFrame : 0);
				return true;
			}
			return false;
		}

		if (!sprite.animation.exists(animation)) return false;
		sprite.animation.play(animation, force, reverse, startFrame != null ? startFrame : 0);
		return true;
	}

	private function setLuaObjectCamera(tag:String, ?camera:String = "game"):Bool
	{
		var object = getLuaObject(tag);
		if (object == null) return false;
		var cam:flixel.FlxCamera = getLuaCamera(camera);
		if (Std.isOfType(object, flixel.FlxBasic))
		{
			(cast object:flixel.FlxBasic).cameras = cam != null ? [cam] : null;
			if (Std.isOfType(object, flixel.FlxObject))
				funkin.game.HudCamera.bypassDownscroll(cast object);
			return true;
		}
		try {
			Reflect.setProperty(object, "cameras", cam != null ? [cam] : null);
			if (Std.isOfType(object, flixel.FlxObject))
				funkin.game.HudCamera.bypassDownscroll(cast object);
			return true;
		} catch (_:Dynamic) {
			return false;
		}
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

	private function scaleLuaObject(tag:String, x:Float, ?y:Float, ?updateHitbox:Bool = true):Bool
	{
		var object = getLuaObject(tag);
		if (object == null) return false;
		var scale = Reflect.getProperty(object, "scale");
		if (scale == null) return false;
		Reflect.setProperty(scale, "x", x);
		Reflect.setProperty(scale, "y", y == null ? x : y);
		if (updateHitbox != false)
		{
			if (Std.isOfType(object, FlxSprite))
				(cast object:FlxSprite).updateHitbox();
			else if (Reflect.hasField(object, "updateHitbox"))
				Reflect.callMethod(object, Reflect.field(object, "updateHitbox"), []);
		}
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
		if (game == null) return false;
		var object:Dynamic = getLuaObject(tag);
		if (object == null && game.variables != null && game.variables.exists(tag))
		{
			var v = game.variables.get(tag);
			if (Std.isOfType(v, flixel.FlxBasic)) object = cast v;
		}
		if (object == null)
		{
			if (tag == "dadGroup" && game.dadGroup != null) object = game.dadGroup;
			else if (tag == "boyfriendGroup" && game.boyfriendGroup != null) object = game.boyfriendGroup;
			else if (tag == "gfGroup" && game.gfGroup != null) object = game.gfGroup;
			else if (tag == "noteGroup" && game.strumLines != null) object = game.strumLines;
		}
		if (object == null || !Std.isOfType(object, flixel.FlxBasic)) return false;
		var basic:flixel.FlxBasic = cast object;
		if ((tag == "dadGroup" || object == game.dadGroup) && game.dad != null && (game.dadGroup == null || game.members.indexOf(game.dadGroup) < 0))
			basic = game.dad;
		else if ((tag == "boyfriendGroup" || object == game.boyfriendGroup) && game.boyfriend != null && (game.boyfriendGroup == null || game.members.indexOf(game.boyfriendGroup) < 0))
			basic = game.boyfriend;
		else if ((tag == "gfGroup" || object == game.gfGroup) && game.gf != null && (game.gfGroup == null || game.members.indexOf(game.gfGroup) < 0))
			basic = game.gf;
		var current = game.members.indexOf(basic);
		if (current >= 0)
			game.remove(basic, true);
		var targetOrder = order;
		if (targetOrder < 0) targetOrder = 0;

		var firstCharacterIndex = getFirstCharacterIndex();
		var lastCharacterIndex = getLastCharacterIndex();

		if (isGhostTrailTag(tag))
		{
			if (firstCharacterIndex >= 0 && targetOrder > firstCharacterIndex)
				targetOrder = firstCharacterIndex;
		}
		else if (game.iconP1 != null && (tag.toLowerCase().indexOf("health") >= 0 || (Std.isOfType(basic, FlxSprite) && (cast basic:FlxSprite).graphic != null && (cast basic:FlxSprite).graphic.key != null && (cast basic:FlxSprite).graphic.key.toLowerCase().indexOf("what.png") >= 0)))
		{
			var iconIdx = game.members.indexOf(game.iconP1);
			if (iconIdx >= 0 && targetOrder >= iconIdx)
				targetOrder = iconIdx;
		}
		else if (isStageScript())
		{
			var lower = tag.toLowerCase();
			var imgLower = (Std.isOfType(basic, FlxSprite) && (cast basic:FlxSprite).graphic != null && (cast basic:FlxSprite).graphic.key != null) ? (cast basic:FlxSprite).graphic.key.toLowerCase() : "";
			var isFore = lower.indexOf("fore") >= 0 || lower.indexOf("fg") >= 0 || lower.indexOf("over") >= 0 || lower.indexOf("front") >= 0
				|| imgLower.indexOf("fore") >= 0 || imgLower.indexOf("fg") >= 0 || imgLower.indexOf("over") >= 0 || imgLower.indexOf("front") >= 0;
			var isAlleyBg = lower.indexOf("alley") >= 0 || imgLower.indexOf("alley") >= 0;
			if (isAlleyBg && !isFore)
			{
				if (firstCharacterIndex >= 0 && targetOrder >= firstCharacterIndex)
					targetOrder = firstCharacterIndex;
			}
		}

		if (tag == "scoreTxt" && game.missesTxt != null && game.accuracyTxt != null)
		{
			game.remove(game.missesTxt, true);
			game.remove(game.accuracyTxt, true);
			var insertPos = Std.int(Math.max(0, Math.min(targetOrder, game.members.length)));
			game.insert(insertPos, basic);
			game.insert(insertPos + 1, game.missesTxt);
			game.insert(insertPos + 2, game.accuracyTxt);
			return true;
		}

		game.insert(Std.int(Math.max(0, Math.min(targetOrder, game.members.length))), basic);
		return true;
	}

	private function getLuaObjectOrder(tag:String):Int
	{
		var game = PlayState.instance;
		if (game == null) return -1;
		var obj = getLuaObject(tag);
		if (obj == null && game.variables != null && game.variables.exists(tag))
		{
			var v = game.variables.get(tag);
			if (Std.isOfType(v, flixel.FlxBasic)) obj = cast v;
		}
		if (obj != null)
		{
			var idx = game.members.indexOf(obj);
			if (idx >= 0) return idx;
		}
		if (tag == "dadGroup" || tag == "dad")
		{
			if (game.dadGroup != null)
			{
				var idx = game.members.indexOf(game.dadGroup);
				if (idx >= 0) return idx;
			}
			if (game.dad != null)
			{
				var dadIdx = game.members.indexOf(game.dad);
				if (dadIdx >= 0) return dadIdx;
			}
			if (game.strumLines != null && game.strumLines.members.length > 0)
			{
				var idx = game.members.indexOf(game.strumLines);
				if (idx >= 0) return idx;
			}
		}
		if (tag == "boyfriendGroup" || tag == "boyfriend")
		{
			if (game.boyfriendGroup != null)
			{
				var idx = game.members.indexOf(game.boyfriendGroup);
				if (idx >= 0) return idx;
			}
			if (game.boyfriend != null)
			{
				var bfIdx = game.members.indexOf(game.boyfriend);
				if (bfIdx >= 0) return bfIdx;
			}
			if (game.strumLines != null && game.strumLines.members.length > 1)
			{
				var idx = game.members.indexOf(game.strumLines);
				if (idx >= 0) return idx;
			}
		}
		if (tag == "gfGroup" || tag == "gf")
		{
			if (game.gfGroup != null)
			{
				var idx = game.members.indexOf(game.gfGroup);
				if (idx >= 0) return idx;
			}
			if (game.gf != null)
			{
				var gfIdx = game.members.indexOf(game.gf);
				if (gfIdx >= 0) return gfIdx;
			}
		}
		if (tag == "noteGroup" && game.strumLines != null)
		{
			var idx = game.members.indexOf(game.strumLines);
			if (idx >= 0) return idx;
		}
		return -1;
	}

	private function loadLuaGraphic(tag:String, image:String, ?animated:Bool = false, ?frameWidth:Int = 0, ?frameHeight:Int = 0):Bool
	{
		var sprite = getOrCreateLuaSprite(tag);
		var path = Paths.image(image);
		if ((path == null || !openfl.utils.Assets.exists(path)) && !image.startsWith("characters/")) {
			var charPath = Paths.image('characters/$image');
			if (charPath != null && openfl.utils.Assets.exists(charPath)) path = charPath;
		}
		sprite.loadGraphic(path, animated, frameWidth, frameHeight);
		return true;
	}

	private function loadLuaFrames(tag:String, image:String, ?spriteType:String = "auto"):Bool
	{
		var sprite = getOrCreateLuaSprite(tag);
		var frames = Paths.getFrames(image);
		if (frames == null && !image.startsWith("characters/"))
			frames = Paths.getFrames('characters/$image');
		if (frames != null)
			sprite.frames = frames;
		return sprite.frames != null;
	}

	private function setLuaTextField(tag:String, field:String, value:Dynamic):Bool
	{
		var object = getLuaObject(tag);
		if (!Std.isOfType(object, FlxText)) return false;
		if (field == "text" && value == null) value = "";
		Reflect.setProperty(object, field, value);
		return true;
	}

	private function getLuaTextField(tag:String, field:String):Dynamic
	{
		var object = getLuaObject(tag);
		return Std.isOfType(object, FlxText) ? Reflect.getProperty(object, field) : null;
	}

	private function setLuaTextAlignment(tag:String, ?alignment:String = "left"):Bool
	{
		var object = getLuaObject(tag);
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
		if (Std.isOfType(value, Int)) {
			var intVal:Int = cast value;
			if (intVal == 0) return flixel.util.FlxColor.BLACK;
			if ((intVal & 0xFF000000) == 0 && intVal <= 0x00FFFFFF)
				intVal |= 0xFF000000;
			return cast intVal;
		}
		if (Std.isOfType(value, Float)) {
			var intVal:Int = Std.int(value);
			if (intVal == 0) return flixel.util.FlxColor.BLACK;
			if ((intVal & 0xFF000000) == 0 && intVal <= 0x00FFFFFF)
				intVal |= 0xFF000000;
			return cast intVal;
		}
		var color = StringTools.trim(Std.string(value));
		if (StringTools.startsWith(color, "#")) color = color.substr(1);
		if (StringTools.startsWith(color.toLowerCase(), "0x")) color = color.substr(2);
		if (color == "000000" || color == "0") return flixel.util.FlxColor.BLACK;
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
			case "playbackRate": return game != null ? game.playbackRate : 1.0;
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
			case "curBeat": return currentDispatchBeat >= 0 ? currentDispatchBeat : Conductor.curBeat;
			case "curStep": return currentDispatchStep >= 0 ? currentDispatchStep : Conductor.curStep;
			case "curSection" | "curMeasure": return currentDispatchSection >= 0 ? currentDispatchSection : Conductor.curMeasure;
			case "curDecBeat": return currentDispatchBeat >= 0 ? (currentDispatchStep >= 0 ? currentDispatchStep / 4.0 : currentDispatchBeat) : Conductor.curBeatFloat;
			case "curDecStep": return currentDispatchStep >= 0 ? currentDispatchStep : Conductor.curStepFloat;
			case "curDecSection": return currentDispatchSection >= 0 ? currentDispatchSection : Conductor.curMeasureFloat;
			case "songPosition" | "songPos": return Conductor.songPosition;
			case "songLength": return FlxG.sound.music != null ? FlxG.sound.music.length : 0;
			case "songName" | "curSong": return game != null ? (game.curSong != null ? game.curSong : (game.rawSongName != null ? game.rawSongName : (PlayState.SONG != null && PlayState.SONG.meta != null ? PlayState.SONG.meta.name : ""))) : (PlayState.SONG != null && PlayState.SONG.meta != null ? PlayState.SONG.meta.name : "");
			case "bpm" | "curBpm": return Conductor.bpm;
			case "crochet": return Conductor.crochet;
			case "stepCrochet": return Conductor.stepCrochet;
			case "score" | "songScore": return game != null ? game.songScore : 0;
			case "misses" | "songMisses": return game != null ? game.misses : 0;
			case "hits" | "songHits": return game != null ? game.ratingNum : 0;
			case "ratingName": return game != null && game.curRating != null ? game.curRating.rating : "?";
			case "ratingFC": return game != null ? (game.misses == 0 ? (game.combo > 0 ? "FC" : "Clear") : (game.misses < 10 ? "SDCB" : "Clear")) : "";
			case "ratingPercent": return game != null ? game.accuracy : 0.0;
			case "combo": return game != null ? game.combo : 0;
			case "downscroll" | "downScroll": return game != null ? game.downscroll : false;
			case "healthBar.y":
				var isDs = (game != null && game.downscroll) || funkin.options.Options.downscroll;
				return isDs ? (flixel.FlxG.height * 0.11) : (game != null && game.healthBar != null ? game.healthBar.y : 648);
			case "healthBarBG.y":
				var isDs = (game != null && game.downscroll) || funkin.options.Options.downscroll;
				return isDs ? (flixel.FlxG.height * 0.11 - 4) : (game != null && game.healthBarBG != null ? game.healthBarBG.y : 644);
			case "StrumY" | "strumY":
				if (psychVariables.exists(path)) return psychVariables.get(path);
				var currentY:Float = 50;
				if (game != null && game.strumLines != null && game.strumLines.members != null)
				{
					for (line in game.strumLines.members)
						if (line != null && line.members != null)
							for (strum in line.members)
								if (strum != null) { currentY = strum.y; break; }
				}
				return currentY;
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
			case "boyfriend.cameraPosition[0]" | "bf.cameraPosition[0]":
				var c = getCharacter("boyfriend");
				return c != null && c.cameraOffset != null ? c.cameraOffset.x : 0.0;
			case "boyfriend.cameraPosition[1]" | "bf.cameraPosition[1]":
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
		if (root == null && game != null && game.variables != null && game.variables.exists(rootName))
			root = game.variables.get(rootName);
		if (root == null) root = getStageSprite(rootName);
		if (root == null && ["notes", "unspawnNotes", "strumLineNotes", "playerStrums", "opponentStrums", "eventNotes", "grpNoteSplashes"].contains(rootName))
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
				case "timeBar": game.timeBar;
				case "timeBarBG" | "timeBG": game.timeBarBG != null ? game.timeBarBG : (cast game.timeBar);
				case "timeTxt": game.timeTxt;
				case "dad": game.dad;
				case "boyfriend" | "bf": game.boyfriend;
				case "gf" | "girlfriend": game.gf;
				case "dadGroup": game.dadGroup != null ? (cast game.dadGroup:Dynamic) : (cast game.dad:Dynamic);
				case "boyfriendGroup": game.boyfriendGroup != null ? (cast game.boyfriendGroup:Dynamic) : (cast game.boyfriend:Dynamic);
				case "gfGroup": game.gfGroup != null ? (cast game.gfGroup:Dynamic) : (cast game.gf:Dynamic);
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
					case "scaleX": return cam.scaleX;
					case "scaleY": return cam.scaleY;
					case "totalScaleX": return cam.totalScaleX;
					case "totalScaleY": return cam.totalScaleY;
					case "initialZoom": return cam.initialZoom;
					case "_fxShakeIntensity": return @:privateAccess cam._fxShakeIntensity;
					case "_fxShakeDuration": return @:privateAccess cam._fxShakeDuration;
					case "_flashOffset": return @:privateAccess cam._flashOffset;
					case "canvas": return cam.canvas;
					case "flashSprite": return cam.flashSprite;
					case "targetOffset": return cam.targetOffset;
					case "targetOffset.x": return cam.targetOffset.x;
					case "targetOffset.y": return cam.targetOffset.y;
					case "scroll": return cam.scroll;
					case "scroll.x": return cam.scroll.x;
					case "scroll.y": return cam.scroll.y;
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
				if (game != null)
				{
					game.skipCountdown = b;
					if (b && game.startedCountdown && game.startingSong)
					{
						if (game.startTimer != null)
						{
							game.startTimer.cancel();
							game.startTimer.destroy();
							game.startTimer = null;
						}
						game.introLength = 0;
						Conductor.songPosition = 0;
					}
				}
				psychVariables.set(path, b);
				if (game != null && game.variables != null) game.variables.set(path, b);
				return value;
			case "score" | "songScore":
				if (game != null) game.songScore = Std.int(Std.parseFloat(Std.string(value)));
				return value;
			case "misses" | "songMisses":
				if (game != null) game.misses = Std.int(Std.parseFloat(Std.string(value)));
				return value;
			case "hits" | "songHits":
				if (game != null) game.ratingNum = Std.int(Std.parseFloat(Std.string(value)));
				return value;
			case "health":
				if (game != null) game.health = Std.parseFloat(Std.string(value));
				return value;
			case "playbackRate":
				var pr = Std.parseFloat(Std.string(value));
				if (Math.isNaN(pr) || pr <= 0) pr = 1.0;
				if (game != null) game.playbackRate = pr;
				psychVariables.set("playbackRate", pr);
				set("playbackRate", pr);
				return pr;
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
					if (FlxG.camera.target == null || (game != null && FlxG.camera.target == game.camFollowPos))
						FlxG.camera.scroll.x = v - FlxG.camera.width * 0.5;
				}
				return value;
			case "camFollowPos.y":
				var v = Std.parseFloat(Std.string(value));
				if (!Math.isNaN(v)) {
					if (game != null && game.camFollowPos != null) game.camFollowPos.y = v;
					if (FlxG.camera.target == null || (game != null && FlxG.camera.target == game.camFollowPos))
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
			case "boyfriend.cameraPosition[0]" | "bf.cameraPosition[0]":
				var c = getCharacter("boyfriend");
				if (c != null && c.cameraOffset != null) c.cameraOffset.x = Std.parseFloat(Std.string(value));
				return value;
			case "boyfriend.cameraPosition[1]" | "bf.cameraPosition[1]":
				var c = getCharacter("boyfriend");
				if (c != null && c.cameraOffset != null) c.cameraOffset.y = Std.parseFloat(Std.string(value));
				return value;
			case "gf.cameraPosition[0]":
				var c = getCharacter("gf");
				if (c != null && c.cameraOffset != null) c.cameraOffset.x = Std.parseFloat(Std.string(value));
				return value;
			case "gf.cameraPosition[1]":
				var c = getCharacter("gf");
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
		if (root == null && game != null && game.variables != null && game.variables.exists(rootName))
			root = game.variables.get(rootName);
		if (root == null) root = getStageSprite(rootName);
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
				case "timeBar": game.timeBar;
				case "timeBarBG" | "timeBG": game.timeBarBG != null ? game.timeBarBG : (cast game.timeBar);
				case "timeTxt": game.timeTxt;
				case "dad": game.dad;
				case "boyfriend" | "bf": game.boyfriend;
				case "gf" | "girlfriend": game.gf;
				case "dadGroup": game.dadGroup != null ? (cast game.dadGroup:Dynamic) : (cast game.dad:Dynamic);
				case "boyfriendGroup": game.boyfriendGroup != null ? (cast game.boyfriendGroup:Dynamic) : (cast game.boyfriend:Dynamic);
				case "gfGroup": game.gfGroup != null ? (cast game.gfGroup:Dynamic) : (cast game.gf:Dynamic);
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
					case "zoom":
						var z = Std.parseFloat(Std.string(value));
						if (Math.isNaN(z) || z < 0.05) z = 0.05;
						cam.zoom = z;
						return value;
					case "alpha": cam.alpha = Std.parseFloat(Std.string(value)); return value;
					case "angle": cam.angle = Std.parseFloat(Std.string(value)); return value;
					case "visible": cam.visible = value == true; return value;
					case "scaleX": @:privateAccess cam.scaleX = Std.parseFloat(Std.string(value)); return value;
					case "scaleY": @:privateAccess cam.scaleY = Std.parseFloat(Std.string(value)); return value;
					case "initialZoom": @:privateAccess cam.initialZoom = Std.parseFloat(Std.string(value)); return value;
					case "_fxShakeIntensity": @:privateAccess cam._fxShakeIntensity = Std.parseFloat(Std.string(value)); return value;
					case "_fxShakeDuration": @:privateAccess cam._fxShakeDuration = Std.parseFloat(Std.string(value)); return value;
					case "targetOffset.x": cam.targetOffset.x = Std.parseFloat(Std.string(value)); return value;
					case "targetOffset.y": cam.targetOffset.y = Std.parseFloat(Std.string(value)); return value;
					case "scroll.x": cam.scroll.x = Std.parseFloat(Std.string(value)); return value;
					case "scroll.y": cam.scroll.y = Std.parseFloat(Std.string(value)); return value;
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
					case "x":
						obj.x = Std.parseFloat(Std.string(value));
						if (Std.isOfType(obj, funkin.game.HealthIcon))
							funkin.game.HudCamera.bypassX(obj);
						return value;
					case "y":
						obj.y = Std.parseFloat(Std.string(value));
						if (!Std.isOfType(obj, funkin.game.Strum) && !Std.isOfType(obj, funkin.game.Note))
							funkin.game.HudCamera.bypassDownscroll(obj);
						if (game != null && obj == game.scoreTxt)
						{
							game.customScoreTxtY = true;
							if (game.missesTxt != null) { game.missesTxt.y = obj.y; funkin.game.HudCamera.bypassDownscroll(game.missesTxt); }
							if (game.accuracyTxt != null) { game.accuracyTxt.y = obj.y; funkin.game.HudCamera.bypassDownscroll(game.accuracyTxt); }
						}
						if (game != null && (obj == game.iconP1 || obj == game.iconP2))
						{
							var isDs = (game != null && game.downscroll) || funkin.options.Options.downscroll;
							if (isDs)
							{
								var otherIcon = (obj == game.iconP1) ? game.iconP2 : game.iconP1;
								if (otherIcon != null && (!funkin.game.HudCamera.shouldBypassDownscroll(otherIcon) || Math.abs(otherIcon.y - obj.y) > 300))
								{
									otherIcon.y = obj.y;
									funkin.game.HudCamera.bypassDownscroll(otherIcon);
								}
							}
						}
						return value;
					case "visible":
						obj.visible = value == true;
						if (game != null && obj == game.scoreTxt)
						{
							if (game.missesTxt != null) game.missesTxt.visible = obj.visible;
							if (game.accuracyTxt != null) game.accuracyTxt.visible = obj.visible;
						}
						if (game != null && obj == game.healthBar && game.healthBarBG != null)
							game.healthBarBG.visible = obj.visible;
						return value;
					case "alpha" if (Std.isOfType(root, FlxSprite)):
						var a = Std.parseFloat(Std.string(value));
						(cast root:FlxSprite).alpha = a;
						if (game != null && root == game.scoreTxt)
						{
							if (game.missesTxt != null) game.missesTxt.alpha = a;
							if (game.accuracyTxt != null) game.accuracyTxt.alpha = a;
						}
						if (game != null && root == game.healthBar && game.healthBarBG != null)
							game.healthBarBG.alpha = a;
						return value;
					case "color" if (Std.isOfType(root, FlxSprite)):
						var c = parseLuaColor(value);
						var spr:FlxSprite = cast root;
						spr.color = c;
						spr.dirty = true;
						if (spr.colorTransform != null)
						{
							spr.colorTransform.redMultiplier = c.redFloat;
							spr.colorTransform.greenMultiplier = c.greenFloat;
							spr.colorTransform.blueMultiplier = c.blueFloat;
						}
						@:privateAccess spr.useColorTransform = (c != flixel.util.FlxColor.WHITE || spr.alpha != 1);
						if (game != null && root == game.scoreTxt)
						{
							if (game.missesTxt != null) game.missesTxt.color = c;
							if (game.accuracyTxt != null) game.accuracyTxt.color = c;
						}
						return value;
					case "angle" if (Std.isOfType(root, FlxSprite)):
						var ang = Std.parseFloat(Std.string(value));
						(cast root:FlxSprite).angle = ang;
						if (game != null && root == game.scoreTxt)
						{
							if (game.missesTxt != null) game.missesTxt.angle = ang;
							if (game.accuracyTxt != null) game.accuracyTxt.angle = ang;
						}
						return value;
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
			case "objects.VideoSprite" | "VideoSprite": cne.compat.PsychVideoSprite;
			default: Type.resolveClass(className);
		}
	}

	private function getCharacter(characterName:String):Character
	{
		var game = PlayState.instance;
		if (game == null || characterName == null) return null;
		var target = game.getPsychTargetCharacter(characterName);
		if (target != null) return target;
		var obj = readPath(game, characterName);
		if (Std.isOfType(obj, Character)) return cast obj;
		return null;
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
				game.ensureStrumsAndNotesGenerated();
				if (game.__psychCachedSpawnedNotes == null || game.__psychCachedUnspawnNotes == null
					|| game.__psychNotesCachePos != Conductor.songPosition || game.__psychNotesCacheSpeed != game.scrollSpeed)
				{
					var spawnedByStrumline:Array<Array<Dynamic>> = [];
					var unspawnByStrumline:Array<Array<Dynamic>> = [];
					var preCountdown = !game.startedCountdown && Conductor.songPosition <= 0;
					var songSpeed:Float = game.scrollSpeed <= 0 ? 1 : game.scrollSpeed;
					for (line in game.strumLines.members)
					{
						if (line == null || line.notes == null || line.notes.members == null) continue;
						var lineSpawned:Array<Dynamic> = [];
						var lineUnspawn:Array<Dynamic> = [];
						for (note in line.notes.members)
						{
							if (note == null || !note.exists || !note.alive) continue;
							var spawned = false;
							if (!preCountdown)
							{
								var noteSpeed:Float = note.multSpeed;
								spawned = PsychHookMap.isPsychNoteSpawned(note.strumTime, Conductor.songPosition, songSpeed, noteSpeed);
							}
							if (spawned) lineSpawned.push(note);
							else lineUnspawn.push(note);
						}
						spawnedByStrumline.push(lineSpawned);
						unspawnByStrumline.push(lineUnspawn);
					}
					game.__psychCachedSpawnedNotes = PsychHookMap.combinePsychNotes(spawnedByStrumline, true);
					game.__psychCachedUnspawnNotes = PsychHookMap.combinePsychNotes(unspawnByStrumline, false);
					game.__psychNotesCachePos = Conductor.songPosition;
					game.__psychNotesCacheSpeed = game.scrollSpeed;
				}
				return groupName == "notes" ? game.__psychCachedSpawnedNotes : game.__psychCachedUnspawnNotes;
			case "playerStrums":
				game.ensureStrumsAndNotesGenerated();
				var pl = game.playerStrums != null ? game.playerStrums : (game.strumLines.members != null && game.strumLines.members.length > 1 ? game.strumLines.members[1] : null);
				return pl != null && pl.members != null ? [for (s in pl.members) if (s != null) s] : [];
			case "opponentStrums":
				game.ensureStrumsAndNotesGenerated();
				var opp = game.cpuStrums != null ? game.cpuStrums : (game.strumLines.members != null && game.strumLines.members.length > 0 ? game.strumLines.members[0] : null);
				return opp != null && opp.members != null ? [for (s in opp.members) if (s != null) s] : [];
			case "strumLineNotes":
				game.ensureStrumsAndNotesGenerated();
				var strums:Array<Dynamic> = [];
				var opp = game.cpuStrums != null ? game.cpuStrums : (game.strumLines.members != null && game.strumLines.members.length > 0 ? game.strumLines.members[0] : null);
				var pl = game.playerStrums != null ? game.playerStrums : (game.strumLines.members != null && game.strumLines.members.length > 1 ? game.strumLines.members[1] : null);
				if (opp != null && opp.members != null)
					for (s in opp.members) if (s != null) strums.push(s);
				if (pl != null && pl.members != null)
					for (s in pl.members) if (s != null) strums.push(s);
				if (game.strumLines != null && game.strumLines.members != null)
				{
					for (line in game.strumLines.members)
					{
						if (line == null || line == opp || line == pl || line.members == null) continue;
						for (s in line.members) if (s != null) strums.push(s);
					}
				}
				return strums;
			case "grpNoteSplashes":
				if (game.splashHandler != null && game.splashHandler.members != null)
					return [for (s in game.splashHandler.members) if (s != null) s];
				return [];
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
		var args = parameters == null ? [] : parameters;
		var prevDispatchStep = currentDispatchStep;
		var prevDispatchBeat = currentDispatchBeat;
		var prevDispatchSection = currentDispatchSection;

		if (funcName == "stepHit" && args.length > 0 && args[0] != null)
		{
			currentDispatchStep = Std.int(args[0]);
			currentDispatchBeat = Math.floor(currentDispatchStep / 4);
			currentDispatchSection = Math.floor(currentDispatchStep / 16);
		}
		else if (funcName == "beatHit" && args.length > 0 && args[0] != null)
		{
			currentDispatchBeat = Std.int(args[0]);
			currentDispatchStep = currentDispatchBeat * 4;
			currentDispatchSection = Math.floor(currentDispatchBeat / 4);
		}
		else if ((funcName == "measureHit" || funcName == "sectionHit") && args.length > 0 && args[0] != null)
		{
			currentDispatchSection = Std.int(args[0]);
			currentDispatchBeat = currentDispatchSection * 4;
			currentDispatchStep = currentDispatchBeat * 4;
		}

		var restoreDispatch = function() {
			currentDispatchStep = prevDispatchStep;
			currentDispatchBeat = prevDispatchBeat;
			currentDispatchSection = prevDispatchSection;
		};

		var res:Dynamic = null;
		try {
			res = dispatchPsychCall(funcName, args);
		} catch (e:Dynamic) {
			restoreDispatch();
			throw e;
		}
		restoreDispatch();
		return res;
	}

	private function dispatchPsychCall(funcName:String, args:Array<Dynamic>):Dynamic
	{
		var psychGlobalsUpdated = funcName == "update" && dispatchPsychSpawnCallbacks();
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
			var hitHook = PsychHookMap.getHooks(funcName)[0];
			if (!hasLuaFunction(hitHook)) return null;
			var psychArgs = getPsychHitArgs(args);
			if (psychArgs == null) return null;

			updatePsychGlobals();
			var hitResult = callLua(hitHook, psychArgs, true);
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
			if (!hasLuaFunction(hook)) continue;
			if (!psychGlobalsUpdated)
			{
				updatePsychGlobals();
				psychGlobalsUpdated = true;
			}
			var hookResult = callLua(hook, args, true);
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

		var normalizedPath = StringTools.replace(rawLuaPath, "\\", "/").toLowerCase();
		var customEventsIdx = normalizedPath.indexOf("/custom_events/");
		if (customEventsIdx >= 0)
		{
			var eventFile = normalizedPath.substr(customEventsIdx + "/custom_events/".length);
			var dotIdx = eventFile.lastIndexOf(".");
			if (dotIdx >= 0) eventFile = eventFile.substr(0, dotIdx);
			var targetEventName = StringTools.replace(event.event.name, "-", " ").toLowerCase();
			var cleanEventFile = StringTools.replace(eventFile, "-", " ").toLowerCase();
			if (StringTools.trim(targetEventName) != StringTools.trim(cleanEventFile) && StringTools.trim(event.event.name.toLowerCase()) != StringTools.trim(eventFile.toLowerCase()))
				return null;
		}

		var params = event.event.params == null ? [] : event.event.params;
		var value1:Dynamic = params.length > 0 && params[0] != null ? params[0] : "";
		var value2:Dynamic = params.length > 1 && params[1] != null ? params[1] : "";

		// Sanitize values where charter might have included accidental spacing in numbers (e.g. "6 0")
		if (Std.isOfType(value1, String))
		{
			var str:String = cast value1;
			var compact = StringTools.replace(str, " ", "");
			if (compact.length > 0 && !Math.isNaN(Std.parseFloat(compact)) && !StringTools.contains(str, ","))
				value1 = compact;
		}
		if (Std.isOfType(value2, String))
		{
			var str:String = cast value2;
			var compact = StringTools.replace(str, " ", "");
			if (compact.length > 0 && !Math.isNaN(Std.parseFloat(compact)) && !StringTools.contains(str, ","))
				value2 = compact;
		}

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

	public var lastPsychCameraTarget:String = null;

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
		if (target == lastPsychCameraTarget) return null;
		lastPsychCameraTarget = target;
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
		var pressHook = postUpdate ? "onKeyPress" : "onKeyPressPre";
		var releaseHook = postUpdate ? "onKeyRelease" : "onKeyReleasePre";
		var psychGlobalsUpdated = false;
		if (event.justPressed != null)
			for (lane in 0...laneCount)
				if (lane < event.justPressed.length && event.justPressed[lane] && hasLuaFunction(pressHook))
				{
					psychGlobalsUpdated = true;
					break;
				}
		if (!psychGlobalsUpdated && event.justReleased != null)
			for (lane in 0...laneCount)
				if (lane < event.justReleased.length && event.justReleased[lane] && hasLuaFunction(releaseHook))
				{
					psychGlobalsUpdated = true;
					break;
				}
		if (psychGlobalsUpdated) updatePsychGlobals();
		var blockedAnyLane = false;
		for (lane in 0...laneCount)
		{
			if (event.justPressed != null && lane < event.justPressed.length && event.justPressed[lane])
			{
				if (postUpdate) callLua("onKeyPress", [lane], psychGlobalsUpdated);
				else
				{
					var result = callLua("onKeyPressPre", [lane], psychGlobalsUpdated);
					if (result == stopValue)
						blockedAnyLane = PsychHookMap.blockInputLane(event.psychBlockedPress, event.psychBlockedRelease, lane, true) || blockedAnyLane;
					else if (PsychCallbackResult.includeResult(result, continueValues) && event.psychBlockedPress != null && lane < event.psychBlockedPress.length)
						event.psychBlockedPress[lane] = false;
				}
			}
			if (event.justReleased != null && lane < event.justReleased.length && event.justReleased[lane])
			{
				if (postUpdate) callLua("onKeyRelease", [lane], psychGlobalsUpdated);
				else
				{
					var result = callLua("onKeyReleasePre", [lane], psychGlobalsUpdated);
					if (result == stopValue)
						blockedAnyLane = PsychHookMap.blockInputLane(event.psychBlockedPress, event.psychBlockedRelease, lane, false) || blockedAnyLane;
					else if (PsychCallbackResult.includeResult(result, continueValues) && event.psychBlockedRelease != null && lane < event.psychBlockedRelease.length)
						event.psychBlockedRelease[lane] = false;
				}
			}
		}
		return blockedAnyLane ? stopValue : null;
	}

	private function dispatchPsychSpawnCallbacks():Bool
	{
		if (!hasLuaFunction("onSpawnNote")) return false;
		var batch = PsychHookMap.collectSpawnNoteBatch(spawnedPsychNotes, true, () -> getPsychGroupMembers("notes"));
		if (batch == null || batch.newlySpawned.length == 0) return false;
		updatePsychGlobals();
		for (note in batch.newlySpawned)
		{
			var noteType:String = note.noteType == null ? "" : note.noteType;
			callLua("onSpawnNote", PsychHookMap.makeSpawnNoteArguments(psychLuaProfileName(), PsychHookMap.indexOfNote(batch.current, note), note.noteData, noteType, note.isSustainNote, note.strumTime), true);
		}
		return true;
	}

	private function hasLuaFunction(functionName:String):Bool
	{
		if (lua == null || scriptClosed || functionName == null) return false;
		var originalTop = Lua.gettop(lua);
		Lua.getglobal(lua, functionName);
		var found = Lua.isfunction(lua, -1) != 0;
		Lua.settop(lua, originalTop);
		return found;
	}

	private function callLua(functionName:String, args:Array<Dynamic>, ?psychGlobalsAlreadyUpdated:Bool = false):Dynamic
	{
		if (lua == null || scriptClosed) return null;
		var originalTop = Lua.gettop(lua);
		Lua.getglobal(lua, functionName);
		if (Lua.isfunction(lua, -1) == 0)
		{
			Lua.settop(lua, originalTop);
			return null;
		}
		if (!psychGlobalsAlreadyUpdated) updatePsychGlobals();
		syncPsychStrumY();

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
			var errKey = '${functionName}:${message}';
			var count = (callbackErrorCounts.exists(errKey) ? callbackErrorCounts.get(errKey) : 0) + 1;
			callbackErrorCounts.set(errKey, count);
			if (count <= 2)
				error('Lua callback ${functionName} failed: ${message}');
			else if (count == 3)
				error('Lua callback ${functionName} failed: ${message} (further identical errors suppressed)');
			return null;
		}

		var result = Convert.fromLua(lua, -1);
		Lua.settop(lua, originalTop);
		return result;
	}

	private function syncPsychStrumY():Void
	{
		var game = PlayState.instance;
		if (game == null) return;

		Lua.getglobal(lua, "StrumY");
		var isStrumYNil = Lua.type(lua, -1) == Lua.LUA_TNIL;
		Lua.pop(lua, 1);

		Lua.getglobal(lua, "strumY");
		var isLowerStrumYNil = Lua.type(lua, -1) == Lua.LUA_TNIL;
		Lua.pop(lua, 1);

		if (isStrumYNil || isLowerStrumYNil)
		{
			var currentY:Float = 50;
			if (game.strumLines != null && game.strumLines.members != null)
			{
				for (line in game.strumLines.members)
				{
					if (line == null || line.members == null) continue;
					for (strum in line.members)
					{
						if (strum != null)
						{
							currentY = strum.y;
							break;
						}
					}
				}
			}
			if (isStrumYNil)
			{
				setNumberConstant("StrumY", currentY);
				set("StrumY", currentY);
				psychVariables.set("StrumY", currentY);
			}
			if (isLowerStrumYNil)
			{
				setNumberConstant("strumY", currentY);
				set("strumY", currentY);
				psychVariables.set("strumY", currentY);
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
		if (!hasLuaFunction("noteMiss")) return null;
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
		if (variable == "game" || variable == "this" || variable == "PlayState" || Std.isOfType(value, funkin.game.PlayState))
		{
			if (luaHScript != null) luaHScript.set(variable, value);
			return;
		}
		var unsupportedPath = findUnsupportedLuaValue(value, variable, 0, new ObjectMap<Dynamic, Bool>());
		if (unsupportedPath != null)
		{
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
		var timerKeys = [for (k in luaTimers.keys()) k];
		for (tag in timerKeys) cancelLuaTimer(tag);
		luaTimers.clear();
		var tweenKeys = [for (k in luaTweens.keys()) k];
		for (tag in tweenKeys) cancelLuaTween(tag);
		luaTweens.clear();
		var soundKeys = [for (k in luaSounds.keys()) k];
		for (tag in soundKeys) stopLuaSound(tag);
		luaSounds.clear();
		lastPsychCameraTarget = null;
		if (game == null) activeLongNoteTweens.clear();
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
