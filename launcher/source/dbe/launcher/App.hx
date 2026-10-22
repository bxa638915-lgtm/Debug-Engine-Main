package dbe.launcher;

import dbe.launcher.net.HttpClient;
import dbe.launcher.net.HttpClient.CancelledException;
import dbe.launcher.update.*;
import dbe.launcher.update.UpdatePlanner;
import dbe.launcher.update.UpdateSession;
import dbe.launcher.util.PathUtil;
import dbe.launcher.util.Platform;
import dbe.launcher.util.ProcessUtil;
import sys.FileSystem;
import sys.io.File;
import sys.thread.Mutex;

typedef ProgressSnapshot = {
	var phase:Phase;
	var done:Float;
	var total:Float;
	var detail:String;
}

/**
 * Application controller shared by all screens. Owns settings, the update
 * session and the latest check result. Long operations go through {@link Worker}.
 */
class App {
	public static var settings:Settings;
	public static var session:UpdateSession;
	public static var releases:Array<ReleaseInfo> = [];
	public static var lastCheck:Null<CheckResult>;
	public static var lastError:String = "";
	public static var status:String = "";

	static var progressMutex = new Mutex();
	static var progress:ProgressSnapshot = {phase: Idle, done: 0, total: 0, detail: ""};
	static var logLines:Array<String> = [];

	public static function init() {
		settings = Settings.load();
		HttpClient.userAgent = 'DBE-Launcher/${LauncherInfo.VERSION}';
		SelfUpdater.cleanup(Settings.launcherDir());
		rebuildSession();
	}

	public static function rebuildSession() {
		var root = settings.resolveEngineRoot();
		session = new UpdateSession({
			root: root,
			owner: settings.owner,
			repo: settings.repo,
			channel: settings.channel,
			platform: Platform.id(),
			launcherVersion: LauncherInfo.VERSION,
			protectedRules: settings.protectedExtra,
			keepBackups: settings.keepBackups,
			keep: [LauncherInfo.INSTALL_DIR + "/"]
		});
		session.onProgress = (ph, d, t, s) -> {
			progressMutex.acquire();
			progress = {phase: ph, done: d, total: t, detail: s};
			progressMutex.release();
		};
		session.log = log;
	}

	public static function getProgress():ProgressSnapshot {
		progressMutex.acquire();
		var p = progress;
		progressMutex.release();
		return p;
	}

	public static function log(s:String) {
		var line = '[${DateTools.format(Date.now(), "%H:%M:%S")}] $s';
		Worker.post(() -> {
			logLines.push(line);
			if (logLines.length > 200) logLines.shift();
		});
		try {
			var f = session.layout.logFile;
			PathUtil.ensureDirFor(f);
			var o = File.append(f, false);
			o.writeString(line + "\n");
			o.close();
		} catch (_:Dynamic) {}
	}

	public static function recentLog(n:Int):Array<String>
		return logLines.slice(-n);

	public static function installed():Null<InstalledState>
		return session.installed();

	public static function engineRoot():String
		return session.config.root;

	// ------------------------------------------------------------------ jobs

	static function start(name:String, job:() -> Void, ?done:Bool->Void) {
		session.cancelRequested = false;
		lastError = "";
		status = name;
		log(name);
		Worker.run(job, (err) -> {
			if (err != null) {
				lastError = Std.isOfType(err, CancelledException) || Std.isOfType(err, DiffEngine.DiffCancelled) ? "Cancelled" : Worker.describe(err);
				log('ERROR: $lastError');
				status = "";
			} else status = "";
			if (done != null) done(err == null);
		});
	}

	public static function cancel()
		session.cancelRequested = true;

	public static function refresh(?done:Bool->Void)
		start("Checking for updates...", () -> {
			releases = session.fetchReleases();
			lastCheck = session.check(releases);
		}, done);

	/** Updates/installs to `release` (null = latest for the channel). */
	public static function updateTo(?release:ReleaseInfo, fullVerify = false, ?done:Bool->Void) {
		start("Updating...", () -> {
			var r = release != null ? release : (lastCheck == null ? null : lastCheck.decision.target);
			if (r == null) throw "No release available for this channel/platform";
			session.updateTo(r, fullVerify);
			lastCheck = session.check(releases);
		}, done);
	}

	/** Re-hashes everything against the installed tag's manifest and repairs differences. */
	public static function verify(?done:Bool->Void) {
		start("Verifying integrity...", () -> {
			var inst = session.installed();
			if (inst == null) throw "Nothing installed yet";
			if (releases.length == 0) releases = session.fetchReleases();
			var r = Lambda.find(releases, (x) -> x.tag == inst.tag);
			if (r == null) throw 'Release ${inst.tag} no longer exists on GitHub';
			session.updateTo(r, true);
		}, done);
	}

	public static function resumeInterrupted(?done:Bool->Void)
		start("Resuming interrupted update...", () -> session.resumeInterrupted(), done);

	public static function rollbackInterrupted(?done:Bool->Void)
		start("Rolling back interrupted update...", () -> session.rollbackInterrupted(), done);

	public static function restoreBackup(b:BackupManager.BackupEntry, ?done:Bool->Void)
		start("Restoring backup...", () -> session.restoreBackup(b), done);

	/** Downloads the launcher package from `release`, swaps files and restarts. */
	public static function selfUpdate(release:ReleaseInfo, ?done:Bool->Void)
		start("Updating launcher...", () -> {
			var a = UpdatePlanner.findAsset(release, UpdatePlanner.launcherAssetName(Platform.id()));
			if (a == null) throw "This release has no launcher package";
			var zip = PathUtil.join(session.layout.downloadsDir, a.name);
			session.downloadFile(a.url, zip, (b) -> session.onProgress(Downloading, b, a.size, a.name));
			SelfUpdater.apply(zip, Settings.launcherDir(), haxe.io.Path.withoutDirectory(Sys.programPath()));
			FileSystem.deleteFile(zip);
		}, (ok) -> {
			if (ok) {
				ProcessUtil.relaunchSelf();
				Sys.exit(0);
			}
			if (done != null) done(ok);
		});

	public static function executable():String {
		if (lastCheck != null && lastCheck.manifest != null && lastCheck.manifest.executable != "") {
			// Prefer the executable recorded for the installed tag if it exists on disk.
			var exe = lastCheck.manifest.executable;
			if (FileSystem.exists(PathUtil.join(engineRoot(), exe))) return exe;
		}
		for (c in ["DBE.exe", "CodenameEngine.exe", "DBE", "CodenameEngine", "DBE.app", "CodenameEngine.app"])
			if (FileSystem.exists(PathUtil.join(engineRoot(), c))) return c;
		return null;
	}

	public static function canPlay():Bool
		return executable() != null && session.pendingJournal() == null;

	public static function play() {
		var exe = executable();
		if (exe == null) {
			lastError = "Game executable not found";
			return;
		}
		log('Launching $exe');
		ProcessUtil.launch(engineRoot(), exe);
		if (settings.closeOnPlay) Sys.exit(0);
	}
}
