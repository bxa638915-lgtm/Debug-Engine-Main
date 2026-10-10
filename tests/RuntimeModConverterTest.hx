import dbe.compatibility.mods.RuntimeModConverter;
import haxe.io.Path;
import haxe.crypto.Sha256;
import haxe.ds.List;
import haxe.io.Bytes;
import sys.FileSystem;
import sys.io.File;
import haxe.zip.Entry;
import haxe.zip.Writer;

class RuntimeModConverterTest {
	static function main():Void {
		var managedRootProvider = Reflect.field(RuntimeModConverter, "defaultManagedRoot");
		if (managedRootProvider == null) throw "Runtime mod conversion must provide a Windows-safe managed cache root";
		var defaultManagedRoot:String = Reflect.callMethod(RuntimeModConverter, managedRootProvider, []);
		var systemTempRoot = Sys.getEnv("TEMP");
		if (systemTempRoot == null || systemTempRoot == "") systemTempRoot = Sys.getEnv("TMPDIR");
		if (systemTempRoot != null && systemTempRoot != "" && defaultManagedRoot.indexOf(Path.normalize(systemTempRoot)) != 0)
			throw "Managed mod conversions must live under the user's temporary directory when it is available";
		if (Sys.systemName() == "Windows") {
			var sampleAssetPath = Path.join([defaultManagedRoot, "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", "shared", "images", "stages", "catastrophe-stage", "cars", "fxCarTemplate", "Animation.json"]);
			if (sampleAssetPath.length >= 260) throw "Managed mod asset paths must stay below the Windows MAX_PATH limit";
		}

		var tempRoot = Sys.getEnv("TEMP");
		if (tempRoot == null || tempRoot == "") tempRoot = Sys.getCwd();
		var root = Path.join([tempRoot, "runtime-mod-converter-test-" + Std.random(1000000000)]);
		if (FileSystem.exists(root)) deleteTree(root);
		FileSystem.createDirectory(root);
		var source = Path.join([root, "source"]);
		var packageRoot = Path.join([source, "Release", "assets", "preload"]);
		var outputRoot = Path.join([root, "managed"]);
		var chartSource = Path.join([packageRoot, "data", "songs", "bopeebo", "charts", "hard.json"]);
		FileSystem.createDirectory(Path.directory(chartSource));
		FileSystem.createDirectory(Path.join([packageRoot, "scripts"]));
		FileSystem.createDirectory(outputRoot);
		File.saveContent(Path.join([packageRoot, "pack.json"]), '{"name":"Psych Fixture"}');
		File.saveContent(chartSource, '{"song":"Bopeebo"}');
		File.saveContent(Path.join([packageRoot, "scripts", "example.lua"]), "function onCreate() end");
		File.saveContent(Path.join([packageRoot, "scripts", "unsupported.js"]), "export function onCreate() {}");
		File.saveContent(Path.join([source, "README.txt"]), "keep this file for review");
		try {
			var convert = Reflect.field(RuntimeModConverter, "convertDirectory");
			if (convert == null) throw "Runtime mod converter must expose folder conversion";
			var prepare = Reflect.field(RuntimeModConverter, "prepare");
			var report:Dynamic = Reflect.callMethod(RuntimeModConverter, convert, [source, outputRoot]);
			var output:String = Reflect.field(report, "output");
			if (Reflect.field(report, "sourceFormat") != "psych")
				throw "Runtime conversion must identify Psych packages from pack.json";
			if (!FileSystem.exists(Path.join([output, "data", "songs", "bopeebo", "charts", "hard.json"]))
				|| !FileSystem.exists(Path.join([output, "scripts", "example.lua"]))
				|| !FileSystem.exists(Path.join([output, "_dbe_preserved", "README.txt"])))
				throw "Runtime conversion must normalize known roots and retain files outside the package root";
			if (File.getContent(chartSource) != '{"song":"Bopeebo"}'
				|| File.getContent(Path.join([source, "README.txt"])) != "keep this file for review")
				throw "Runtime conversion must leave the source package unchanged";
			if (Reflect.field(report, "converted") == null || Reflect.field(report, "retained") == null
				|| Reflect.field(report, "ignored") == null || Reflect.field(report, "unsupported") == null)
				throw "Runtime conversion must emit the structured conversion report";
			var unsupported:Array<Dynamic> = cast Reflect.field(report, "unsupported");
			if (unsupported.length != 1 || unsupported[0].source != "Release/assets/preload/scripts/unsupported.js")
				throw "Runtime conversion must list scripts with unsupported runtimes in the report";
			var cached:Dynamic = Reflect.callMethod(RuntimeModConverter, convert, [source, outputRoot]);
			if (cached.output != output || cached.contentHash != report.contentHash)
				throw "Repeated conversion must reuse the content-addressed managed package";

			var psychLayoutSource = Path.join([root, "psych-layout"]);
			FileSystem.createDirectory(Path.join([psychLayoutSource, "characters"]));
			FileSystem.createDirectory(Path.join([psychLayoutSource, "custom_events"]));
			FileSystem.createDirectory(Path.join([psychLayoutSource, "data", "characters"]));
			FileSystem.createDirectory(Path.join([psychLayoutSource, "stages"]));
			FileSystem.createDirectory(Path.join([psychLayoutSource, "weeks"]));
			File.saveContent(Path.join([psychLayoutSource, "pack.json"]), '{"name":"Psych Layout Fixture"}');
			var psychCharacterJson = '{"image":"characters/elmeena","position":[-800,-590],"scale":0.4}';
			File.saveContent(Path.join([psychLayoutSource, "characters", "elmeena.json"]), psychCharacterJson);
			var psychCharacterXml = '<!DOCTYPE codename-engine-character>\n<character sprite="characters/elmeena"><anim name="idle" anim="idle"/></character>';
			File.saveContent(Path.join([psychLayoutSource, "data", "characters", "elmeena.xml"]), psychCharacterXml);
			File.saveContent(Path.join([psychLayoutSource, "custom_events", "cameraShit.lua"]), "function onEvent(name, value1, value2) end");
			File.saveContent(Path.join([psychLayoutSource, "custom_events", "cameraShit.txt"]), "sucMyDick");
			File.saveContent(Path.join([psychLayoutSource, "stages", "heaven.json"]), '{"defaultZoom":1,"boyfriend":[770,100],"girlfriend":[400,130],"opponent":[-100,80],"camera_boyfriend":[1,2],"camera_speed":0.8,}');
			File.saveContent(Path.join([psychLayoutSource, "stages", "heaven.lua"]), "function onCreate() end");
			File.saveContent(Path.join([psychLayoutSource, "weeks", "smit.json"]), '{"songs":[["Smitten Rings","elmo",[255,201,209]]],"difficulties":"hard","storyName":"sup","hideStoryMode":true,}');
			var psychLayout:Dynamic = Reflect.callMethod(RuntimeModConverter, prepare, [psychLayoutSource, outputRoot]);
			if (psychLayout.blocked == true || psychLayout.converted != true || psychLayout.report.sourceFormat != "psych")
				throw "Psych folder layouts must be detected and normalized automatically";
			var normalizedPsych:String = psychLayout.loadPath;
			var missingPsychPaths:Array<String> = [];
			for (relative in ["data/characters/elmeena.json", "data/events/cameraShit.lua", "data/events/cameraShit.json", "data/stages/heaven.lua", "data/stages/heaven.xml", "data/weeks/weeks/smit.xml"])
				if (!FileSystem.exists(Path.join([normalizedPsych, relative]))) missingPsychPaths.push(relative);
			if (missingPsychPaths.length > 0)
				throw 'Psych paths missing from the normalized DBE package: ${missingPsychPaths.join(", ")}';
			var generatedEventPath = Path.join([normalizedPsych, "data", "events", "cameraShit.json"]);
			var preservedStagePath = Path.join([normalizedPsych, "_dbe_preserved", "psych_source", "stages", "heaven.json"]);
			var preservedWeekPath = Path.join([normalizedPsych, "_dbe_preserved", "psych_source", "weeks", "smit.json"]);
			if (!FileSystem.exists(generatedEventPath) || File.getContent(generatedEventPath) != '{"params":[]}\n'
				|| !FileSystem.exists(preservedStagePath) || !FileSystem.exists(preservedWeekPath))
				throw 'Psych event/original metadata mismatch: eventExists=${FileSystem.exists(generatedEventPath)}, event=${FileSystem.exists(generatedEventPath) ? File.getContent(generatedEventPath) : "missing"}, stageExists=${FileSystem.exists(preservedStagePath)}, weekExists=${FileSystem.exists(preservedWeekPath)}';
			var stageXml = File.getContent(Path.join([normalizedPsych, "data", "stages", "heaven.xml"]));
			var weekXml = File.getContent(Path.join([normalizedPsych, "data", "weeks", "weeks", "smit.xml"]));
			var stageRoot = Xml.parse(stageXml).firstElement();
			var boyfriendNodes = [for (node in stageRoot.elements()) if (node.nodeName == "boyfriend") node];
			if (stageXml.indexOf('zoom="1"') < 0 || stageXml.indexOf('x="770"') < 0 || stageXml.indexOf('camxoffset="1"') < 0
				|| weekXml.indexOf('name="sup"') < 0 || weekXml.indexOf("Smitten Rings") < 0 || weekXml.indexOf('name="hard"') < 0)
				throw "Psych stage and week metadata must retain their supported values when converted";
			if (boyfriendNodes.length != 1 || boyfriendNodes[0].get("x") != "770" || boyfriendNodes[0].get("camxoffset") != "1")
				throw "Psych stage position and camera data must share one DBE character node";
			if (File.getContent(Path.join([normalizedPsych, "_dbe_preserved", "psych_source", "stages", "heaven.json"]))
				!= '{"defaultZoom":1,"boyfriend":[770,100],"girlfriend":[400,130],"opponent":[-100,80],"camera_boyfriend":[1,2],"camera_speed":0.8,}'
				|| File.getContent(Path.join([normalizedPsych, "_dbe_preserved", "psych_source", "weeks", "smit.json"]))
				!= '{"songs":[["Smitten Rings","elmo",[255,201,209]]],"difficulties":"hard","storyName":"sup","hideStoryMode":true,}')
				throw "Converted Psych packages must keep the exact original metadata whenever fields are omitted";
			var psychUnsupported:Array<Dynamic> = cast Reflect.field(psychLayout.report, "unsupported");
			var stageUnsupportedField = false;
			var weekUnsupportedField = false;
			for (item in psychUnsupported) {
				if (item.source == "stages/heaven.json" && item.fields.contains("camera_speed")) stageUnsupportedField = true;
				if (item.source == "weeks/smit.json" && item.fields.contains("hideStoryMode")) weekUnsupportedField = true;
			}
			if (!stageUnsupportedField || !weekUnsupportedField)
				throw "Psych metadata fields without a DBE equivalent must be listed in the conversion report";
			if (File.getContent(Path.join([psychLayoutSource, "stages", "heaven.json"])).indexOf('"camera_speed"') < 0
				|| File.getContent(Path.join([psychLayoutSource, "weeks", "smit.json"])).indexOf('"storyName"') < 0)
				throw "Psych normalization must not modify source metadata";

			var mixedCneSource = Path.join([root, "mixed-cne"]);
			FileSystem.createDirectory(Path.join([mixedCneSource, "data", "config"]));
			FileSystem.createDirectory(Path.join([mixedCneSource, "data", "songs", "cat-o-strophe"]));
			FileSystem.createDirectory(Path.join([mixedCneSource, "scripts", "characters"]));
			FileSystem.createDirectory(Path.join([mixedCneSource, "shared", "images"]));
			FileSystem.createDirectory(Path.join([mixedCneSource, "songs", "cat-o-strophe"]));
			File.saveContent(Path.join([mixedCneSource, "data", "config", "modpack.ini"]), "[Common]");
			File.saveContent(Path.join([mixedCneSource, "data", "songs", "cat-o-strophe", "cat-o-strophe-metadata.json"]), "{}");
			File.saveContent(Path.join([mixedCneSource, "scripts", "characters", "masyunya.hxc"]), "function onCreate() {}");
			File.saveContent(Path.join([mixedCneSource, "shared", "images", "character.png"]), "image bytes");
			File.saveContent(Path.join([mixedCneSource, "songs", "cat-o-strophe", "Inst.ogg"]), "audio bytes");
			File.saveContent(Path.join([mixedCneSource, "_polymod_meta.json"]), '{"api_version":"0.8.4","mod_version":"1.0.0"}');
			File.saveContent(Path.join([mixedCneSource, "concept.png"]), "preserve for review");
			File.saveContent(Path.join([mixedCneSource, "mod_url.txt"]), "https://example.invalid/mod");
			File.saveContent(Path.join([mixedCneSource, ".nomedia"]), "");
			var mixedCne:Dynamic = Reflect.callMethod(RuntimeModConverter, prepare, [mixedCneSource, outputRoot]);
			if (mixedCne.blocked == true || mixedCne.converted != true || mixedCne.report.sourceFormat != "cne")
				throw 'CNE structure must take precedence over generic Polymod api_version metadata and convert automatically (blocked=${mixedCne.blocked}, converted=${mixedCne.converted}, sourceFormat=${mixedCne.report == null ? "none" : mixedCne.report.sourceFormat})';
			var normalizedCne:String = mixedCne.loadPath;
			if (!FileSystem.exists(Path.join([normalizedCne, "data", "config", "modpack.ini"]))
				|| !FileSystem.exists(Path.join([normalizedCne, "scripts", "characters", "masyunya.hxc"]))
				|| !FileSystem.exists(Path.join([normalizedCne, "shared", "images", "character.png"]))
				|| !FileSystem.exists(Path.join([normalizedCne, "songs", "cat-o-strophe", "Inst.ogg"]))
				|| !FileSystem.exists(Path.join([normalizedCne, "_dbe_preserved", "concept.png"]))
				|| !FileSystem.exists(Path.join([normalizedCne, "_dbe_preserved", "mod_url.txt"])))
				throw "CNE conversion must infer canonical roots and preserve loose package files in the managed output";
			if (File.getContent(Path.join([mixedCneSource, "data", "config", "modpack.ini"])) != "[Common]"
				|| File.getContent(Path.join([mixedCneSource, "concept.png"])) != "preserve for review")
				throw "Automatic CNE normalization must leave the original mod folder unchanged";
			var cneRetained:Array<Dynamic> = cast Reflect.field(mixedCne.report, "retained");
			var looseFileWasMapped = false;
			for (item in cneRetained) if (item.source == "concept.png" && item.target == "_dbe_preserved/concept.png") looseFileWasMapped = true;
			if (!looseFileWasMapped)
				throw "The conversion report must record inferred paths for files preserved outside canonical roots";

			var vsliceSource = Path.join([root, "vslice"]);
			FileSystem.createDirectory(Path.join([vsliceSource, "data"]));
			File.saveContent(Path.join([vsliceSource, "_polymod_meta.json"]), '{"api_version":"0.8.0","mod_version":"1.0.0"}');
			File.saveContent(Path.join([vsliceSource, "data", "introText.txt"]), "V-Slice fixture");
			var vsliceReport:Dynamic = Reflect.callMethod(RuntimeModConverter, convert, [vsliceSource, outputRoot]);
			if (vsliceReport.sourceFormat != "vslice" || !FileSystem.exists(Path.join([vsliceReport.output, "data", "introText.txt"])))
				throw "Generic Polymod api_version metadata must still identify standalone V-Slice packages";

			var inferredVSliceSource = Path.join([root, "vslice-animate-assets"]);
			var inferredVSliceAssets = Path.join([inferredVSliceSource, "shared", "images", "stages", "catastrophe-stage", "cars", "fxCarTemplate"]);
			FileSystem.createDirectory(inferredVSliceAssets);
			File.saveContent(Path.join([inferredVSliceAssets, "Animation.json"]), '{"AN":{},"MD":{"ASV":3}}');
			File.saveContent(Path.join([inferredVSliceAssets, "spritemap1.json"]), '{"frames":[]}');
			File.saveContent(Path.join([inferredVSliceAssets, "spritemap1.png"]), "png fixture");
			var inferredVSlice:Dynamic = Reflect.callMethod(RuntimeModConverter, prepare, [inferredVSliceSource, outputRoot]);
			if (inferredVSlice.blocked == true || inferredVSlice.converted != true || inferredVSlice.report.sourceFormat != "vslice")
				throw "Markerless V-Slice Animate asset packages must be inferred and normalized into the managed mod hierarchy";
			for (fileName in ["Animation.json", "spritemap1.json", "spritemap1.png"]) {
				var normalizedAssetPath = Path.join([inferredVSlice.loadPath, "shared", "images", "stages", "catastrophe-stage", "cars", "fxCarTemplate", fileName]);
				if (!FileSystem.exists(normalizedAssetPath))
					throw 'V-Slice asset missing from normalized DBE hierarchy: $fileName';
			}
			if (File.getContent(Path.join([inferredVSliceAssets, "Animation.json"])) != '{"AN":{},"MD":{"ASV":3}}')
				throw "V-Slice inference and normalization must leave the source mod unchanged";
			var normalizedCharacterXml = File.getContent(Path.join([normalizedPsych, "data", "characters", "elmeena.xml"]));
			if (normalizedCharacterXml.indexOf('sprite="elmeena"') < 0 || normalizedCharacterXml.indexOf('sprite="characters/elmeena"') >= 0
				|| normalizedCharacterXml.indexOf('<!DOCTYPE codename-engine-character>') < 0 || normalizedCharacterXml.indexOf('<anim name="idle"') < 0)
				throw "Psych character sprite paths must be normalized for DBE's character folder prefix";
			var normalizedCharacterData:Dynamic = haxe.Json.parse(File.getContent(Path.join([normalizedPsych, "data", "characters", "elmeena.json"])));
			var sourceCharacterData:Dynamic = haxe.Json.parse(File.getContent(Path.join([psychLayoutSource, "characters", "elmeena.json"])));
			if (normalizedCharacterData.image != "elmeena" || sourceCharacterData.image != "characters/elmeena")
				throw "Psych character JSON image paths must be normalized only in the managed DBE copy";
			if (File.getContent(Path.join([normalizedPsych, "_dbe_preserved", "psych_source", "characters", "elmeena.json"])) != psychCharacterJson
				|| File.getContent(Path.join([normalizedPsych, "_dbe_preserved", "psych_source", "data", "characters", "elmeena.xml"])) != psychCharacterXml)
				throw "Psych character definitions rewritten for DBE must keep an exact original copy in the managed package";
			if (File.getContent(Path.join([psychLayoutSource, "data", "characters", "elmeena.xml"])) != psychCharacterXml)
				throw "Character path normalization must leave the source mod unchanged";

			var ambiguousSource = Path.join([root, "ambiguous"]);
			FileSystem.createDirectory(Path.join([ambiguousSource, "assets", "preload"]));
			FileSystem.createDirectory(Path.join([ambiguousSource, "data", "config"]));
			File.saveContent(Path.join([ambiguousSource, "assets", "preload", "pack.json"]), "{}");
			File.saveContent(Path.join([ambiguousSource, "data", "config", "modpack.ini"]), "[mod]");
			var blocked:Dynamic = Reflect.callMethod(RuntimeModConverter, prepare, [ambiguousSource, outputRoot]);
			if (blocked.blocked != true || blocked.loadPath != null || blocked.report.incompatibilities.length == 0)
				throw "Ambiguous mod packages must be blocked with an actionable report";
			if (File.getContent(Path.join([ambiguousSource, "assets", "preload", "pack.json"])) != "{}")
				throw "A blocked conversion attempt must preserve its source package";
			var explicitlyCne:Dynamic = Reflect.callMethod(RuntimeModConverter, convert, [ambiguousSource, outputRoot, "cne"]);
			var explicitlyPsych:Dynamic = Reflect.callMethod(RuntimeModConverter, convert, [ambiguousSource, outputRoot, "psych"]);
			if (explicitlyCne.sourceFormat != "cne" || explicitlyPsych.sourceFormat != "psych" || explicitlyCne.contentHash == explicitlyPsych.contentHash || explicitlyCne.output == explicitlyPsych.output)
				throw "Content-addressed conversions must distinguish explicit source format choices for the same ambiguous package";

			var normalize = Reflect.field(RuntimeModConverter, "normalizeRelativePath");
			var unsafeRejected = false;
			try Reflect.callMethod(RuntimeModConverter, normalize, ["../outside.txt"])
			catch (_:Dynamic) unsafeRejected = true;
			if (!unsafeRejected) throw "Runtime conversion must reject traversal paths";

			var zipPath = Path.join([root, "psych-fixture.zip"]);
			writeZip(zipPath, [
				{fileName: "assets/preload/pack.json", content: '{"name":"ZIP Psych"}'},
				{fileName: "assets/preload/data/songs/test/hard.json", content: '{"song":"Test"}'}
			]);
			var zipHashBefore = Sha256.make(File.getBytes(zipPath)).toHex();
			var zipReport:Dynamic = Reflect.callMethod(RuntimeModConverter, Reflect.field(RuntimeModConverter, "convertArchive"), [zipPath, outputRoot]);
			if (zipReport.sourceFormat != "psych" || !FileSystem.exists(Path.join([zipReport.output, "data", "songs", "test", "hard.json"])))
				throw "Runtime conversion must normalize valid ZIP packages";
			if (Sha256.make(File.getBytes(zipPath)).toHex() != zipHashBefore)
				throw "ZIP conversion must leave the original archive unchanged";

			var traversalPath = Path.join([root, "traversal.zip"]);
			writeZip(traversalPath, [{fileName: "../outside.txt", content: "blocked"}]);
			var traversalRejected = false;
			try Reflect.callMethod(RuntimeModConverter, Reflect.field(RuntimeModConverter, "convertArchive"), [traversalPath, outputRoot])
			catch (_:Dynamic) traversalRejected = true;
			if (!traversalRejected || !FileSystem.exists(traversalPath))
				throw "ZIP traversal entries must be rejected while preserving the source archive";

			var collisionPath = Path.join([root, "collision.zip"]);
			writeZip(collisionPath, [
				{fileName: "assets/preload/pack.json", content: "{}"},
				{fileName: "assets/preload/PACK.json", content: "{}"}
			]);
			var collisionRejected = false;
			try Reflect.callMethod(RuntimeModConverter, Reflect.field(RuntimeModConverter, "convertArchive"), [collisionPath, outputRoot])
			catch (_:Dynamic) collisionRejected = true;
			if (!collisionRejected) throw "ZIP entries that collide on Windows must be rejected";

			var malformedPath = Path.join([root, "malformed.zip"]);
			File.saveContent(malformedPath, "not a ZIP file");
			var malformedRejected = false;
			try Reflect.callMethod(RuntimeModConverter, Reflect.field(RuntimeModConverter, "convertArchive"), [malformedPath, outputRoot])
			catch (_:Dynamic) malformedRejected = true;
			if (!malformedRejected) throw "Malformed ZIP archives must be rejected";
		} catch (error:Dynamic) {
			try deleteTree(root) catch (_:Dynamic) {}
			throw error;
		}
		deleteTree(root);
		trace("RuntimeModConverterTest: PASS");
	}

	static function writeZip(path:String, files:Array<{fileName:String, content:String}>):Void {
		var entries:List<Entry> = new List();
		for (file in files) {
			var contents = Bytes.ofString(file.content);
			entries.add({
				fileName: file.fileName,
				fileSize: contents.length,
				fileTime: Date.now(),
				compressed: false,
				dataSize: contents.length,
				data: contents,
				crc32: null,
				extraFields: null
			});
		}
		var output = File.write(path, true);
		new Writer(output).write(entries);
		output.close();
	}

	static function deleteTree(path:String):Void {
		if (!FileSystem.exists(path)) return;
		for (entry in FileSystem.readDirectory(path)) {
			var child = Path.join([path, entry]);
			if (!FileSystem.exists(child)) continue;
			if (FileSystem.isDirectory(child)) deleteTree(child);
			else FileSystem.deleteFile(child);
		}
		if (FileSystem.exists(path)) FileSystem.deleteDirectory(path);
	}
}
