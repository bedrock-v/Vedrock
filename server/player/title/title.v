module title

import time

// tick is the length of a single server tick, the unit the client expects the
// fade and stay durations of a title in.
const tick = time.second / 20

// Title is a piece of large text drawn in the middle of a player's screen,
// optionally with a subtitle under it and action bar text at the bottom. It is
// a value type: the with_* methods return a modified copy instead of mutating
// the receiver.
pub struct Title {
	text        string
	subtitle    string
	action_text string
	fade_in     time.Duration = tick
	fade_out    time.Duration = tick
	duration    time.Duration = 2 * time.second
}

// new returns a Title showing the text passed, using the default fade and stay
// durations.
pub fn new(text string) Title {
	return Title{
		text: text
	}
}

// text returns the main text of the Title.
pub fn (t Title) text() string {
	return t.text
}

// subtitle returns the text drawn under the main text, empty if none was set.
pub fn (t Title) subtitle() string {
	return t.subtitle
}

// action_text returns the text drawn above the hotbar for as long as the Title
// is shown, empty if none was set.
pub fn (t Title) action_text() string {
	return t.action_text
}

// duration returns how long the Title stays on screen, excluding the fades.
pub fn (t Title) duration() time.Duration {
	return t.duration
}

// fade_in_duration returns how long the Title takes to fade in.
pub fn (t Title) fade_in_duration() time.Duration {
	return t.fade_in
}

// fade_out_duration returns how long the Title takes to fade out.
pub fn (t Title) fade_out_duration() time.Duration {
	return t.fade_out
}

// with_subtitle returns a copy of the Title with the subtitle passed.
pub fn (t Title) with_subtitle(text string) Title {
	return Title{
		...t
		subtitle: text
	}
}

// with_action_text returns a copy of the Title with the action bar text passed.
pub fn (t Title) with_action_text(text string) Title {
	return Title{
		...t
		action_text: text
	}
}

// with_duration returns a copy of the Title that stays on screen for d.
pub fn (t Title) with_duration(d time.Duration) Title {
	return Title{
		...t
		duration: d
	}
}

// with_fade_in_duration returns a copy of the Title that fades in over d.
pub fn (t Title) with_fade_in_duration(d time.Duration) Title {
	return Title{
		...t
		fade_in: d
	}
}

// with_fade_out_duration returns a copy of the Title that fades out over d.
pub fn (t Title) with_fade_out_duration(d time.Duration) Title {
	return Title{
		...t
		fade_out: d
	}
}

// ticks converts a duration to the tick count the client expects, rounding
// down but never below zero.
pub fn ticks(d time.Duration) i32 {
	if d <= 0 {
		return 0
	}
	return i32(d / tick)
}
