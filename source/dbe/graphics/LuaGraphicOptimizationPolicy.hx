package dbe.graphics;

/** Shared policy for avoiding oversized generated solid-color Lua graphics. */
class LuaGraphicOptimizationPolicy
{
	static inline var MIN_COMPACT_GRAPHIC_PIXELS:Float = 4194304;

	public static inline function shouldUseCompactGraphic(width:Int, height:Int):Bool
	{
		return width > 0 && height > 0 && width * (height:Float) >= MIN_COMPACT_GRAPHIC_PIXELS;
	}
}
