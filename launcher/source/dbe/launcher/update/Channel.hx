package dbe.launcher.update;

/** Update channel. A channel also accepts every "more stable" channel. */
enum abstract Channel(String) from String to String {
	var Stable = "stable";
	var Beta = "beta";
	var Nightly = "nightly";

	public static function fromString(s:String):Channel {
		return switch (s == null ? "" : s.toLowerCase()) {
			case "beta": Beta;
			case "nightly": Nightly;
			default: Stable;
		}
	}

	public function rank():Int
		return switch (this) {
			case "beta": 1;
			case "nightly": 2;
			default: 0;
		}

	/** True if a user subscribed to `this` channel should be offered `tagChannel`. */
	public function accepts(tagChannel:Channel):Bool
		return tagChannel.rank() <= rank();
}
