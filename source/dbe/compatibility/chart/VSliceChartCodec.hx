package dbe.compatibility.chart;

/**
 * Pure data conversion for exporting a DBE chart to the V-Slice 2.0 format
 * used by Friday Night Funkin' 0.8.7. Kept separate from the editor and
 * Flixel runtime so lane/event mapping can be verified with small fixtures.
 */
class VSliceChartCodec {
	public static inline var VSLICE_CHART_VERSION:String = "2.0.0";
	public static inline var RAW_EVENT_PREFIX:String = "V-Slice Raw Event: ";

	/** Extract the V-Slice song fields used by Freeplay without depending on game runtime types. */
	public static function extractFreeplayMetadata(metadata:Dynamic):Dynamic {
		if (metadata == null)
			throw new haxe.Exception("V-Slice Freeplay metadata cannot be null.");

		var playData:Dynamic = Reflect.field(metadata, "playData");
		if (playData == null)
			throw new haxe.Exception("V-Slice song metadata is missing playData.");

		var difficulties:Array<String> = Reflect.field(playData, "difficulties");
		if (difficulties == null) difficulties = [];
		var ratings:Dynamic = Reflect.field(playData, "ratings");
		var characters:Dynamic = Reflect.field(playData, "characters");
		return {
			songName: _stringField(metadata, "songName", "Unknown"),
			artist: _stringField(metadata, "artist", "Unknown"),
			album: _nullableStringField(playData, "album"),
			characters: characters == null ? {} : Reflect.copy(characters),
			difficulties: difficulties.copy(),
			ratings: ratings == null ? {} : Reflect.copy(ratings),
			previewStart: _numberField(playData, "previewStart", 0),
			previewEnd: _numberField(playData, "previewEnd", 0.2)
		};
	}

	/** Summarize the saved DBE score using the rank thresholds used by V-Slice Freeplay. */
	public static function summarizeFreeplayScore(score:Dynamic):Dynamic {
		if (score == null)
			return {rank: "UNPLAYED", accuracy: 0.0, misses: 0, completion: 0.0};

		var rawMisses:Dynamic = Reflect.field(score, "misses");
		var misses:Int = Std.isOfType(rawMisses, Int) ? cast rawMisses : 0;
		var rawAccuracy:Dynamic = Reflect.field(score, "accuracy");
		var accuracy:Float = Std.isOfType(rawAccuracy, Int) || Std.isOfType(rawAccuracy, Float) ? cast rawAccuracy : 0;
		var rawHits:Dynamic = Reflect.field(score, "hits");
		var hits:Map<String, Int> = rawHits == null ? null : cast rawHits;
		var sick:Int = hits == null ? 0 : (hits.get("sick") ?? 0);
		var good:Int = hits == null ? 0 : (hits.get("good") ?? 0);
		var total:Int = misses < 0 ? 0 : misses;
		if (hits != null) for (count in hits) total += count < 0 ? 0 : count;

		var date:Dynamic = Reflect.field(score, "date");
		if (date == null || date == "" || total == 0)
			return {rank: "UNPLAYED", accuracy: 0.0, misses: 0, completion: 0.0};

		var completion:Float = Math.max(0, Math.min(1, (sick + good - misses) / total));
		var rank:String;
		if (misses == 0 && sick == total) rank = "PERFECT GOLD";
		else if (completion >= 1) rank = "PERFECT";
		else if (completion >= 0.90) rank = "EXCELLENT";
		else if (completion >= 0.80) rank = "GREAT";
		else if (completion >= 0.60) rank = "GOOD";
		else rank = "SHIT";

		return {
			rank: rank,
			accuracy: Math.round(Math.max(0, Math.min(1, accuracy)) * 1000) / 10,
			misses: Math.max(0, misses),
			completion: Math.round(completion * 1000) / 10
		};
	}

