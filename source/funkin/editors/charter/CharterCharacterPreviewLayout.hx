package funkin.editors.charter;

/** Layout values shared by the character preview and its focused tests. */
class CharterCharacterPreviewLayout {
	public static inline var WINDOW_WIDTH_PADDING:Int = 32;
	public static inline var WINDOW_HEIGHT_PADDING:Int = 64;
	public static inline var VIEWPORT_PADDING_X:Int = 12;
	public static inline var VIEWPORT_PADDING_Y:Int = 16;

	public static inline function getWindowWidth(boundsWidth:Float):Int
		return Std.int(Math.ceil(Math.max(boundsWidth, 0))) + WINDOW_WIDTH_PADDING;

	public static inline function getWindowHeight(boundsHeight:Float):Int
		return Std.int(Math.ceil(Math.max(boundsHeight, 0))) + WINDOW_HEIGHT_PADDING;

	/** Expand a [left, top, right, bottom] envelope with one rendered pose. */
	public static function includeBounds(envelope:Array<Float>, left:Float, top:Float, width:Float, height:Float):Array<Float> {
		var right = left + Math.max(width, 0);
		var bottom = top + Math.max(height, 0);
		if (envelope == null || envelope.length < 4)
			return [left, top, right, bottom];

		envelope[0] = Math.min(envelope[0], left);
		envelope[1] = Math.min(envelope[1], top);
		envelope[2] = Math.max(envelope[2], right);
		envelope[3] = Math.max(envelope[3], bottom);
		return envelope;
	}

	/** Move the rendered bounds to the original preview's padded component origin. */
	public static inline function getCharacterPositionX(renderedBoundsLeft:Float):Float
		return VIEWPORT_PADDING_X - renderedBoundsLeft;

	/** Move the rendered bounds to the original preview's padded component origin. */
	public static inline function getCharacterPositionY(renderedBoundsTop:Float):Float
		return VIEWPORT_PADDING_Y - renderedBoundsTop;
}
