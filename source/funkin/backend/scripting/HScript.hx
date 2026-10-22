package funkin.backend.scripting;

import hscript.*;
import hscript.Expr.Error;
import hscript.Parser;
import openfl.Assets;

class HScript extends Script {
	private static inline var RUN_HAXE_EXPR_CACHE_LIMIT:Int = 64;

	public var interp:Interp;
	public var parser:Parser;
	public var expr:Expr;
	public var code:String = null;
	public var lastExecutionResult:Dynamic;
	private var runHaxeExprCache:haxe.ds.StringMap<Expr> = new haxe.ds.StringMap<Expr>();
	private var runHaxeExprCacheOrder:Array<String> = [];
	public var runHaxeCodeCacheHits(default, null):Int = 0;
	public var runHaxeCodeCacheMisses(default, null):Int = 0;
	//public var folderlessPath:String;
	var __importedPaths:Map<String, Bool>;

	public static function initParser() {
		var parser = new Parser();
		parser.allowJSON = parser.allowMetadata = parser.allowTypes = true;
		parser.preprocessorValues = Script.getDefaultPreprocessors();
		return parser;
	}

	/** Pool of idle parsers, reused across script instances to avoid repeated Parser construction. **/
	private static var __parserPool:Array<Parser> = [];

	private static function getParser():Parser {
		var parser = __parserPool.pop();
		if (parser == null)
			return initParser();
		parser.line = 1; // reusing a parser only requires resetting `line`; all other vars get reset on parse
		return parser;
	}

	private static function returnParser(parser:Parser) {
		if (parser != null)
			__parserPool.push(parser);
	}

	public override function onCreate(path:String) {
		super.onCreate(path);

		interp = new Interp();

		try {
			if(Assets.exists(rawPath)) code = Assets.getText(rawPath);
		} catch(e) Logs.error('Error while reading $path: ${Std.string(e)}');

		parser = getParser();
		//folderlessPath = Path.directory(path);
		__importedPaths = [path => true];

		interp.errorHandler = _errorHandler;
		interp.warnHandler = _warnHandler;
		interp.importFailedCallback = importFailedCallback;
		interp.staticVariables = Script.staticVariables;
		interp.allowStaticVariables = interp.allowPublicVariables = true;

		interp.variables.set("trace", Reflect.makeVarArgs((args) -> {
			var v:String = Std.string(args.shift());
			for (a in args) v += ", " + Std.string(a);
			this.trace(v);
		}));

		interp.variables.set("setVar", function(name:String, value:Dynamic):Dynamic {
			if (funkin.game.PlayState.instance != null && funkin.game.PlayState.instance.variables != null)
				funkin.game.PlayState.instance.variables.set(name, value);
			funkin.backend.scripting.LuaScript.setPsychVariable(name, value);
			return value;
		});
		interp.variables.set("getVar", function(name:String):Dynamic {
			if (funkin.game.PlayState.instance != null && funkin.game.PlayState.instance.variables != null && funkin.game.PlayState.instance.variables.exists(name))
				return funkin.game.PlayState.instance.variables.get(name);
			return funkin.backend.scripting.LuaScript.getPsychVariable(name);
		});
		interp.variables.set("removeVar", function(name:String):Bool {
			var r1 = (funkin.game.PlayState.instance != null && funkin.game.PlayState.instance.variables != null) ? funkin.game.PlayState.instance.variables.remove(name) : false;
			var r2 = funkin.backend.scripting.LuaScript.removePsychVariable(name);
			return r1 || r2;
		});
		interp.variables.set("debugPrint", Reflect.makeVarArgs((args) -> {
			var parts:Array<String> = [];
			for (a in args) if (a != null) parts.push(Std.string(a));
			this.trace(parts.join(' '));
		}));
		interp.variables.set("getLuaObject", function(tag:String):Dynamic {
			#if LUA_ALLOWED
			return funkin.backend.scripting.LuaScript.resolveSharedLuaObject(tag);
			#else
			return (funkin.game.PlayState.instance != null && funkin.game.PlayState.instance.variables != null) ? funkin.game.PlayState.instance.variables.get(tag) : null;
			#end
		});
		interp.variables.set("createGlobalCallback", function(name:String, func:Dynamic):Void {
			#if LUA_ALLOWED
			funkin.backend.scripting.LuaScript.registerGlobalCallback(name, func);
			#end
		});
		interp.variables.set("ClientPrefs", funkin.options.Options);
		interp.variables.set("FlxCamera", funkin.game.HudCamera);
		#if sys
		dbe.compatibility.rea.REARuntimeBridge.injectHScriptGlobals(this);
		#end

		#if GLOBAL_SCRIPT
		funkin.backend.scripting.GlobalScript.call("onScriptCreated", [this, "hscript"]);
		#end
		loadFromString(code);
	}

