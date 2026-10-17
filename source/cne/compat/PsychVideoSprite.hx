package cne.compat;

import flixel.FlxSprite;
import flixel.util.FlxSignal;

class PsychVideoSprite extends FlxSprite {
	public var videoSprite:PsychVideoDummySubSprite;
	public var bitmap:PsychVideoDummySubSprite;

	public function new(?path:Dynamic, ?loop:Dynamic = false, ?pauseMusic:Bool = false, ?isPrecaching:Bool = false) {
		super();
		visible = false;
		videoSprite = new PsychVideoDummySubSprite();
		bitmap = videoSprite;
	}

	public function load(?path:Dynamic, ?options:Dynamic):Bool {
		return false;
	}

	public function play():Void {}
	public function pause():Void {}
	public function resume():Void {}
}

class PsychVideoDummySubSprite extends FlxSprite {
	public var bitmap:PsychVideoDummySubSprite;
	public var onEndReached:FlxSignal = new FlxSignal();
	public var onFormatSetup:FlxSignal = new FlxSignal();

	public function new() {
		super();
		visible = false;
		bitmap = this;
	}
}
