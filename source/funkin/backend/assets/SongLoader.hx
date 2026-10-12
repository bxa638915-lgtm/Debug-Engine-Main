package funkin.backend.assets;

import flixel.FlxG;
import flixel.graphics.FlxGraphic;
import flixel.sound.FlxSoundData;
import funkin.backend.chart.ChartData;
import funkin.backend.assets.SongAssetManifest.SongAssetEntry;
import funkin.backend.assets.SongAssetManifest.SongAssetKind;
import funkin.game.SongLoadingState;
import haxe.Timer;
import openfl.utils.Assets;

/** Coordinates one active song preparation and hands its parsed chart to PlayState once. */
class SongLoader {
	public static var lastReport(default, null):SongLoadReport;

	static var nextGeneration:Int = 1;
	static var active:LoadJob;

	public static function start(request:SongLoadRequest, loadChart:Void->ChartData):Int {
		if (active != null && active.report.status == "loading") finish(active, "cancelled", null, "Superseded by a newer song load.");

		var id = nextGeneration++;
		active = new LoadJob(id, request, loadChart);
		FlxG.switchState(new SongLoadingState(id, request));
		return id;
	}

	public static function update(generation:Int):Void {
		var job = getActive(generation);
		if (job == null || job.report.status != "loading") return;

		if (Paths.getAssetsRoot() != job.request.assetRoot) {
			finish(job, "failed", job.phase, "The active mod or asset root changed during loading.");
			return;
		}

		switch (job.phase) {
			case "chart":
				var started = Timer.stamp();
				try {
					job.chart = job.loadChart();
					if (job.chart == null) throw "Chart parser returned no chart data.";
				} catch (e:Dynamic) {
					job.report.addPhaseTime("chart", elapsedMs(started));
					finish(job, "failed", "chart", Std.string(e));
					return;
				}
				job.report.addPhaseTime("chart", elapsedMs(started));
				job.phase = "manifest";
				job.report.phase = job.phase;

			case "manifest":
				var started = Timer.stamp();
				try {
					job.manifest = SongAssetManifest.build(job.request, job.chart);
					job.report.duplicateCount = job.manifest.duplicateCount;
				} catch (e:Dynamic) {
					job.report.addPhaseTime("manifest", elapsedMs(started));
					finish(job, "failed", "manifest", Std.string(e));
					return;
				}
				job.report.addPhaseTime("manifest", elapsedMs(started));
				job.phase = "assets";
				job.report.phase = job.phase;
				if (job.manifest.entries.length == 0) finish(job, "completed", null, null);

			case "assets":
				if (job.assetIndex >= job.manifest.entries.length) {
					finish(job, "completed", null, null);
					return;
				}
				loadEntry(job, job.manifest.entries[job.assetIndex]);
				job.assetIndex++;
				if (job.report.status == "loading" && job.assetIndex >= job.manifest.entries.length)
					finish(job, "completed", null, null);

			default:
				finish(job, "failed", job.phase, "Unknown song loading phase.");
		}
	}

	public static function progress(generation:Int):Float {
		var job = getActive(generation);
		if (job == null) return 0;
		if (job.report.status == "completed") return 1;
		if (job.manifest == null) return job.phase == "manifest" ? 0.12 : 0;

		var totalSteps = 2 + job.manifest.entries.length;
		var completedSteps = switch (job.phase) {
			case "chart": 0;
			case "manifest": 1;
			case "assets": 2 + job.assetIndex;
			default: totalSteps;
		};
		return totalSteps == 0 ? 1 : Math.min(1, completedSteps / totalSteps);
	}

	public static function isComplete(generation:Int):Bool {
		var job = getActive(generation);
		return job != null && job.report.status == "completed";
	}

	public static function isActive(generation:Int):Bool {
		return getActive(generation) != null;
	}

	public static function currentPhase(generation:Int):String {
		var job = getActive(generation);
		return job == null ? "inactive" : job.report.phase;
	}

	public static function errorMessage(generation:Int):Null<String> {
		var job = getActive(generation);
		return job == null ? null : job.errorMessage;
	}