	/** Apply Freeplay's selected playable character to a parsed chart without changing its notes. */
	public static function applyPlayerCharacter(chart:Dynamic, character:String):Bool {
		if (chart == null || character == null || StringTools.trim(character) == "") return false;
	var strumLines:Array<Dynamic> = Reflect.field(chart, "strumLines");
		if (strumLines == null) return false;
		for (line in strumLines) if (line != null && Reflect.field(line, "type") == 1) {
			Reflect.setField(line, "characters", [character]);
			return true;
		}
		return false;
	}

	public static function encode(chart:Dynamic, difficulty:String = "normal"):Dynamic {
		if (chart == null)
			throw new haxe.Exception("Cannot export a null chart to V-Slice.");
		if (difficulty == null || StringTools.trim(difficulty) == "")
			throw new haxe.Exception("V-Slice export requires a non-empty difficulty name.");

		var strumLines:Array<Dynamic> = Reflect.field(chart, "strumLines");
		if (strumLines == null)
			throw new haxe.Exception("Cannot export a chart without strumlines to V-Slice.");
		var noteTypes:Array<String> = Reflect.field(chart, "noteTypes");
		if (noteTypes == null) noteTypes = [];

		var sortableNotes:Array<{note:Dynamic, order:Int}> = [];
		var noteOrder = 0;
		for (lineIndex in 0...strumLines.length) {
			var strumLine = strumLines[lineIndex];
			if (strumLine == null)
				throw new haxe.Exception('Cannot export null strumline ${lineIndex} to V-Slice.');
			var lineType:Dynamic = Reflect.field(strumLine, "type");
			var lineNotes:Array<Dynamic> = Reflect.field(strumLine, "notes");
			if (lineNotes == null) lineNotes = [];
			if (lineType == 2 && lineNotes.length > 0)
				throw new haxe.Exception("V-Slice 0.8.7 charts have only opponent/player lanes; additional-strumline notes cannot be exported without loss.");
			if (lineType != 0 && lineType != 1 && lineNotes.length > 0)
				throw new haxe.Exception('V-Slice export does not support strumline type ${Std.string(lineType)}.');

			for (note in lineNotes) {
				if (note == null)
					throw new haxe.Exception("Cannot export null chart notes to V-Slice.");
				var id:Dynamic = Reflect.field(note, "id");
				if (!Std.isOfType(id, Int) || (cast id:Int) < 0 || (cast id:Int) > 3)
					throw new haxe.Exception('V-Slice 0.8.7 supports four lanes per side; note lane ${Std.string(id)} cannot be exported.');

				var time:Dynamic = Reflect.field(note, "time");
				var length:Dynamic = Reflect.field(note, "sLen");
				if (!Std.isOfType(time, Int) && !Std.isOfType(time, Float))
					throw new haxe.Exception("V-Slice note timestamps must be numeric.");
				if (length != null && !Std.isOfType(length, Int) && !Std.isOfType(length, Float))
					throw new haxe.Exception("V-Slice note lengths must be numeric.");

				var encodedNote:Dynamic = {
					t: cast time,
					d: (cast id:Int) + (lineType == 1 ? 4 : 0)
				};
				if (length != null && (cast length:Float) > 0)
					Reflect.setField(encodedNote, "l", length);

				var typeIndex:Dynamic = Reflect.field(note, "type");
				if (typeIndex != null && typeIndex != 0) {
					if (!Std.isOfType(typeIndex, Int) || (cast typeIndex:Int) < 1 || (cast typeIndex:Int) > noteTypes.length)
						throw new haxe.Exception('Note type index ${Std.string(typeIndex)} does not resolve in the chart noteTypes list.');
					var typeName = noteTypes[(cast typeIndex:Int) - 1];
					Reflect.setField(encodedNote, "k", typeName == "Alt Anim Note" ? "alt" : typeName);
				}

				var params:Array<Dynamic> = Reflect.field(note, "params");
				if (params != null && params.length > 0) {
					var encodedParams:Array<Dynamic> = [];
					for (param in params) {
						if (param == null || !Std.isOfType(Reflect.field(param, "name"), String))
							throw new haxe.Exception("V-Slice note parameters require a string name and a value.");
						encodedParams.push({n: Reflect.field(param, "name"), v: Reflect.field(param, "value")});
					}
					Reflect.setField(encodedNote, "p", encodedParams);
				}
				sortableNotes.push({note: encodedNote, order: noteOrder++});
			}
		}

		sortableNotes.sort(function(a, b) {
			var timeA:Float = Reflect.field(a.note, "t");
			var timeB:Float = Reflect.field(b.note, "t");
			return timeA < timeB ? -1 : (timeA > timeB ? 1 : a.order - b.order);
		});
		var encodedNotes:Array<Dynamic> = [for (entry in sortableNotes) entry.note];
		var noteMap:Dynamic = {};
		Reflect.setField(noteMap, difficulty, encodedNotes);

		var encodedEvents:Array<{event:Dynamic, order:Int}> = [];
		var events:Array<Dynamic> = Reflect.field(chart, "events");
		if (events != null) {
			var eventOrder = 0;
			for (event in events) {
				if (event == null) continue;
				var name:Dynamic = Reflect.field(event, "name");
				if (!Std.isOfType(name, String))
					throw new haxe.Exception("V-Slice chart events require a string name.");
				var time:Dynamic = Reflect.field(event, "time");
				if (!Std.isOfType(time, Int) && !Std.isOfType(time, Float))
					throw new haxe.Exception('V-Slice event "${name}" has a non-numeric timestamp.');
				var params:Array<Dynamic> = Reflect.field(event, "params");
				if (params == null) params = [];
				var converted = _encodeEvent(chart, cast name, cast time, params);
				for (outputEvent in converted) encodedEvents.push({event: outputEvent, order: eventOrder++});
			}
		}
		encodedEvents.sort(function(a, b) {
			var timeA:Float = Reflect.field(a.event, "t");
			var timeB:Float = Reflect.field(b.event, "t");
			return timeA < timeB ? -1 : (timeA > timeB ? 1 : a.order - b.order);
		});

		var result:Dynamic = {
			version: VSLICE_CHART_VERSION,
			scrollSpeed: {},
			events: [for (entry in encodedEvents) entry.event],
			notes: noteMap,
			generatedBy: "DBE (Debug Engine) - Codename Editor"
		};
		var speed:Dynamic = Reflect.field(chart, "scrollSpeed");
		Reflect.setField(result.scrollSpeed, difficulty, speed == null ? 1 : speed);
		return result;
	}

