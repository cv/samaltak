-- osascript tools/qemu-window.applescript W H: wait for QEMU's window, give it W x H points of screen (zoom-to-fit
-- scales the guest's screen to that), center it and bring it to the front. Needs Accessibility for the terminal.
on run argv
	set w to (item 1 of argv) as integer
	set h to (item 2 of argv) as integer
	tell application "Finder" to set {sx, sy, sw, sh} to bounds of window of desktop
	tell application "System Events"
		repeat 300 times
			set ps to processes whose name starts with "qemu-system"
			if ps is not {} then
				set p to last item of ps
				if (count of windows of p) > 0 then exit repeat
			end if
			delay 0.1
		end repeat
		set win to window 1 of p
		set {ww, wh} to size of win
		set t to wh - (ww * h div w)
		-- Both take effect but can report an error (-10006).
		try
			set position of win to {(sw - w) div 2, (sh - h - t) div 2}
		end try
		try
			set size of win to {w, h + t}
		end try
		set frontmost of p to true
	end tell
end run
