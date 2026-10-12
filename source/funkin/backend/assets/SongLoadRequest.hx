package funkin.backend.assets;

import funkin.game.PlayState;

/** Immutable identity and gameplay context for one song load. */
class SongLoadRequest {
	public final songName:String;
	public final difficulty:String;
	public final variation:Null<String>;
	public final opponentMode:Bool;
	public final coopMode:Bool;
	public final storyMode:Bool;
	public final chartingMode:Bool;
	public final origin:String;
	public final assetRoot:String;

	public function new(songName:String, difficulty:String, variation:Null<String>, opponentMode:Bool, coopMode:Bool, storyMode:Bool,
		chartingMode:Bool, origin:String, assetRoot:String) {
		this.songName = songName;
		this.difficulty = difficulty == null ? Flags.DEFAULT_DIFFICULTY : difficulty;
		this.variation = variation == "" ? null : variation;
		this.opponentMode = opponentMode;
		this.coopMode = coopMode;
		this.storyMode = storyMode;
		this.chartingMode = chartingMode;
		this.origin = origin;
		this.assetRoot = assetRoot;
	}

	public static function forSong(songName:String, difficulty:String, variation:String, opponentMode:Bool, coopMode:Bool, origin:String):SongLoadRequest {
		return new SongLoadRequest(songName, difficulty, variation, opponentMode, coopMode, false, false, origin, Paths.getAssetsRoot());
	}

	public static function fromPlayState(origin:String):SongLoadRequest {
		var songName = PlayState.SONG != null && PlayState.SONG.meta != null ? PlayState.SONG.meta.name : "";
		return new SongLoadRequest(songName, PlayState.difficulty, PlayState.variation, PlayState.opponentMode, PlayState.coopMode,
			PlayState.isStoryMode, PlayState.chartingMode, origin, Paths.getAssetsRoot());
	}

	/** Returns true only while the requested song, modes, and active mod still match. */
	public function matchesCurrentPlayState():Bool {
		if (PlayState.SONG == null || PlayState.SONG.meta == null) return false;

		return sameText(PlayState.SONG.meta.name, songName)
			&& sameText(PlayState.difficulty, difficulty)
			&& sameText(PlayState.variation, variation)
			&& PlayState.opponentMode == opponentMode
			&& PlayState.coopMode == coopMode
			&& PlayState.isStoryMode == storyMode
			&& PlayState.chartingMode == chartingMode
			&& Paths.getAssetsRoot() == assetRoot;
	}

	static function sameText(a:Null<String>, b:Null<String>):Bool {
		if (a == null || a == "") return b == null || b == "";
		if (b == null || b == "") return false;
		return a.toLowerCase() == b.toLowerCase();
	}
}