	public override function loadFromString(code:String) {
		if (code != null) {
			code = StringTools.replace(code, "import flixel.FlxCamera;", "import funkin.game.HudCamera as FlxCamera;");
			code = StringTools.replace(code, "import flixel.FlxCamera\n", "import funkin.game.HudCamera as FlxCamera\n");
			code = StringTools.replace(code, "import flixel.FlxCamera\r\n", "import funkin.game.HudCamera as FlxCamera\r\n");
		}
		this.code = code;
		this.expr = null;
		if (parser != null) parser.line = 1;
		try {
			if (code != null && code.length > 0)
				expr = parser.parseString(code, fileName);
		} catch(e:Error) {
			_errorHandler(e);
		} catch(e) {
			_errorHandler(new Error(ECustom(e.toString()), 0, 0, fileName, 0));
		}

		return this;
	}

	private function importFailedCallback(cl:Array<String>, ?asName:String):Bool {
		#if sys
		if (dbe.compatibility.rea.REARuntimeBridge.resolveHScriptImport(interp, cl, asName)) {
			return true;
		}
		#end
		var full = cl.join(".");
		var targetVar = asName != null ? asName : cl[cl.length - 1];
		switch (full) {
			case "flixel.FlxCamera" | "FlxCamera":
				interp.variables.set(targetVar, funkin.game.HudCamera);
				return true;
			case "options.OptionsState" | "OptionsState":
				interp.variables.set(targetVar, funkin.options.OptionsMenu);
				return true;
			case "backend.MusicBeatState" | "MusicBeatState":
				interp.variables.set(targetVar, funkin.backend.MusicBeatState);
				return true;
			case "backend.Paths" | "Paths":
				interp.variables.set(targetVar, funkin.backend.assets.Paths);
				return true;
			case "backend.ClientPrefs" | "ClientPrefs":
				interp.variables.set(targetVar, funkin.options.Options);
				return true;
			case "backend.Conductor" | "Conductor":
				interp.variables.set(targetVar, funkin.backend.system.Conductor);
				return true;
			case "backend.CoolUtil" | "CoolUtil":
				interp.variables.set(targetVar, funkin.backend.utils.CoolUtil);
				return true;
			case "kade.hex.chart.Scene" | "Scene":
				interp.variables.set(targetVar, kade.hex.chart.Scene);
				return true;
			case "funkin.play.song.Song" | "Song":
				interp.variables.set(targetVar, funkin.play.song.Song);
				return true;
			case "funkin.modding.module.ModuleHandler" | "ModuleHandler":
				interp.variables.set(targetVar, funkin.modding.module.ModuleHandler);
				return true;
			case "psychlua.LuaUtils" | "LuaUtils":
				interp.variables.set(targetVar, cne.compat.PsychLuaUtils);
				return true;
			case "psychlua.ModchartSprite" | "ModchartSprite":
				interp.variables.set(targetVar, flixel.FlxSprite);
				return true;
			case "openfl.filters.ShaderFilter" | "ShaderFilter":
				interp.variables.set(targetVar, openfl.filters.ShaderFilter);
				return true;
			case "openfl.filters.BitmapFilter" | "BitmapFilter":
				interp.variables.set(targetVar, openfl.filters.BitmapFilter);
				return true;
			case "objects.VideoSprite" | "VideoSprite" | "hxvlc.flixel.FlxVideoSprite" | "FlxVideoSprite":
				interp.variables.set(targetVar, cne.compat.PsychVideoSprite);
				return true;
		}
		if(_importFailedCallback(cl, "source/") || _importFailedCallback(cl, "")) {
			return true;
		}
		return false;
	}
	private function _importFailedCallback(cl:Array<String>, prefix:String):Bool {
		var assetsPath = 'assets/$prefix${cl.join("/")}';
		for(hxExt in ["hx", "hscript", "hsc", "hxs", "hxc"]) {
			var p = '$assetsPath.$hxExt';
			if (__importedPaths.exists(p))
				return true; // no need to reimport again
			if (Assets.exists(p)) {
				var code = Assets.getText(p);
				var expr:Expr = null;
				try {
					if (code != null && code.length > 0) {
						parser.line = 1; // fun fact: this is all you need to reuse a parser without issues. all the other vars get reset on parse.
						expr = parser.parseString(code, cl.join("/") + "." + hxExt);
					}
				} catch(e:Error) {
					_errorHandler(e);
				} catch(e) {
					_errorHandler(new Error(ECustom(e.toString()), 0, 0, fileName, 0));
				}
				if (expr != null) {
					@:privateAccess
					interp.exprReturn(expr);
					__importedPaths.set(p, true);
				}
				return true;
			}
		}
		return false;
	}

