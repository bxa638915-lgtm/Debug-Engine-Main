package funkin.backend.assets;

typedef SongLoadFailure = {
	var path:String;
	var phase:String;
	var message:String;
}

/** Bounded snapshot of one completed, failed, or cancelled preparation. */
class SongLoadReport {
	public final generation:Int;
	public final request:SongLoadRequest;
	public var status:String = "loading";
	public var phase:String = "chart";
	public var totalMs:Float = 0;
	public var phaseMs:Map<String, Float> = [];
	public var bitmapResources:Int = 0;
	public var audioResources:Int = 0;
	public var assetsLoaded:Int = 0;
	public var duplicateCount:Int = 0;
	public var bitmapCacheHits:Int = 0;
	public var bitmapCacheMisses:Int = 0;
	public var audioCacheHits:Int = 0;
	public var audioCacheMisses:Int = 0;
	public var failures:Array<SongLoadFailure> = [];

	public function new(generation:Int, request:SongLoadRequest) {
		this.generation = generation;
		this.request = request;
	}

	public function addPhaseTime(phase:String, durationMs:Float):Void {
		var current = phaseMs.get(phase);
		phaseMs.set(phase, (current == null ? 0 : current) + durationMs);
	}

	public function recordBitmap(path:String, cacheHit:Bool):Void {
		bitmapResources++;
		if (cacheHit) bitmapCacheHits++ else bitmapCacheMisses++;
	}

	public function recordAudio(path:String, cacheHit:Bool, loaded:Bool):Void {
		audioResources++;
		if (cacheHit) audioCacheHits++ else audioCacheMisses++;
		if (loaded) assetsLoaded++;
	}

	public function addFailure(path:String, phase:String, message:String):Void {
		failures.push({path: path == null ? "" : path, phase: phase == null ? "unknown" : phase,
			message: message == null ? "Unknown load failure" : message});
	}
}
