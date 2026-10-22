package dbe.launcher;

#if sys
import sys.thread.Mutex;
import sys.thread.Thread;
#end

/**
 * Runs blocking jobs on a background thread and delivers completion callbacks
 * back on the main (UI) thread via {@link pump}, which must be called every frame.
 */
class Worker {
	static var mutex = new Mutex();
	static var queue:Array<() -> Void> = [];

	public static var busy(default, null) = false;

	public static function run(job:() -> Void, done:(error:Null<Dynamic>) -> Void):Bool {
		if (busy) return false;
		busy = true;
		Thread.create(() -> {
			var err:Dynamic = null;
			try job() catch (e:Dynamic) err = e;
			post(() -> {
				busy = false;
				done(err);
			});
		});
		return true;
	}

	/** Schedules `fn` to run on the main thread. Safe from any thread. */
	public static function post(fn:() -> Void) {
		mutex.acquire();
		queue.push(fn);
		mutex.release();
	}

	public static function pump() {
		mutex.acquire();
		var q = queue;
		queue = [];
		mutex.release();
		for (fn in q) fn();
	}

	public static function describe(e:Dynamic):String {
		if (e == null) return "";
		if (Std.isOfType(e, haxe.Exception)) return (e : haxe.Exception).message;
		return Std.string(e);
	}
}
