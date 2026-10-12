import funkin.game.CharacterJSONAdapter;

class CharacterJSONAdapterTest {
	static function main():Void {
		var original = haxe.Json.parse('{"assetPath":"characters/bf","offsets":[17,-29],"position":[4,5],"animations":[{"name":"idle","prefix":"BF idle dance","frameRate":30,"looped":true,"frameIndices":[1,3],"animType":"framelabel","offsets":[8,-6]}]}');
		assert(CharacterJSONAdapter.getSpritePath(original, "fallback") == "bf", "Funkin assetPath is adapted to the XML loader's character-relative path");
		assert(CharacterJSONAdapter.getGlobalOffset(original, 0) == 17 && CharacterJSONAdapter.getGlobalOffset(original, 1) == -29, "Funkin global offsets take precedence over legacy position");
		var originalAnimation = original.animations[0];
		assert(CharacterJSONAdapter.getAnimationName(originalAnimation) == "idle", "Funkin animation name is preserved");
		assert(CharacterJSONAdapter.getAnimationPrefix(originalAnimation, "idle") == "BF idle dance", "Funkin animation prefix is preserved");
		assert(CharacterJSONAdapter.getAnimationFrameRate(originalAnimation) == 30, "Funkin frameRate is preserved");
		assert(CharacterJSONAdapter.isAnimationLooped(originalAnimation), "Funkin looped is preserved");
		assert(CharacterJSONAdapter.getAnimationIndices(originalAnimation).join(",") == "1,3", "Funkin frameIndices are preserved");
		assert(CharacterJSONAdapter.getAnimationLabelMode(originalAnimation) == true, "Funkin frame-label animation mode is preserved");
		var symbolAnimation = haxe.Json.parse('{"animType":"symbol"}');
		assert(CharacterJSONAdapter.getAnimationLabelMode(symbolAnimation) == false, "Funkin symbol animation mode is preserved");

		var legacy = haxe.Json.parse('{"image":"characters/legacy","position":[2,3],"animations":[{"anim":"singLEFT","name":"BF left","fps":24,"loop":true,"indices":[0,2]}]}');
		assert(CharacterJSONAdapter.getSpritePath(legacy, "fallback") == "characters/legacy", "legacy image remains supported");
		assert(CharacterJSONAdapter.getGlobalOffset(legacy, 0) == 2 && CharacterJSONAdapter.getGlobalOffset(legacy, 1) == 3, "legacy position remains supported");
		var legacyAnimation = legacy.animations[0];
		assert(CharacterJSONAdapter.getAnimationName(legacyAnimation) == "singLEFT", "legacy animation name remains supported");
		assert(CharacterJSONAdapter.getAnimationPrefix(legacyAnimation, "singLEFT") == "BF left", "legacy animation prefix remains supported");
		assert(CharacterJSONAdapter.isAnimationLooped(legacyAnimation), "legacy loop remains supported");
		assert(CharacterJSONAdapter.getAnimationIndices(legacyAnimation).join(",") == "0,2", "legacy indices remain supported");
	}

	static function assert(condition:Bool, message:String):Void {
		if (!condition) throw message;
	}
}
