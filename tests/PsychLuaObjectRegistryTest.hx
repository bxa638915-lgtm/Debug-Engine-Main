import cne.compat.PsychLuaObjectRegistry;

class PsychLuaObjectRegistryTest
{
	static function assertTrue(value:Bool, message:String):Void
	{
		if (!value) throw message;
	}

	static function main():Void
	{
		var registry = new PsychLuaObjectRegistry<Dynamic>();
		var sprite:Dynamic = {name: "background"};
		registry.set("stage.bg", sprite);

		assertTrue(registry.exists("stagebg"), "Psych tags must normalize dots when storing objects");
		assertTrue(registry.get("stage.bg") == sprite, "Psych tags must resolve to their registered object");
		assertTrue(registry.remove("stagebg") == sprite, "Removing a tag must return its object");
		assertTrue(!registry.exists("stage.bg"), "Removed tags must no longer be registered");
		Sys.println("PsychLuaObjectRegistryTest: PASS");
	}
}
