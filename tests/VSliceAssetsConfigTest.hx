import dbe.compatibility.assets.VSliceAssetsConfig;
import haxe.io.Path;
import sys.FileSystem;

class VSliceAssetsConfigTest {
	static function main():Void {
		var root = Path.join([Sys.getCwd(), "tmp", "vslice-assets-config-test"]);
		if (FileSystem.exists(root)) FileSystem.deleteDirectory(root);
		FileSystem.createDirectory(root);
		try {
			var repositoryRoot = Path.join([root, "repository"]);
			var assetRoot = Path.join([repositoryRoot, "assets"]);
			FileSystem.createDirectory(repositoryRoot);
			FileSystem.createDirectory(assetRoot);
			FileSystem.createDirectory(Path.join([assetRoot, "data"]));
			var resolved = VSliceAssetsConfig.resolveAssetsRoot(repositoryRoot);
			if (resolved != Path.normalize(assetRoot))
				throw "V-Slice asset configuration must accept the Funkin.assets repository root";

			var directRoot = Path.join([root, "direct-assets"]);
			FileSystem.createDirectory(directRoot);
			FileSystem.createDirectory(Path.join([directRoot, "images"]));
			resolved = VSliceAssetsConfig.resolveAssetsRoot(directRoot);
			if (resolved != Path.normalize(directRoot))
				throw "V-Slice asset configuration must also accept a direct asset directory";

			if (VSliceAssetsConfig.resolveAssetsRoot(Path.join([root, "missing"])) != null)
				throw "Invalid V-Slice asset paths must not mount silently";
		} catch (error:Dynamic) {
			deleteTree(root);
			throw error;
		}
		deleteTree(root);
		trace("VSliceAssetsConfigTest: PASS");
	}

	static function deleteTree(path:String):Void {
		if (!FileSystem.exists(path)) return;
		for (entry in FileSystem.readDirectory(path)) {
			var child = Path.join([path, entry]);
			if (FileSystem.isDirectory(child)) deleteTree(child);
			else FileSystem.deleteFile(child);
		}
		FileSystem.deleteDirectory(path);
	}
}
