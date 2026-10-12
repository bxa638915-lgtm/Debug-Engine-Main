import funkin.editors.charter.CharterCharacterPreviewLayout;

class CharterCharacterPreviewLayoutTest {
	static function main():Void {
		assert(CharterCharacterPreviewLayout.getWindowWidth(270.5) == 303, "window width follows character bounds and original chrome padding");
		assert(CharterCharacterPreviewLayout.getWindowHeight(304.1) == 369, "window height follows character bounds and original chrome padding");
		assert(CharterCharacterPreviewLayout.getCharacterPositionX(240) + 240 == 12, "rendered X bounds anchor inside the preview viewport");
		assert(CharterCharacterPreviewLayout.getCharacterPositionY(480) + 480 == 16, "rendered Y bounds anchor inside the preview viewport");

		var envelope:Array<Float> = null;
		envelope = CharterCharacterPreviewLayout.includeBounds(envelope, 12, 16, 100, 200);
		envelope = CharterCharacterPreviewLayout.includeBounds(envelope, -30, 80, 140, 180);
		envelope = CharterCharacterPreviewLayout.includeBounds(envelope, 25, -12, 40, 60);
		assert(envelope[0] == -30 && envelope[1] == -12, "animation envelope keeps the most negative pose offsets");
		assert(envelope[2] == 112 && envelope[3] == 260, "animation envelope includes the far edge of every pose");
		assert(CharterCharacterPreviewLayout.getWindowWidth(envelope[2] - envelope[0]) == 174, "window width follows the full animation envelope");
		assert(CharterCharacterPreviewLayout.getWindowHeight(envelope[3] - envelope[1]) == 336, "window height follows the full animation envelope");
		assert(CharterCharacterPreviewLayout.getCharacterPositionX(envelope[0]) + envelope[0] == 12, "the complete envelope stays anchored in the viewport");
		assert(CharterCharacterPreviewLayout.getCharacterPositionY(envelope[1]) + envelope[1] == 16, "pose changes cannot move the envelope anchor");
	}

	static function assert(condition:Bool, message:String):Void {
		if (!condition) throw message;
	}
}
