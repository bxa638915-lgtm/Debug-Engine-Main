package dbe.launcher.net;

import haxe.io.Bytes;
import haxe.io.BytesInput;

typedef ZipEntry = {
	var name:String;
	var method:Int;
	var crc32:Int;
	var compressedSize:Int;
	var size:Int;
	var localOffset:Int;
	/** Offset where the next entry (or the central directory) begins. */
	var dataEnd:Int;
}

class ZipFormatError extends haxe.Exception {}

/**
 * Parses only the central directory of a ZIP through a {@link ByteSource},
 * then extracts individual entries by fetching just their byte ranges.
 * Works identically for a local file or a remote GitHub release asset.
 *
 * Limits: archives < 2 GiB, methods stored (0) and deflate (8).
 */
class ZipIndex {
	static inline var SIG_EOCD = 0x06054b50;
	static inline var SIG_CEN = 0x02014b50;
	static inline var SIG_LOC = 0x04034b50;
	static inline var EOCD_MAX = 22 + 65535;

	public var entries(default, null):Array<ZipEntry> = [];
	public var centralOffset(default, null):Int;

	var byName = new Map<String, ZipEntry>();

	function new() {}

	public function get(name:String):Null<ZipEntry>
		return byName.get(name);

	public static function read(src:ByteSource):ZipIndex {
		var total = src.size();
		if (total < 22) throw new ZipFormatError("File too small to be a zip");
		var tailLen = total < EOCD_MAX ? total : EOCD_MAX;
		var tail = src.read(total - tailLen, tailLen);

		var eocd = -1;
		var i = tail.length - 22;
		while (i >= 0) {
			if (tail.getInt32(i) == SIG_EOCD) {
				eocd = i;
				break;
			}
			i--;
		}
		if (eocd < 0) throw new ZipFormatError("End of central directory not found");

		var count = tail.getUInt16(eocd + 10);
		var cdSize = tail.getInt32(eocd + 12);
		var cdOffset = tail.getInt32(eocd + 16);
		if (count == 0xFFFF || cdSize == -1 || cdOffset == -1 || cdOffset < 0)
			throw new ZipFormatError("ZIP64 archives are not supported (package must be < 2 GiB / 65535 files)");

		var idx = new ZipIndex();
		idx.centralOffset = cdOffset;
		var cd = src.read(cdOffset, cdSize);
		var p = 0;
		for (_ in 0...count) {
			if (cd.getInt32(p) != SIG_CEN) throw new ZipFormatError('Bad central directory entry at $p');
			var flags = cd.getUInt16(p + 8);
			var nameLen = cd.getUInt16(p + 28);
			var extraLen = cd.getUInt16(p + 30);
			var commentLen = cd.getUInt16(p + 32);
			var nameBytes = cd.sub(p + 46, nameLen);
			var name = (flags & 0x800) != 0 ? nameBytes.toString() : nameBytes.toString();
			var e:ZipEntry = {
				name: StringTools.replace(name, "\\", "/"),
				method: cd.getUInt16(p + 10),
				crc32: cd.getInt32(p + 16),
				compressedSize: cd.getInt32(p + 20),
				size: cd.getInt32(p + 24),
				localOffset: cd.getInt32(p + 42),
				dataEnd: 0
			};
			if (e.compressedSize < 0 || e.size < 0 || e.localOffset < 0) throw new ZipFormatError("ZIP64 entry not supported: " + e.name);
			if ((flags & 1) != 0) throw new ZipFormatError("Encrypted entries not supported: " + e.name);
			idx.entries.push(e);
			if (!StringTools.endsWith(e.name, "/")) idx.byName.set(e.name, e);
			p += 46 + nameLen + extraLen + commentLen;
		}

		var sorted = idx.entries.copy();
		sorted.sort((a, b) -> a.localOffset - b.localOffset);
		for (k in 0...sorted.length) sorted[k].dataEnd = k + 1 < sorted.length ? sorted[k + 1].localOffset : cdOffset;
		return idx;
	}

	/**
	 * Fetches and decompresses `wanted` entries, grouping neighbours into one
	 * request when the gap between them is small (fewer HTTP round-trips).
	 * `onEntry` receives each decompressed, CRC-verified entry.
	 */
	public function extract(src:ByteSource, wanted:Array<ZipEntry>, onEntry:(ZipEntry, Bytes) -> Void, ?maxGap:Int = 262144, ?maxBatch:Int = 16777216,
			?isCancelled:() -> Bool) {
		var list = wanted.copy();
		list.sort((a, b) -> a.localOffset - b.localOffset);
		var i = 0;
		while (i < list.length) {
			if (isCancelled != null && isCancelled()) throw new HttpClient.CancelledException("cancelled");
			var start = list[i].localOffset;
			var end = list[i].dataEnd;
			var j = i + 1;
			while (j < list.length && list[j].localOffset - end <= maxGap && list[j].dataEnd - start <= maxBatch) {
				end = list[j].dataEnd;
				j++;
			}
			var chunk = src.read(start, end - start);
			for (k in i...j) {
				var e = list[k];
				onEntry(e, decode(e, chunk, e.localOffset - start));
			}
			i = j;
		}
	}

	static function decode(e:ZipEntry, chunk:Bytes, at:Int):Bytes {
		if (chunk.getInt32(at) != SIG_LOC) throw new ZipFormatError('Bad local header for ${e.name}');
		var nameLen = chunk.getUInt16(at + 26);
		var extraLen = chunk.getUInt16(at + 28);
		var dataStart = at + 30 + nameLen + extraLen;
		if (dataStart + e.compressedSize > chunk.length) throw new ZipFormatError('Truncated data for ${e.name}');
		var raw = chunk.sub(dataStart, e.compressedSize);
		var out = switch (e.method) {
			case 0: raw;
			case 8: inflate(raw, e.size);
			default: throw new ZipFormatError('Unsupported compression method ${e.method} for ${e.name}');
		}
		if (out.length != e.size) throw new ZipFormatError('Size mismatch for ${e.name}');
		if (haxe.crypto.Crc32.make(out) != e.crc32) throw new ZipFormatError('CRC mismatch for ${e.name}');
		return out;
	}

	static function inflate(raw:Bytes, size:Int):Bytes {
		if (size == 0) return Bytes.alloc(0);
		#if (cpp || hl || neko)
		try {
			var u = new haxe.zip.Uncompress(-15);
			u.setFlushMode(haxe.zip.FlushMode.FINISH);
			var dst = Bytes.alloc(size);
			var r = u.execute(raw, 0, dst, 0);
			u.close();
			if (r.write == size) return dst;
		} catch (_:Dynamic) {}
		#end
		var inf = new haxe.zip.InflateImpl(new BytesInput(raw), false, false);
		var out = Bytes.alloc(size);
		var got = 0;
		while (got < size) {
			var n = inf.readBytes(out, got, size - got);
			if (n <= 0) break;
			got += n;
		}
		return got == size ? out : out.sub(0, got);
	}
}
