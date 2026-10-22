package dbe.launcher.ui;

import dbe.launcher.App;
import dbe.launcher.LauncherInfo;
import dbe.launcher.Worker;
import dbe.launcher.update.Channel;
import dbe.launcher.update.UpdatePlanner;
import dbe.launcher.util.ProcessUtil;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;

class HomeState extends FlxState {
	var overlay:UIProgressOverlay;

	var installedText:FlxText;
	var targetText:FlxText;
	var statusMsgText:FlxText;
	var channelBadge:FlxText;

	var playBtn:UIButton;
	var updateBtn:UIButton;
	var verifyBtn:UIButton;
	var changelogBtn:UIButton;
	var versionsBtn:UIButton;
	var settingsBtn:UIButton;
	var openFolderBtn:UIButton;

	var recoveryGroup:FlxSpriteGroup;
	var launcherUpdateGroup:FlxSpriteGroup;

	static var hasCheckedOnStart:Bool = false;

	override public function create() {
		super.create();

		FlxG.mouse.visible = true;

		var bg = new FlxSprite(0, 0);
		bg.makeGraphic(960, 540, UITheme.BG_DARK);
		add(bg);

		// Top Header
		var headerBg = new FlxSprite(0, 0);
		headerBg.makeGraphic(960, 70, UITheme.BG_PANEL);
		add(headerBg);

		var headerBorder = new FlxSprite(0, 69);
		headerBorder.makeGraphic(960, 1, UITheme.BORDER);
		add(headerBorder);

		var logo = new FlxText(28, 14, 400, "DEBUG ENGINE", 24);
		logo.font = UITheme.FONT;
		logo.color = UITheme.TEXT;
		add(logo);

		var subLogo = new FlxText(28, 42, 400, "AUTO-UPDATER & LAUNCHER", 12);
		subLogo.font = UITheme.FONT;
		subLogo.color = UITheme.PRIMARY;
		add(subLogo);

		channelBadge = new FlxText(260, 22, 140, "[ STABLE ]", 14);
		channelBadge.font = UITheme.FONT;
		channelBadge.color = UITheme.SUCCESS;
		add(channelBadge);

		var verText = new FlxText(720, 26, 216, 'Launcher v${LauncherInfo.VERSION}', 14);
		verText.font = UITheme.FONT;
		verText.alignment = RIGHT;
		verText.color = UITheme.TEXT_MUTED;
		add(verText);

		// Status Card
		var cardX = 28;
		var cardY = 90;
		var cardW = 904;
		var cardH = 220;

		var cardBorder = new FlxSprite(cardX, cardY);
		cardBorder.makeGraphic(cardW, cardH, UITheme.BORDER);
		add(cardBorder);

		var cardBg = new FlxSprite(cardX + 1, cardY + 1);
		cardBg.makeGraphic(cardW - 2, cardH - 2, UITheme.BG_PANEL);
		add(cardBg);

		var cardTitle = new FlxText(cardX + 24, cardY + 20, 400, "STATUS DA INSTALACAO", 16);
		cardTitle.font = UITheme.FONT;
		cardTitle.color = UITheme.PRIMARY;
		add(cardTitle);

		installedText = new FlxText(cardX + 24, cardY + 55, 600, "Versao Instalada: Verificando...", 15);
		installedText.font = UITheme.FONT;
		installedText.color = UITheme.TEXT;
		add(installedText);

		targetText = new FlxText(cardX + 24, cardY + 85, 600, "Ultima Versao: Verificando...", 15);
		targetText.font = UITheme.FONT;
		targetText.color = UITheme.TEXT;
		add(targetText);

		statusMsgText = new FlxText(cardX + 24, cardY + 125, 856, "Pronto.", 14);
		statusMsgText.font = UITheme.FONT;
		statusMsgText.color = UITheme.TEXT_MUTED;
		add(statusMsgText);

		// Recovery Group (shown if pending journal exists)
		recoveryGroup = new FlxSpriteGroup(cardX + 24, cardY + 155);
		var recBg = new FlxSprite(0, 0);
		recBg.makeGraphic(856, 48, UITheme.WARNING_BG);
		recoveryGroup.add(recBg);

		var recWarn = new FlxText(16, 14, 500, "AVISO: Uma atualizacao anterior foi interrompida!", 14);
		recWarn.font = UITheme.FONT;
		recWarn.color = UITheme.WARNING;
		recoveryGroup.add(recWarn);

		var recResumeBtn = new UIButton(580, 8, 120, 32, "Retomar", () -> {
			overlay.show("Retomando Atualizacao");
			App.resumeInterrupted((ok) -> refreshUI());
		}, UITheme.SUCCESS, 13);
		recoveryGroup.add(recResumeBtn);

		var recRollbackBtn = new UIButton(710, 8, 130, 32, "Reverter", () -> {
			overlay.show("Revertendo Alteracoes");
			App.rollbackInterrupted((ok) -> refreshUI());
		}, UITheme.DANGER, 13);
		recoveryGroup.add(recRollbackBtn);
		add(recoveryGroup);

		// Launcher Self-Update Banner
		launcherUpdateGroup = new FlxSpriteGroup(cardX + 24, cardY + 155);
		var lBg = new FlxSprite(0, 0);
		lBg.makeGraphic(856, 48, 0xFF1E2838);
		launcherUpdateGroup.add(lBg);

		var lText = new FlxText(16, 14, 600, "Nova versao do Launcher disponivel!", 14);
		lText.font = UITheme.FONT;
		lText.color = UITheme.PRIMARY_HOVER;
		launcherUpdateGroup.add(lText);

		var lUpdateBtn = new UIButton(690, 8, 150, 32, "Atualizar Launcher", () -> {
			if (App.lastCheck != null && App.lastCheck.decision.target != null) {
				overlay.show("Atualizando Launcher");
				App.selfUpdate(App.lastCheck.decision.target, (ok) -> refreshUI());
			}
		}, UITheme.PRIMARY, 13);
		launcherUpdateGroup.add(lUpdateBtn);
		add(launcherUpdateGroup);

		// Action Buttons (Bottom)
		var bY = 330;

		playBtn = new UIButton(cardX, bY, 440, 54, "JOGAR", () -> {
			App.play();
		}, UITheme.SUCCESS, 22);
		add(playBtn);

		updateBtn = new UIButton(cardX + 464, bY, 440, 54, "ATUALIZAR", () -> {
			overlay.show("Atualizando DBE");
			App.updateTo(null, false, (ok) -> refreshUI());
		}, UITheme.PRIMARY, 22);
		add(updateBtn);

		// Second button row
		var sY = 400;
		var w = 172;
		var gap = 11;

		verifyBtn = new UIButton(cardX, sY, w, 40, "Verificar Integridade", () -> {
			overlay.show("Verificando Integridade");
			App.verify((ok) -> refreshUI());
		}, UITheme.BG_CARD, 12);
		add(verifyBtn);

		changelogBtn = new UIButton(cardX + (w + gap), sY, w, 40, "Changelog", () -> {
			var notes = "";
			if (App.lastCheck != null && App.lastCheck.decision.between.length > 0) {
				for (r in App.lastCheck.decision.between) {
					notes += '=== RELEASE ${r.tag} ===\n' + r.body + "\n\n";
				}
			} else if (App.lastCheck != null && App.lastCheck.decision.target != null) {
				notes = App.lastCheck.decision.target.body;
			}
			openSubState(new ChangelogSubState("NOTAS DE ATUALIZACAO", notes));
		}, UITheme.BG_CARD, 13);
		add(changelogBtn);

		versionsBtn = new UIButton(cardX + (w + gap) * 2, sY, w, 40, "Versoes & Backups", () -> {
			FlxG.switchState(() -> new VersionsState());
		}, UITheme.BG_CARD, 13);
		add(versionsBtn);

		settingsBtn = new UIButton(cardX + (w + gap) * 3, sY, w, 40, "Configuracoes", () -> {
			FlxG.switchState(() -> new SettingsState());
		}, UITheme.BG_CARD, 13);
		add(settingsBtn);

		openFolderBtn = new UIButton(cardX + (w + gap) * 4, sY, w, 40, "Abrir Pasta", () -> {
			ProcessUtil.open(App.engineRoot());
		}, UITheme.BG_CARD, 13);
		add(openFolderBtn);

		// Refresh button in top card
		var checkBtn = new UIButton(cardX + cardW - 130, cardY + 16, 110, 30, "Buscar Updates", () -> {
			overlay.show("Buscando Atualizacoes");
			App.refresh((ok) -> refreshUI());
		}, UITheme.BG_CARD, 12);
		add(checkBtn);

		overlay = new UIProgressOverlay();
		add(overlay);

		refreshUI();

		if (!hasCheckedOnStart && App.settings.autoCheck) {
			hasCheckedOnStart = true;
			overlay.show("Verificando Atualizacoes");
			App.refresh((ok) -> refreshUI());
		}
	}

