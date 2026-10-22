package dbe.launcher.ui;

import dbe.launcher.App;
import dbe.launcher.Worker;
import dbe.launcher.update.BackupManager;
import dbe.launcher.update.Channel;
import dbe.launcher.update.UpdatePlanner;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;

class VersionsState extends FlxState {
	var releasesGroup:FlxSpriteGroup;
	var backupsGroup:FlxSpriteGroup;

	var releasesScroll:Float = 0;
	var backupsScroll:Float = 0;

	var overlay:UIProgressOverlay;
	var activeTab:Int = 0; // 0 = Releases, 1 = Backups

	var tabReleasesBtn:UIButton;
	var tabBackupsBtn:UIButton;

	override public function create() {
		super.create();

		var bg = new FlxSprite(0, 0);
		bg.makeGraphic(960, 540, UITheme.BG_DARK);
		add(bg);

		// Header Bar
		var headerBg = new FlxSprite(0, 0);
		headerBg.makeGraphic(960, 60, UITheme.BG_PANEL);
		add(headerBg);

		var headerBorder = new FlxSprite(0, 59);
		headerBorder.makeGraphic(960, 1, UITheme.BORDER);
		add(headerBorder);

		var title = new FlxText(24, 16, 400, "VERSOES & BACKUPS", 22);
		title.font = UITheme.FONT;
		title.color = UITheme.TEXT;
		add(title);

		var backBtn = new UIButton(820, 14, 116, 32, "<- Voltar", () -> {
			FlxG.switchState(() -> new HomeState());
		}, UITheme.BG_CARD, 14);
		add(backBtn);

		// Tabs
		tabReleasesBtn = new UIButton(24, 76, 200, 36, "Releases do GitHub", () -> selectTab(0), UITheme.PRIMARY, 14);
		add(tabReleasesBtn);

		tabBackupsBtn = new UIButton(234, 76, 200, 36, "Backups Locais", () -> selectTab(1), UITheme.BG_CARD, 14);
		add(tabBackupsBtn);

		releasesGroup = new FlxSpriteGroup(24, 126);
		add(releasesGroup);

		backupsGroup = new FlxSpriteGroup(24, 126);
		backupsGroup.visible = false;
		add(backupsGroup);

		overlay = new UIProgressOverlay();
		add(overlay);

		populateReleases();
		populateBackups();
		selectTab(0);
	}

	function selectTab(tab:Int) {
		activeTab = tab;
		if (tab == 0) {
			tabReleasesBtn.bg.color = UITheme.PRIMARY;
			tabBackupsBtn.bg.color = UITheme.BG_CARD;
			releasesGroup.visible = true;
			backupsGroup.visible = false;
		} else {
			tabReleasesBtn.bg.color = UITheme.BG_CARD;
			tabBackupsBtn.bg.color = UITheme.PRIMARY;
			releasesGroup.visible = false;
			backupsGroup.visible = true;
		}
	}