	public static function takePrepared():Null<PreparedSong> {
		if (active == null || active.report.status != "completed" || active.preparedTaken) return null;
		active.preparedTaken = true;
		var prepared = active.prepared;
		active.prepared = null;
		return prepared;
	}

	public static function cancel(generation:Int):Void {
		var job = getActive(generation);
		if (job == null || job.report.status != "loading") return;
		finish(job, "cancelled", null, "Song loading was cancelled.");
	}

	static function loadEntry(job:LoadJob, entry:SongAssetEntry):Void {
		var started = Timer.stamp();
		var loaded = false;
		var cacheHit = false;
		var failure:Null<String> = null;

		try {
			switch (entry.kind) {
				case IMAGE:
					var graphic:FlxGraphic = FlxG.bitmap.get(entry.path);
					cacheHit = graphic != null;
					if (!Paths.framesExists(entry.path, true, true, true)) {
						failure = "Image or atlas asset was not found.";
					} else {
						if (graphic == null) graphic = FlxG.bitmap.add(entry.path);
						loaded = graphic != null;
						if (loaded && FlxG.state is SongLoadingState)
							cast(FlxG.state, SongLoadingState).cachePreloadedGraphic(graphic);
						if (!loaded) failure = "Image bitmap could not be loaded.";
					}

				case AUDIO:
					cacheHit = FlxG.sound.getCache(entry.path) != null;
					if (!Assets.exists(entry.path) && !cacheHit) {
						failure = "Audio asset was not found.";
					} else {
						var data:FlxSoundData = cacheHit ? FlxG.sound.getCache(entry.path) : FlxSoundData.fromAssetKey(entry.path, entry.stream);
						loaded = data != null;
						if (loaded) job.audioDataByPath.set(entry.path, data);
						else failure = "Audio data could not be decoded.";
					}
			}
		} catch (e:Dynamic) {
			failure = Std.string(e);
		}

		if (entry.kind == IMAGE) job.report.recordBitmap(entry.path, cacheHit);
		else job.report.recordAudio(entry.path, cacheHit, loaded);

		job.report.addPhaseTime("assets", elapsedMs(started));
		if (failure != null) {
			job.report.addFailure(entry.path, "assets", failure);
			if (entry.required) {
				finish(job, "failed", "assets", 'Required ${entry.kind} asset failed: ${entry.path} — $failure');
				return;
			}
		}

		if (loaded && entry.kind == IMAGE) job.report.assetsLoaded++;
	}

	static function finish(job:LoadJob, status:String, phase:Null<String>, error:Null<String>):Void {
		if (job == null || job.report.status != "loading") return;
		job.phase = status;
		job.report.status = status;
		job.report.phase = phase == null ? status : phase;
		job.errorMessage = error;
		job.report.totalMs = elapsedMs(job.startedAt);
		if (status == "completed")
			job.prepared = new PreparedSong(job.request, job.chart, job.audioDataByPath, job.report);
		else
			job.prepared = null;
		lastReport = job.report;
	}

	static function elapsedMs(startedAt:Float):Float {
		return (Timer.stamp() - startedAt) * 1000;
	}

	static function getActive(generation:Int):Null<LoadJob> {
		return active != null && active.id == generation ? active : null;
	}
}

private class LoadJob {
	public final id:Int;
	public final request:SongLoadRequest;
	public final loadChart:Void->ChartData;
	public final startedAt:Float;
	public final audioDataByPath:Map<String, FlxSoundData> = [];
	public final report:SongLoadReport;
	public var chart:ChartData;
	public var manifest:SongAssetManifest;
	public var assetIndex:Int = 0;
	public var phase:String = "chart";
	public var prepared:PreparedSong;
	public var preparedTaken:Bool = false;
	public var errorMessage:Null<String>;

	public function new(id:Int, request:SongLoadRequest, loadChart:Void->ChartData) {
		this.id = id;
		this.request = request;
		this.loadChart = loadChart;
		this.startedAt = Timer.stamp();
		this.report = new SongLoadReport(id, request);
	}
}
