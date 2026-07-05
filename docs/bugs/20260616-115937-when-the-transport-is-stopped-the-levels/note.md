When the transport is stopped, the levels don't go to zero in the mixer, they stay on their last value

Status: RESOLVED — db4bb944. Transport-stop meter reset now snaps the shared channel/master meter bank to silence, covered by `ChannelMeterBankTests.test_mainAudioGraphStopMeterResetSnapsChannelsAndMasterToSilence`.
