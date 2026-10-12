package cne.compat;

/** Resolves and applies explicit, per-mod Psych Lua compatibility profiles. */
class PsychLuaProfile
{
	public static inline var UNSPECIFIED:String = "unspecified";
	public static inline var PSYCH_063:String = "0.6.3";
	public static inline var PSYCH_104:String = "1.0.4";
	public static inline var CONFIG_PATH:String = "data/config/dbe-compat.json";

	public var modName(default, null):String;
	public var profile(default, null):String;

	private var diagnosticSink:String->Void;
	private var diagnosedApis:Map<String, Bool> = [];

	public function new(modName:String, profile:String, ?diagnosticSink:String->Void)
	{
		this.modName = modName == null || StringTools.trim(modName).length == 0 ? "(default)" : modName;
		this.profile = isSupportedProfile(profile) ? profile : UNSPECIFIED;
		this.diagnosticSink = diagnosticSink;
	}

	/** Parse only DBE's opt-in profile field; unrelated mod metadata is left untouched. */
	public static function resolveConfig(configText:Null<String>):PsychLuaProfileResolution
	{
		if (configText == null)
			return {profile: UNSPECIFIED, configStatus: "missing", diagnostic: null};

		var config:Dynamic;
		try
		{
			config = haxe.Json.parse(configText);
		}
		catch (_:Dynamic)
		{
			return invalidConfig("malformed", "could not be parsed as JSON");
		}

		if (config == null || !Reflect.isObject(config) || Std.isOfType(config, Array))
			return invalidConfig("malformed", "must be a JSON object");

		if (!Reflect.hasField(config, "psychLuaProfile"))
			return {profile: UNSPECIFIED, configStatus: "missing", diagnostic: null};

		var rawProfile:Dynamic = Reflect.field(config, "psychLuaProfile");
		if (!Std.isOfType(rawProfile, String))
			return invalidConfig("unsupported", "psychLuaProfile must be a string");

		var requestedProfile = StringTools.trim(cast rawProfile);
		if (requestedProfile.length == 0)
			return invalidConfig("empty", "psychLuaProfile is empty");
		if (!isSupportedProfile(requestedProfile))
			return invalidConfig("unsupported", 'unsupported psychLuaProfile "$requestedProfile"');

		return {profile: requestedProfile, configStatus: "selected", diagnostic: null};
	}

	/**
	 * Returns true for shared contracts or for a contract supported by this
	 * mod's explicit profile. Unspecified or incompatible calls fail closed.
	 */
	public function allowsApi(apiName:String, supportedProfiles:Array<String>):Bool
	{
		if (apiName == null || StringTools.trim(apiName).length == 0 || supportedProfiles == null) return false;

		var supports063 = supportedProfiles.contains(PSYCH_063);
		var supports104 = supportedProfiles.contains(PSYCH_104);
		if (supports063 && supports104) return true;
		if (profile != UNSPECIFIED && supportedProfiles.contains(profile)) return true;

		warnOnce(apiName, supports063, supports104);
		return false;
	}

	public static function isSupportedProfile(profile:String):Bool
	{
		return profile == PSYCH_063 || profile == PSYCH_104;
	}

	public static function supportedProfiles():Array<String>
	{
		return [PSYCH_063, PSYCH_104];
	}

	private static function invalidConfig(status:String, reason:String):PsychLuaProfileResolution
	{
		return {
			profile: UNSPECIFIED,
			configStatus: status,
			diagnostic: 'Psych Lua profile config ${CONFIG_PATH} $reason. Supported values: ${PSYCH_063}, ${PSYCH_104}.'
		};
	}

	private function warnOnce(apiName:String, supports063:Bool, supports104:Bool):Void
	{
		if (diagnosedApis.exists(apiName)) return;
		diagnosedApis.set(apiName, true);
		if (diagnosticSink == null) return;

		var availability = supports063 && supports104 ? "both profiles" : (supports063 ? PSYCH_063 : (supports104 ? PSYCH_104 : "no declared profile"));
		var reason = profile == UNSPECIFIED
			? 'has no selected profile; this API requires ${availability}'
			: 'selected profile ${profile} does not support this API; it requires ${availability}';
		diagnosticSink('Psych Lua API "$apiName" for mod "$modName" $reason. Choose ${PSYCH_063} or ${PSYCH_104} in ${CONFIG_PATH}.');
	}
}

typedef PsychLuaProfileResolution = {
	var profile:String;
	var configStatus:String;
	var diagnostic:Null<String>;
}
