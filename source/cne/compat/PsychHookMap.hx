package cne.compat;

/** Maps lifecycle calls emitted by CNE to the corresponding Psych Lua hooks. */
class PsychHookMap
{
	public static inline var API_VERSION:Int = 1;

	public static function getHooks(engineHook:String):Array<String>
	{
		return switch (engineHook)
		{
			case "create": ["onCreate", "create"];
			case "postCreate": ["onCreatePost", "postCreate"];
			case "onPostStartCountdown": ["onCountdownStarted"];
			case "update": ["onUpdate", "update"];
			case "postUpdate": ["onUpdatePost", "postUpdate"];
			case "stepHit": ["onStepHit", "stepHit"];
			case "measureHit": ["onSectionHit", "measureHit"];
			case "beatHit": ["onBeatHit", "beatHit"];
			case "destroy": ["onDestroy", "destroy"];
			case "onPlayerHit": ["goodNoteHit"];
			case "onDadHit": ["opponentNoteHit"];
			default: [engineHook];
		}
	}

	/** Builds the scalar arguments expected by Psych's goodNoteHit callback. */
	public static function makeNoteHitArguments(noteIndex:Int, direction:Int, noteType:String, isSustainNote:Bool):Array<Dynamic>
	{
		return [noteIndex, direction, noteType, isSustainNote];
	}

	/** Builds the scalar arguments expected by Psych's noteMiss callback. */
	public static function makeNoteMissArguments(noteIndex:Int, direction:Int, noteType:String, isSustainNote:Bool):Array<Dynamic>
	{
		return [noteIndex, direction, noteType, isSustainNote];
	}

	/** Returns a note's zero-based index in its CNE note group, or -1 if absent. */
	public static function indexOfNote(notes:Array<Dynamic>, note:Dynamic):Int
	{
		return notes == null || note == null ? -1 : notes.indexOf(note);
	}

	/** Suppresses only the requested key edge, matching Psych's per-lane pre-input stop behavior. */
	public static function blockInputLane(blockedPress:Array<Bool>, blockedRelease:Array<Bool>, lane:Int, pressEdge:Bool):Bool
	{
		var blocked = pressEdge ? blockedPress : blockedRelease;
		if (blocked == null || lane < 0 || lane >= blocked.length || blocked[lane]) return false;
		blocked[lane] = true;
		return true;
	}

	/** Computes the chart timestamp at which Psych dispatches an early-triggered event. */
	public static inline function getEventTriggerTime(chartTime:Float, earlyTrigger:Null<Float>):Float
	{
		return chartTime - (earlyTrigger == null ? 0 : earlyTrigger);
	}

	/** Returns each note entering Psych's spawned-note view once and records it for later frames. */
	public static function collectNewlySpawnedNotes(seen:Array<Dynamic>, current:Array<Dynamic>):Array<Dynamic>
	{
		if (seen == null || current == null) return [];
		var newlySpawned:Array<Dynamic> = [];
		for (note in current)
			if (note != null && !seen.contains(note))
			{
				seen.push(note);
				newlySpawned.push(note);
			}
		return newlySpawned;
	}

	/** Psych inserts newly spawned notes at index zero; unspawned notes stay earliest-first. */
	public static function sortPsychNotes(notes:Array<Dynamic>, newestFirst:Bool):Array<Dynamic>
	{
		if (notes == null) return [];
		var direction = newestFirst ? -1 : 1;
		notes.sort(function(a:Dynamic, b:Dynamic):Int
		{
			var delta:Float = cast Reflect.field(a, "strumTime") - cast Reflect.field(b, "strumTime");
			return delta < 0 ? -direction : (delta > 0 ? direction : 0);
		});
		return notes;
	}
}
