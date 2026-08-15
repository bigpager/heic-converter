-- HEIC Converter.app — the double-clickable way into the settings window.
--
-- Deliberately just a launcher. It spawns the settings window as its own
-- detached /usr/bin/osascript process and then exits, which means this applet's
-- lifetime is irrelevant: no stay-open handler, no idle handler, no second run
-- loop competing with the one the window creates. The window ends up in exactly
-- the same process shape as `heic-converter setup` from a shell, so there is one
-- code path to reason about rather than two.
--
-- It also keeps the signing surface minimal. The only Mach-O this project ships
-- is the applet stub osacompile generates from this file; the window itself runs
-- inside Apple's own /usr/bin/osascript, which is already signed by Apple and is
-- not part of our payload.

on run
	try
		do shell script "/usr/local/bin/heic-converter setup > /dev/null 2>&1 &"
	on error errMsg
		display dialog "Could not open HEIC Converter settings." & return & return & errMsg ¬
			buttons {"OK"} default button "OK" with title "HEIC Converter" with icon caution
	end try
end run
