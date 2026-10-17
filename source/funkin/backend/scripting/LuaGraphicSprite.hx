package funkin.backend.scripting;

import flixel.FlxCamera;
import flixel.FlxSprite;
import flixel.math.FlxMatrix;
import flixel.util.FlxColor;
import dbe.graphics.LuaGraphicOptimizationPolicy;

/**
	A Lua sprite that can represent very large, generated solid-color rectangles
	with a single backing pixel while keeping the original logical size and scale.
 */
class LuaGraphicSprite extends FlxSprite
{
	var compactWidth:Int = 0;
	var compactHeight:Int = 0;

	public function new(?X:Float = 0, ?Y:Float = 0)
	{
		super(X, Y);
		makeGraphic(1, 1, FlxColor.TRANSPARENT);
	}

	public function makeLuaGraphic(width:Int, height:Int, color:FlxColor):FlxSprite
	{
		compactWidth = 0;
		compactHeight = 0;

		if (!LuaGraphicOptimizationPolicy.shouldUseCompactGraphic(width, height))
			return makeGraphic(width, height, color);

		makeGraphic(1, 1, color);
		compactWidth = width;
		compactHeight = height;
		frame.sourceSize.set(width, height);
		resetFrameSize();
		updateHitbox();
		return this;
	}

	public function compactPixelColor(x:Int, y:Int):Null<Int>
	{
		if (!hasCompactGraphic() || pixels == null || x < 0 || y < 0 || x >= compactWidth || y >= compactHeight)
			return null;

		return pixels.getPixel32(0, 0);
	}

	inline function hasCompactGraphic():Bool
	{
		return compactWidth > 0 && compactHeight > 0 && frame != null && graphic != null && graphic.width == 1 && graphic.height == 1
			&& frameWidth == compactWidth && frameHeight == compactHeight;
	}

	public override function isSimpleRenderBlit(?camera:FlxCamera):Bool
	{
		if (hasCompactGraphic()) return false;
		return super.isSimpleRenderBlit(camera);
	}

	public override function doAdditionalMatrixStuff(matrix:FlxMatrix, camera:FlxCamera):Void
	{
		super.doAdditionalMatrixStuff(matrix, camera);
		if (!hasCompactGraphic()) return;

		// The frame samples one pixel; stretch its local x/y axes to the logical
		// frame dimensions after FlxSprite has applied scale, rotation and position.
		matrix.a *= compactWidth;
		matrix.b *= compactWidth;
		matrix.c *= compactHeight;
		matrix.d *= compactHeight;
	}
}
