package funkin.play.song;

/**
 * Compatibility base class for V-Slice / Hex songs running on DBE.
 */
class Song {
    public var songId:String;

    public function new(songId:String = "") {
        this.songId = songId;
    }

    public function onCreate(event:Dynamic = null):Void {}
    public function onSongLoaded(event:Dynamic = null):Void {}
    public function onSongStart(event:Dynamic = null):Void {}
    public function onSongRetry(event:Dynamic = null):Void {}
    public function onUpdate(event:Dynamic = null):Void {}
    public function onBeatHit(event:Dynamic = null):Void {}
    public function onStepHit(event:Dynamic = null):Void {}
    public function onSongEvent(event:Dynamic = null):Void {}
    public function onDestroy(event:Dynamic = null):Void {}

    public function rimOn():Void {}
    public function lookOn():Void {}
}
