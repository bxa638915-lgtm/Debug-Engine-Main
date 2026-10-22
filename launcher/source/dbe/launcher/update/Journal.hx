package dbe.launcher.update;

import dbe.launcher.util.PathUtil;
import haxe.Json;
import sys.FileSystem;
import sys.io.File;

enum abstract OpKind(String) from String to String {
	var Write = "write";
	var Delete = "delete";
}

typedef JournalOp = {
	var kind:OpKind;
	var path:String;
	/** Whether the target existed *before* the update started (decides rollback action). */
	var existed:Bool;
	@:optional var exec:Bool;
	@:optional var sha256:String;
}

/**
 * Write-ahead journal for one update transaction.
 *
 * Lifecycle:
 *   1. created and saved to `.dbe/journal.json` BEFORE any install file is touched
 *   2. ops are applied (idempotently, so a crash can be resumed)
 *   3. on commit it is moved to `<backupDir>/backup.json` (enables later restore)
 *
 * If `.dbe/journal.json` exists on startup, the previous update was interrupted.
 */
class Journal {
	public var fromTag:Null<String>;
	public var fromEpoch:Int = 0;
	public var toTag:String;
	public var toEpoch:Int;
	public var channel:String;
	public var platform:String;
	/** Absolute folder with downloaded+verified files (`<stagingDir>/<path>`). */
	public var stagingDir:String;
	/** Absolute folder receiving originals (`<backupDir>/files/<path>`). */
	public var backupDir:String;
	public var createdAt:String;
	public var ops:Array<JournalOp> = [];

	public function new() {
		createdAt = Date.now().toString();
	}

	public inline function stagedPath(op:JournalOp):String
		return PathUtil.join(stagingDir, op.path);

	public inline function backupPath(op:JournalOp):String
		return PathUtil.join(PathUtil.join(backupDir, "files"), op.path);

	public function toJson():String
		return Json.stringify({
			fromTag: fromTag,
			fromEpoch: fromEpoch,
			toTag: toTag,
			toEpoch: toEpoch,
			channel: channel,
			platform: platform,
			stagingDir: stagingDir,
			backupDir: backupDir,
			createdAt: createdAt,
			ops: ops
		}, null, "\t");

	public function save(file:String) {
		PathUtil.ensureDirFor(file);
		var tmp = file + ".tmp";
		File.saveContent(tmp, toJson());
		if (FileSystem.exists(file)) FileSystem.deleteFile(file);
		FileSystem.rename(tmp, file);
	}

	public static function load(file:String):Null<Journal> {
		if (!FileSystem.exists(file)) return null;
		var d:Dynamic = Json.parse(File.getContent(file));
		var j = new Journal();
		j.fromTag = d.fromTag;
		j.fromEpoch = d.fromEpoch == null ? 0 : Std.int(d.fromEpoch);
		j.toTag = d.toTag;
		j.toEpoch = Std.int(d.toEpoch);
		j.channel = d.channel;
		j.platform = d.platform;
		j.stagingDir = d.stagingDir;
		j.backupDir = d.backupDir;
		j.createdAt = d.createdAt;
		var raw:Array<Dynamic> = d.ops;
		for (o in raw) {
			if (!PathUtil.isSafeRelative(o.path)) throw 'Unsafe path in journal: ${o.path}';
			j.ops.push({
				kind: (o.kind : String),
				path: o.path,
				existed: o.existed == true,
				exec: o.exec == true,
				sha256: o.sha256
			});
		}
		return j;
	}
}
