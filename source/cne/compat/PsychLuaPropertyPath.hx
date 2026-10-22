package cne.compat;

/** Resolves Psych-style dotted properties and indexed array members. */
class PsychLuaPropertyPath
{
	public static var cameraOffsets:Map<String, Array<Float>> = [
		"opponentCameraOffset" => [0.0, 0.0],
		"boyfriendCameraOffset" => [0.0, 0.0],
		"girlfriendCameraOffset" => [0.0, 0.0]
	];

	public static function resetCameraOffsets():Void
	{
		cameraOffsets.set("opponentCameraOffset", [0.0, 0.0]);
		cameraOffsets.set("boyfriendCameraOffset", [0.0, 0.0]);
		cameraOffsets.set("girlfriendCameraOffset", [0.0, 0.0]);
	}

	private static function split(path:String):Array<String>
	{
		if (path == null) return [];
		var normalized = StringTools.replace(path, "[", ".");
		normalized = StringTools.replace(normalized, "]", "");
		var result:Array<String> = [];
		for (part in normalized.split("."))
		{
			var key = StringTools.trim(part);
			if (key.length >= 2 && ((key.charAt(0) == "'" && key.charAt(key.length - 1) == "'") || (key.charAt(0) == '"' && key.charAt(key.length - 1) == '"')))
				key = key.substr(1, key.length - 2);
			if (key.length > 0) result.push(key);
		}
		return result;
	}

