package cne.compat;

/** Converts the line data in Psych Engine's dialogue JSON to CNE dialogue XML. */
class PsychDialogueConverter
{
	static function field(value:Dynamic, name:String, fallback:String):String
	{
		var result:Dynamic = value == null ? null : Reflect.field(value, name);
		return result == null ? fallback : Std.string(result);
	}

	static function characterName(portrait:String):String
	{
		return switch (portrait)
		{
			case "", "null": "boyfriend";
			case "bf": "boyfriend";
			default: portrait;
		}
	}

	static function characterPosition(portrait:String):String
	{
		return switch (portrait.toLowerCase())
		{
			case "bf" | "boyfriend" | "gf" | "girlfriend" | "player" | "pixelbf": "right";
			default: "left";
		}
	}

	static function isFiniteNumber(value:Float):Bool
		return !Math.isNaN(value) && value != Math.POSITIVE_INFINITY && value != Math.NEGATIVE_INFINITY;

	/**
	 * Returns a CNE dialogue document, or null if the Psych JSON is malformed.
	 * Psych portrait IDs are kept as character IDs except for its built-in `bf`
	 * alias, which maps to CNE's `boyfriend` dialogue character.
	 */
	public static function toCneXml(source:String):Null<String>
	{
		if (source == null) return null;
		try
		{
			var payload:Dynamic = haxe.Json.parse(source);
			var lines:Dynamic = Reflect.field(payload, "dialogue");
			if (!Std.isOfType(lines, Array)) return null;

			var root = Xml.createElement("dialogue");
			root.set("box", "default");
			var characters:Map<String, Bool> = [];
			var parsedLines:Array<Dynamic> = cast lines;
			for (entry in parsedLines)
			{
				if (entry == null || Std.isOfType(entry, String) || Std.isOfType(entry, Int) || Std.isOfType(entry, Bool)) return null;
				var portrait = characterName(field(entry, "portrait", "boyfriend"));
				if (portrait.length == 0) portrait = "boyfriend";
				if (!characters.exists(portrait))
				{
					characters.set(portrait, true);
					var character = Xml.createElement("char");
					character.set("name", portrait);
					character.set("position", characterPosition(portrait));
					root.addChild(character);
				}

				var line = Xml.createElement("line");
				line.set("char", portrait);
				line.set("bubble", field(entry, "boxState", "normal"));
				var expression = field(entry, "expression", "");
				if (expression.length > 0) line.set("changeDefAnim", expression);
				var textSound = field(entry, "sound", "");
				if (textSound.length > 0) line.set("textSound", textSound);
				var speed:Dynamic = Reflect.field(entry, "speed");
				if (speed != null)
				{
					var parsedSpeed = Std.parseFloat(Std.string(speed));
					if (!isFiniteNumber(parsedSpeed) || parsedSpeed < 0) return null;
					line.set("speed", Std.string(parsedSpeed));
				}
				line.addChild(Xml.createPCData(field(entry, "text", "")));
				root.addChild(line);
			}

			var document = Xml.createDocument();
			document.addChild(root);
			return document.toString();
		}
		catch (_:Dynamic)
		{
			return null;
		}
	}
}
