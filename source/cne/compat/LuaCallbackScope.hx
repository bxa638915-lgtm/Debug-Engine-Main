package cne.compat;

import llua.Lua;
import llua.Lua.Lua_helper;
import llua.Convert;
import llua.State;

/**
	Gives each Lua state unique native callback names while exposing stable API
	names to Lua. linc_luajit stores callbacks globally by name, so this scope
	prevents callbacks from separate scripts replacing one another.
**/
class LuaCallbackScope
{
	private static var nextScopeId:Int = 0;
	private static inline var INTERNAL_PREFIX:String = "__cne_callback_";

	private var state:State;
	private var scopeId:Int;
	private var callbackNames:Array<String> = [];
	private var disposed:Bool = false;
	private var errorHandler:Dynamic->Void;

	public function new(state:State, ?errorHandler:Dynamic->Void)
	{
		this.state = state;
		this.errorHandler = errorHandler;
		scopeId = nextScopeId++;
		Lua.init_callbacks(state);
		// linc_luajit's default dispatcher converts each argument by its original
		// stack index, while Convert.fromLuaTable expects the value at the top of
		// the stack. Copy each argument to the top before converting it so tables
		// followed by other arguments (for example addAnimation(..., frames, fps))
		// are read safely.
		Lua.set_callbacks_function(cpp.Callable.fromStaticFunction(callbackHandler));
	}

	@:keep
	public static function callbackHandler(callbackState:State, callbackName:String):Int
	{
		var callback = Lua_helper.callbacks.get(callbackName);
		if (callback == null) return 0;

		var args:Array<Dynamic> = [];
		var argCount = Lua.gettop(callbackState);
		for (index in 1...(argCount + 1))
		{
			Lua.pushvalue(callbackState, index);
			args.push(Convert.fromLua(callbackState, -1));
			Lua.pop(callbackState, 1);
		}

		var result:Dynamic = Reflect.callMethod(null, callback, args);
		if (result == null || !canConvert(result, 0))
			Lua.pushnil(callbackState);
		else
			Convert.toLua(callbackState, result);
		return 1;
	}

	/** Registers a Haxe callback and exposes it under the requested Lua name. */
	public function bind(name:String, callback:Dynamic):Bool
	{
		if (disposed || state == null || name == null || StringTools.trim(name).length == 0 || callback == null)
			return false;

		var internalName = INTERNAL_PREFIX + scopeId + "_" + callbackNames.length;
		var callbackState = state;
		var callbackErrorHandler = errorHandler;
		var safeCallback = Reflect.makeVarArgs((args:Array<Dynamic>) ->
		{
			var result:Dynamic = null;
			var called:Bool = false;
			try
			{
				result = Reflect.callMethod(null, callback, args);
				called = true;
			}
			catch (error:Dynamic)
			{
				var paddedArgs = args.copy();
				for (_ in 0...8)
				{
					paddedArgs.push(null);
					try
					{
						result = Reflect.callMethod(null, callback, paddedArgs);
						called = true;
						break;
					}
					catch (_:Dynamic) {}
				}
				if (!called && callbackErrorHandler != null)
					try callbackErrorHandler(error) catch (_:Dynamic) {}
			}
			// linc_luajit returns one result even for void callbacks. Push nil
			// explicitly so it cannot accidentally return the last input argument.
			// Unsupported Haxe classes also become nil instead of leaving the Lua
			// stack unbalanced in linc_luajit's conversion helper.
			if (result == null || !canConvert(result, 0))
			{
				Lua.pushnil(callbackState);
				return null;
			}
			return result;
		});
		Lua.register(state, internalName, safeCallback);
		Lua.getglobal(state, internalName);
		Lua.setglobal(state, name);
		callbackNames.push(internalName);
		return true;
	}

	private static function canConvert(value:Dynamic, depth:Int):Bool
	{
		if (depth > 16) return false;
		return switch (Type.typeof(value))
		{
			case TNull | TBool | TInt | TFloat | TClass(String): true;
			case TClass(Array):
				var supported = true;
				for (item in (cast value:Array<Dynamic>))
					if (!canConvert(item, depth + 1)) supported = false;
				supported;
			case TClass(haxe.ds.StringMap):
				var supported = true;
				for (item in (cast value:haxe.ds.StringMap<Dynamic>))
					if (!canConvert(item, depth + 1)) supported = false;
				supported;
			case TObject:
				var supported = true;
				for (field in Reflect.fields(value))
					if (!canConvert(Reflect.field(value, field), depth + 1)) supported = false;
				supported;
			default: false;
		}
	}

	/** Removes the callbacks owned by this state from linc_luajit's global map. */
	public function dispose():Void
	{
		if (disposed) return;
		disposed = true;
		if (state != null)
			for (name in callbackNames)
				llua.Lua.Lua_helper.remove_callback(state, name);
		callbackNames = [];
		state = null;
	}
}
