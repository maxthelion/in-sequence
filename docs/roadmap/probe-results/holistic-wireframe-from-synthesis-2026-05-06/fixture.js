export const workbenchFixture = {
  id: "happy-accident-workbench-fixture-2026-05-06",
  title: "Happy Accident Workbench",
  transport: {
    mode: "Free",
    state: "Playing",
    bpm: 126,
    step: 23,
    phraseStep: 7,
    activePhraseID: "phrase-intro-loop",
    queuedPhraseID: "phrase-breakdown-cue",
    selectedTrackIDs: ["track-drums", "track-melody", "track-audio-loop"]
  },
  phrases: [
    {
      id: "phrase-intro-loop",
      label: "NOW Intro Loop",
      lengthBars: 4,
      repeats: 2,
      sceneA: "scene-a-dry-kit",
      sceneB: "scene-b-wide-space",
      patternSlots: {
        "track-drums": "slot-drums-main",
        "track-melody": "slot-melody-generator",
        "track-audio-loop": "slot-audio-shared-buffer",
        "track-bass": "slot-bass-captured"
      },
      layers: ["slot", "mute", "fill", "macro"]
    },
    {
      id: "phrase-breakdown-cue",
      label: "NEXT Breakdown Cue",
      lengthBars: 8,
      repeats: 1,
      sceneA: "scene-a-filtered",
      sceneB: "scene-b-delay-freeze",
      patternSlots: {
        "track-drums": "slot-drums-fill",
        "track-melody": "slot-melody-captured-clip",
        "track-audio-loop": "slot-audio-sliced-buffer",
        "track-bass": "slot-bass-captured"
      },
      layers: ["slot", "mute", "fill", "macro"]
    }
  ],
  scenes: {
    a: {
      id: "scene-a-dry-kit",
      label: "A Dry Kit",
      authoredBlend: 0.18
    },
    b: {
      id: "scene-b-wide-space",
      label: "B Wide Space",
      authoredBlend: 0.82
    },
    liveCrossfader: {
      owner: "runtime-session",
      value: 0.64,
      authoredValue: 0.32,
      label: "Live crossfader override writes to Scene A/B only if kept"
    }
  },
  captures: {
    generatedClipHistory: [
      {
        id: "clip-melody-captured-032",
        sourceGeneratorID: "gen-melody-surprise",
        label: "Captured take 032",
        bars: 2,
        steps: 32,
        status: "kept-history",
        owner: "document-clip-pool"
      }
    ],
    nextActions: [
      {
        id: "capture-generated-clip",
        label: "Capture Generated Clip",
        target: "clip history for slot B2",
        owner: "document-clip-pool"
      },
      {
        id: "capture-loop-buffer",
        label: "Capture Loop To Shared Buffer",
        target: "buffer audio-loop-amber-voice",
        owner: "runtime-buffer then document reference"
      }
    ]
  },
  sharedAudioBuffer: {
    id: "buffer-audio-loop-amber-voice",
    label: "Amber Voice 4-bar loop",
    owner: "runtime-audio-buffer",
    sourceTrackID: "track-audio-loop",
    sampleRate: 48000,
    durationBars: 4,
    loopRange: {
      startBeat: 0,
      endBeat: 16
    },
    sliceCues: [
      { id: "slice-01", beat: 0, label: "downbeat" },
      { id: "slice-02", beat: 3.5, label: "breath" },
      { id: "slice-03", beat: 7.75, label: "lift" },
      { id: "slice-04", beat: 12, label: "tail" }
    ],
    users: [
      { id: "track-audio-loop", label: "Audio Loop track", role: "input playback" },
      { id: "slot-audio-sliced-buffer", label: "Queued sliced slot", role: "slice triggers" },
      { id: "track-drums", label: "Drum sidechain", role: "ducking key" }
    ]
  },
  performanceOverride: {
    id: "override-fill-repeat-023",
    owner: "runtime-session",
    label: "Transient until kept",
    selectedTrackIDs: ["track-drums", "track-melody", "track-audio-loop"],
    target: "selected track set",
    values: {
      fill: "on",
      noteRepeat: "1/16 burst",
      stepOrder: "pendulum",
      macro: "+18% intensity"
    },
    keepTarget: "write to active phrase cells and scene blend",
    discardTarget: "clear session overlay, restore authored phrase/scene/mixer state"
  },
  mixer: {
    owner: "audio-graph",
    routeSummary: "Drums -> Drum Bus -> Master, sends -> Delay Return + Reverb Return",
    tracksToBus: [
      { trackID: "track-drums", busID: "bus-drums" },
      { trackID: "track-audio-loop", busID: "bus-drums" }
    ],
    busses: [
      { id: "bus-drums", label: "Drum Bus", levelDB: -3.2, sends: ["return-delay", "return-reverb"] }
    ],
    returns: [
      { id: "return-delay", label: "Delay Return", amount: 0.34 },
      { id: "return-reverb", label: "Reverb Return", amount: 0.27 }
    ],
    master: {
      label: "Post-blend Master",
      peakDBFS: -5.4,
      clipLatched: false
    }
  },
  tracks: [
    {
      id: "track-drums",
      label: "Drum Kit Group",
      type: "drum/group",
      group: "Kit A",
      slotID: "slot-drums-main",
      source: "Holistic drum pattern",
      sourceKind: "clip",
      sounding: "kick/snare/hats via Drum Bus",
      badges: ["selected", "fill live", "bus routed"],
      route: "Drum Bus -> Master",
      meter: -8.2
    },
    {
      id: "track-melody",
      label: "Melodic Generator",
      type: "melodic generator",
      group: "Lead",
      slotID: "slot-melody-generator",
      source: "Generator recipe: Surprise Steps",
      sourceKind: "generator",
      sounding: "generated notes, capture-ready",
      badges: ["selected", "captured history", "note repeat"],
      route: "Master + Delay Return",
      meter: -12.1
    },
    {
      id: "track-audio-loop",
      label: "Audio Input Loop",
      type: "audio input/loop",
      group: "Input",
      slotID: "slot-audio-shared-buffer",
      source: "Shared buffer: Amber Voice",
      sourceKind: "audio-buffer",
      sounding: "looping buffer, slice cues armed",
      badges: ["selected", "buffer", "crossfade live"],
      route: "Drum Bus + Reverb Return",
      meter: -9.5
    },
    {
      id: "track-bass",
      label: "Bass Clip",
      type: "bass clip",
      group: "Low",
      slotID: "slot-bass-captured",
      source: "Captured bass clip",
      sourceKind: "clip",
      sounding: "authored clip",
      badges: ["authored", "steady"],
      route: "Master",
      meter: -10.6
    }
  ]
};

