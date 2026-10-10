package funkin.backend.chart;

import haxe.ds.Either;

typedef ConvertorEventData =
{
  public var time:Float;
  public var name:String;
  public var params:Array<Dynamic>;
}

typedef ConvertorNote =
{
  public var time:Float;
  public var type:Int;
  @:optional
  public var id:Null<Int>;
  @:optional
  public var sLen:Null<Float>;
}

typedef ConvertorStrumLine =
{
  public var notes:Array<ConvertorNote>;
}

/**
 * Data structure for modern chart format (e.g. Sla1recreation).
 */
class ConvertorChartData
{
  public var song:ConvertorSongData;
}

class ConvertorSongData
{
  public var songName:String;
  public var bpm:Float;
  @:optional
  public var stage:Null<String>;

  /**
   * Chart notes organized by strumlines.
   */
  public var strumLines:Array<ConvertorStrumLine>;

  /**
   * Events associated with the song.
   */
  @:optional
  public var events:Array<ConvertorEventData>;

  public function new() {}
}