	function refreshUI() {
		var ch = App.settings.channel;
		channelBadge.text = '[ ${(ch : String).toUpperCase()} ]';
		channelBadge.color = ch == Channel.Nightly ? UITheme.PURPLE : (ch == Channel.Beta ? UITheme.WARNING : UITheme.SUCCESS);

		var inst = App.installed();
		if (inst != null) {
			installedText.text = 'Versao Instalada: ${inst.tag} (Epoch de Assets: ${inst.assetsEpoch})';
		} else {
			installedText.text = "Versao Instalada: Nenhuma instalacao detectada.";
		}

		var check = App.lastCheck;
		if (check != null && check.decision.target != null) {
			var tgt = check.decision.target;
			var epochInfo = check.manifest != null ? ' (Epoch: ${check.manifest.assetsEpoch})' : "";
			targetText.text = 'Ultima Versao: ${tgt.tag}$epochInfo';

			if (check.decision.isNewer) {
				updateBtn.setText(inst == null ? "INSTALAR ENGINE" : "ATUALIZAR AGORA");
				updateBtn.enabled = true;
				statusMsgText.text = 'Uma nova versao esta disponivel (${tgt.tag}). Clique em Atualizar!';
				statusMsgText.color = UITheme.SUCCESS;
			} else {
				updateBtn.setText("ATUALIZADO");
				updateBtn.enabled = false;
				statusMsgText.text = "Sua engine esta atualizada!";
				statusMsgText.color = UITheme.TEXT_MUTED;
			}
		} else {
			targetText.text = "Ultima Versao: Verificacao pendente.";
			updateBtn.setText("ATUALIZAR");
			updateBtn.enabled = false;
			statusMsgText.text = "Clique em Buscar Updates para verificar novas versoes.";
			statusMsgText.color = UITheme.TEXT_MUTED;
		}

		playBtn.enabled = App.canPlay();
		if (!playBtn.enabled) {
			playBtn.setText(inst == null ? "NAO INSTALADA" : "EXECUTAVEL NAO ACHADO");
		} else {
			playBtn.setText("JOGAR DBE");
		}

		// Check interrupted update
		var pending = App.session.pendingJournal();
		if (pending != null) {
			recoveryGroup.visible = true;
			launcherUpdateGroup.visible = false;
			playBtn.enabled = false;
			updateBtn.enabled = false;
		} else {
			recoveryGroup.visible = false;
			// Check launcher self update
			if (check != null && check.manifest != null && check.manifest.launcherVersion != ""
				&& UpdatePlanner.launcherTooOld(LauncherInfo.VERSION, check.manifest)) {
				launcherUpdateGroup.visible = true;
			} else {
				launcherUpdateGroup.visible = false;
			}
		}
	}

	override public function update(elapsed:Float) {
		Worker.pump();
		super.update(elapsed);
	}
}
