package funkin.backend.chart;

import haxe.Json;
import funkin.backend.chart.ChartData;
import funkin.backend.chart.ConvertorChartData;

@:nullSafety
class ConvertorChartImporter
{
  public static function parseChartData(input:String, fileName:String = 'raw'):Null<ConvertorChartData>
  {
    try {
      return cast(Json.parse(input), ConvertorChartData);
    } catch(e:Dynamic) {
      trace('[ConvertorChartImporter] Error parsing JSON: ' + fileName + ' - ' + e);
      return null;
    }
  }

  public static function migrateChartData(data:ConvertorChartData, ?externalEvents:Array<ConvertorEventData>, difficulty:String = 'normal'):ChartData
  {
    var base:ChartData = {
      strumLines: [],
      noteTypes: [],
      events: [],
      meta: { name: null },
      scrollSpeed: 1.0, // Default
      stage: 'mainStage',
      codenameChart: true,
      fromMods: false
    };

    if (data.song != null && data.song.strumLines != null)
    {
      var strumIndex:Int = 0;
      for (strum in data.song.strumLines)
      {
        var isPlayer:Bool = (strumIndex == 1);
        var line:ChartStrumLine = {
          characters: [isPlayer ? "bf" : "dad"],
          type: isPlayer ? 1 : 0,
          position: isPlayer ? "boyfriend" : "dad",
          keyCount: 4,
          notes: []
        };
        for (note in strum.notes)
        {
          line.notes.push({
            time: note.time,
            id: note.id != null ? note.id : (note.type % 4),
            type: note.type,
            sLen: note.sLen != null ? note.sLen : 0.0
          });
        }
        base.strumLines.push(line);
        strumIndex++;
      }
    }

    var events:Array<ChartEvent> = [];
    if (externalEvents != null) {
      for (ev in externalEvents) events.push({ time: ev.time, name: ev.name, params: ev.params, global: true });
    }
    if (data.song != null && data.song.events != null) {
      for (ev in data.song.events) events.push({ time: ev.time, name: ev.name, params: ev.params, global: true });
    }
    base.events = events;

    return base;
  }
}
