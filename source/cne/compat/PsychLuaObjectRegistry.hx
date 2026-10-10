package cne.compat;

/** Stores Psych-style tagged objects for one Lua script instance. */
class PsychLuaObjectRegistry<T>
{
	private var objects:Map<String, T> = [];

	public static function normalizeTag(tag:String):String
	{
		return tag == null ? "" : StringTools.replace(tag, ".", "");
	}

	public function new() {}

	public function set(tag:String, object:T):T
	{
		var key = normalizeTag(tag);
		if (key.length > 0 && object != null) objects.set(key, object);
		return object;
	}

	public function get(tag:String):Null<T>
	{
		return objects.get(normalizeTag(tag));
	}

	public function exists(tag:String):Bool
	{
		return objects.exists(normalizeTag(tag));
	}

	public function remove(tag:String):Null<T>
	{
		var key = normalizeTag(tag);
		var object = objects.get(key);
		objects.remove(key);
		return object;
	}

	public function keys():Array<String>
	{
		return [for (key in objects.keys()) key];
	}

	public function clear():Void
	{
		objects.clear();
	}
}
