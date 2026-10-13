import dbe.compatibility.mods.RuntimeModConverter;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

class RuntimeModMenuAssetsTest {
	static var fixtureRoot:String;

	static function main():Void {
		fixtureRoot = Path.join([Sys.getCwd(), "../.menu-assets-" + Std.string(Std.int(Date.now().getTime())) + "-" + Std.random(1000000)]);
		var sourceRoot = Path.join([fixtureRoot, "source"]);
		var managedRoot = Path.join([fixtureRoot, "managed"]);
		var failure:Dynamic = null;

		try {
			write(sourceRoot, "pack.json", "{}\n");
			write(sourceRoot, "weeks/weekTABI.json", '{"storyName":"d 3 S 0 r","weekBackground":"d3r","difficulties":"d3r","songs":[["genocide-d3r"]]}');
			write(sourceRoot, "images/mainmenu/menu_story_mode.png", "story-mode-image");
			write(sourceRoot, "images/mainmenu/menu_story_mode.xml", '<TextureAtlas imagePath="menu_story_mode.png"><SubTexture name="story_mode basic0000"/><SubTexture name="story_mode white0001"/></TextureAtlas>');
			write(sourceRoot, "images/menuBG.png", "menu-bg-image");
			write(sourceRoot, "images/menudesat.png", "menu-desat-image");
			write(sourceRoot, "images/storymenu/weekTABI.png", "week-card-image");
			write(sourceRoot, "images/menudifficulties/D3R.png", "difficulty-image");
			write(sourceRoot, "images/menubackgrounds/menu_d3r.png", "week-background-image");
			write(sourceRoot, "images/campaign_menu_UI_assets.png", "story-arrows-image");
			write(sourceRoot, "images/logoBumpin.png", "title-logo-image");
			write(sourceRoot, "images/logoBumpin.xml", '<TextureAtlas imagePath="logoBumpin.png"><SubTexture name="logo bumpin0000" x="0" y="0" width="1" height="1"/></TextureAtlas>');
			write(sourceRoot, "images/gfdancetitle.png", "title-girlfriend-image");
			write(sourceRoot, "images/titleenter.png", "title-enter-image");
			write(sourceRoot, "images/titleenter.xml", '<TextureAtlas imagePath="titleenter.png"><SubTexture name="ENTER IDLE0000" x="0" y="0" width="1" height="1"/><SubTexture name="ENTER PRESSED0000" x="0" y="0" width="1" height="1"/></TextureAtlas>');

			var result:Dynamic = RuntimeModConverter.prepare(sourceRoot, managedRoot);
			assert(result.blocked != true, "Psych menu fixture should not be blocked by conversion: " + haxe.Json.stringify(result.report.incompatibilities));
			assert(result.converted == true, "Psych menu fixture should pass through runtime normalization");

			var convertedRoot:String = result.loadPath;
			assertExists(convertedRoot, "images/menus/mainmenu/story mode.png", "main-menu atlas image should use the path DBE loads");
			assertExists(convertedRoot, "images/menus/menuBG.png", "Psych menu background should use the path DBE loads");
			assertExists(convertedRoot, "images/menus/menuDesat.png", "Psych desaturated menu background should use the path DBE loads");
			assertExists(convertedRoot, "images/menus/storymenu/weeks/weekTABI.png", "Psych week card should use the path DBE loads");
			assertExists(convertedRoot, "images/menus/storymenu/difficulties/d3r.png", "difficulty asset should match the lower-case DBE lookup");
			assertExists(convertedRoot, "images/menus/storymenu/backgrounds/menu_d3r.png", "Psych week background should use the DBE story-menu path");
			assertExists(convertedRoot, "images/menus/storymenu/assets.png", "Psych campaign UI atlas should use the DBE story-menu path");
			assertExists(convertedRoot, "images/menus/titlescreen/logo.png", "Psych title logo should use the DBE title-screen path");
			assertExists(convertedRoot, "images/menus/titlescreen/logo.xml", "Psych title logo atlas should use the DBE title-screen path");
			assertExists(convertedRoot, "images/menus/titlescreen/gf.png", "Psych title character should use the DBE title-screen path");
			assertExists(convertedRoot, "images/menus/titlescreen/gf.xml", "Psych title character dummy atlas should be generated when XML is missing");
			assertExists(convertedRoot, "images/menus/titlescreen/titleEnter.png", "Psych title prompt should use the DBE title-screen path");
			assertExists(convertedRoot, "images/menus/titlescreen/titleEnter.xml", "Psych title prompt atlas should use the DBE title-screen path");

			var menuXml = File.getContent(Path.join([convertedRoot, "images/menus/mainmenu/story mode.xml"]));
			assert(menuXml.indexOf('name="story mode basic0000"') >= 0, "main-menu atlas prefixes should use DBE option spelling");
			assert(menuXml.indexOf('name="story mode white0001"') >= 0, "selected main-menu atlas prefix should use DBE option spelling");
			var titleEnterXml = File.getContent(Path.join([convertedRoot, "images/menus/titlescreen/titleEnter.xml"]));
			assert(titleEnterXml.indexOf('name="Press Enter to Begin0000"') >= 0, "Psych idle title prompt prefix should match the DBE title state");

			var weekXml = new haxe.xml.Access(Xml.parse(File.getContent(Path.join([convertedRoot, "data/weeks/weeks/weekTABI.xml"]))).firstElement());
			assert(weekXml.att.sprite == "weekTABI", "Psych week card should be identified by the week file name");
			assert(weekXml.att.background == "d3r", "Psych week background should be kept separately from the card image");
		} catch (error:Dynamic) {
			failure = error;
		}

		removeTree(fixtureRoot);
		if (failure != null) throw failure;
		Sys.println("RuntimeModMenuAssetsTest: PASS");
	}

	static function write(root:String, relative:String, contents:String):Void {
		var path = Path.join([root, relative]);
		createDirectories(Path.directory(path));
		File.saveContent(path, contents);
	}

	static function createDirectories(path:String):Void {
		if (path == null || path == "" || FileSystem.exists(path)) return;
		createDirectories(Path.directory(path));
		FileSystem.createDirectory(path);
	}

	static function assertExists(root:String, relative:String, message:String):Void {
		assert(FileSystem.exists(Path.join([root, relative])), message);
	}

	static function assert(condition:Bool, message:String):Void {
		if (!condition) throw message;
	}

	static function removeTree(path:String):Void {
		if (path == null || !FileSystem.exists(path)) return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path)) removeTree(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else FileSystem.deleteFile(path);
	}
}
