when it's been playing for a while, pressing the stop button doesn't stop audio straight away. It keeps playing for a bit before stopping

Status: RESOLVED 56ef102e

Stop now sends immediate AU all-notes-off and sample-voice silence before it
waits for the scheduler queue to join.
