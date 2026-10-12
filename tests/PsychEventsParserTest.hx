import dbe.compatibility.chart.PsychEventsParser;

class PsychEventsParserTest {
	static function main():Void {
		var psychData:Dynamic = haxe.Json.parse('{"song":{"events":[[1250,[["Play Animation","hey","dad"],["Camera Movement","1","0"]]],[2500,[["Alt Animation Toggle","true","false","0"]]]]}}');
		var psychEvents = PsychEventsParser.parse(psychData);
		assert(psychEvents.length == 3, "Psych event groups are flattened into chart events");
		assert(psychEvents[0].time == 1250 && psychEvents[0].name == "Play Animation", "first Psych event keeps its timestamp and name");
		assert(psychEvents[0].params.join(",") == "hey,dad", "Psych event parameters are preserved");
		assert(psychEvents[1].time == 1250 && psychEvents[1].name == "Camera Movement", "events in one timestamp group share that timestamp");
		assert(psychEvents[2].time == 2500 && psychEvents[2].name == "Alt Animation Toggle", "later Psych event groups preserve order and timestamp");

		var dbeData:Dynamic = haxe.Json.parse('{"events":[{"time":4200,"name":"Play Animation","params":[1,"hey",true]}]}');
		var dbeEvents = PsychEventsParser.parse(dbeData);
		assert(dbeEvents.length == 1 && dbeEvents[0].time == 4200 && dbeEvents[0].params[0] == 1, "DBE event JSON remains supported");
	}

	static function assert(condition:Bool, message:String):Void {
		if (!condition) throw message;
	}
}
