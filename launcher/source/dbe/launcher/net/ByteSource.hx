package dbe.launcher.net;

import dbe.launcher.net.HttpClient;
import haxe.io.Bytes;
import sys.io.File;
import sys.io.FileInput;

/** Random-access byte source (local file or remote HTTP resource). */
interface ByteSource {
	function size():Int;
	function read(start:Int, len:Int):Bytes;
	function close():Void;
}

class FileByteSource implements ByteSource {
	var input:FileInput;
	var length:Int;

	public function new(path:String) {
		length = sys.FileSystem.stat(path).size;
		input = File.read(path, true);
	}

	public function size():Int
		return length;

	public function read(start:Int, len:Int):Bytes {
		input.seek(start, SeekBegin);
		return input.read(len);
	}

	public function close()
		input.close();
}

class RangeUnsupported extends haxe.Exception {}

/**
 * Reads arbitrary byte ranges of a remote file with HTTP `Range` requests.
 * The redirected (signed CDN) URL is cached and re-resolved on 403/404 expiry.
 */
class HttpRangeSource implements ByteSource {
	var originalUrl:String;
	var resolvedUrl:String;
	var totalSize:Int = -1;
	var isCancelled:() -> Bool;

	public var bytesFetched(default, null):Float = 0;
	public var requestCount(default, null):Int = 0;

	public function new(url:String, ?isCancelled:() -> Bool) {
		originalUrl = url;
		this.isCancelled = isCancelled;
	}

	public function size():Int {
		if (totalSize < 0) {
			// Probe with a 1-byte range: gives total size via Content-Range and resolves redirects.
			fetch(0, 1);
		}
		return totalSize;
	}

	public function read(start:Int, len:Int):Bytes {
		if (len <= 0) return Bytes.alloc(0);
		return fetch(start, len);
	}

	function fetch(start:Int, len:Int):Bytes {
		var headers = ["Range" => 'bytes=$start-${start + len - 1}'];
		var res = null;
		try {
			res = HttpClient.getBytes(resolvedUrl != null ? resolvedUrl : originalUrl, headers, isCancelled);
		} catch (e:HttpException) {
			if (resolvedUrl != null && (e.status == 403 || e.status == 404 || e.status == 410)) {
				resolvedUrl = null; // signed URL expired → resolve again
				res = HttpClient.getBytes(originalUrl, headers, isCancelled);
			} else throw e;
		}
		requestCount++;
		resolvedUrl = res.response.url;
		if (res.response.status != 206) throw new RangeUnsupported('Server ignored Range (status ${res.response.status})');

		var cr = res.response.headers.get("content-range");
		var re = ~/bytes\s+(\d+)-(\d+)\/(\d+|\*)/;
		if (cr == null || !re.match(cr)) throw new RangeUnsupported("Missing Content-Range");
		if (re.matched(3) != "*") totalSize = Std.parseInt(re.matched(3));
		if (Std.parseInt(re.matched(1)) != start) throw new RangeUnsupported("Content-Range start mismatch");
		if (res.body.length != len) throw new HttpException('Short range read (${res.body.length}/$len)', originalUrl, 206);
		bytesFetched += res.body.length;
		return res.body;
	}

	public function close() {}
}
