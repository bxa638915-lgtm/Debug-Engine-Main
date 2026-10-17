package cne.compat;

import flixel.FlxSubState;
import funkin.game.PlayState;

/** A lightweight host for Psych-style custom-substate Lua callbacks. */
class PsychLuaSubState extends FlxSubState
{
	public static var instance:PsychLuaSubState;
	public static var currentName:String = "unnamed";

	public final substateName:String;
	final game:PlayState;
	final pauseGame:Bool;
	var previousPersistentUpdate:Bool;
	var previousPersistentDraw:Bool;
	var previousPaused:Bool;
	var previousFollowLerp:Float;
	var musicWasPlaying:Bool;
	var vocalsWerePlaying:Bool;
	var justOpened:Bool = true;

	public function new(name:String, pauseGame:Bool = false)
	{
		substateName = name == null || name.length == 0 ? "unnamed" : name;
		this.pauseGame = pauseGame;
		game = PlayState.instance;
		if (pauseGame && game != null)
		{
			previousPersistentUpdate = game.persistentUpdate;
			previousPersistentDraw = game.persistentDraw;
			previousPaused = game.paused;
			previousFollowLerp = game.camGame == null ? 0 : game.camGame.followLerp;
			musicWasPlaying = game.inst != null && game.inst.playing;
			vocalsWerePlaying = game.vocals != null && game.vocals.playing;
		}
		super();
		currentName = substateName;
		if (pauseGame && game != null)
		{
			game.persistentUpdate = false;
			game.persistentDraw = true;
			game.paused = true;
			if (game.camGame != null) game.camGame.followLerp = 0;
			if (game.inst != null) game.inst.pause();
			if (game.vocals != null) game.vocals.pause();
			if (game.strumLines != null && game.strumLines.members != null)
				for (strumLine in game.strumLines.members)
					if (strumLine != null && strumLine.vocals != null)
						strumLine.vocals.pause();
		}
	}

	public override function create():Void
	{
		instance = this;
		justOpened = true;
		if (game != null && game.scripts != null)
			game.scripts.call("onCustomSubstateCreate", [substateName]);
		super.create();
		if (game != null && game.scripts != null)
			game.scripts.call("onCustomSubstateCreatePost", [substateName]);
	}

	public override function update(elapsed:Float):Void
	{
		if (justOpened)
		{
			justOpened = false;
			return;
		}
		if (game != null && game.scripts != null)
			game.scripts.call("onCustomSubstateUpdate", [substateName, elapsed]);
		super.update(elapsed);
		if (game != null && game.scripts != null)
			game.scripts.call("onCustomSubstateUpdatePost", [substateName, elapsed]);
	}

	public override function destroy():Void
	{
		if (game != null && game.scripts != null)
			game.scripts.call("onCustomSubstateDestroy", [substateName]);
		if (instance == this)
		{
			instance = null;
			currentName = "unnamed";
		}
		if (pauseGame && game != null)
		{
			game.persistentUpdate = previousPersistentUpdate;
			game.persistentDraw = previousPersistentDraw;
			game.paused = previousPaused;
			if (game.camGame != null) game.camGame.followLerp = previousFollowLerp;
			if (!musicWasPlaying && game.inst != null) game.inst.pause();
			if (!vocalsWerePlaying && game.vocals != null) game.vocals.pause();
		}
		super.destroy();
	}
}
