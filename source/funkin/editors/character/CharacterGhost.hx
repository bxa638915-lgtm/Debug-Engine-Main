package funkin.editors.character;

import funkin.backend.system.FakeCamera.FakeCallCamera;
import openfl.geom.ColorTransform;
import flixel.animation.FlxAnimation;
import funkin.game.Character;
import haxe.xml.Access;
import animate.internal.RenderTexture;

typedef AtlasState = {
	var oldAnim:String;
	var oldFrame:Int;
	var oldTick:Float;
	var oldPlaying:Bool;
};

class CharacterGhost extends Character {
	public var ghosts:Array<String> = [];


	public override function buildCharacter(xml:Access) {
		useRenderTexture = true; // per request from maru heh, still overridable
		super.buildCharacter(xml);
	}

	public override function draw() @:privateAccess {
		ghostDraw = FakeCallCamera.instance.ignoreDraws = true;

		var wasInvalidFrame:Bool = !colorTransform.__isDefault(false);
		colorTransform.__identity();

		var animName = animation.curAnim?.name ?? null;
		var animFrame = animation.curAnim?.curFrame ?? 0;
		var animFrameTimer = animation.curAnim?._frameTimer ?? 0;

		for (anim in ghosts) @:privateAccess {
			alpha = 0.4; color = 0xFFAEAEAE;

			var flxanim:FlxAnimation = animation._animations.get(anim);
			if (flxanim == null || flxanim.frames == null || flxanim.frames.length == 0) continue;
			var targetFrame = (anim == animName) ? animFrame : 0;
			animation.play(anim, true, false, targetFrame);

			setAnimOffset(anim);
			super.draw();
		}

		if (ghosts.length > 0)
			frame = frames.frames[animation.frameIndex];
		ghostDraw = FakeCallCamera.instance.ignoreDraws = false; 

		alpha = 1; color = 0xFFFFFFFF;
		if (wasInvalidFrame) {
			frameOffset.set(0, 0); 
			offset.set(globalOffset.x * (isPlayer != playerOffsets ? 1 : -1), -globalOffset.y);
			colorTransform.color = 0xFFEF0202;
		} else {
			animation.play(animName, true, false, animFrame);
			setAnimOffset(animName);
			if (animation.curAnim != null)
				animation.curAnim._frameTimer = animFrameTimer;
		}
		
		super.draw();
	}

	public function setAnimOffset(anim:String) {
		var daOffset:FlxPoint = animOffsets.get(anim);
		if (daOffset != null) {
			if (isPsychCamera) {
				var sx = scale.x != 0 ? scale.x : 1;
				var sy = scale.y != 0 ? scale.y : 1;
				frameOffset.set(daOffset.x / sx, daOffset.y / sy);
			} else {
				frameOffset.set(daOffset.x, daOffset.y);
			}
			daOffset.putWeak();
		}

		offset.set(globalOffset.x * (isPlayer != playerOffsets ? 1 : -1), -globalOffset.y);
	}

	public function generateRenderTextureForAnim(anim:String):RenderTexture @:privateAccess {
		if (!isAnimate) return null;

		var wasInvalidFrame:Bool = !colorTransform.__isDefault(false);
		colorTransform.__identity();
		
		var animName = animation.curAnim?.name ?? null;
		var animFrame = animation.curAnim?.curFrame ?? 0;
		var animFrameTimer = animation.curAnim?._frameTimer ?? 0;

		var oldRenderTexture:RenderTexture = this._renderTexture;
		var oldRenderTextureDirty = _renderTextureDirty;
		var oldAlpha = alpha;

		this._renderTexture = null;
		this._renderTextureDirty = true;
		this.alpha = 256.0/257.0;

		animation.play(anim, true, false, 0);

		drawAnimate(FakeCallCamera.instance);

		var renderTex = this._renderTexture;

		this._renderTexture = oldRenderTexture;
		this._renderTextureDirty = oldRenderTextureDirty;
		this.alpha = oldAlpha;

		if (wasInvalidFrame) {
			colorTransform.color = 0xFFEF0202;
		} else {
			animation.play(animName, true, false, animFrame);
			if (animation.curAnim != null)
				animation.curAnim._frameTimer = animFrameTimer;
		}

		return renderTex;
	}

	// This gets annoying lmao -lunar
	// it's gone now <3 -yosh
}