package dbe.launcher.util;

import haxe.crypto.Sha256;
import haxe.io.Bytes;
import sys.io.File;

/** SHA-256 helpers (lower-case hex). */
class Hasher {
	public static inline function sha256Bytes(b:Bytes):String
		return Sha256.make(b).toHex().toLowerCase();

	public static function sha256File(path:String):String
		return sha256Bytes(File.getBytes(path));

	static final HEX64 = ~/^[0-9a-f]{64}$/;

	public static function isValidSha256(s:String):Bool
		return s != null && HEX64.match(s.toLowerCase());
}
