import cne.compat.ReentrantEventArgsStack;

class ScriptPackEventArgsStackTest {
	static function main():Void {
		var stack = new ReentrantEventArgsStack();
		var pauseEvent = {cancelled: false};
		var outerArgs = stack.beginDispatch(pauseEvent);
		var substateEvent = {cancelled: false};
		var innerArgs = stack.beginDispatch(substateEvent);

		assert(outerArgs != innerArgs, "nested events need separate callback argument slots");
		stack.endDispatch();
		assert(outerArgs[0] == pauseEvent, "ending a nested dispatch must restore the outer event argument");
		outerArgs[0].cancelled = true;
		stack.endDispatch();

		assert(pauseEvent.cancelled, "a callback result must still apply to the original outer event");
		assert(!substateEvent.cancelled, "the nested event must not receive the outer callback result");
		Sys.println("ScriptPackEventArgsStackTest: PASS");
	}

	static function assert(condition:Bool, message:String):Void {
		if (!condition) throw message;
	}
}
