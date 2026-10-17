package funkin.game;

import funkin.backend.scripting.events.splash.*;

class SplashHandler extends FlxTypedGroup<Splash> {
	/**
	 * Map containing all of the splashes group.
	 */
	public var grpMap:Map<String, SplashGroup> = [];

	public function new() {
		super();
	}

	/**
	 * Returns a group of splashes, and creates it if it doesn't exist.
	 * @param name Name of the splash skin
	 */
	public function getSplashGroup(name:String) {
		if (name == null || name.length == 0) name = "default";
		if (!grpMap.exists(name)) {
			var xmlPath = Paths.xml('splashes/$name');
			var grp:SplashGroup = null;
			if (openfl.utils.Assets.exists(xmlPath)) {
				grp = new SplashGroup(xmlPath);
			} else {
				// Check for Psych Engine splash skin
				var psychImgPath:String = null;
				for (candidate in ['noteSplashes/$name', name, 'splashes/$name']) {
					if (openfl.utils.Assets.exists(Paths.image(candidate))) {
						psychImgPath = candidate;
						break;
					}
				}

				if (psychImgPath != null) {
					var generatedXml = '<splashes sprite="$psychImgPath" alpha="0.6">
	<strum id="0">
		<anim name="splashleft1" anim="note splash purple 1" fps="24" x="0" y="0" />
		<anim name="splashleft2" anim="note splash purple 2" fps="24" x="0" y="0" />
	</strum>
	<strum id="1">
		<anim name="splashdown1" anim="note splash blue 1" fps="24" x="0" y="0" />
		<anim name="splashdown2" anim="note splash blue 2" fps="24" x="0" y="0" />
	</strum>
	<strum id="2">
		<anim name="splashup1" anim="note splash green 1" fps="24" x="0" y="0" />
		<anim name="splashup2" anim="note splash green 2" fps="24" x="0" y="0" />
	</strum>
	<strum id="3">
		<anim name="splashright1" anim="note splash red 1" fps="24" x="0" y="0" />
		<anim name="splashright2" anim="note splash red 2" fps="24" x="0" y="0" />
	</strum>
</splashes>';
					grp = new SplashGroup(name, generatedXml);
				} else {
					var defaultPath = Paths.xml('splashes/default');
					grp = new SplashGroup(defaultPath);
				}
			}
			grpMap.set(name, grp);
		}
		var res = grpMap.get(name);
		if (res != null && !res.valid && name != "default") {
			return getSplashGroup("default");
		}
		return res;
	}

	public override function destroy() {
		super.destroy();
		for(grp in grpMap)
			grp.destroy();
		grpMap = null;
	}

	var _firstDraw:Bool = true;
	public override function draw() {
		super.draw();
		if (_firstDraw != (_firstDraw = false))
			for(grp in grpMap)
				grp.draw();
	}

	var __grp:SplashGroup;
	public function showSplash(name:String, strum:Strum) {
		__grp = getSplashGroup(name);
		if (__grp == null || !__grp.valid)
			__grp = getSplashGroup("default");
		if (__grp == null || !__grp.valid) return;

		var spr = __grp.showOnStrum(strum);
		if (spr == null) return;

		var event = EventManager.get(SplashShowEvent).recycle(name, spr, strum, __grp);
		event = PlayState.instance.gameAndCharsEvent("onSplashShown", event);

		if (!event.cancelled && event.splash != null)
			add(event.splash);

		// max 8 rendered splashes
		while(members.length > Flags.MAX_SPLASHES)
			remove(members[0], true);
	}
}