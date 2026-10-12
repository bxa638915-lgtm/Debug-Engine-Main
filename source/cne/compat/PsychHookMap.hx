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

	/** Combines each strumline's current note members and orders the shared Psych group view. */
	public static function combinePsychNotes(notesByStrumline:Array<Array<Dynamic>>, newestFirst:Bool):Array<Dynamic>
	{
		var notes:Array<Dynamic> = [];
		if (notesByStrumline != null)
			for (lineNotes in notesByStrumline)
				if (lineNotes != null)
					for (note in lineNotes)
						if (note != null) notes.push(note);
		return sortPsychNotes(notes, newestFirst);
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

	/** Psych 0.6.3 passes only the event name; 1.0.4 adds values and chart time. */
	public static function makeEventEarlyTriggerArguments(profile:String, name:String, value1:Dynamic, value2:Dynamic, chartTime:Float):Array<Dynamic>
	{
		return profile == "0.6.3" ? [name] : [name, psychEventValue(value1), psychEventValue(value2), chartTime];
	}

	/** Converts DBE chart event values to Psych's string parameters and profile-specific arity. */
	public static function makeEventArguments(profile:String, name:String, value1:Dynamic, value2:Dynamic, chartTime:Float):Array<Dynamic>
	{
		var args:Array<Dynamic> = [name, psychEventValue(value1), psychEventValue(value2)];
		if (profile != "0.6.3") args.push(chartTime);
		return args;
	}

	/** Psych 0.6.3 omits the tween target; 1.0.4 passes it after the tag. */
	public static function makeTweenCompletedArguments(profile:String, tag:String, target:String, ?alwaysIncludeTarget:Bool = false):Array<Dynamic>
		return profile == "0.6.3" && !alwaysIncludeTarget ? [tag] : [tag, target];

	private static inline function psychEventValue(value:Dynamic):String
		return value == null ? "" : Std.string(value);

	/** The callback gained strumTime in Psych 1.0.4. */
	public static function makeSpawnNoteArguments(profile:String, noteIndex:Int, noteData:Int, noteType:String, isSustainNote:Bool, strumTime:Float):Array<Dynamic>
	{
		var args:Array<Dynamic> = [noteIndex, noteData, noteType, isSustainNote];
		if (profile != "0.6.3") args.push(strumTime);
		return args;
	}

	/** Psych reports the absolute lane for successful hits, while noteMiss retains signed noteData. */
	public static inline function noteDirectionForHit(noteData:Int):Int
	{
		return Std.int(Math.abs(noteData));
	}

	/** Matches PlayState's spawnTime comparison, including its strict boundary and speed adjustments. */
	public static function isPsychNoteSpawned(strumTime:Float, songPosition:Float, songSpeed:Float, ?noteSpeed:Float = 1,
		?spawnTime:Float = 2000, ?playbackRate:Float = 1):Bool
	{
		var time = spawnTime * playbackRate;
		if (songSpeed < 1) time /= songSpeed;
		if (noteSpeed < 1) time /= noteSpeed;
		return strumTime - songPosition < time;
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
		var indexed:Array<{note:Dynamic, index:Int}> = [];
		for (index in 0...notes.length) indexed.push({note: notes[index], index: index});
		indexed.sort(function(a:{note:Dynamic, index:Int}, b:{note:Dynamic, index:Int}):Int
		{
			var delta:Float = cast Reflect.field(a.note, "strumTime") - cast Reflect.field(b.note, "strumTime");
			return delta < 0 ? -direction : (delta > 0 ? direction : a.index - b.index);
		});
		for (index in 0...indexed.length) notes[index] = indexed[index].note;
		return notes;
	}
}
