package;

import cne.compat.PsychHookMap;
import haxe.ds.ObjectMap;

class PsychHookMapContractTest
{
	static function main():Void
	{
		assertArrayEquals([4, 2, "Hurt", true], PsychHookMap.makeNoteHitArguments(4, 2, "Hurt", true), "goodNoteHit arguments");
		assertArrayEquals([1, 3, "", false], PsychHookMap.makeNoteMissArguments(1, 3, "", false), "noteMiss arguments");

		var earlyTime:Float = PsychHookMap.getEventTriggerTime(1200, 350);
		assertEquals(850.0, earlyTime, "event early trigger time");
		assertEquals(1200.0, PsychHookMap.getEventTriggerTime(1200, null), "event without early trigger");
		var oldEarlyArgs:Array<Dynamic> = PsychHookMap.makeEventEarlyTriggerArguments("0.6.3", "Camera Follow Pos", "1", "2", 1200);
		var newEarlyArgs:Array<Dynamic> = PsychHookMap.makeEventEarlyTriggerArguments("1.0.4", "Camera Follow Pos", 1, false, 1200);
		assertArrayEquals(["Camera Follow Pos"], oldEarlyArgs, "Psych 0.6.3 early-trigger arguments");
		var expectedNewEarlyArgs:Array<Dynamic> = ["Camera Follow Pos", "1", "false", 1200];
		assertArrayEquals(expectedNewEarlyArgs, newEarlyArgs, "Psych 1.0.4 early-trigger arguments");
		assertArrayEquals(["Set Property", "1.25", "false"], PsychHookMap.makeEventArguments("0.6.3", "Set Property", 1.25, false, 1200), "Psych 0.6.3 chart-event arguments");
		assertArrayEquals(["Set Property", "1.25", "false", 1200], PsychHookMap.makeEventArguments("1.0.4", "Set Property", 1.25, false, 1200), "Psych 1.0.4 chart-event arguments");
		assertArrayEquals(["move"], PsychHookMap.makeTweenCompletedArguments("0.6.3", "move", "sprite"), "Psych 0.6.3 tween completion arguments");
		assertArrayEquals(["move", "sprite"], PsychHookMap.makeTweenCompletedArguments("1.0.4", "move", "sprite"), "Psych 1.0.4 tween completion arguments");
		assertArrayEquals(["color", "sprite"], PsychHookMap.makeTweenCompletedArguments("0.6.3", "color", "sprite", true), "Psych 0.6.3 color tween completion arguments");

		assertArrayEquals([2, 3, "Hurt", true], PsychHookMap.makeSpawnNoteArguments("0.6.3", 2, 3, "Hurt", true, 980), "Psych 0.6.3 spawn arguments");
		var expectedSpawnArgs:Array<Dynamic> = [2, 3, "Hurt", true, 980.0];
		assertArrayEquals(expectedSpawnArgs, PsychHookMap.makeSpawnNoteArguments("1.0.4", 2, 3, "Hurt", true, 980), "Psych 1.0.4 spawn arguments");
		assertEquals(3, PsychHookMap.noteDirectionForHit(-3), "hit direction is absolute note data");

		assertTrue(PsychHookMap.isPsychNoteSpawned(1999.9, 0, 1), "note enters spawn view before the threshold");
		assertFalse(PsychHookMap.isPsychNoteSpawned(2000, 0, 1), "exact spawn threshold remains unspawned");
		assertTrue(PsychHookMap.isPsychNoteSpawned(1500, 0, 0.5), "slow song speed expands the spawn window");
		assertTrue(PsychHookMap.isPsychNoteSpawned(1000, 0, 1, 0.5), "slow note speed expands its spawn window");

		var press = [false, false, false, false];
		var release = [false, false, false, false];
		assertTrue(PsychHookMap.blockInputLane(press, release, 1, true), "first press cancellation");
		assertFalse(PsychHookMap.blockInputLane(press, release, 1, true), "duplicate press cancellation");
		assertTrue(PsychHookMap.blockInputLane(press, release, 3, false), "release cancellation");
		assertArrayEquals([false, true, false, false], press, "only selected press lane blocked");
		assertArrayEquals([false, false, false, true], release, "only selected release lane blocked");
		assertFalse(PsychHookMap.blockInputLane(press, release, 8, true), "out-of-range lane ignored");

		var first = note(100, "first-line");
		var second = note(100, "second-line");
		var later = note(250, "later-line");
		var earlier = note(50, "earlier-line");
		var combined = PsychHookMap.combinePsychNotes([[first, later], [second, earlier]], true);
		assertArrayEquals([later, first, second, earlier], combined, "multiple strumlines newest first and stable ties");
		assertEquals(2, PsychHookMap.indexOfNote(combined, second), "note index across strumlines");

		combined.remove(first);
		assertEquals(-1, PsychHookMap.indexOfNote(combined, first), "removed note has no group index");
		combined.insert(1, first);
		assertEquals(1, PsychHookMap.indexOfNote(combined, first), "note index reflects group reordering");
		assertEquals(-1, PsychHookMap.indexOfNote(null, first), "missing group index");

		var seen:ObjectMap<Dynamic, Bool> = new ObjectMap();
		assertArrayEquals([later, first], PsychHookMap.collectNewlySpawnedNotes(seen, [later, first]), "first spawn delivery");
		assertArrayEquals([], PsychHookMap.collectNewlySpawnedNotes(seen, [later, first]), "same notes are not delivered twice");
		assertArrayEquals([], PsychHookMap.collectNewlySpawnedNotes(seen, [first]), "removed note is not re-fired");
		assertArrayEquals([second], PsychHookMap.collectNewlySpawnedNotes(seen, [second, first]), "new note after reorder is delivered once");

		var spawnScanCalls = 0;
		var skippedSpawnBatch = PsychHookMap.collectSpawnNoteBatch(seen, false, () -> {
			spawnScanCalls++;
			return [note(300, "unused")];
		});
		assertEquals(null, skippedSpawnBatch, "no spawn hook skips the note scan");
		assertEquals(0, spawnScanCalls, "no spawn hook does not load the note group");
		var spawnBatch = PsychHookMap.collectSpawnNoteBatch(seen, true, () -> {
			spawnScanCalls++;
			return [second, earlier];
		});
		assertEquals(1, spawnScanCalls, "spawn hook loads the note group once");
		assertArrayEquals([second, earlier], spawnBatch.current, "spawn batch preserves current group");
		assertArrayEquals([earlier], spawnBatch.newlySpawned, "spawn batch reports only unseen notes");

		trace("PsychHookMapContractTest passed");
	}

	static function note(strumTime:Float, tag:String):Dynamic
		return {strumTime: strumTime, tag: tag};

	static function assertTrue(value:Bool, label:String):Void
	{
		if (!value) throw '$label: expected true';
	}

	static function assertFalse(value:Bool, label:String):Void
	{
		if (value) throw '$label: expected false';
	}

	static function assertEquals<T>(expected:T, actual:T, label:String):Void
	{
		if (expected != actual) throw '$label: expected $expected, got $actual';
	}

	static function assertArrayEquals(expected:Array<Dynamic>, actual:Array<Dynamic>, label:String):Void
	{
		if (actual == null || expected.length != actual.length) throw '$label: expected $expected, got $actual';
		for (index in 0...expected.length)
			if (expected[index] != actual[index]) throw '$label: mismatch at $index, expected ${expected[index]}, got ${actual[index]}';
	}
}
