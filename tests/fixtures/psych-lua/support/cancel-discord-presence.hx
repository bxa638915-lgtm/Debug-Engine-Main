function onDiscordPresenceUpdate(event) {
	event.cancel();
	trace("DBE_PRESENCE_UPDATE_CANCELLED");
}
