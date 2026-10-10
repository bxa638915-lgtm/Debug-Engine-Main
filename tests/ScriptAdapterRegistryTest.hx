import cne.compat.ScriptAdapterRegistry;

class ScriptAdapterRegistryTest
{
	static function assertTrue(value:Bool, message:String):Void
	{
		if (!value) throw message;
	}

	static function assertFalse(value:Bool, message:String):Void
	{
		if (value) throw message;
	}

	static function main():Void
	{
		var registry = new ScriptAdapterRegistry<String>();
		var registered = registry.register(
			"HScript",
			"HScript-Improved",
			[".HX", "hscript", "hsc", "hxs", "hxc"],
			(path:String) -> "file:" + path,
			(code:String, path:String) -> "source:" + path + "=" + code
		);

		assertTrue(registered, "A valid adapter must register");
		assertTrue(registry.supportsLanguage("hscript"), "Language lookup must ignore case");
		assertTrue(registry.supportsLanguage(" HSCRIPT-IMPROVED "), "Runtime aliases must be discoverable as languages");
		assertTrue(registry.supportsExtension("mods/example.HX"), "Extension lookup must accept paths and ignore case");
		assertTrue(registry.supportsExtension("mods/stage.hxc"), "V-Slice scripted-class extension must dispatch through the HScript adapter");
		assertFalse(registry.supportsExtension("example.pack"), "Unknown extensions must stay unsupported");
		assertTrue(registry.getLanguages().contains("hscript"), "Registry must report canonical languages");
		assertTrue(registry.getRuntimes().contains("hscript-improved"), "Registry must report runtimes");
		assertTrue(registry.getSupportedExtensions().contains("hxs"), "Registry must report registered extensions");
		assertTrue(registry.create("mods/test.hx") == "file:mods/test.hx", "File creation must dispatch to its adapter");
		assertTrue(registry.create("mods/stage.hxc") == "file:mods/stage.hxc", "V-Slice scripted classes must reach the registered HScript factory");
		assertTrue(registry.createFromString("trace(1);", "memory.hscript") == "source:memory.hscript=trace(1);", "String creation must dispatch with code and path");
		assertTrue(registry.create("unknown.lua") == null, "Unknown formats must return null for the caller to handle");

		var duplicate = registry.register(
			"lua",
			"luajit",
			["lua", "hx"],
			(path:String) -> "lua:" + path,
			(code:String, path:String) -> code
		);
		assertFalse(duplicate, "Overlapping extensions must be rejected atomically");
		assertFalse(registry.supportsLanguage("lua"), "Rejected adapters must not leak a language entry");
		assertTrue(registry.create("after.hx") == "file:after.hx", "A rejected registration must preserve prior dispatch");

		var extensionCopy = registry.getSupportedExtensions();
		extensionCopy.push("lua");
		assertFalse(registry.supportsExtension("example.lua"), "Callers must not mutate the registry through returned arrays");

		Sys.println("ScriptAdapterRegistryTest: PASS");
	}
}
