import funkin.editors.charter.CharterPreviewTimeline;

class CharterPreviewTimelineTest {
	static function main():Void {
		assert(!CharterPreviewTimeline.crosses(100, 100, 200), "previous boundary must not fire twice");
		assert(CharterPreviewTimeline.crosses(150, 100, 200), "crossed action must fire");
		assert(CharterPreviewTimeline.crosses(200, 100, 200), "current boundary must fire");
		assert(!CharterPreviewTimeline.crosses(201, 100, 200), "future action must not fire");
		assert(!CharterPreviewTimeline.crosses(150, 200, 100), "backward seek must not fire actions");
		assert(CharterPreviewTimeline.compare(100, true, 2, 101, true, 0) < 0, "earlier actions must run first");
		assert(CharterPreviewTimeline.compare(100, true, 2, 100, false, 0) < 0, "events must run before note hits at the same time");
		assert(CharterPreviewTimeline.compare(100, true, 1, 100, true, 2) < 0, "same-time events must preserve chart order");

		var playerSwap = CharterPreviewTimeline.parseCharacterChange("Change Character", ["BF", "bf-car"]);
		assert(playerSwap != null && playerSwap.target == "player" && playerSwap.characterName == "bf-car", "Psych BF swaps resolve to the player preview");
		var opponentSwap = CharterPreviewTimeline.parseCharacterChange("Change Character", ["dad", "dad-car"]);
		assert(opponentSwap != null && opponentSwap.target == "opponent" && opponentSwap.characterName == "dad-car", "Psych Dad swaps resolve to the opponent preview");
		var numericParams:Array<Dynamic> = [0, "bf-alt"];
		var numericPlayerSwap = CharterPreviewTimeline.parseCharacterChange("Change Character", numericParams);
		assert(numericPlayerSwap != null && numericPlayerSwap.target == "player", "Psych numeric character type 0 targets BF");
		var girlfriendSwap = CharterPreviewTimeline.parseCharacterChange("Change Character", ["gf", "gf-car"]);
		assert(girlfriendSwap != null && girlfriendSwap.target == "girlfriend", "Psych GF swaps retain their target role");
		assert(CharterPreviewTimeline.parseCharacterChange("Play Animation", ["bf", "hey"]) == null, "other event names are not treated as character swaps");
		assert(CharterPreviewTimeline.parseCharacterChange("Change Character", ["unknown", "char"]) == null, "unknown character swap targets are ignored");
	}

	static function assert(condition:Bool, message:String):Void {
		if (!condition) throw message;
	}
}