	/** Merge DBE tempo/meter events into the full-state timeline required by V-Slice metadata. */
	public static function encodeTimeChanges(source:Array<Dynamic>, chartEvents:Array<Dynamic>, initialBpm:Float, initialNumerator:Int, initialDenominator:Int):Array<Dynamic> {
		var result:Array<Dynamic> = source == null ? [] : [for (change in source) Reflect.copy(change)];
		if (result.length == 0)
			result.push({t: -1, bpm: initialBpm, n: initialNumerator, d: initialDenominator});
		result.sort(function(a, b) return a.t - b.t);
		if (result[0].t > -1)
			result.unshift({t: -1, bpm: initialBpm, n: initialNumerator, d: initialDenominator});
		result[0].bpm = initialBpm;

		var sortedEvents:Array<Dynamic> = chartEvents == null ? [] : chartEvents.copy();
		sortedEvents.sort(function(a, b) return a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
		for (event in sortedEvents) {
			if (event == null) continue;
			var eventName:Dynamic = Reflect.field(event, "name");
			if (eventName != "BPM Change" && eventName != "Time Signature Change" && eventName != "Continuous BPM Change")
				continue;
			if (eventName == "Continuous BPM Change")
				throw new haxe.Exception("V-Slice metadata cannot represent continuous BPM ramps; export stopped to avoid silently flattening the event.");
			var rawTime:Dynamic = Reflect.field(event, "time");
			if (!Std.isOfType(rawTime, Int) && !Std.isOfType(rawTime, Float))
				throw new haxe.Exception('Cannot export ${eventName} event with a non-numeric timestamp.');
			var time:Int = Math.round(cast rawTime);
			var params:Array<Dynamic> = Reflect.field(event, "params");
			if (params == null) params = [];
			var change:Dynamic = null;
			for (candidate in result) if (candidate.t == time) {
				change = candidate;
				break;
			}

			if (eventName == "BPM Change") {
				if (params.length == 0 || (!Std.isOfType(params[0], Int) && !Std.isOfType(params[0], Float)))
					throw new haxe.Exception("Cannot export BPM Change event without a numeric target BPM.");
				if (change == null) {
					change = {t: time, bpm: params[0]};
					result.push(change);
				} else change.bpm = params[0];
			} else {
				if (params.length < 2 || (!Std.isOfType(params[0], Int) && !Std.isOfType(params[0], Float))
					|| (!Std.isOfType(params[1], Int) && !Std.isOfType(params[1], Float)))
					throw new haxe.Exception("Cannot export Time Signature Change event without numeric numerator and denominator.");
				if (change == null) {
					var activeBpm:Float = initialBpm;
					for (candidate in result) if (candidate.t < time && candidate.bpm != null && candidate.t >= -1)
						activeBpm = candidate.bpm;
					change = {t: time, bpm: activeBpm};
					result.push(change);
				}
				change.n = Std.int(params[0]);
				change.d = Std.int(params[1]);
			}
		}

		result.sort(function(a, b) return a.t - b.t);
		var activeBpm:Float = initialBpm;
		var activeNumerator:Int = initialNumerator;
		var activeDenominator:Int = initialDenominator;
		for (change in result) {
			if (change.bpm == null) change.bpm = activeBpm;
			else activeBpm = change.bpm;
			if (change.n == null) change.n = activeNumerator;
			else activeNumerator = change.n;
			if (change.d == null) change.d = activeDenominator;
			else activeDenominator = change.d;
		}
		return result;
	}

	static function _encodeEvent(chart:Dynamic, name:String, time:Float, params:Array<Dynamic>):Array<Dynamic> {
		var values:Dynamic;
		var eventName:String = name;
		switch (name) {
			case "BPM Change" | "Time Signature Change":
				// These are serialized into metadata.timeChanges by VSliceParser.encodeMeta.
				return [];
			case "Camera Movement":
				var target = _numberParam(params, 0, 0);
				var char = switch (Std.int(target)) {
					case 0: 1;
					case 1: 0;
					case 2: 2;
					case -1: -1;
					default: throw new haxe.Exception('Camera target ${target} has no V-Slice equivalent.');
				};
				values = {char: char};
				_applyTween(values, params, 1, 2, 3, 4);
				if (_numberParam(params, 5, 0) != 0) Reflect.setField(values, "x", params[5]);
				if (_numberParam(params, 6, 0) != 0) Reflect.setField(values, "y", params[6]);
			case "Camera Position":
				values = {char: -1, x: _numberParam(params, 0, 0), y: _numberParam(params, 1, 0)};
				_applyTween(values, params, 2, 3, 4, 5);
			case "Play Animation":
				var lines:Array<Dynamic> = Reflect.field(chart, "strumLines");
				var lineIndex = Std.int(_numberParam(params, 0, -1));
				if (lineIndex < 0 || lineIndex >= lines.length)
					throw new haxe.Exception("Play Animation event references a strumline that does not exist.");
				var lineType:Dynamic = Reflect.field(lines[lineIndex], "type");
				var target = switch (lineType) {
					case 0: "opponent";
					case 1: "boyfriend";
					case 2: "girlfriend";
					default: throw new haxe.Exception("Play Animation event references a strumline type V-Slice cannot represent.");
				};
				eventName = "PlayAnimation";
				values = {target: target, anim: _stringParam(params, 1, "idle"), force: _boolParam(params, 2, false)};
			case "Scroll Speed Change":
				eventName = "ScrollSpeed";
				values = {
					scroll: _numberParam(params, 1, 1),
					duration: _numberParam(params, 2, 4),
					ease: _tweenEase(params, 0, 3, 4),
					absolute: !_boolParam(params, 5, false)
				};
			case "Camera Modulo Change":
				eventName = "SetCameraBop";
				values = {rate: _numberParam(params, 0, 4), intensity: _numberParam(params, 1, 1)};
			case "Camera Zoom":
				if (_stringParam(params, 2, "camGame") != "camGame" || _boolParam(params, 7, false))
					throw new haxe.Exception("V-Slice ZoomCamera cannot represent this camera target or multiplicative zoom mode.");
				eventName = "ZoomCamera";
				values = {
					zoom: _numberParam(params, 1, 1),
					duration: _numberParam(params, 3, 4),
					ease: _tweenEase(params, 0, 3, 4),
					mode: _stringParam(params, 6, "stage")
				};
			default:
				if (StringTools.startsWith(name, RAW_EVENT_PREFIX)) {
					eventName = name.substr(RAW_EVENT_PREFIX.length);
					values = params.length > 0 ? params[0] : null;
				} else {
					throw new haxe.Exception('CNE event "${name}" has no V-Slice 0.8.7 mapping.');
				}
		}
		return [{t: time, e: eventName, v: values}];
	}

	static function _applyTween(values:Dynamic, params:Array<Dynamic>, tweenIndex:Int, durationIndex:Int, easeIndex:Int, typeIndex:Int):Void {
		var ease = _tweenEase(params, tweenIndex, easeIndex, typeIndex);
		Reflect.setField(values, "ease", ease);
		if (ease != "INSTANT" && ease != "CLASSIC")
			Reflect.setField(values, "duration", _numberParam(params, durationIndex, 4));
	}

	static function _tweenEase(params:Array<Dynamic>, tweenIndex:Int, easeIndex:Int, typeIndex:Int):String {
		if (params.length > tweenIndex && params[tweenIndex] == false)
			return "INSTANT";
		var ease = _stringParam(params, easeIndex, "CLASSIC");
		if (ease == "CLASSIC" || ease == "INSTANT") return ease;
		var type = _stringParam(params, typeIndex, "In");
		return ease + type;
	}

	static function _numberParam(params:Array<Dynamic>, index:Int, fallback:Float):Float {
		if (index < 0 || index >= params.length || params[index] == null) return fallback;
		var value:Dynamic = params[index];
		if (!Std.isOfType(value, Int) && !Std.isOfType(value, Float)) return fallback;
		return cast value;
	}

	static function _stringParam(params:Array<Dynamic>, index:Int, fallback:String):String {
		if (index < 0 || index >= params.length || !Std.isOfType(params[index], String)) return fallback;
		return cast params[index];
	}

	static function _boolParam(params:Array<Dynamic>, index:Int, fallback:Bool):Bool {
		if (index < 0 || index >= params.length || !Std.isOfType(params[index], Bool)) return fallback;
		return cast params[index];
	}

	static function _stringField(source:Dynamic, name:String, fallback:String):String {
		var value:Dynamic = Reflect.field(source, name);
		return Std.isOfType(value, String) && StringTools.trim(cast value) != "" ? cast value : fallback;
	}

	static function _nullableStringField(source:Dynamic, name:String):Null<String> {
		var value:Dynamic = Reflect.field(source, name);
		return Std.isOfType(value, String) && StringTools.trim(cast value) != "" ? cast value : null;
	}

	static function _numberField(source:Dynamic, name:String, fallback:Float):Float {
		var value:Dynamic = Reflect.field(source, name);
		return (Std.isOfType(value, Int) || Std.isOfType(value, Float)) ? cast value : fallback;
	}
}