	private function _errorHandler(error:Error) {
		var fileName = error.origin;
		var oldfn = '$fileName:${error.line}: ';
		if(remappedNames.exists(fileName))
			fileName = remappedNames.get(fileName);
		var fn = '$fileName:${error.line}: ';
		var err = error.toString();
		while(err.startsWith(oldfn) || err.startsWith(fn)) {
			if (err.startsWith(oldfn)) err = err.substr(oldfn.length);
			if (err.startsWith(fn)) err = err.substr(fn.length);
		}

		Logs.traceColored([
			Logs.logText(fn, GREEN),
			Logs.logText(err, RED)
		], ERROR);
	}

	private function _warnHandler(error:Error) {
		var fileName = error.origin;
		var oldfn = '$fileName:${error.line}: ';
		if(remappedNames.exists(fileName))
			fileName = remappedNames.get(fileName);
		var fn = '$fileName:${error.line}: ';
		var err = error.toString();
		while(err.startsWith(oldfn) || err.startsWith(fn)) {
			if (err.startsWith(oldfn)) err = err.substr(oldfn.length);
			if (err.startsWith(fn)) err = err.substr(fn.length);
		}

		Logs.traceColored([
			Logs.logText(fn, GREEN),
			Logs.logText(err, YELLOW)
		], WARNING);
	}

	public override function setParent(parent:Dynamic) {
		interp.scriptObject = parent;
		if (parent != null) {
			interp.variables.set("game", parent);
			if (Std.isOfType(parent, funkin.game.PlayState)) {
				var ps:funkin.game.PlayState = cast parent;
				interp.variables.set("camHUD", ps.camHUD);
				interp.variables.set("camGame", ps.camGame);
				interp.variables.set("camOther", ps.camOther);
				interp.variables.set("camera", ps.camera);
			}
		}
	}

	public override function onLoad() {
		@:privateAccess
		interp.execute(parser.mk(EBlock([]), 0, 0));
		if (expr != null) {
			lastExecutionResult = interp.execute(expr);
			interp.variables.set("FlxCamera", funkin.game.HudCamera);
			call("new", []);
		}

		#if GLOBAL_SCRIPT
		funkin.backend.scripting.GlobalScript.call("onScriptSetup", [this, "hscript"]);
		#end
	}

	/** Parses and executes a Psych runHaxeCode snippet in this script's persistent interpreter. */
	public function executeString(source:String):Dynamic
	{
		if (source == null || source.length == 0)
		{
			loadFromString(source);
		}
		else
		{
			var cachedExpr = runHaxeExprCache.get(source);
			if (cachedExpr != null)
			{
				code = source;
				expr = cachedExpr;
				runHaxeCodeCacheHits++;
			}
			else
			{
				runHaxeCodeCacheMisses++;
				loadFromString(source);
				if (expr != null)
				{
					if (runHaxeExprCacheOrder.length >= RUN_HAXE_EXPR_CACHE_LIMIT)
					{
						var oldestSource = runHaxeExprCacheOrder.shift();
						if (oldestSource != null)
							runHaxeExprCache.remove(oldestSource);
					}
					runHaxeExprCache.set(source, expr);
					runHaxeExprCacheOrder.push(source);
				}
			}
		}

		if (funkin.game.PlayState.instance != null) {
			var ps = funkin.game.PlayState.instance;
			if (!interp.variables.exists("game")) interp.variables.set("game", ps);
			if (!interp.variables.exists("camHUD")) interp.variables.set("camHUD", ps.camHUD);
			if (!interp.variables.exists("camGame")) interp.variables.set("camGame", ps.camGame);
			if (!interp.variables.exists("camOther")) interp.variables.set("camOther", ps.camOther);
			if (!interp.variables.exists("camera")) interp.variables.set("camera", ps.camera);
		}

		lastExecutionResult = expr == null ? null : interp.execute(expr);
		return lastExecutionResult;
	}

