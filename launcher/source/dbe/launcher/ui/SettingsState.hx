package dbe.launcher.ui;

import dbe.launcher.App;
import dbe.launcher.Worker;
import dbe.launcher.update.Channel;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.text.FlxText;

class SettingsState extends FlxState {
	var currentChannel:Channel;
	var autoCheck:Bool;
	var closeOnPlay:Bool;
	var backupsCount:Int;

	var btnStable:UIButton;
	var btnBeta:UIButton;
	var btnNightly:UIButton;

	var btnAutoCheck:UIButton;
	var btnCloseOnPlay:UIButton;
	var textBackups:FlxText;

	override public function create() {
		super.create();

		currentChannel = App.settings.channel;
		autoCheck = App.settings.autoCheck;
		closeOnPlay = App.settings.closeOnPlay;
		backupsCount = App.settings.keepBackups;

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

		var title = new FlxText(24, 16, 400, "CONFIGURACOES", 22);
		title.font = UITheme.FONT;
		title.color = UITheme.TEXT;
		add(title);

		var backBtn = new UIButton(820, 14, 116, 32, "<- Voltar", () -> {
			saveAndExit();
		}, UITheme.BG_CARD, 14);
		add(backBtn);

		var startY = 85;

		// 1. Channel
		var lblCh = new FlxText(40, startY, 300, "Canal de Atualizacao:", 16);
		lblCh.font = UITheme.FONT;
		lblCh.color = UITheme.TEXT;
		add(lblCh);

		btnStable = new UIButton(40, startY + 30, 130, 36, "Stable", () -> selectChannel(Stable), UITheme.BG_CARD, 14);
		add(btnStable);
		btnBeta = new UIButton(180, startY + 30, 130, 36, "Beta", () -> selectChannel(Beta), UITheme.BG_CARD, 14);
		add(btnBeta);
		btnNightly = new UIButton(320, startY + 30, 130, 36, "Nightly", () -> selectChannel(Nightly), UITheme.BG_CARD, 14);
		add(btnNightly);
		updateChannelButtons();

		// 2. Auto-Check
		startY += 90;
		var lblAuto = new FlxText(40, startY, 400, "Verificar updates ao iniciar o Launcher:", 16);
		lblAuto.font = UITheme.FONT;
		lblAuto.color = UITheme.TEXT;
		add(lblAuto);

		btnAutoCheck = new UIButton(40, startY + 30, 160, 36, autoCheck ? "Ativado [x]" : "Desativado [ ]", () -> {
			autoCheck = !autoCheck;
			btnAutoCheck.setText(autoCheck ? "Ativado [x]" : "Desativado [ ]");
			btnAutoCheck.bg.color = autoCheck ? UITheme.SUCCESS : UITheme.BG_CARD;
		}, autoCheck ? UITheme.SUCCESS : UITheme.BG_CARD, 14);
		add(btnAutoCheck);

		// 3. Close on Play
		startY += 90;
		var lblClose = new FlxText(40, startY, 400, "Fechar Launcher apos clicar em Jogar:", 16);
		lblClose.font = UITheme.FONT;
		lblClose.color = UITheme.TEXT;
		add(lblClose);

		btnCloseOnPlay = new UIButton(40, startY + 30, 160, 36, closeOnPlay ? "Ativado [x]" : "Desativado [ ]", () -> {
			closeOnPlay = !closeOnPlay;
			btnCloseOnPlay.setText(closeOnPlay ? "Ativado [x]" : "Desativado [ ]");
			btnCloseOnPlay.bg.color = closeOnPlay ? UITheme.SUCCESS : UITheme.BG_CARD;
		}, closeOnPlay ? UITheme.SUCCESS : UITheme.BG_CARD, 14);
		add(btnCloseOnPlay);

		// 4. Backups count
		startY += 90;
		var lblBackups = new FlxText(40, startY, 400, "Quantidade de Backups locais retidos:", 16);
		lblBackups.font = UITheme.FONT;
		lblBackups.color = UITheme.TEXT;
		add(lblBackups);

		var minusBtn = new UIButton(40, startY + 30, 44, 36, "-", () -> {
			if (backupsCount > 1) {
				backupsCount--;
				textBackups.text = Std.string(backupsCount);
			}
		}, UITheme.BG_CARD, 18);
		add(minusBtn);

		textBackups = new FlxText(94, startY + 36, 50, Std.string(backupsCount), 18);
		textBackups.font = UITheme.FONT;
		textBackups.alignment = CENTER;
		textBackups.color = UITheme.PRIMARY;
		add(textBackups);

		var plusBtn = new UIButton(154, startY + 30, 44, 36, "+", () -> {
			if (backupsCount < 10) {
				backupsCount++;
				textBackups.text = Std.string(backupsCount);
			}
		}, UITheme.BG_CARD, 18);
		add(plusBtn);

		// Bottom Save Button
		var saveBtn = new UIButton(40, 470, 220, 42, "Salvar Alteracoes", () -> {
			saveAndExit();
		}, UITheme.PRIMARY, 16);
		add(saveBtn);
	}

	function selectChannel(ch:Channel) {
		currentChannel = ch;
		updateChannelButtons();
	}

	function updateChannelButtons() {
		btnStable.bg.color = currentChannel == Stable ? UITheme.SUCCESS : UITheme.BG_CARD;
		btnBeta.bg.color = currentChannel == Beta ? UITheme.WARNING : UITheme.BG_CARD;
		btnNightly.bg.color = currentChannel == Nightly ? UITheme.PURPLE : UITheme.BG_CARD;
	}

	function saveAndExit() {
		App.settings.channel = currentChannel;
		App.settings.autoCheck = autoCheck;
		App.settings.closeOnPlay = closeOnPlay;
		App.settings.keepBackups = backupsCount;
		App.settings.save();

		App.rebuildSession();
		FlxG.switchState(() -> new HomeState());
	}

	override public function update(elapsed:Float) {
		Worker.pump();
		super.update(elapsed);

		if (FlxG.keys.justPressed.ESCAPE) {
			saveAndExit();
		}
	}
}
