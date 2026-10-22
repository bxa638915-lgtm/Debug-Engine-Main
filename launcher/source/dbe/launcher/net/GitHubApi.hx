package dbe.launcher.net;

import dbe.launcher.update.UpdatePlanner.ReleaseInfo;
import dbe.launcher.util.PathUtil;
import haxe.Json;
import sys.FileSystem;
import sys.io.File;

/**
 * Minimal GitHub Releases client.
 * Responses are cached with their ETag; conditional requests answered with
 * `304 Not Modified` don't count against the 60 req/hour anonymous limit.
 */
class GitHubApi {
	public var owner(default, null):String;
	public var repo(default, null):String;

	var cacheFile:Null<String>;

	public function new(owner:String, repo:String, ?cacheFile:String) {
		this.owner = owner;
		this.repo = repo;
		this.cacheFile = cacheFile;
	}

	public function releasesUrl():String
		return 'https://api.github.com/repos/$owner/$repo/releases?per_page=100';

	public function fetchReleases(?isCancelled:() -> Bool):Array<ReleaseInfo> {
		var cached = loadCache();
		var headers = ["Accept" => "application/vnd.github+json", "X-GitHub-Api-Version" => "2022-11-28"];
		if (cached != null && cached.etag != null) headers.set("If-None-Match", cached.etag);

		var body:String;
		try {
			var r = HttpClient.getBytes(releasesUrl(), headers, isCancelled);
			if (r.response.status == 304 && cached != null) body = cached.body;
			else {
				body = r.body.toString();
				saveCache(r.response.headers.get("etag"), body);
			}
		} catch (e:HttpClient.HttpException) {
			// Offline / rate limited: fall back to the last good response.
			if (cached != null) body = cached.body;
			else if (e.status == 403 || e.status == 429) throw new HttpClient.HttpException("GitHub rate limit reached, try again later", e.url, e.status);
			else throw e;
		}
		return parseReleases(body);
	}

	public static function parseReleases(json:String):Array<ReleaseInfo> {
		var arr:Array<Dynamic> = Json.parse(json);
		var out:Array<ReleaseInfo> = [];
		for (r in arr) {
			var assets:Array<Dynamic> = r.assets == null ? [] : r.assets;
			out.push({
				tag: r.tag_name,
				name: r.name == null ? r.tag_name : r.name,
				body: r.body == null ? "" : r.body,
				prerelease: r.prerelease == true,
				draft: r.draft == true,
				publishedAt: r.published_at == null ? "" : r.published_at,
				htmlUrl: r.html_url == null ? "" : r.html_url,
				assets: [for (a in assets) {name: a.name, url: a.browser_download_url, size: a.size == null ? 0 : a.size}]
			});
		}
		return out;
	}

	function loadCache():Null<{etag:String, body:String}> {
		if (cacheFile == null || !FileSystem.exists(cacheFile)) return null;
		try {
			var d:Dynamic = Json.parse(File.getContent(cacheFile));
			if (d.url != releasesUrl()) return null;
			return {etag: d.etag, body: d.body};
		} catch (_:Dynamic) return null;
	}

	function saveCache(etag:String, body:String) {
		if (cacheFile == null) return;
		try {
			PathUtil.ensureDirFor(cacheFile);
			File.saveContent(cacheFile, Json.stringify({url: releasesUrl(), etag: etag, body: body}));
		} catch (_:Dynamic) {}
	}
}
