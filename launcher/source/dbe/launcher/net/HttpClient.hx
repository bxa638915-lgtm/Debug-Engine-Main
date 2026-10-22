package dbe.launcher.net;

import haxe.io.Bytes;
import haxe.io.BytesOutput;
import haxe.io.Output;

typedef HttpResponse = {
	var status:Int;
	var headers:Map<String, String>;
	/** Final URL after redirects. */
	var url:String;
}

class HttpException extends haxe.Exception {
	public var status(default, null):Int;
	public var url(default, null):String;

	public function new(msg:String, url:String, status:Int = -1) {
		super(msg);
		this.url = url;
		this.status = status;
	}
}

class CancelledException extends haxe.Exception {}

/**
 * Blocking HTTP client on top of `sys.Http` adding: redirect following,
 * custom headers (Range, If-None-Match), streaming to any Output,
 * byte-progress callbacks and cooperative cancellation.
 * Call it from a worker thread — never from the UI thread.
 */
class HttpClient {
	public static var userAgent = "DBE-Launcher";
	public static var maxRedirects = 8;
	public static var retries = 3;

	/** Performs a GET, writing the body of the *final* response into the output created by `makeOutput`. */
	public static function get(url:String, ?headers:Map<String, String>, makeOutput:() -> Output, ?onProgress:Float->Void,
			?isCancelled:() -> Bool):HttpResponse {
		var current = url;
		for (_ in 0...maxRedirects + 1) {
			var h = new sys.Http(current);
			h.setHeader("User-Agent", userAgent);
			if (headers != null) for (k => v in headers) h.setHeader(k, v);

			var status = -1;
			var error:String = null;
			h.onStatus = (s) -> status = s;
			h.onError = (e) -> error = e;

			var out = new ProgressOutput(makeOutput(), onProgress, isCancelled);
			try {
				h.customRequest(false, out);
			} catch (e:CancelledException) {
				out.close();
				throw e;
			}
			out.close();
			if (out.cancelled) throw new CancelledException("cancelled");

			var hdrs = lowerHeaders(h.responseHeaders);
			if (isRedirect(status) && hdrs.exists("location")) {
				current = resolve(current, hdrs.get("location"));
				continue;
			}
			if (error != null && status < 0) throw new HttpException(error, current, status);
			if (status >= 400) throw new HttpException('HTTP $status', current, status);
			return {status: status, headers: hdrs, url: current};
		}
		throw new HttpException("Too many redirects", url);
	}

	/** GET into memory with retries (for small payloads: API JSON, manifests, range chunks). */
	public static function getBytes(url:String, ?headers:Map<String, String>, ?isCancelled:() -> Bool):{response:HttpResponse, body:Bytes} {
		var lastErr:haxe.Exception = null;
		for (attempt in 0...retries) {
			var buf:BytesOutput = null;
			try {
				var r = get(url, headers, () -> buf = new BytesOutput(), null, isCancelled);
				return {response: r, body: buf.getBytes()};
			} catch (e:CancelledException) {
				throw e;
			} catch (e:HttpException) {
				// 4xx (except 429) won't succeed on retry
				if (e.status >= 400 && e.status < 500 && e.status != 429) throw e;
				lastErr = e;
			} catch (e:haxe.Exception) {
				lastErr = e;
			}
			Sys.sleep(0.5 * (attempt + 1));
		}
		throw lastErr;
	}

	public static function getText(url:String, ?headers:Map<String, String>, ?isCancelled:() -> Bool):String
		return getBytes(url, headers, isCancelled).body.toString();

	/** Streams a (large) download to `path` with retries. */
	public static function download(url:String, path:String, ?onProgress:Float->Void, ?isCancelled:() -> Bool):HttpResponse {
		var lastErr:haxe.Exception = null;
		for (attempt in 0...retries) {
			try {
				dbe.launcher.util.PathUtil.ensureDirFor(path);
				return get(url, null, () -> sys.io.File.write(path, true), onProgress, isCancelled);
			} catch (e:CancelledException) {
				throw e;
			} catch (e:haxe.Exception) {
				lastErr = e;
				Sys.sleep(1.0 * (attempt + 1));
			}
		}
		throw lastErr;
	}

	static inline function isRedirect(s:Int):Bool
		return s == 301 || s == 302 || s == 303 || s == 307 || s == 308;

	static function lowerHeaders(m:Map<String, String>):Map<String, String> {
		var o = new Map<String, String>();
		if (m != null) for (k => v in m) o.set(k.toLowerCase(), v);
		return o;
	}

	static function resolve(base:String, loc:String):String {
		if (~/^https?:\/\//i.match(loc)) return loc;
		var re = ~/^(https?:\/\/[^\/]+)/i;
		if (!re.match(base)) return loc;
		if (StringTools.startsWith(loc, "/")) return re.matched(1) + loc;
		var dir = base.substr(0, base.lastIndexOf("/") + 1);
		return dir + loc;
	}
}

/** Output wrapper counting bytes for progress and supporting cancellation. */
private class ProgressOutput extends Output {
	var inner:Output;
	var onProgress:Float->Void;
	var isCancelled:() -> Bool;
	var written = 0.0;
	var lastReport = 0.0;

	public var cancelled(default, null) = false;

	public function new(inner:Output, onProgress:Float->Void, isCancelled:() -> Bool) {
		this.inner = inner;
		this.onProgress = onProgress;
		this.isCancelled = isCancelled;
	}

	override public function writeByte(c:Int) {
		inner.writeByte(c);
		tick(1);
	}

	override public function writeBytes(s:Bytes, pos:Int, len:Int):Int {
		var n = inner.writeBytes(s, pos, len);
		tick(n);
		return n;
	}

	function tick(n:Int) {
		written += n;
		if (isCancelled != null && isCancelled()) {
			cancelled = true;
			throw new CancelledException("cancelled");
		}
		if (onProgress != null && written - lastReport >= 65536) {
			lastReport = written;
			onProgress(written);
		}
	}

	override public function close() {
		if (onProgress != null) onProgress(written);
		try inner.close() catch (_:Dynamic) {}
	}
}
