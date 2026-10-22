package;

class TestMain {
	static function main() {
		CoreTests.run();
		SessionTests.run();
		var code = T.report();
		try dbe.launcher.util.PathUtil.deleteRecursive(haxe.io.Path.join([Sys.getCwd(), "tests", ".tmp"])) catch (_:Dynamic) {}
		Sys.exit(code);
	}
}
