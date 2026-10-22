package dbe.launcher.ui;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxSubState;
import flixel.text.FlxText;

class ChangelogSubState extends FlxSubState {
	var notesText:FlxText;
	var scrollY:Float = 0;
	var maxScroll:Float = 0;

	public function new(title:String, changelog:String) {
		super(0xCC000000);

		var pw = 760;
		var ph = 460;
		var px = (960 - pw) / 2;
		var py = (540 - ph) / 2;

		var border = new FlxSprite(px, py);
		border.makeGraphic(pw, ph, UITheme.BORDER_LIGHT);
		add(border);

		var panel = new FlxSprite(px + 2, py + 2);
		panel.makeGraphic(pw - 4, ph - 4, UITheme.BG_PANEL);
		add(panel);

		var header = new FlxText(px + 20, py + 16, pw - 40, title, 18);
		header.font = UITheme.FONT;
		header.color = UITheme.PRIMARY;
		add(header);

		var closeBtn = new UIButton(Math.floor(px + pw - 120), Math.floor(py + 12), 100, 32, "Fechar", () -> {
			close();
		}, UITheme.BG_CARD, 14);
		add(closeBtn);

		var line = new FlxSprite(px + 10, py + 52);
		line.makeGraphic(pw - 20, 1, UITheme.BORDER);
		add(line);

		var cleaned = cleanupMarkdown(changelog);
		notesText = new FlxText(px + 20, py + 65, pw - 40, cleaned, 14);
		notesText.font = UITheme.FONT;
		notesText.color = UITheme.TEXT;
		add(notesText);

		maxScroll = Math.max(0, notesText.height - (ph - 100));
	}

	override public function update(elapsed:Float) {
		super.update(elapsed);

		if (FlxG.keys.justPressed.ESCAPE) {
			close();
			return;
		}

		if (FlxG.mouse.wheel != 0 && maxScroll > 0) {
			scrollY -= FlxG.mouse.wheel * 30;
			scrollY = Math.max(0, Math.min(maxScroll, scrollY));
			notesText.y = (540 - 460) / 2 + 65 - scrollY;
		}
	}

	static function cleanupMarkdown(md:String):String {
		if (md == null || md == "") return "Nenhum changelog disponivel para esta versao.";
		var s = StringTools.replace(md, "\r\n", "\n");
		// Strip raw HTML if any
		s = ~/<[^>]+>/g.replace(s, "");
		return StringTools.trim(s);
	}
}
