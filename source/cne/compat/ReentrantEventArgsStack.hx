package cne.compat;

/** Reuses event argument arrays while keeping nested dispatches reentrant. */
class ReentrantEventArgsStack
{
	private var eventArgs:Array<Array<Dynamic>> = [];
	private var depth:Int = 0;

	public function new() {}

	public function beginDispatch(event:Dynamic):Array<Dynamic>
	{
		if (depth == eventArgs.length) eventArgs.push([null]);
		var args = eventArgs[depth++];
		args[0] = event;
		return args;
	}

	public function endDispatch():Void
	{
		if (depth <= 0) throw "Cannot end an event dispatch when none is active.";
		eventArgs[--depth][0] = null;
	}
}
