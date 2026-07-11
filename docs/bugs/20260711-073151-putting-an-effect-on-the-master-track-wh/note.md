Putting an effect on the master track while playing also kills audio

Status: RESOLVED 56ef102e b1f4055c

Master insert topology now rewires behind a dedicated persistent silence gate
without stopping or restarting the audio engine. Scene-only inserts preserve
the stable post-blend master spine rather than reconnecting a live HAL edge.
