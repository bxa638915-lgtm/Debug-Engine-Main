package funkin.backend.assets;

import flixel.sound.FlxSoundData;
import funkin.backend.chart.ChartData;

/** Resources prepared by SongLoader and consumed once by PlayState. */
class PreparedSong {
	public final request:SongLoadRequest;
	public final chart:ChartData;
	public final audioDataByPath:Map<String, FlxSoundData>;
	public final report:SongLoadReport;

	public function new(request:SongLoadRequest, chart:ChartData, audioDataByPath:Map<String, FlxSoundData>, report:SongLoadReport) {
		this.request = request;
		this.chart = chart;
		this.audioDataByPath = audioDataByPath;
		this.report = report;
	}

	public function getAudioData(path:String):Null<FlxSoundData> {
		if (path == null) return null;
		var data = audioDataByPath.get(path);
		if (data == null) data = audioDataByPath.get(path.toLowerCase());
		return data;
	}
}
