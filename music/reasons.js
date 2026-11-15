// Short reason texts sent in "failed" events.
// The Ruby side (music_controller.rb) matches on these exact strings to detect
// a failed join, so do not change the text without changing Ruby too.
export const JOIN_FAILED_REASON = "could not join the voice channel";
export const NOT_CONNECTED_REASON = "not connected to a voice channel";
