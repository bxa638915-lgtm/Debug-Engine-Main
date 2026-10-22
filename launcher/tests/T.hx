package;

import haxe.PosInfos;

/** Minimal dependency-free test harness (runs under `--interp` and hxcpp). */
class T {
	public static var passed = 0;
	public static var failed = 0;
	static var current = "";

	public static function run(name:String, fn:() -> Void) {
		current = name;
		try {
			fn();
		} catch (e:haxe.Exception) {
			fail('threw: ${e.message}\n${e.stack}');
		} catch (e:Dynamic) {
			fail('threw: $e');
		}
	}

	public static function ok(cond:Bool, msg:String = "", ?p:PosInfos) {
		if (cond) passed++;
		else fail('assert failed $msg (${p.fileName}:${p.lineNumber})');
	}

	public static function eq<V>(expected:V, actual:V, msg:String = "", ?p:PosInfos) {
		if (expected == actual) passed++;
		else fail('expected <$expected> got <$actual> $msg (${p.fileName}:${p.lineNumber})');
	}

	public static function throws(fn:() -> Void, msg:String = "", ?p:PosInfos) {
		var threw = false;
		try fn() catch (_:Dynamic) threw = true;
		ok(threw, 'expected throw $msg', p);
	}

	static function fail(msg:String) {
		failed++;
		Sys.println('  FAIL [$current] $msg');
	}

	public static function report():Int {
		Sys.println('\n$passed passed, $failed failed');
		return failed == 0 ? 0 : 1;
	}
}
