Putting an effect on the master track while playing also kills audio

Status: RESOLVED 56ef102e

Master insert topology now rewires behind a dedicated persistent silence gate
without stopping or restarting the audio engine.
