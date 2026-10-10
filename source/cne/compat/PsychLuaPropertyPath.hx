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
			return null;
		}
		if (Std.isOfType(value, Array))
		{
			var index = Std.parseInt(part);
			var items:Array<Dynamic> = cast value;
			return index != null && index >= 0 && index < items.length ? items[index] : null;
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
		// Psych sprite _frame.frame fallback for FlxSprite / clipping.
		// In FlxSprite: _frame is FlxFrame, and .frame (property) also returns the current FlxFrame.
		// So sprite._frame.frame.width === sprite.frame.frame.width.
		if (part == "_frame")
		{
			var frameObj = Reflect.getProperty(value, "_frame");
			if (frameObj != null) return frameObj;
			// Fallback: sprite.frame property IS the current FlxFrame (same as _frame).
			return Reflect.getProperty(value, "frame");
		}
		if (isCamera(value))
		{
			switch (part)
			{
				case "x" | "y" | "width" | "height" | "zoom" | "alpha" | "angle" | "visible" | "bgColor":
					var res:Dynamic = Reflect.getProperty(value, part);
					if (res == null) res = Reflect.field(value, part);
					return res;
			}
		}
		var res:Dynamic = Reflect.getProperty(value, part);
		if (res == null) res = Reflect.field(value, part);
		return res;
	}

	private static function isCamera(value:Dynamic):Bool
	{
		if (value == null) return false;
		var cls = Type.getClass(value);
		if (cls == null) return false;
		return Type.getClassName(cls) == "flixel.FlxCamera";
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
		var value = root;
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

		var target = root;
		for (i in 0...(parts.length - 1))
		{
			target = readPart(target, parts[i]);
			if (target == null) return null;
		}

		var property = parts[parts.length - 1];
		if (property == "direction" && hasNoteAngle(target))
		{
			var psychDirection = Std.parseFloat(Std.string(newValue));
			if (Math.isNaN(psychDirection)) return null;
			var cneAngle = psychDirection - 90;
			Reflect.setProperty(target, "noteAngle", cneAngle);
			return newValue;
		}
		var field = property;
		if (isCamera(target))
		{
			switch (field)
			{
				case "x" | "y" | "width" | "height" | "zoom" | "alpha" | "angle" | "visible":
					try {
						Reflect.setProperty(target, field, newValue);
						return newValue;
					} catch (_:Dynamic) {
						try {
							Reflect.setField(target, field, newValue);
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
					try { Reflect.setProperty(target, "bgColor", colVal); } catch (_:Dynamic) {}
					return newValue;
			}
		}
		if (Std.isOfType(target, Array))
		{
			var index = Std.parseInt(field);
			var items:Array<Dynamic> = cast target;
			if (index == null || index < 0 || index >= items.length) return null;
			items[index] = newValue;
		}
		else
		{
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
		}
		return newValue;
	}
}
