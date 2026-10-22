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
    base.stage = (song.stage != null && song.stage != "") ? song.stage : 'mainStage';
    base.scrollSpeed = song.scrollSpeed != null ? song.scrollSpeed : 1.0;
    if (song.arrowSkin != null && song.arrowSkin != "") {
      base.arrowSkin = song.arrowSkin;
      base.meta.arrowSkin = song.arrowSkin;
    }
    if (song.splashSkin != null && song.splashSkin != "") {
      base.splashSkin = song.splashSkin;
      base.meta.splashSkin = song.splashSkin;
    }

    // Create 3 default strumlines (Opponent 0, Player 1, Girlfriend 2)
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
    var gfName:String = (song.gfVersion != null && song.gfVersion != "") ? song.gfVersion : ((song.player3 != null && song.player3 != "") ? song.player3 : "gf");
    base.strumLines.push({
      characters: [gfName],
      type: 2,
      position: "girlfriend",
      keyCount: 4,
      notes: []
    });

    // Import Notes & Section Events
    if (song.notes != null)
    {
      var curBPM:Float = song.bpm != null ? song.bpm : 100;
      var curCrochet:Float = ((60 / curBPM) * 1000);
      var curTime:Float = 0;
      var curCamTarget:Int = -1;
      var sections:Array<Dynamic> = cast song.notes;
      for (section in sections)
      {
        if (section == null) continue;

        var beatsPerMeasure:Float = (section.sectionBeats != null) ? section.sectionBeats : 4;
        var targetStrum:Int = (section.gfSection == true) ? 2 : (section.mustHitSection == true ? 1 : 0);
        if (curCamTarget != targetStrum) {
          curCamTarget = targetStrum;
          base.events.push({
            time: curTime,
            name: "Camera Movement",
            params: [targetStrum],
            global: true
          });
        }

        if (section.changeBPM == true && section.bpm != null && section.bpm != curBPM) {
          curCrochet = ((60 / (curBPM = section.bpm)) * 1000);
          base.events.push({
            time: curTime,
            name: "BPM Change",
            params: [section.bpm],
            global: true
          });
        }
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

        curTime += curCrochet * beatsPerMeasure;
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
