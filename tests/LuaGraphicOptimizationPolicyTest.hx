import dbe.graphics.LuaGraphicOptimizationPolicy;

class LuaGraphicOptimizationPolicyTest
{
	static function assertSame(actual:Dynamic, expected:Dynamic, message:String):Void
	{
		if (actual != expected) throw message;
	}

	static function main():Void
	{
		assertSame(LuaGraphicOptimizationPolicy.shouldUseCompactGraphic(2047, 2048), false,
			"Generated graphics below the memory threshold must keep their existing bitmap dimensions");
		assertSame(LuaGraphicOptimizationPolicy.shouldUseCompactGraphic(2048, 2048), true,
			"Generated graphics at the memory threshold must use a compact solid backing pixel");
		assertSame(LuaGraphicOptimizationPolicy.shouldUseCompactGraphic(12000, 12000), true,
			"Very large generated solid graphics must use a compact backing pixel");
		assertSame(LuaGraphicOptimizationPolicy.shouldUseCompactGraphic(0, 12000), false,
			"Invalid dimensions must not use the compact path");
		assertSame(LuaGraphicOptimizationPolicy.shouldUseCompactGraphic(-1, 12000), false,
			"Negative dimensions must not use the compact path");
		Sys.println("LuaGraphicOptimizationPolicyTest: PASS");
	}
}
