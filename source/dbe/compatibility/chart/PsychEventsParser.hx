package dbe.compatibility.chart;

/** Normalizes standalone Psych event files and DBE event JSON for Charter. */
class PsychEventsParser {
	public static function parse(data:Dynamic):Array<Dynamic> {
		if (data == null) return [];

		var song = Reflect.field(data, "song");
		var eventData:Dynamic = song != null ? Reflect.field(song, "events") : null;
		if (eventData == null) eventData = Reflect.field(data, "events");
		if (eventData == null || !Std.isOfType(eventData, Array)) return [];

		var parsedEvents:Array<Dynamic> = [];
		for (entry in (cast eventData:Array<Dynamic>)) {
			if (entry == null) continue;

			if (Std.isOfType(entry, Array)) {
				var group:Array<Dynamic> = cast entry;
				if (group.length < 2 || group[0] == null || !Std.isOfType(group[1], Array)) continue;

				var time:Dynamic = group[0];
				for (rawEvent in (cast group[1]:Array<Dynamic>)) {
					if (rawEvent == null || !Std.isOfType(rawEvent, Array)) continue;
					var values:Array<Dynamic> = cast rawEvent;
					if (values.length == 0 || values[0] == null) continue;

					parsedEvents.push({
						time: time,
						name: Std.string(values[0]),
						params: values.slice(1)
					});
				}
			} else {
				parsedEvents.push(entry);
			}
		}

		return parsedEvents;
	}
}