	private function clearRunHaxeExprCache():Void
	{
		runHaxeExprCache = new haxe.ds.StringMap<Expr>();
		runHaxeExprCacheOrder = [];
		runHaxeCodeCacheHits = 0;
		runHaxeCodeCacheMisses = 0;
		expr = null;
	}

	public override function reload() {
		clearRunHaxeExprCache();
		// save variables

		interp.allowStaticVariables = interp.allowPublicVariables = false;
		var savedVariables:Map<String, Dynamic> = [];
		var defaultVars = Script.getDefaultVariables(this);
		for(k=>e in interp.variables) {
			if (!Reflect.isFunction(e) && !defaultVars.exists(k)) {
				savedVariables[k] = e;
			}
		}
		var oldParent = interp.scriptObject;
		returnParser(parser);
		onCreate(path);

		for(k=>e in defaultVars)
			set(k, e);

		load();
		setParent(oldParent);

		for(k=>e in savedVariables)
			interp.variables.set(k, e);

		interp.allowStaticVariables = interp.allowPublicVariables = true;
	}

	private var __dispatchedSpawnNotes:Map<funkin.game.Note, Bool> = new Map();

	private override function onCall(funcName:String, parameters:Array<Dynamic>):Dynamic {
		if (interp == null) return null;

		if (funcName == "update") {
			var onSpawn = interp.variables.get("onSpawnNote");
			var onSpawnPost = interp.variables.get("onSpawnNotePost");
			if ((onSpawn != null && Reflect.isFunction(onSpawn)) || (onSpawnPost != null && Reflect.isFunction(onSpawnPost))) {
				var game = funkin.game.PlayState.instance;
				if (game != null && game.strumLines != null && game.strumLines.members != null && game.startedCountdown) {
					var songSpeed:Float = game.scrollSpeed <= 0 ? 1 : game.scrollSpeed;
					for (line in game.strumLines.members) {
						if (line == null || line.notes == null || line.notes.members == null) continue;
						for (note in line.notes.members) {
							if (note == null || !note.exists || !note.alive) continue;
							if (!__dispatchedSpawnNotes.exists(note)) {
								if (cne.compat.PsychHookMap.isPsychNoteSpawned(note.strumTime, funkin.backend.system.Conductor.songPosition, songSpeed, note.multSpeed)) {
									__dispatchedSpawnNotes.set(note, true);
									if (onSpawn != null && Reflect.isFunction(onSpawn)) {
										try { Reflect.callMethod(null, onSpawn, [note]); } catch (_) {}
									}
									if (onSpawnPost != null && Reflect.isFunction(onSpawnPost)) {
										try { Reflect.callMethod(null, onSpawnPost, [note]); } catch (_) {}
									}
								}
							}
						}
					}
				}
			}
		}

		var candidateNames:Array<String> = [funcName];
		for (mapped in cne.compat.PsychHookMap.getHooks(funcName)) {
			if (!candidateNames.contains(mapped))
				candidateNames.push(mapped);
		}
		if (funcName == "onDadHit" && !candidateNames.contains("opponentNoteHit"))
			candidateNames.push("opponentNoteHit");
		if (funcName == "onPlayerHit" && !candidateNames.contains("goodNoteHit"))
			candidateNames.push("goodNoteHit");
		if (funcName == "onPlayerMiss" && !candidateNames.contains("noteMiss"))
			candidateNames.push("noteMiss");

		var lastResult:Dynamic = null;
		for (targetFuncName in candidateNames) {
			var func = interp.variables.get(targetFuncName);
			if (func == null || !Reflect.isFunction(func)) continue;

			var args = parameters == null ? Script._EMPTY_ARGS : parameters;
			if ((targetFuncName == "goodNoteHit" || targetFuncName == "opponentNoteHit") && args.length == 1 && Std.isOfType(args[0], funkin.backend.scripting.events.note.NoteHitEvent)) {
				var hitEvt:funkin.backend.scripting.events.note.NoteHitEvent = cast args[0];
				if (targetFuncName == "opponentNoteHit" && !hitEvt.character.isPlayer)
					args = [hitEvt.note];
				else if (targetFuncName == "goodNoteHit" && hitEvt.character.isPlayer)
					args = [hitEvt.note];
				else if (funcName == "onNoteHit")
					continue;
				else
					args = [hitEvt.note];
			} else if (targetFuncName == "noteMiss" && args.length == 1 && Std.isOfType(args[0], funkin.backend.scripting.events.note.NoteMissEvent)) {
				var missEvt:funkin.backend.scripting.events.note.NoteMissEvent = cast args[0];
				args = [missEvt.note];
			}

			try {
				lastResult = Reflect.callMethod(null, func, args);
			} catch(e:Dynamic) {
				var errStr:String = Std.string(e);
				if ((targetFuncName == "onEvent" || targetFuncName == "onPostEvent") && args.length == 1 && Std.isOfType(args[0], funkin.backend.scripting.events.gameplay.EventGameEvent)) {
					var gameEvent:funkin.backend.scripting.events.gameplay.EventGameEvent = args[0];
					var ev = gameEvent.event;
					var evName = ev != null ? ev.name : "";
					var val1:Dynamic = (ev != null && ev.params != null && ev.params.length > 0) ? ev.params[0] : "";
					var val2:Dynamic = (ev != null && ev.params != null && ev.params.length > 1) ? ev.params[1] : "";
					var time:Float = ev != null ? ev.time : 0;

					var psychArgs3:Array<Dynamic> = [evName, Std.string(val1 ?? ""), Std.string(val2 ?? "")];
					var psychArgs4:Array<Dynamic> = [evName, Std.string(val1 ?? ""), Std.string(val2 ?? ""), time];
					var psychArgs2:Array<Dynamic> = [evName, Std.string(val1 ?? "")];
					var psychArgs1:Array<Dynamic> = [evName];

					var reg = ~/required (\d+)/i;
					if (reg.match(errStr)) {
						var req = Std.parseInt(reg.matched(1));
						var targetArgs = switch(req) {
							case 0: [];
							case 1: psychArgs1;
							case 2: psychArgs2;
							case 3: psychArgs3;
							case 4: psychArgs4;
							default:
								var a = psychArgs4.copy();
								while (a.length < req) a.push(null);
								a.slice(0, req);
						};
						try {
							lastResult = Reflect.callMethod(null, func, targetArgs);
							continue;
						} catch(_) {}
					}
					var succeeded = false;
					for (trial in [psychArgs3, psychArgs4, psychArgs2, psychArgs1]) {
						try {
							lastResult = Reflect.callMethod(null, func, trial);
							succeeded = true;
							break;
						} catch(_) {}
					}
					if (succeeded) continue;
				}

				var reg = ~/required (\d+)/i;
				if (reg.match(errStr)) {
					var req = Std.parseInt(reg.matched(1));
					if (req != null) {
						var adapted = args.copy();
						while (adapted.length < req) adapted.push(null);
						if (adapted.length > req) adapted = adapted.slice(0, req);
						try {
							lastResult = Reflect.callMethod(null, func, adapted);
							continue;
						} catch(_) {}
					}
				}

				_errorHandler(new hscript.Expr.Error(ECustom('Call failed for function $targetFuncName: ' + errStr), 0, 0, fileName, 0));
			}
		}

		return lastResult;
	}

	public override function get(val:String):Dynamic {
		var v = interp.variables.get(val);
		if (v == null && val == "game") {
			return interp.scriptObject != null ? interp.scriptObject : funkin.game.PlayState.instance;
		}
		return v;
	}

	public override function set(val:String, value:Dynamic) {
		interp.variables.set(val, value);
		// A runtime-injected variable may shadow a previously-cached VNotFound/type-resolve result, so drop stale cache entries.
		interp.invalidateCache();
	}

	public override function trace(v:Dynamic) {
		var posInfo = interp.posInfos();
		Logs.traceColored([
			Logs.logText('${fileName}:${posInfo.lineNumber}: ', GREEN),
			Logs.logText(Std.isOfType(v, String) ? v : Std.string(v))
		], TRACE);
	}

	public override function setPublicMap(map:Map<String, Dynamic>) {
		this.interp.publicVariables = map;
	}

	override public function destroy() {
		clearRunHaxeExprCache();
		returnParser(parser);
		parser = null;
		interp = null;
		super.destroy();
	}
}
