package dbe.launcher;

/** Compile-time launcher identity. Bump VERSION when releasing a new launcher. */
class LauncherInfo {
	public static inline var VERSION = "1.0.0";
	public static inline var NAME = "DBE Launcher";
	public static inline var DEFAULT_OWNER = "bxa638915-lgtm";
	public static inline var DEFAULT_REPO = "Debug-Engine-Main";
	/** Folder (inside the engine root) where the launcher lives. Protected from engine updates. */
	public static inline var INSTALL_DIR = "launcher";
}
