package cne.compat;

import flixel.util.FlxSave;
import funkin.backend.assets.ModsFolder;
import funkin.backend.assets.Paths;
import openfl.utils.Assets;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

/** Minimal persistent implementation of Psych's named achievement Lua API. */
class PsychAchievementStore
{
	private static var definitionsByMod:Map<String, Map<String, Float>> = [];
	private static var save:FlxSave;

	public static function exists(name:String):Bool
		return name != null && getDefinitions().exists(name);

	public static function isUnlocked(name:String):Bool
	{
		if (!exists(name)) return false;
		var data = getSaveData();
		return data != null && Reflect.field(data, unlockedField(name)) == true;
	}

	public static function getScore(name:String):Float
	{
		var maxScore = getMaxScore(name);
		if (maxScore == null) return -1;
		if (maxScore <= 0) return -1;
		if (isUnlocked(name)) return maxScore;
		var data = getSaveData();
		var value:Dynamic = data == null ? null : Reflect.field(data, scoreField(name));
		return value == null ? 0 : Std.parseFloat(Std.string(value));
	}

	public static function setScore(name:String, value:Float, ?saveIfNotUnlocked:Bool = true):Float
		return updateScore(name, value, false, saveIfNotUnlocked);

	public static function addScore(name:String, ?value:Float = 1, ?saveIfNotUnlocked:Bool = true):Float
		return updateScore(name, value, true, saveIfNotUnlocked);

	public static function unlock(name:String):String
	{
		if (!exists(name) || isUnlocked(name)) return null;
		var data = getSaveData();
		if (data == null) return null;
		Reflect.setField(data, unlockedField(name), true);
		if (save != null) save.flush();
		return name;
	}

	private static function updateScore(name:String, value:Float, add:Bool, saveIfNotUnlocked:Bool):Float
	{
		var maxScore = getMaxScore(name);
		if (maxScore == null || maxScore < 1) return -1;
		if (isUnlocked(name)) return maxScore;
		var current = getScore(name);
		var next = add ? current + value : value;
		if (next >= maxScore) next = maxScore;
		var data = getSaveData();
		if (data == null) return -1;
		Reflect.setField(data, scoreField(name), next);
		if (next >= maxScore)
		{
			unlock(name);
			return maxScore;
		}
		if (saveIfNotUnlocked && save != null) save.flush();
		return next;
	}

	private static function getMaxScore(name:String):Null<Float>
	{
		if (!exists(name)) return null;
		return getDefinitions().get(name);
	}

	private static function getDefinitions():Map<String, Float>
	{
		var mod = ModsFolder.currentModFolder == null ? "(base)" : ModsFolder.currentModFolder;
		var definitions = definitionsByMod.get(mod);
		if (definitions != null) return definitions;

		definitions = [
			"friday_night_play" => 0,
			"week1_nomiss" => 0,
			"week2_nomiss" => 0,
			"week3_nomiss" => 0,
			"week4_nomiss" => 0,
			"week5_nomiss" => 0,
			"week6_nomiss" => 0,
			"week7_nomiss" => 0,
			"weekend1_nomiss" => 0,
			"ur_bad" => 0,
			"ur_good" => 0,
			"roadkill_enthusiast" => 50,
			"oversinging" => 0,
			"hype" => 0,
			"two_keys" => 0,
			"toastie" => 0,
			"debugger" => 0,
			"pessy_easter_egg" => 0
		];

		var source:String = null;
		#if sys
		var modRoots:Array<String> = [];
		if (ModsFolder.currentModLoadPath != null) modRoots.push(ModsFolder.currentModLoadPath);
		if (ModsFolder.currentModFolder != null)
			modRoots.push(haxe.io.Path.join([ModsFolder.modsPath, ModsFolder.currentModFolder]));
		for (root in modRoots)
		{
			var modFile = haxe.io.Path.join([root, "data", "achievements.json"]);
			if (FileSystem.exists(modFile) && !FileSystem.isDirectory(modFile))
				try { source = File.getContent(modFile); break; } catch (_:Dynamic) {}
		}
		#end
		var path = Paths.json("achievements");
		if (source == null && Assets.exists(path)) source = Assets.getText(path);
		if (source != null)
			try
			{
				var parsed:Dynamic = haxe.Json.parse(source);
				var entries:Dynamic = Std.isOfType(parsed, Array) ? parsed : Reflect.field(parsed, "achievements");
				if (Std.isOfType(entries, Array))
					for (entry in (cast entries:Array<Dynamic>))
					{
						var key:Dynamic = entry == null ? null : Reflect.field(entry, "save");
					if (key == null || Std.string(key).length == 0) continue;
					var max:Dynamic = Reflect.field(entry, "maxScore");
					definitions.set(Std.string(key), max == null ? 0 : Std.parseFloat(Std.string(max)));
				}
			}
			catch (_:Dynamic) {}

		definitionsByMod.set(mod, definitions);
		return definitions;
	}

	private static function getSaveData():Dynamic
	{
		if (save == null)
		{
			save = new FlxSave();
			if (!save.bind("psychAchievements", "psychenginemods"))
			{
				save.destroy();
				save = null;
				return null;
			}
		}
		return save.data;
	}

	private static inline function scoreField(name:String):String
		return 'score_$name';

	private static inline function unlockedField(name:String):String
		return 'unlocked_$name';
}
