import dbe.compatibility.mods.RuntimeModConverter;
import haxe.io.Path;

class RealModProbe {
	static function main():Void {
		var modsRoot = "C:/Users/esque/Downloads/A_1/A/Vs Impostor alternated Scripts Converts/Debug Engine-Main/export/release/windows/bin/mods";
		var managedRoot = RuntimeModConverter.defaultManagedRoot();
		var samples = [
			{label: "v-slice", name: "CAT-O-STROPHE! ONESHOT MOD (V-Slice Mod)"},
			{label: "psych", name: "Lovers Angel Number (Psych Mod)"},
			{label: "cne", name: "CNE MOD"}
		];
		for (sample in samples) {
			var source = Path.join([modsRoot, sample.name]);
			var prepared:Dynamic = RuntimeModConverter.prepare(source, managedRoot);
			Sys.println(sample.label + ": blocked=" + prepared.blocked + ", converted=" + prepared.converted + ", loadPath=" + prepared.loadPath);
			if (prepared.report != null) {
				var report:Dynamic = prepared.report;
				Sys.println("  sourceFormat=" + report.sourceFormat + ", files=" + report.fileCount + ", converted=" + report.converted.length + ", retained=" + report.retained.length + ", unsupported=" + report.unsupported.length);
				for (item in (cast report.converted:Array<Dynamic>)) Sys.println("  MOVE " + item.source + " => " + item.target);
				for (item in (cast report.retained:Array<Dynamic>)) if (item.source.indexOf("/") < 0) Sys.println("  KEEP " + item.source + " => " + item.target);
				for (item in (cast report.unsupported:Array<Dynamic>)) Sys.println("  UNSUPPORTED " + item.source + " => " + item.reason);
				if (report.incompatibilities != null) for (issue in (cast report.incompatibilities:Array<String>)) Sys.println("  ISSUE " + issue);
			}
		}
	}
}
