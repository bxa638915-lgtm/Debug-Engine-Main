package dbe.launcher.tools;

import haxe.io.Bytes;
import haxe.io.Output;

private typedef CdRecord = {
	var name:Bytes;
	var method:Int;
	var crc:Int;
	var csize:Int;
	var size:Int;
	var offset:Int;
}

/**
 * Streaming ZIP writer (one entry in memory at a time), UTF-8 names (flag 0x800),
 * stored or raw-deflate entries. Produces archives readable by {@link dbe.launcher.net.ZipIndex}.
 */
class ZipWriter {
	var o:Output;
	var pos = 0;
	var records:Array<CdRecord> = [];

	public function new(o:Output)
		this.o = o;

	public function add(name:String, data:Bytes, compress:Bool) {
		var nameBytes = Bytes.ofString(name);
		var crc = haxe.crypto.Crc32.make(data);
		var payload = data;
		var method = 0;
		if (compress && data.length > 0) {
			var z = deflateRaw(data);
			if (z.length < data.length) {
				payload = z;
				method = 8;
			}
		}
		records.push({name: nameBytes, method: method, crc: crc, csize: payload.length, size: data.length, offset: pos});

		u32(0x04034b50);
		u16(20);
		u16(0x800);
		u16(method);
		u16(0); // time
		u16(0x21); // date 1980-01-01
		u32(crc);
		u32(payload.length);
		u32(data.length);
		u16(nameBytes.length);
		u16(0);
		bytes(nameBytes);
		bytes(payload);
	}

	public function close() {
		var cdStart = pos;
		for (r in records) {
			u32(0x02014b50);
			u16(0x031e); // made by: unix, v3.0 (keeps external attrs meaningful)
			u16(20);
			u16(0x800);
			u16(r.method);
			u16(0);
			u16(0x21);
			u32(r.crc);
			u32(r.csize);
			u32(r.size);
			u16(r.name.length);
			u16(0);
			u16(0);
			u16(0);
			u16(0);
			u32(0x81a40000); // -rw-r--r--
			u32(r.offset);
			bytes(r.name);
		}
		var cdSize = pos - cdStart;
		if (records.length > 0xFFFF) throw "Too many files for a non-ZIP64 archive";
		u32(0x06054b50);
		u16(0);
		u16(0);
		u16(records.length);
		u16(records.length);
		u32(cdSize);
		u32(cdStart);
		u16(0);
		o.close();
	}

	public var bytesWritten(get, never):Int;

	inline function get_bytesWritten()
		return pos;

	inline function u16(v:Int) {
		o.writeUInt16(v);
		pos += 2;
	}

	inline function u32(v:Int) {
		o.writeInt32(v);
		pos += 4;
		if (pos < 0) throw "Package exceeds 2 GiB";
	}

	inline function bytes(b:Bytes) {
		o.writeFullBytes(b, 0, b.length);
		pos += b.length;
		if (pos < 0) throw "Package exceeds 2 GiB";
	}

	/** zlib stream minus 2-byte header and 4-byte Adler-32 trailer = raw deflate. */
	static function deflateRaw(data:Bytes):Bytes {
		var z = haxe.zip.Compress.run(data, 9);
		return z.sub(2, z.length - 6);
	}
}
