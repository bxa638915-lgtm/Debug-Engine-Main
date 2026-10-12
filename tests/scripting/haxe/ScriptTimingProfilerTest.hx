import dbe.diagnostics.ScriptTimingProfiler;

class ScriptTimingProfilerTest {
	static function main():Void {
		ScriptTimingProfiler.reset();
		ScriptTimingProfiler.recordScriptCallback("mods/example.lua", "update", 1.25);
		ScriptTimingProfiler.recordScriptCallback("mods/example.lua", "update", 2.75);
		ScriptTimingProfiler.recordRunHaxeCode("mods/example.lua", 0.5);
		ScriptTimingProfiler.recordFrameInterval(1000.0);
		ScriptTimingProfiler.recordPlayStateUpdate(12.0);
		ScriptTimingProfiler.recordPlayStateDraw(8.0);

		assertEntry("script-callback", "mods/example.lua::update", 2, 4.0, 2.75);
		assertEntry("runHaxeCode", "mods/example.lua", 1, 0.5, 0.5);
		assertEntry("frame-interval", "PlayState", 1, 1000.0, 1000.0);
		assertEntry("playstate-update", "PlayState", 1, 12.0, 12.0);
		assertEntry("playstate-draw", "PlayState", 1, 8.0, 8.0);

		ScriptTimingProfiler.stop();
		ScriptTimingProfiler.recordScriptCallback("mods/ignored.lua", "update", 5.0);
		if (ScriptTimingProfiler.snapshot().length != 5)
			throw "stop() must freeze the current profile";

		ScriptTimingProfiler.reset();
		if (!ScriptTimingProfiler.enabled || ScriptTimingProfiler.snapshot().length != 0)
			throw "reset() must start a fresh profile";

		trace("ScriptTimingProfilerTest passed");
	}

	static function assertEntry(category:String, label:String, calls:Int, totalMs:Float, maxMs:Float):Void {
		for (entry in ScriptTimingProfiler.snapshot()) {
			if (entry.category == category && entry.label == label) {
				if (entry.calls != calls || entry.totalMs != totalMs || entry.maxMs != maxMs)
					throw 'unexpected stats for $category/$label: $entry';
				return;
			}
		}
		throw 'missing stats for $category/$label';
	}
}