	function populateReleases() {
		releasesGroup.clear();

		if (App.releases.length == 0) {
			var empty = new FlxText(0, 40, 912, "Nenhuma release encontrada ou sem conexao.", 16);
			empty.font = UITheme.FONT;
			empty.alignment = CENTER;
			empty.color = UITheme.TEXT_MUTED;
			releasesGroup.add(empty);
			return;
		}

		var y:Float = 0;
		for (r in App.releases) {
			var cardH = 68;
			var card = new FlxSprite(0, y);
			card.makeGraphic(912, cardH, UITheme.BG_PANEL);
			releasesGroup.add(card);

			var border = new FlxSprite(0, y + cardH - 1);
			border.makeGraphic(912, 1, UITheme.BORDER);
			releasesGroup.add(border);

			var tag = new FlxText(16, y + 12, 300, r.tag, 18);
			tag.font = UITheme.FONT;
			tag.color = UITheme.TEXT;
			releasesGroup.add(tag);

			var ch = UpdatePlanner.channelOf(r);
			var chStr = ch == null ? "STABLE" : (ch : String).toUpperCase();
			var badge = new FlxText(16, y + 38, 200, chStr + (r.prerelease ? " (PRERELEASE)" : ""), 12);
			badge.font = UITheme.FONT;
			badge.color = ch == Channel.Nightly ? UITheme.PURPLE : (ch == Channel.Beta ? UITheme.WARNING : UITheme.SUCCESS);
			releasesGroup.add(badge);

			var date = new FlxText(320, y + 24, 250, r.publishedAt.substr(0, 10), 14);
			date.font = UITheme.FONT;
			date.color = UITheme.TEXT_MUTED;
			releasesGroup.add(date);

			var changelogBtn = new UIButton(640, Math.floor(y + 16), 110, 36, "Changelog", () -> {
				openSubState(new ChangelogSubState("NOTAS: " + r.tag, r.body));
			}, UITheme.BG_CARD, 13);
			releasesGroup.add(changelogBtn);

			var installBtn = new UIButton(760, Math.floor(y + 16), 136, 36, "Instalar Esta", () -> {
				overlay.show("Instalando " + r.tag);
				App.updateTo(r, false, (ok) -> {
					if (ok) populateBackups();
				});
			}, UITheme.PRIMARY, 13);
			releasesGroup.add(installBtn);

			y += cardH + 8;
		}
	}

	function populateBackups() {
		backupsGroup.clear();

		var backups = BackupManager.list(App.session.layout);
		if (backups.length == 0) {
			var empty = new FlxText(0, 40, 912, "Nenhum backup encontrado em .dbe/backups/.", 16);
			empty.font = UITheme.FONT;
			empty.alignment = CENTER;
			empty.color = UITheme.TEXT_MUTED;
			backupsGroup.add(empty);
			return;
		}

		var y:Float = 0;
		for (b in backups) {
			var cardH = 68;
			var card = new FlxSprite(0, y);
			card.makeGraphic(912, cardH, UITheme.BG_PANEL);
			backupsGroup.add(card);

			var border = new FlxSprite(0, y + cardH - 1);
			border.makeGraphic(912, 1, UITheme.BORDER);
			backupsGroup.add(border);

			var name = new FlxText(16, y + 12, 500, b.name, 16);
			name.font = UITheme.FONT;
			name.color = UITheme.TEXT;
			backupsGroup.add(name);

			var desc = new FlxText(16, y + 38, 500, 'De: ${b.journal.fromTag == null ? "original" : b.journal.fromTag} -> Para: ${b.journal.toTag} (${b.journal.ops.length} arquivos)', 12);
			desc.font = UITheme.FONT;
			desc.color = UITheme.TEXT_MUTED;
			backupsGroup.add(desc);

			var restoreBtn = new UIButton(740, Math.floor(y + 16), 156, 36, "Restaurar Backup", () -> {
				overlay.show("Restaurando Backup");
				App.restoreBackup(b, (ok) -> {
					if (ok) populateBackups();
				});
			}, UITheme.WARNING, 13);
			backupsGroup.add(restoreBtn);

			y += cardH + 8;
		}
	}

	override public function update(elapsed:Float) {
		Worker.pump();
		super.update(elapsed);

		if (FlxG.keys.justPressed.ESCAPE && !overlay.visible) {
			FlxG.switchState(() -> new HomeState());
			return;
		}

		// Mouse wheel scrolling
		if (FlxG.mouse.wheel != 0 && !overlay.visible) {
			var grp = activeTab == 0 ? releasesGroup : backupsGroup;
			var maxH = Math.max(0, grp.height - 380);
			if (activeTab == 0) {
				releasesScroll -= FlxG.mouse.wheel * 40;
				releasesScroll = Math.max(0, Math.min(maxH, releasesScroll));
				grp.y = 126 - releasesScroll;
			} else {
				backupsScroll -= FlxG.mouse.wheel * 40;
				backupsScroll = Math.max(0, Math.min(maxH, backupsScroll));
				grp.y = 126 - backupsScroll;
			}
		}
	}
}
