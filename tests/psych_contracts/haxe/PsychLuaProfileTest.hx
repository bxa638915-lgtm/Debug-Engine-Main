package;

import cne.compat.PsychLuaProfile;

class PsychLuaProfileTest
{
	static function main():Void
	{
		var missing = PsychLuaProfile.resolveConfig(null);
		assertEquals("unspecified", missing.profile, "absent config profile");
		assertEquals("missing", missing.configStatus, "absent config status");

		var psych063 = PsychLuaProfile.resolveConfig('{"psychLuaProfile":"0.6.3"}');
		assertEquals("0.6.3", psych063.profile, "Psych 0.6.3 profile");
		assertEquals("selected", psych063.configStatus, "Psych 0.6.3 config status");

		var psych104 = PsychLuaProfile.resolveConfig('{"psychLuaProfile":"1.0.4","otherModMetadata":{"keep":true}}');
		assertEquals("1.0.4", psych104.profile, "Psych 1.0.4 profile");
		assertEquals("selected", psych104.configStatus, "Psych 1.0.4 config status");

		var malformed = PsychLuaProfile.resolveConfig('{"psychLuaProfile":');
		assertEquals("unspecified", malformed.profile, "malformed config profile");
		assertEquals("malformed", malformed.configStatus, "malformed config status");
		assertTrue(malformed.diagnostic != null, "malformed config diagnostic");

		var unsupported = PsychLuaProfile.resolveConfig('{"psychLuaProfile":"2.0.0"}');
		assertEquals("unspecified", unsupported.profile, "unsupported profile fallback");
		assertEquals("unsupported", unsupported.configStatus, "unsupported profile status");
		assertTrue(unsupported.diagnostic != null, "unsupported profile diagnostic");

		var empty = PsychLuaProfile.resolveConfig('{"psychLuaProfile":"  "}');
		assertEquals("unspecified", empty.profile, "empty profile fallback");
		assertEquals("empty", empty.configStatus, "empty profile status");
		assertTrue(empty.diagnostic != null, "empty profile diagnostic");

		var warnings:Array<String> = [];
		var firstMod = new PsychLuaProfile("first-mod", psych063.profile, (message:String) -> { warnings.push(message); });
		var secondMod = new PsychLuaProfile("second-mod", missing.profile, (message:String) -> { warnings.push(message); });
		assertTrue(firstMod.allowsApi("sharedApi", ["0.6.3", "1.0.4"]), "shared API runs without ambiguity");
		assertTrue(firstMod.allowsApi("oldApi", ["0.6.3"]), "selected profile permits its API");
		assertFalse(secondMod.allowsApi("versionedApi", ["1.0.4"]), "unspecified profile fails closed");
		assertFalse(secondMod.allowsApi("versionedApi", ["1.0.4"]), "repeated ambiguous API remains blocked");	
		assertEquals(1, warnings.length, "one warning per mod/API");
		assertContains(warnings[0], "second-mod", "diagnostic mod name");
		assertContains(warnings[0], "versionedApi", "diagnostic API name");
		assertContains(warnings[0], "0.6.3", "diagnostic candidate profile");
		assertContains(warnings[0], "1.0.4", "diagnostic candidate profile");
		assertContains(warnings[0], "data/config/dbe-compat.json", "diagnostic required config path");
		assertEquals("0.6.3", firstMod.profile, "second mod did not replace first mod profile");
		assertEquals("unspecified", secondMod.profile, "second mod did not inherit first mod profile");

		trace("PsychLuaProfileTest passed");
	}

	static function assertTrue(value:Bool, label:String):Void
	{
		if (!value) throw '$label: expected true';
	}

	static function assertFalse(value:Bool, label:String):Void
	{
		if (value) throw '$label: expected false';
	}

	static function assertEquals<T>(expected:T, actual:T, label:String):Void
	{
		if (expected != actual) throw '$label: expected $expected, got $actual';
	}

	static function assertContains(value:String, expected:String, label:String):Void
	{
		if (value == null || value.indexOf(expected) < 0) throw '$label: expected "$value" to contain "$expected"';
	}
}
