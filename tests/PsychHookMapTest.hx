import cne.compat.PsychHookMap;

class PsychHookMapTest
{
	static function assertHooks(engineHook:String, expected:Array<String>):Void
	{
		var actual = PsychHookMap.getHooks(engineHook);
		if (actual.length != expected.length) throw 'Unexpected callback count for $engineHook: $actual';
		for (index in 0...expected.length)
			if (actual[index] != expected[index]) throw 'Unexpected callback mapping for $engineHook: $actual';
	}

	static function main():Void
	{
		assertHooks("create", ["onCreate", "create"]);
		assertHooks("postCreate", ["onCreatePost", "postCreate"]);
		assertHooks("update", ["onUpdate", "update"]);
		assertHooks("postUpdate", ["onUpdatePost", "postUpdate"]);
		assertHooks("stepHit", ["onStepHit", "stepHit"]);
		assertHooks("measureHit", ["onSectionHit", "measureHit"]);
		assertHooks("beatHit", ["onBeatHit", "beatHit"]);
		assertHooks("destroy", ["onDestroy", "destroy"]);
		assertHooks("onPlayerHit", ["goodNoteHit"]);
		assertHooks("onDadHit", ["opponentNoteHit"]);
		var hitArgs = PsychHookMap.makeNoteHitArguments(7, 2, "Alt Animation", true);
		if (hitArgs.length != 4 || hitArgs[0] != 7 || hitArgs[1] != 2 || hitArgs[2] != "Alt Animation" || hitArgs[3] != true)
			throw 'Psych note hit arguments must preserve the group index, direction, type, and sustain flag: $hitArgs';
		var missArgs = PsychHookMap.makeNoteMissArguments(4, 1, null, false);
		if (missArgs.length != 4 || missArgs[0] != 4 || missArgs[1] != 1 || missArgs[2] != null || missArgs[3] != false)
			throw 'Psych note miss arguments must preserve the group index, direction, type, and sustain flag: $missArgs';
		var firstNote = {};
		var secondNote = {};
		if (PsychHookMap.indexOfNote([firstNote, secondNote], secondNote) != 1)
			throw "Psych callback note ids must use the note's group index";
		if (PsychHookMap.indexOfNote([firstNote], secondNote) != -1)
			throw "Missing notes must return the documented sentinel id";
		var justPressed = [true, true, false];
		var justReleased = [false, true, true];
		var blockedPress = [false, false, false];
		var blockedRelease = [false, false, false];
		if (!PsychHookMap.blockInputLane(blockedPress, blockedRelease, 1, true))
			throw "A stopped Psych key press must be reported as blocked";
		if (!blockedPress[1] || blockedPress[0] || !justPressed[1] || !justPressed[0] || !justReleased[1])
			throw "Stopping one Psych key press must preserve callback input while blocking only its lane";
		if (!PsychHookMap.blockInputLane(blockedPress, blockedRelease, 2, false))
			throw "A stopped Psych key release must be reported as blocked";
		if (!blockedRelease[2] || blockedRelease[1] || !justReleased[2] || !justReleased[1])
			throw "Stopping one Psych key release must preserve callback input while blocking only its lane";
		if (PsychHookMap.getEventTriggerTime(1000, 250) != 750 || PsychHookMap.getEventTriggerTime(1000, null) != 1000)
			throw "Psych early trigger offsets must schedule events before their original chart time";
		var seenNotes:Array<Dynamic> = [firstNote];
		var spawned = PsychHookMap.collectNewlySpawnedNotes(seenNotes, [firstNote, secondNote]);
		if (spawned.length != 1 || spawned[0] != secondNote || seenNotes.length != 2)
			throw "Psych spawn callbacks must fire once for notes newly entering the spawned group";
		if (PsychHookMap.collectNewlySpawnedNotes(seenNotes, [firstNote, secondNote]).length != 0)
			throw "Psych spawn callbacks must not repeat for already observed notes";
		var earlyNote:Dynamic = {strumTime: 100.0};
		var lateNote:Dynamic = {strumTime: 300.0};
		var psychNotes = PsychHookMap.sortPsychNotes([earlyNote, lateNote], true);
		if (psychNotes[0] != lateNote || psychNotes[1] != earlyNote)
			throw "Psych spawned-note indexes must put the newest note first";
		var unspawnedNotes = PsychHookMap.sortPsychNotes([lateNote, earlyNote], false);
		if (unspawnedNotes[0] != earlyNote || unspawnedNotes[1] != lateNote)
			throw "Psych unspawned-note indexes must put the next note first";
		assertHooks("unknownHook", ["unknownHook"]);
		Sys.println("PsychHookMapTest: PASS");
	}
}