	private static function readPart(value:Dynamic, part:String):Dynamic
	{
		if (value == null)
		{
			if (part == "cameraPosition" || part == "opponentCameraOffset" || part == "boyfriendCameraOffset" || part == "girlfriendCameraOffset")
				return [0.0, 0.0];
			if (part == "playbackRate")
				return (funkin.game.PlayState.instance != null) ? funkin.game.PlayState.instance.playbackRate : 1.0;
			return null;
		}
		if (value == funkin.options.Options)
		{
			switch (part)
			{
				case "data": return funkin.options.Options;
				case "downScroll" | "downscroll": return funkin.options.Options.downscroll;
				case "middleScroll" | "middlescroll": return funkin.options.Options.centeredFields;
				case "ghostTapping": return funkin.options.Options.ghostTapping;
				case "flashing": return funkin.options.Options.flashingMenu;
				case "lowQuality": return funkin.options.Options.lowMemoryMode;
				case "framerate": return funkin.options.Options.framerate;
				case "camZooms": return funkin.options.Options.camZoomOnBeat;
				case "noteSplashes": return funkin.options.Options.splashesEnabled;
				case "opponentStrums": return true;
				case "nopixelstage" | "nopixel" | "nocredits": return false;
				default:
			}
		}
		if (value == funkin.backend.system.Conductor)
		{
			switch (part)
			{
				case "bpm": return funkin.backend.system.Conductor.bpm;
				case "crochet": return funkin.backend.system.Conductor.crochet;
				case "stepCrochet": return funkin.backend.system.Conductor.stepCrochet;
				case "songPosition": return funkin.backend.system.Conductor.songPosition;
				case "curBeat": return funkin.backend.system.Conductor.curBeat;
				case "curStep": return funkin.backend.system.Conductor.curStep;
				case "curBeatFloat": return funkin.backend.system.Conductor.curBeatFloat;
				case "curStepFloat": return funkin.backend.system.Conductor.curStepFloat;
				default:
			}
		}
		if (value == flixel.FlxG)
		{
			switch (part)
			{
				case "camera": return flixel.FlxG.camera;
				case "cameras": return flixel.FlxG.cameras;
				case "scaleMode": return flixel.FlxG.scaleMode;
				case "width": return flixel.FlxG.width;
				case "height": return flixel.FlxG.height;
				default:
			}
		}
		if (Std.isOfType(value, Array))
		{
			var items:Array<Dynamic> = cast value;
			if (part == "length") return items.length;
			if (part == "members") return items;
			var index = Std.parseInt(part);
			return index != null && index >= 0 && index < items.length ? items[index] : null;
		}
		if (Std.isOfType(value, flixel.group.FlxGroup.FlxTypedGroup))
		{
			var grp:flixel.group.FlxGroup.FlxTypedGroup<Dynamic> = cast value;
			if (part == "length") return grp.members != null ? grp.members.length : 0;
			if (part == "members") return grp.members != null ? grp.members : [];
			var index = Std.parseInt(part);
			return index != null && grp.members != null && index >= 0 && index < grp.members.length ? grp.members[index] : null;
		}
		if (Std.isOfType(value, funkin.game.PlayState))
		{
			var game:funkin.game.PlayState = cast value;
			switch (part)
			{
				case "grpNoteSplashes":
					return game.splashHandler != null && game.splashHandler.members != null ? game.splashHandler.members : [];
				case "timeBar":
					return game.timeBar;
				case "timeBarBG" | "timeBG":
					return game.timeBarBG != null ? game.timeBarBG : (cast game.timeBar);
				case "timeTxt":
					return game.timeTxt;
				case "songName" | "curSong":
					return game.curSong != null ? game.curSong : (game.rawSongName != null ? game.rawSongName : (funkin.game.PlayState.SONG != null && funkin.game.PlayState.SONG.meta != null ? funkin.game.PlayState.SONG.meta.name : ""));
				case "score" | "songScore": return game.songScore;
				case "misses" | "songMisses": return game.misses;
				case "hits" | "songHits": return game.ratingNum;
				case "ratingName": return game.curRating != null ? game.curRating.rating : "?";
				case "ratingFC": return game.misses == 0 ? (game.combo > 0 ? "FC" : "Clear") : (game.misses < 10 ? "SDCB" : "Clear");
				case "ratingPercent": return game.accuracy;
				case "playbackRate": return game.playbackRate;
				case "botPlay" | "botplay" | "cpuControlled":
					return (game.playerStrums != null && (game.playerStrums.botplay || game.playerStrums.cpu));
				case "opponentStrums" | "cpuStrums":
					game.ensureStrumsAndNotesGenerated();
					return game.cpuStrums != null ? game.cpuStrums : (game.strumLines.members != null && game.strumLines.members.length > 0 ? game.strumLines.members[0] : null);
				case "playerStrums":
					game.ensureStrumsAndNotesGenerated();
					return game.playerStrums != null ? game.playerStrums : (game.strumLines.members != null && game.strumLines.members.length > 1 ? game.strumLines.members[1] : null);
				case "strumLineNotes":
					game.ensureStrumsAndNotesGenerated();
					var strums:Array<Dynamic> = [];
					var opp = game.cpuStrums != null ? game.cpuStrums : (game.strumLines.members != null && game.strumLines.members.length > 0 ? game.strumLines.members[0] : null);
					var pl = game.playerStrums != null ? game.playerStrums : (game.strumLines.members != null && game.strumLines.members.length > 1 ? game.strumLines.members[1] : null);
					if (opp != null && opp.members != null) for (s in opp.members) if (s != null) strums.push(s);
					if (pl != null && pl.members != null) for (s in pl.members) if (s != null) strums.push(s);
					return strums;
				case "unspawnNotes":
					return game.unspawnNotes;
				case "noteGroup":
					return game.strumLines;
				case "boyfriendGroup":
					return game.boyfriendGroup != null ? game.boyfriendGroup : game.boyfriend;
				case "dadGroup":
					return game.dadGroup != null ? game.dadGroup : game.dad;
				case "gfGroup":
					return game.gfGroup != null ? game.gfGroup : game.gf;
				case "healthBar":
					return game.healthBar;
				case "healthBarBG":
					return game.healthBarBG;
				case "iconP1":
					return game.iconP1;
				case "iconP2":
					return game.iconP2;
				case "camOther":
					return game.camOther;
				case "camHUD":
					return game.camHUD;
				case "camGame":
					return game.camGame;
				default:
			}
		}
		if (funkin.game.PlayState.instance != null)
		{
			var game = funkin.game.PlayState.instance;
			if (value == game.healthBar || value == game.healthBarBG)
			{
				if (part == "y")
				{
					var isDs = funkin.options.Options.downscroll || (game.camHUD != null && game.camHUD.downscroll);
					if (isDs && !funkin.game.HudCamera.shouldBypassDownscroll(value))
						return (value == game.healthBarBG) ? (flixel.FlxG.height * 0.11 - 4) : (flixel.FlxG.height * 0.11);
				}
			}
		}
		if (isFlxPoint(value))
		{
			return switch (part)
			{
				case "x" | "0": Reflect.getProperty(value, "x");
				case "y" | "1": Reflect.getProperty(value, "y");
				default: null;
			};
		}
		if (Std.isOfType(value, funkin.game.Note))
		{
			var note:funkin.game.Note = cast value;
			switch (part)
			{
				case "hitHealth":
					return note.hitHealth != null ? note.hitHealth : 0.023;
				case "missHealth":
					return note.missHealth != null ? note.missHealth : 0.0475;
				default:
			}
		}
		if (part == "direction" && hasNoteAngle(value))
		{
			var angle:Dynamic = Reflect.getProperty(value, "noteAngle");
			if (angle == null) angle = Reflect.getProperty(value, "angle");
			return (angle == null ? 0 : Std.parseFloat(Std.string(angle))) + 90;
		}
		// Psych cameraPosition on Character fallback to cameraOffset
		if (part == "cameraPosition")
		{
			var camPos:Dynamic = Reflect.getProperty(value, "cameraPosition");
			if (camPos != null) return camPos;
			var offset:Dynamic = Reflect.getProperty(value, "cameraOffset");
			if (offset != null)
			{
				var ox:Dynamic = Reflect.getProperty(offset, "x");
				var oy:Dynamic = Reflect.getProperty(offset, "y");
				var fx:Float = ox != null ? Std.parseFloat(Std.string(ox)) : 0.0;
				var fy:Float = oy != null ? Std.parseFloat(Std.string(oy)) : 0.0;
				if (Math.isNaN(fx)) fx = 0.0;
				if (Math.isNaN(fy)) fy = 0.0;
				return [fx, fy];
			}
			return [0.0, 0.0];
		}
		// Psych camera offset fallback on PlayState or global
		if (part == "opponentCameraOffset" || part == "boyfriendCameraOffset" || part == "girlfriendCameraOffset")
		{
			var prop:Dynamic = Reflect.getProperty(value, part);
			if (prop != null) return prop;
			var off = cameraOffsets.get(part);
			if (off != null) return off;
			return [0.0, 0.0];
		}
		if (part == "offset")
		{
			if (Std.isOfType(value, funkin.backend.FunkinSprite))
			{
				var spr:funkin.backend.FunkinSprite = cast value;
				var ox:Float = spr.offset != null ? spr.offset.x : 0.0;
				var oy:Float = spr.offset != null ? spr.offset.y : 0.0;
				if (spr.frameOffset != null)
				{
					ox += spr.frameOffset.x;
					oy += spr.frameOffset.y;
				}
				return new flixel.math.FlxPoint(ox, oy);
			}
		}
		if (part == "imageFile" || part == "image")
		{
			if (Std.isOfType(value, funkin.game.Character))
			{
				var char:funkin.game.Character = cast value;
				var spr:String = char.sprite;
				if (spr == null || spr == "") spr = char.curCharacter;
				if (spr != null && spr != "")
				{
					if (!StringTools.startsWith(spr, "characters/"))
						return 'characters/$spr';
					return spr;
				}
				return "characters/bf";
			}
			var prop:Dynamic = Reflect.getProperty(value, part);
			if (prop != null) return prop;
			prop = Reflect.getProperty(value, "imageFile");
			if (prop != null) return prop;
			return Reflect.getProperty(value, "sprite");
		}
		if (part == "healthColorArray")
		{
			if (Std.isOfType(value, funkin.game.Character))
				return (cast value:funkin.game.Character).healthColorArray;
		}
		if (part == "frameName")
		{
			if (Std.isOfType(value, flixel.animation.FlxAnimationController))
			{
				var controller:flixel.animation.FlxAnimationController = cast value;
				@:privateAccess {
					if (controller._sprite != null)
					{
						if (controller._sprite.frame != null && controller._sprite.frame.name != null)
							return controller._sprite.frame.name;
						if (controller._curAnim != null && controller._sprite.frames != null)
						{
							var curIdx = controller._curAnim.curFrame;
							var frames = controller._curAnim.frames;
							if (frames != null && curIdx >= 0 && curIdx < frames.length)
							{
								var frameIdx = frames[curIdx];
								if (frameIdx >= 0 && frameIdx < controller._sprite.frames.frames.length)
									return controller._sprite.frames.frames[frameIdx].name;
							}
						}
					}
				}
				return null;
			}
			else if (Std.isOfType(value, flixel.FlxSprite))
			{
				var spr:flixel.FlxSprite = cast value;
				if (spr.frame != null && spr.frame.name != null) return spr.frame.name;
				if (spr.animation != null)
				{
					var ctrl = spr.animation;
					@:privateAccess {
						if (ctrl._curAnim != null && spr.frames != null)
						{
							var curIdx = ctrl._curAnim.curFrame;
							var frames = ctrl._curAnim.frames;
							if (frames != null && curIdx >= 0 && curIdx < frames.length)
							{
								var frameIdx = frames[curIdx];
								if (frameIdx >= 0 && frameIdx < spr.frames.frames.length)
									return spr.frames.frames[frameIdx].name;
							}
						}
					}
				}
			}
		}
		if (part == "curAnim")
		{
			var anim:Dynamic = null;
			if (Std.isOfType(value, flixel.animation.FlxAnimationController))
			{
				var ctrl:flixel.animation.FlxAnimationController = cast value;
				anim = ctrl.curAnim;
			}
			else if (Std.isOfType(value, flixel.FlxSprite))
			{
				anim = (cast value:flixel.FlxSprite).animation?.curAnim;
			}
			else if (Std.isOfType(value, flixel.animation.FlxAnimation))
			{
				anim = value;
			}
			else
				anim = Reflect.getProperty(value, "curAnim");

			return anim;
		}
		if (Std.isOfType(value, flixel.animation.FlxAnimation))
		{
			var anim:flixel.animation.FlxAnimation = cast value;
			switch (part)
			{
				case "name": return anim.name;
				case "curFrame": return anim.curFrame;
				case "finished":
					var animFinished:Bool = anim.finished;
					@:privateAccess {
						var parentCtrl = anim.parent;
						if (parentCtrl != null && parentCtrl._sprite != null && Std.isOfType(parentCtrl._sprite, funkin.game.Character)) {
							var char:funkin.game.Character = cast parentCtrl._sprite;
							if (char.isHoldingNote() && anim.name != null && StringTools.startsWith(anim.name, "sing"))
								animFinished = false;
						}
					}
					return animFinished;
				case "frameRate": return anim.frameRate;
				case "numFrames": return anim.numFrames;
				case "paused": return anim.paused;
				case "looped": return anim.looped;
				case "reversed": return anim.reversed;
			}
		}
		if (part == "finished" && Std.isOfType(value, flixel.animation.FlxAnimation))
		{
			var flxAnim:flixel.animation.FlxAnimation = cast value;
			var animFinished:Bool = flxAnim.finished;
			@:privateAccess {
				var parentCtrl = flxAnim.parent;
				if (parentCtrl != null && parentCtrl._sprite != null && Std.isOfType(parentCtrl._sprite, funkin.game.Character)) {
					var char:funkin.game.Character = cast parentCtrl._sprite;
					if (char.isHoldingNote() && flxAnim.name != null && StringTools.startsWith(flxAnim.name, "sing"))
						animFinished = false;
				}
			}
			return animFinished;
		}
		if (part == "holdTimer")
		{
			if (Std.isOfType(value, funkin.game.Character))
			{
				var char:funkin.game.Character = cast value;
				return Math.max(0, (funkin.backend.system.Conductor.songPosition - char.lastHit) / 1000.0);
			}
			return 0.0;
		}
		// Psych sprite _frame.frame fallback for FlxSprite / clipping.
		// In FlxSprite: _frame is FlxFrame, and .frame (property) also returns the current FlxFrame.
		// So sprite._frame.frame.width === sprite.frame.frame.width.
		if (part == "_frame")
		{
			var frameObj = Reflect.getProperty(value, "_frame");
			if (frameObj == null) frameObj = Reflect.field(value, "_frame");
			if (frameObj == null && Std.isOfType(value, flixel.FlxSprite))
				frameObj = (cast value:flixel.FlxSprite).frame;
			if (frameObj != null) return frameObj;
			return Reflect.getProperty(value, "frame");
		}
		if (funkin.game.PlayState.instance != null && value == funkin.game.PlayState.instance)
		{
			var game = funkin.game.PlayState.instance;
			if (game.variables != null && game.variables.exists(part))
				return game.variables.get(part);
		}
		if (isCamera(value))
		{
			var cam:flixel.FlxCamera = cast value;
			switch (part)
			{
				case "scroll": return cam.scroll;
				case "scroll.x": return cam.scroll.x;
				case "scroll.y": return cam.scroll.y;
				case "targetOffset": return cam.targetOffset;
				case "targetOffset.x": return cam.targetOffset.x;
				case "targetOffset.y": return cam.targetOffset.y;
				case "flashSprite": return cam.flashSprite;
				case "canvas": return cam.canvas;
				case "initialZoom":
					var iz = cam.initialZoom;
					return (Math.isNaN(iz) || iz == 0) ? 1.0 : iz;
				case "scaleX": return cam.scaleX;
				case "scaleY": return cam.scaleY;
				case "totalScaleX": return cam.totalScaleX;
				case "totalScaleY": return cam.totalScaleY;
				case "_flashOffset": return @:privateAccess cam._flashOffset;
				case "_fxShakeIntensity": return @:privateAccess cam._fxShakeIntensity;
				case "_fxShakeDuration": return @:privateAccess cam._fxShakeDuration;
				case "followLerp": return cam.followLerp;
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
		if (Std.isOfType(value, openfl.geom.Matrix))
		{
			var mat:openfl.geom.Matrix = cast value;
			switch (part)
			{
				case "a": return mat.a;
				case "b": return mat.b;
				case "c": return mat.c;
				case "d": return mat.d;
				case "tx": return mat.tx;
				case "ty": return mat.ty;
				default:
			}
		}
		if (Std.isOfType(value, openfl.display.DisplayObject))
		{
			var dobj:openfl.display.DisplayObject = cast value;
			if (part == "__transform")
				return @:privateAccess dobj.__transform;
			if (part == "transform")
				return dobj.transform;
		}
		var res:Dynamic = Reflect.getProperty(value, part);
		if (res == null) res = Reflect.field(value, part);
		return res;
	}

	private static function isCamera(value:Dynamic):Bool
	{
		if (value == null) return false;
		return Std.isOfType(value, flixel.FlxCamera);
	}

	private static function isFlxPoint(value:Dynamic):Bool
	{
		if (value == null) return false;
		var cls = Type.getClass(value);
		while (cls != null)
		{
			var className = Type.getClassName(cls);
			if (className == "flixel.math.FlxPoint" || className == "flixel.math.FlxBasePoint") return true;
			cls = Type.getSuperClass(cls);
		}
		return false;
	}

	private static function hasNoteAngle(value:Dynamic):Bool
	{
		if (value == null) return false;
		if (Reflect.hasField(value, "noteAngle")) return true;
		var className = Type.getClassName(Type.getClass(value));
		return className == "funkin.game.Strum";
	}

	public static function read(root:Dynamic, path:String):Dynamic
	{
		var value:Dynamic = root;
		var parts = split(path);
		if (value == null)
		{
			if (parts.length > 0 && (parts[0] == "cameraPosition" || parts[0] == "opponentCameraOffset" || parts[0] == "boyfriendCameraOffset" || parts[0] == "girlfriendCameraOffset"))
				value = cameraOffsets.get(parts[0]);
			else
				return null;
		}
		for (part in parts)
		{
			value = readPart(value, part);
			if (value == null) return null;
		}
		return value;
	}

	public static function write(root:Dynamic, path:String, newValue:Dynamic):Dynamic
	{
		if (root == null) return null;
		var parts = split(path);
		if (parts.length == 0) return null;

		// Writing to camera offsets (e.g. setProperty('opponentCameraOffset[0]', 10))
		if (parts.length >= 1 && (parts[0] == "opponentCameraOffset" || parts[0] == "boyfriendCameraOffset" || parts[0] == "girlfriendCameraOffset"))
		{
			var arr = cameraOffsets.get(parts[0]);
			if (arr == null)
			{
				arr = [0.0, 0.0];
				cameraOffsets.set(parts[0], arr);
			}
			if (parts.length == 2)
			{
				var idx = Std.parseInt(parts[1]);
				if (idx != null && idx >= 0 && idx < arr.length)
				{
					var valFloat = Std.parseFloat(Std.string(newValue));
					arr[idx] = Math.isNaN(valFloat) ? 0.0 : valFloat;
					return newValue;
				}
			}
			else if (parts.length == 1 && Std.isOfType(newValue, Array))
			{
				cameraOffsets.set(parts[0], cast newValue);
				return newValue;
			}
		}

		var target:Dynamic = root;
		var parent:Dynamic = null;
		for (i in 0...(parts.length - 1))
		{
			parent = target;
			target = readPart(target, parts[i]);
			if (target == null) return null;
		}

		var property = parts[parts.length - 1];
		if (property == "holdTimer" && Std.isOfType(target, funkin.game.Character))
		{
			var char:funkin.game.Character = cast target;
			var valFloat = Std.parseFloat(Std.string(newValue));
			if (Math.isNaN(valFloat)) valFloat = 0.0;
			char.lastHit = funkin.backend.system.Conductor.songPosition - (valFloat * 1000.0);
			return newValue;
		}
		if (property == "direction" && hasNoteAngle(target))
		{
			var psychDirection = Std.parseFloat(Std.string(newValue));
			if (Math.isNaN(psychDirection)) return null;
			var cneAngle = psychDirection - 90;
			Reflect.setProperty(target, "noteAngle", cneAngle);
			return newValue;
		}
		var field = property;
		if (field == "curFrame")
		{
			var frameInt:Int = Std.int(Math.floor(Std.parseFloat(Std.string(newValue))));
			if (Std.isOfType(target, flixel.animation.FlxAnimation))
			{
				var a:flixel.animation.FlxAnimation = cast target;
				a.curFrame = frameInt;
				return a.curFrame;
			}
			if (Std.isOfType(target, flixel.animation.FlxAnimationController))
			{
				var ctrl:flixel.animation.FlxAnimationController = cast target;
				if (ctrl.curAnim != null)
				{
					ctrl.curAnim.curFrame = frameInt;
					return ctrl.curAnim.curFrame;
				}
			}
			if (Std.isOfType(target, flixel.FlxSprite))
			{
				var spr:flixel.FlxSprite = cast target;
				if (spr.animation != null && spr.animation.curAnim != null)
				{
					spr.animation.curAnim.curFrame = frameInt;
					return spr.animation.curAnim.curFrame;
				}
			}
		}
		if (isFlxPoint(target) && (field == "x" || field == "y" || field == "0" || field == "1"))
		{
			var axis = (field == "0" ? "x" : (field == "1" ? "y" : field));
			var valueFloat = Std.parseFloat(Std.string(newValue));
			if (Math.isNaN(valueFloat)) return null;
			Reflect.setProperty(target, axis, valueFloat);
			if (parent != null && Std.isOfType(parent, funkin.backend.FunkinSprite) && parts.length >= 2 && parts[parts.length - 2] == "offset")
			{
				var fspr:funkin.backend.FunkinSprite = cast parent;
				if (fspr.frameOffset != null)
				{
					var sprOff = (fspr.offset != null) ? (axis == "x" ? fspr.offset.x : fspr.offset.y) : 0.0;
					Reflect.setProperty(fspr.frameOffset, axis, valueFloat - sprOff);
				}
				else if (fspr.offset != null)
				{
					Reflect.setProperty(fspr.offset, axis, valueFloat);
				}
			}
			return newValue;
		}
		if (isCamera(target))
		{
			var cam:flixel.FlxCamera = cast target;
			switch (field)
			{
				case "scroll":
					if (isFlxPoint(newValue))
						cam.scroll = newValue;
					return newValue;
				case "scroll.x":
					cam.scroll.x = Std.parseFloat(Std.string(newValue));
					return newValue;
				case "scroll.y":
					cam.scroll.y = Std.parseFloat(Std.string(newValue));
					return newValue;
				case "targetOffset":
					if (isFlxPoint(newValue))
					{
						if (cam.targetOffset != null)
							cam.targetOffset.set(Reflect.getProperty(newValue, "x"), Reflect.getProperty(newValue, "y"));
						else
							@:privateAccess cam.targetOffset = newValue;
					}
					return newValue;
				case "targetOffset.x":
					cam.targetOffset.x = Std.parseFloat(Std.string(newValue));
					return newValue;
				case "targetOffset.y":
					cam.targetOffset.y = Std.parseFloat(Std.string(newValue));
					return newValue;
				case "scaleX":
					@:privateAccess cam.scaleX = Std.parseFloat(Std.string(newValue));
					return newValue;
				case "scaleY":
					@:privateAccess cam.scaleY = Std.parseFloat(Std.string(newValue));
					return newValue;
				case "initialZoom":
					@:privateAccess cam.initialZoom = Std.parseFloat(Std.string(newValue));
					return newValue;
				case "_fxShakeIntensity":
					@:privateAccess cam._fxShakeIntensity = Std.parseFloat(Std.string(newValue));
					return newValue;
				case "_fxShakeDuration":
					@:privateAccess cam._fxShakeDuration = Std.parseFloat(Std.string(newValue));
					return newValue;
				case "followLerp":
					var lerp = Std.parseFloat(Std.string(newValue));
					if (!Math.isNaN(lerp)) {
						cam.followLerp = lerp;
						if (funkin.game.PlayState.instance != null && (cam == funkin.game.PlayState.instance.camGame || cam == flixel.FlxG.camera)) {
							funkin.game.PlayState.instance.customFollowLerp = lerp;
						}
					}
					return newValue;
				case "zoom":
					var z = Std.parseFloat(Std.string(newValue));
					if (Math.isNaN(z) || z < 0.05) z = 0.05;
					cam.zoom = z;
					if (funkin.game.PlayState.instance != null) {
						if (cam == funkin.game.PlayState.instance.camGame || cam == flixel.FlxG.camera)
							funkin.game.PlayState.instance.defaultCamZoom = z;
						else if (cam == funkin.game.PlayState.instance.camHUD)
							funkin.game.PlayState.instance.defaultHudZoom = z;
					}
					return newValue;
				case "x" | "y" | "width" | "height" | "alpha" | "angle" | "visible":
					try {
						Reflect.setProperty(cam, field, newValue);
						return newValue;
					} catch (_:Dynamic) {
						try {
							Reflect.setField(cam, field, newValue);
							return newValue;
						} catch (_:Dynamic) {}
					}
				case "bgColor":
					var colVal:Dynamic = newValue;
					if (!Std.isOfType(newValue, Int) && !Std.isOfType(newValue, Float)) {
						var colStr = Std.string(newValue);
						if (StringTools.startsWith(colStr, "#")) colStr = colStr.substr(1);
						if (StringTools.startsWith(colStr.toLowerCase(), "0x")) colStr = colStr.substr(2);
						if (colStr.length == 6) colStr = "FF" + colStr;
						var parsed = Std.parseInt("0x" + colStr);
						if (parsed != null) colVal = parsed;
					}
					try { Reflect.setProperty(cam, "bgColor", colVal); } catch (_:Dynamic) {}
					return newValue;
			}
		}
		if (parts.contains("flashSprite") || parts.contains("_flashOffset") || (parts.contains("canvas") && (parts.contains("__transform") || field == "x" || field == "y" || field == "rotation" || field == "visible" || field == "alpha")))
		{
			// Ignore camera display-tree corruption from legacy Psych 0.6.3 modchart scripts (e.g. zCameraFix.lua).
			// Modern Flixel/Codename camera rendering manages flashSprite and canvas transform natively.
			return newValue;
		}
		if (Std.isOfType(target, openfl.geom.Matrix))
		{
			var mat:openfl.geom.Matrix = cast target;
			var vFloat = Std.parseFloat(Std.string(newValue));
			if (!Math.isNaN(vFloat))
			{
				switch (field)
				{
					case "a": mat.a = vFloat;
					case "b": mat.b = vFloat;
					case "c": mat.c = vFloat;
					case "d": mat.d = vFloat;
					case "tx": mat.tx = vFloat;
					case "ty": mat.ty = vFloat;
					default: Reflect.setField(target, field, vFloat);
				}
			}
			if (parent != null && Std.isOfType(parent, openfl.display.DisplayObject))
			{
				@:privateAccess {
					var dobj:openfl.display.DisplayObject = cast parent;
					dobj.__setTransformDirty();
					dobj.__setRenderDirty();
				}
			}
			return newValue;
		}
		if (funkin.game.PlayState.instance != null && target == funkin.game.PlayState.instance)
		{
			var game = funkin.game.PlayState.instance;
			if (field == "playbackRate")
			{
				var pr = Std.parseFloat(Std.string(newValue));
				if (Math.isNaN(pr) || pr <= 0) pr = 1.0;
				game.playbackRate = pr;
				return pr;
			}
			if (game.variables != null && game.variables.exists(field))
			{
				game.variables.set(field, newValue);
				return newValue;
			}
		}
		if (Std.isOfType(target, Array))
		{
			var index = Std.parseInt(field);
			var items:Array<Dynamic> = cast target;
			if (index == null || index < 0 || index >= items.length) return null;
			items[index] = newValue;
			if (parent != null && Std.isOfType(parent, funkin.game.Character))
			{
				var char:funkin.game.Character = cast parent;
				if (parts.length >= 2)
				{
					var propName = parts[parts.length - 2];
					if (propName == "cameraPosition" && char.cameraOffset != null)
					{
						var fVal = Std.parseFloat(Std.string(newValue));
						if (!Math.isNaN(fVal)) {
							if (index == 0) char.cameraOffset.x = fVal;
							else if (index == 1) char.cameraOffset.y = fVal;
						}
					}
					else if (propName == "positionArray" && char.positionOffset != null)
					{
						var fVal = Std.parseFloat(Std.string(newValue));
						if (!Math.isNaN(fVal)) {
							if (index == 0) char.positionOffset.x = fVal;
							else if (index == 1) char.positionOffset.y = fVal;
						}
					}
					else if (propName == "healthColorArray")
					{
						char.healthColorArray = cast items;
					}
				}
			}
			return newValue;
		}
		else
		{
			if (Std.isOfType(target, funkin.game.HealthIcon))
			{
				if (field == "x")
					funkin.game.HudCamera.bypassX(cast target);
				else if (field == "y")
					funkin.game.HudCamera.bypassDownscroll(cast target);
			}
			else if (Std.isOfType(target, funkin.game.Strum))
			{
				var strum:funkin.game.Strum = cast target;
				if (field == "x" || field == "y" || field == "alpha" || field == "angle" || field == "direction" || field == "visible")
					strum.__pendingIntroAnim = false;
				if (field == "angle" && strum.noteAngle == null)
					strum.noteAngle = 0;
			}
			else if (Std.isOfType(target, funkin.game.Note))
			{
				var note:funkin.game.Note = cast target;
				if (field == "x" || field == "y")
					note.strumRelativePos = false;
				else if (field == "alpha")
				{
					var parsedAlpha = Std.parseFloat(Std.string(newValue));
					if (!Math.isNaN(parsedAlpha))
						note.multAlpha = parsedAlpha;
				}
			}

			if (field == "color" && Std.isOfType(target, flixel.FlxSprite))
			{
				var col:flixel.util.FlxColor = flixel.util.FlxColor.WHITE;
				if (Std.isOfType(newValue, Int)) {
					var iv:Int = cast newValue;
					if (iv == 0) col = flixel.util.FlxColor.BLACK;
					else {
						if ((iv & 0xFF000000) == 0 && iv <= 0x00FFFFFF) iv |= 0xFF000000;
						col = cast iv;
					}
				}
				else if (Std.isOfType(newValue, Float)) {
					var iv:Int = Std.int(newValue);
					if (iv == 0) col = flixel.util.FlxColor.BLACK;
					else {
						if ((iv & 0xFF000000) == 0 && iv <= 0x00FFFFFF) iv |= 0xFF000000;
						col = cast iv;
					}
				}
				else if (newValue != null)
				{
					var colStr = StringTools.trim(Std.string(newValue));
					if (StringTools.startsWith(colStr, "#")) colStr = colStr.substr(1);
					if (StringTools.startsWith(colStr.toLowerCase(), "0x")) colStr = colStr.substr(2);
					if (colStr == "000000" || colStr == "0") col = flixel.util.FlxColor.BLACK;
					else {
						if (colStr.length == 6) colStr = "FF" + colStr;
						var parsed = Std.parseInt("0x" + colStr);
						if (parsed != null) col = cast parsed;
					}
				}
				var spr:flixel.FlxSprite = cast target;
				spr.color = col;
				spr.dirty = true;
				if (spr.colorTransform != null)
				{
					spr.colorTransform.redMultiplier = col.redFloat;
					spr.colorTransform.greenMultiplier = col.greenFloat;
					spr.colorTransform.blueMultiplier = col.blueFloat;
				}
				@:privateAccess spr.useColorTransform = (col != flixel.util.FlxColor.WHITE || spr.alpha != 1);
				return newValue;
			}

			if (field == "text" && Std.isOfType(target, flixel.text.FlxText) && newValue == null)
				newValue = "";
			else if (Std.isOfType(newValue, String) && field != "text" && field != "name" && field != "font" && field != "curCharacter" && field != "antialiasing")
			{
				var isNumField = (field == "x" || field == "y" || field == "alpha" || field == "angle" || field == "width" || field == "height" || field == "size");
				if (!isNumField)
				{
					try {
						var existing = Reflect.getProperty(target, field);
						if (Std.isOfType(existing, Float) || Std.isOfType(existing, Int)) isNumField = true;
					} catch (_:Dynamic) {}
				}
				if (isNumField)
				{
					var parsed = Std.parseFloat(cast newValue);
					if (!Math.isNaN(parsed)) newValue = parsed;
				}
			}

			try
			{
				Reflect.setProperty(target, field, newValue);
			}
			catch (_:Dynamic)
			{
				try
				{
					Reflect.setField(target, field, newValue);
				}
				catch (_:Dynamic) {}
			}

			if (parts.length >= 2 && parts[parts.length - 2] == "colorTransform" && parent != null && Std.isOfType(parent, flixel.FlxSprite))
			{
				var spr:flixel.FlxSprite = cast parent;
				@:privateAccess spr.useColorTransform = true;
				spr.dirty = true;
			}

			if (parent != null && Std.isOfType(parent, flixel.graphics.frames.FlxFrame))
			{
				try {
					var frame:flixel.graphics.frames.FlxFrame = cast parent;
					@:privateAccess frame.updateUV();
					@:privateAccess frame.cacheFrameMatrix();
				} catch (_:Dynamic) {}
			}
			else if (Std.isOfType(target, flixel.graphics.frames.FlxFrame))
			{
				try {
					var frame:flixel.graphics.frames.FlxFrame = cast target;
					@:privateAccess frame.updateUV();
					@:privateAccess frame.cacheFrameMatrix();
				} catch (_:Dynamic) {}
			}

			if (funkin.game.PlayState.instance != null && (target:Dynamic) == funkin.game.PlayState.instance.scoreTxt)
			{
				var game = funkin.game.PlayState.instance;
				switch (field)
				{
					case "alpha":
						if (game.missesTxt != null) game.missesTxt.alpha = game.scoreTxt.alpha;
						if (game.accuracyTxt != null) game.accuracyTxt.alpha = game.scoreTxt.alpha;
					case "visible":
						if (game.missesTxt != null) game.missesTxt.visible = game.scoreTxt.visible;
						if (game.accuracyTxt != null) game.accuracyTxt.visible = game.scoreTxt.visible;
					case "y":
						game.customScoreTxtY = true;
						if (game.missesTxt != null) {
							game.missesTxt.y = game.scoreTxt.y;
							funkin.game.HudCamera.bypassDownscroll(game.missesTxt);
						}
						if (game.accuracyTxt != null) {
							game.accuracyTxt.y = game.scoreTxt.y;
							funkin.game.HudCamera.bypassDownscroll(game.accuracyTxt);
						}
						funkin.game.HudCamera.bypassDownscroll(game.scoreTxt);
					case "color":
						if (game.missesTxt != null) game.missesTxt.color = game.scoreTxt.color;
						if (game.accuracyTxt != null) game.accuracyTxt.color = game.scoreTxt.color;
					case "cameras":
						if (game.missesTxt != null) game.missesTxt.cameras = game.scoreTxt.cameras;
						if (game.accuracyTxt != null) game.accuracyTxt.cameras = game.scoreTxt.cameras;
					case "text":
						if (game.missesTxt != null) game.missesTxt.visible = false;
						if (game.accuracyTxt != null) game.accuracyTxt.visible = false;
				}
			}
			else if (funkin.game.PlayState.instance != null && (target:Dynamic) == funkin.game.PlayState.instance.healthBar)
			{
				var game = funkin.game.PlayState.instance;
				if (game.healthBarBG != null)
				{
					if (field == "visible") game.healthBarBG.visible = game.healthBar.visible;
					else if (field == "alpha") game.healthBarBG.alpha = game.healthBar.alpha;
				}
			}
			else if (funkin.game.PlayState.instance != null && ((target:Dynamic) == funkin.game.PlayState.instance.iconP1 || (target:Dynamic) == funkin.game.PlayState.instance.iconP2))
			{
				var icon:funkin.game.HealthIcon = cast target;
				var game = funkin.game.PlayState.instance;
				if (field == "x")
				{
					funkin.game.HudCamera.bypassX(icon);
				}
				else if (field == "y")
				{
					funkin.game.HudCamera.bypassDownscroll(icon);
					var isDs = funkin.options.Options.downscroll || (game.camHUD != null && game.camHUD.downscroll);
					if (isDs)
					{
						var otherIcon = (icon == game.iconP1) ? game.iconP2 : game.iconP1;
						if (otherIcon != null && (!funkin.game.HudCamera.shouldBypassDownscroll(otherIcon) || Math.abs(otherIcon.y - icon.y) > 300))
						{
							otherIcon.y = icon.y;
							funkin.game.HudCamera.bypassDownscroll(otherIcon);
						}
					}
				}
			}
		}
		return newValue;
	}
}
