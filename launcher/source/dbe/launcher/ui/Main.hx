package dbe.launcher.ui;

import dbe.launcher.App;
import flixel.FlxG;
import flixel.FlxGame;
import openfl.Lib;
import openfl.display.Sprite;
import openfl.events.UncaughtErrorEvent;

class Main extends Sprite {
	public function new() {
		super();

		Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onUncaughtError);

		App.init();

		var game = new FlxGame(960, 540, HomeState, 60, 60, true);
		addChild(game);

		FlxG.autoPause = false;
	}

	static function onUncaughtError(e:UncaughtErrorEvent) {
		var msg = 'Uncaught error: ${e.error}';
		try {
			App.log(msg);
		} catch (_:Dynamic) {}
	}
}
