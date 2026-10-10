package funkin.editors;

import flixel.FlxState;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import funkin.backend.assets.Paths;

/** Displays why an automatically detected mod package was kept out of the runtime. */
class ModConversionReportState extends MusicBeatState {
	public var returnState:Class<FlxState>;
	public var reports:Array<Dynamic>;

	public function new(returnState:Class<FlxState>, reports:Array<Dynamic>) {
		super();
		this.returnState = returnState;
		this.reports = reports == null ? [] : reports.copy();
	}

	public override function create():Void {
		super.create();
		add(new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0xFF11131A));

		var title = new FlxText(32, 24, FlxG.width - 64, "Mod conversion needs attention", 30);
		title.setFormat(Paths.font("vcr.ttf"), 30, FlxColor.WHITE, CENTER);
		add(title);

		var lines:Array<String> = [];
		for (index in 0...reports.length) {
			var report = reports[index];
			lines.push('Package ${index + 1}: ${Reflect.field(report, "sourceFormat")}');
			lines.push('Source: ${Reflect.field(report, "source")}');
			var issues:Array<String> = cast Reflect.field(report, "incompatibilities");
			if (issues != null) for (issue in issues) lines.push('Action: $issue');
			var reportPath:Dynamic = Reflect.field(report, "reportPath");
			if (reportPath != null) lines.push('Full report: $reportPath');
			if (index + 1 < reports.length) lines.push("");
		}

		var details = new FlxText(36, 90, FlxG.width - 72, lines.join("\n"), 18);
		details.setFormat(Paths.font("vcr.ttf"), 18, FlxColor.WHITE, LEFT);
		details.wordWrap = true;
		add(details);

		var hint = new FlxText(32, FlxG.height - 52, FlxG.width - 64, "Press Enter or Esc to continue without the blocked package", 16);
		hint.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.GRAY, CENTER);
		add(hint);
	}

	public override function update(elapsed:Float):Void {
		super.update(elapsed);
		if (controls.ACCEPT || controls.BACK || FlxG.keys.justPressed.ENTER || FlxG.keys.justPressed.ESCAPE)
			FlxG.switchState(cast Type.createInstance(returnState, []));
	}
}