export function selectedTracks(fixture = workbenchFixture) {
  const selected = new Set(fixture.transport.selectedTrackIDs);
  return fixture.tracks.filter((track) => selected.has(track.id));
}

export function firstViewportLabels(fixture = workbenchFixture) {
  const activePhrase = fixture.phrases.find((phrase) => phrase.id === fixture.transport.activePhraseID);
  const queuedPhrase = fixture.phrases.find((phrase) => phrase.id === fixture.transport.queuedPhraseID);
  return [
    fixture.title,
    fixture.transport.state,
    activePhrase?.label,
    queuedPhrase?.label,
    fixture.captures.generatedClipHistory[0]?.label,
    fixture.captures.nextActions[0]?.label,
    fixture.captures.nextActions[1]?.label,
    fixture.performanceOverride.label,
    fixture.performanceOverride.keepTarget,
    fixture.performanceOverride.discardTarget,
    fixture.sharedAudioBuffer.label,
    fixture.mixer.routeSummary
  ].filter(Boolean);
}

export function scenarioInvariants(fixture = workbenchFixture) {
  const trackKinds = new Set(fixture.tracks.map((track) => track.type));
  const selected = selectedTracks(fixture);
  const activePhrase = fixture.phrases.find((phrase) => phrase.id === fixture.transport.activePhraseID);
  const queuedPhrase = fixture.phrases.find((phrase) => phrase.id === fixture.transport.queuedPhraseID);
  const capture = fixture.captures.generatedClipHistory[0];
  const buffer = fixture.sharedAudioBuffer;
  const overrideTargetsMatchSelection =
    fixture.performanceOverride.selectedTrackIDs.every((id) => fixture.transport.selectedTrackIDs.includes(id)) &&
    selected.length === fixture.performanceOverride.selectedTrackIDs.length;
  const bufferUsersReferenceFixtureIDs = buffer.users.every((user) => {
    return fixture.tracks.some((track) => track.id === user.id) ||
      Object.values(activePhrase.patternSlots).includes(user.id) ||
      Object.values(queuedPhrase.patternSlots).includes(user.id);
  });

  return {
    hasFourTracks: fixture.tracks.length === 4,
    hasDrumGroup: trackKinds.has("drum/group"),
    hasMelodicGenerator: trackKinds.has("melodic generator"),
    hasAudioInputLoop: trackKinds.has("audio input/loop"),
    hasBassClip: trackKinds.has("bass clip"),
    hasActiveAndQueuedPhrase: Boolean(activePhrase && queuedPhrase && activePhrase.id !== queuedPhrase.id),
    hasCapturedGeneratedClip: Boolean(capture && capture.sourceGeneratorID && capture.owner === "document-clip-pool"),
    hasSharedAudioBufferIdentity: Boolean(buffer.id && buffer.loopRange && buffer.sliceCues.length >= 4),
    bufferUsersReferenceFixtureIDs,
    hasTransientOverride: fixture.performanceOverride.owner === "runtime-session" && overrideTargetsMatchSelection,
    hasMixerRouteThroughBusAndReturns:
      fixture.mixer.busses.some((bus) => bus.id === "bus-drums") &&
      fixture.mixer.returns.some((route) => route.id === "return-delay") &&
      fixture.mixer.returns.some((route) => route.id === "return-reverb"),
    hasSceneCrossfaderOverride:
      fixture.scenes.liveCrossfader.owner === "runtime-session" &&
      fixture.scenes.liveCrossfader.value !== fixture.scenes.liveCrossfader.authoredValue
  };
}

export function validateScenario(fixture = workbenchFixture) {
  const invariants = scenarioInvariants(fixture);
  const failures = Object.entries(invariants)
    .filter(([, passed]) => !passed)
    .map(([name]) => name);
  return {
    ok: failures.length === 0,
    failures,
    invariants
  };
}
