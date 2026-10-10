import dbe.compatibility.chart.VSliceChartCodec;

class VSliceParserTest {
	static function main():Void {
		var chart:Dynamic = {
			strumLines: [
				{
					characters: ["dad"],
					type: 0,
					position: "dad",
					notes: [{time: 500, id: 2, type: 1, sLen: 250, params: [{name: "damage", value: 0.25}]}]
				},
				{
					characters: ["bf"],
					type: 1,
					position: "boyfriend",
					notes: [{time: 1200, id: 3, type: 0, sLen: 0}]
				}
			],
			events: [
				{name: "Camera Modulo Change", time: 1000, params: ([8, 0.75] : Array<Dynamic>)},
				{name: "BPM Change", time: 1500, params: [180]}
			],
			meta: {name: "compat-song", bpm: 120, beatsPerMeasure: 4, stepsPerBeat: 4, difficulties: ["hard"], customValues: {}},
			codenameChart: true,
			stage: "stage",
			scrollSpeed: 1.4,
			noteTypes: ["Alt Anim Note"]
		};

		var encoded:Dynamic = VSliceChartCodec.encode(chart, "hard");
		if (encoded == null)
			throw "DBE chart editor must encode its active difficulty as V-Slice chart data";
		if (Reflect.field(encoded, "version") != "2.0.0" || Reflect.field(Reflect.field(encoded, "scrollSpeed"), "hard") != 1.4)
			throw "V-Slice chart export must declare the 0.8.7 chart version and active scroll speed";

		var notes:Array<Dynamic> = Reflect.field(Reflect.field(encoded, "notes"), "hard");
		if (notes == null || notes.length != 2)
			throw "V-Slice chart export must include notes from both DBE play-side strumlines";
		if (notes[0].t != 500 || notes[0].d != 2 || notes[0].l != 250 || notes[0].k != "alt")
			throw "Opponent note data must map to the V-Slice lane and note-kind fields";
		if (notes[0].p == null || notes[0].p.length != 1 || notes[0].p[0].n != "damage" || notes[0].p[0].v != 0.25)
			throw "V-Slice note parameters must survive chart export";
		if (notes[1].t != 1200 || notes[1].d != 7 || notes[1].l != null)
			throw "Player note data must map to V-Slice player lanes and omit zero-length holds";

		var events:Array<Dynamic> = Reflect.field(encoded, "events");
		if (events.length != 1 || events[0].e != "SetCameraBop" || events[0].t != 1000 || events[0].v.rate != 8 || events[0].v.intensity != 0.75)
			throw "Supported DBE events must be encoded with V-Slice event names and values";

		var rawValue:Dynamic = {futureProperty: "keep-me"};
		var rawEventChart:Dynamic = Reflect.copy(chart);
		rawEventChart.events = [{name: VSliceChartCodec.RAW_EVENT_PREFIX + "FutureEvent", time: 2000, params: [rawValue]}];
		var rawEventOutput:Dynamic = VSliceChartCodec.encode(rawEventChart, "hard");
		if (rawEventOutput.events.length != 1 || rawEventOutput.events[0].e != "FutureEvent" || rawEventOutput.events[0].v.futureProperty != "keep-me")
			throw "Unknown V-Slice events retained by the parser must survive an export round-trip";

		var unsupportedEventRejected = false;
		var unsupportedEventChart:Dynamic = Reflect.copy(chart);
		unsupportedEventChart.events = [{name: "Continuous BPM Change", time: 2000, params: ([180, 8] : Array<Dynamic>)}];
		try {
			VSliceChartCodec.encode(unsupportedEventChart, "hard");
		} catch (_:Dynamic) {
			unsupportedEventRejected = true;
		}
		if (!unsupportedEventRejected)
			throw "The V-Slice exporter must reject events without an equivalent instead of silently dropping them";

		var unsupportedLaneRejected = false;
		var unsupportedLaneChart:Dynamic = Reflect.copy(chart);
		unsupportedLaneChart.strumLines = chart.strumLines.copy();
		unsupportedLaneChart.strumLines.push({characters: ["extra"], type: 2, position: "girlfriend", notes: [{time: 1500, id: 0, type: 0, sLen: 0}]});
		try {
			VSliceChartCodec.encode(unsupportedLaneChart, "hard");
		} catch (_:Dynamic) {
			unsupportedLaneRejected = true;
		}
		if (!unsupportedLaneRejected)
			throw "The V-Slice exporter must report additional-strumline notes as unrepresentable";

		var mergeTimeChangesFunction = Reflect.field(VSliceChartCodec, "encodeTimeChanges");
		if (mergeTimeChangesFunction == null)
			throw "V-Slice metadata export must merge BPM and time-signature events into a single timeline";
		var timeChanges:Array<Dynamic> = Reflect.callMethod(VSliceChartCodec, mergeTimeChangesFunction, [
			[{t: -1, bpm: 120, n: 4, d: 4}],
			[
				{name: "Time Signature Change", time: 2000, params: [3, 4]},
				{name: "BPM Change", time: 1000, params: [180]}
			],
			120,
			4,
			4
		]);
		if (timeChanges.length != 3 || timeChanges[1].t != 1000 || timeChanges[1].bpm != 180
			|| timeChanges[1].n != 4 || timeChanges[1].d != 4 || timeChanges[2].t != 2000
			|| timeChanges[2].bpm != 180 || timeChanges[2].n != 3 || timeChanges[2].d != 4)
			throw "Time-signature changes must retain the active BPM and inherit prior meter fields";

		var freeplayMeta:Dynamic = {
			songName: "Bopeebo",
			artist: "Kawai Sprite",
			timeChanges: [{bpm: 100, t: 0, n: 4, d: 4}],
			playData: {
				difficulties: ["easy", "normal", "hard"],
				songVariations: [],
				characters: {player: "bf", girlfriend: "gf", opponent: "dad"},
				stage: "mainStage",
				album: "volume1",
				previewStart: 12.5,
				previewEnd: 32.0,
				ratings: {easy: 1, normal: 3, hard: 5}
			}
		};
		var freeplayMetadataReader = Reflect.field(VSliceChartCodec, "extractFreeplayMetadata");
		if (freeplayMetadataReader == null)
			throw "V-Slice codec must expose a Freeplay metadata adapter";
		var freeplayValues:Dynamic = Reflect.callMethod(VSliceChartCodec, freeplayMetadataReader, [freeplayMeta]);
		if (freeplayValues.characters == null || freeplayValues.characters.player != "bf" || freeplayValues.characters.opponent != "dad")
			throw "V-Slice metadata must preserve playable characters for Freeplay filters and previews";
		if (freeplayValues.album != "volume1" || freeplayValues.previewStart != 12.5 || freeplayValues.previewEnd != 32.0
			|| freeplayValues.ratings.hard != 5 || freeplayValues.artist != "Kawai Sprite")
			throw "V-Slice metadata must preserve album, audio preview, rating, and artist fields for Freeplay";

		var characterOverride = Reflect.field(VSliceChartCodec, "applyPlayerCharacter");
		if (characterOverride == null)
			throw "V-Slice Freeplay must be able to apply its selected playable character to the chart";
		var overrideChart:Dynamic = Reflect.copy(chart);
		var sourceLines:Array<Dynamic> = cast chart.strumLines;
		overrideChart.strumLines = [for (line in sourceLines) Reflect.copy(line)];
		var overrideLines:Array<Dynamic> = cast overrideChart.strumLines;
		if (Reflect.callMethod(VSliceChartCodec, characterOverride, [overrideChart, "pico"]) != true
			|| overrideLines[1].characters[0] != "pico"
			|| overrideLines[0].characters[0] != "dad")
			throw "Freeplay character selection must affect only the player strumline";

		var unplayedProgress = VSliceChartCodec.summarizeFreeplayScore({score: 0, accuracy: 0, misses: 0, hits: new Map<String, Int>(), date: null});
		if (unplayedProgress.rank != "UNPLAYED") throw "Freeplay progress must distinguish songs without a saved score";
		var scoreHits = new Map<String, Int>();
		scoreHits.set("sick", 95);
		var excellentProgress = VSliceChartCodec.summarizeFreeplayScore({score: 95000, accuracy: 0.95, misses: 5, hits: scoreHits, date: "2026-10-07"});
		if (excellentProgress.rank != "EXCELLENT" || excellentProgress.misses != 5 || excellentProgress.accuracy != 95)
			throw "Freeplay must show V-Slice style rank, accuracy, and miss progress from the saved score";

		trace("VSliceParserTest: PASS");
	}
}
