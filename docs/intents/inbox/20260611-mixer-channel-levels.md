mixer channel levels everywhere

All channels on the mixer should have level meters so you can see
activity, using the master bus's existing meter as the template. Track
strips, send/return strips, and user buses all show live levels the same
way the master does. (Raised while debugging silent output: the master
meters were the only visibility into whether anything was flowing, and
per-channel meters would have located the dead link immediately.)

Related cosmetic fix, same area: the transport's status summary shows
"No default output" for audio-input tracks even though their monitor
path routes to a bus/master independently of the Destination model — the
summary should describe the input track's actual monitor routing.
