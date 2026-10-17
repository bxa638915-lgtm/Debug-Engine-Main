package funkin.backend.chart;

import haxe.Json;
import funkin.backend.chart.ChartData;

@:nullSafety
class PsychChartImporter
{
  public static function parseChartData(input:String, fileName:String = 'raw'):Null<Dynamic>
  {
    try {
      return Json.parse(input);
    } catch(e:Dynamic) {
      trace('[PsychChartImporter] Error parsing JSON: ' + fileName + ' - ' + e);
      return null;
    }
  }

  public static function migrateChartData(data:Dynamic, difficulty:String = 'normal'):ChartData
  {
    var base:ChartData = {
      strumLines: [],
      noteTypes: [],
      events: [],
      meta: { name: null },
      scrollSpeed: 1.0,
      stage: 'mainStage',
      codenameChart: true,
      fromMods: false
    };

    var song = data.song;
    if (song == null) return base;

    // Import Meta
    base.meta.name = song.song;
    base.meta.rawSongName = song.song;
    base.scrollSpeed = song.scrollSpeed != null ? song.scrollSpeed : 1.0;
    if (song.arrowSkin != null && song.arrowSkin != "") {
      base.arrowSkin = song.arrowSkin;
      base.meta.arrowSkin = song.arrowSkin;
    }
    if (song.splashSkin != null && song.splashSkin != "") {
      base.splashSkin = song.splashSkin;
      base.meta.splashSkin = song.splashSkin;
    }

    // Create 2 default strumlines (Opponent 0, Player 1)
    base.strumLines.push({
      characters: [song.player2 != null ? song.player2 : "dad"],
      type: 0,
      position: "dad",
      keyCount: 4,
      notes: []
    });
    base.strumLines.push({
      characters: [song.player1 != null ? song.player1 : "bf"],
      type: 1,
      position: "boyfriend",
      keyCount: 4,
      notes: []
    });

    // Import Notes
    if (song.notes != null)
    {
      var sections:Array<Dynamic> = cast song.notes;
      for (section in sections)
      {
        if (section != null && section.sectionNotes != null)
        {
          var sectionNotes:Array<Dynamic> = cast section.sectionNotes;
          var mustHit:Bool = section.mustHitSection == true;
          for (noteArr in sectionNotes)
          {
            var noteData:Int = Std.int(noteArr[1]);
            var isPlayer:Bool = mustHit ? (noteData < 4) : (noteData >= 4);
            var strumIdx:Int = isPlayer ? 1 : 0;
            var noteId:Int = noteData % 4;

            var noteTypeIdx:Int = 0;
            if (noteArr.length > 3 && noteArr[3] != null) {
              var noteTypeStr:String = Std.string(noteArr[3]);
              if (noteTypeStr != "" && noteTypeStr != "0") {
                var existing = base.noteTypes.indexOf(noteTypeStr);
                if (existing >= 0) {
                  noteTypeIdx = existing + 1;
                } else {
                  base.noteTypes.push(noteTypeStr);
                  noteTypeIdx = base.noteTypes.length;
                }
              }
            }

            base.strumLines[strumIdx].notes.push({
              time: cast noteArr[0],
              id: noteId,
              sLen: noteArr[2] != null ? cast noteArr[2] : 0.0,
              type: noteTypeIdx
            });
          }
        }
      }
    }

    // Import Events
    if (song.events != null)
    {
      var eventsArray:Array<Dynamic> = cast song.events;
      for (evArr in eventsArray)
      {
        var time:Float = cast evArr[0];
        if (evArr[1] != null)
        {
          var eventList:Array<Dynamic> = cast evArr[1];
          for (ev in eventList)
          {
            var evItems:Array<Dynamic> = cast ev;
            var name:String = Std.string(evItems[0]);
            var params:Array<Dynamic> = [];
            for (i in 1...evItems.length) params.push(evItems[i]);

            base.events.push({
              time: time,
              name: name,
              params: params,
              global: true
            });
          }
        }
      }
    }

    return base;
  }
}
