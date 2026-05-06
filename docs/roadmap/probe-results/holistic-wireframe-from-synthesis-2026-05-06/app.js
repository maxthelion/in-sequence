import {
  firstViewportLabels,
  selectedTracks,
  validateScenario,
  workbenchFixture
} from "./fixture.js";

const fixture = workbenchFixture;
const state = {
  overrideVisible: true,
  captureCount: fixture.captures.generatedClipHistory.length,
  bufferCaptured: false,
  decisionOutcome: "active"
};

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function renderPill(text, tone = "") {
  const pill = el("span", `pill ${tone}`, text);
  return pill;
}

function renderTrack(track) {
  const article = el("article", `track-card ${track.badges.includes("selected") ? "selected" : ""}`);
  article.dataset.trackId = track.id;

  const head = el("div", "track-head");
  head.append(el("strong", "", track.label));
  head.append(renderPill(track.type));
  article.append(head);

  article.append(el("p", "muted", track.source));

  const badges = el("div", "badge-row");
  track.badges.forEach((badge) => badges.append(renderPill(badge, badge.includes("live") ? "hot" : "")));
  article.append(badges);

  const meter = el("div", "meter-row");
  meter.append(el("span", "", track.route));
  meter.append(el("span", "", `${track.meter} dB`));
  article.append(meter);

  return article;
}

function renderSourceArea() {
  const selected = selectedTracks(fixture);
  const source = el("section", "panel source-panel");
  source.append(el("h2", "", "Source, Capture, And Consequence"));

  const chain = el("div", "source-chain");
  chain.append(renderPill("Slot B2", "dark"));
  chain.append(renderPill("Generator Recipe", "dark"));
  chain.append(renderPill("Modifier: humanize 18%", "dark"));
  chain.append(renderPill("Captured Clip Preserved", "ok"));
  source.append(chain);

  const work = el("div", "work-grid");
  const waveform = el("div", "waveform");
  const bars = [32, 58, 46, 75, 51, 67, 29, 84, 62, 44, 72, 38, 57, 69, 41, 80];
  bars.forEach((height, index) => {
    const bar = el("span");
    bar.style.height = `${height}%`;
    if (fixture.sharedAudioBuffer.sliceCues.some((cue) => Math.round(cue.beat) === index)) {
      bar.classList.add("cue");
    }
    waveform.append(bar);
  });
  work.append(waveform);

  const history = el("div", "history-rail");
  history.append(el("h3", "", "Clip History"));
  fixture.captures.generatedClipHistory.forEach((clip) => {
    const item = el("button", "history-item", `${clip.label} - ${clip.bars} bars`);
    item.type = "button";
    history.append(item);
  });
  const newTake = el("button", "history-item ghost", `Pending take ${String(33 + state.captureCount - 1).padStart(3, "0")}`);
  newTake.type = "button";
  history.append(newTake);
  work.append(history);

  source.append(work);

  const actions = el("div", "action-row");
  const captureGenerated = el("button", "primary-action", "Capture Generated Clip");
  captureGenerated.type = "button";
  captureGenerated.addEventListener("click", () => {
    state.captureCount += 1;
    render();
  });
  const captureLoop = el("button", "secondary-action", state.bufferCaptured ? "Shared Buffer Updated" : "Capture Loop To Shared Buffer");
  captureLoop.type = "button";
  captureLoop.addEventListener("click", () => {
    state.bufferCaptured = true;
    render();
  });
  actions.append(captureGenerated, captureLoop);
  source.append(actions);

  const selectedSummary = el("p", "muted", `Selected target set: ${selected.map((track) => track.label).join(", ")}`);
  source.append(selectedSummary);

  return source;
}

function renderConsequenceRail() {
  const transaction = fixture.performanceOverride.transaction;
  const rail = el("aside", "panel consequence");
  rail.append(el("h2", "", "What Is Sounding"));
  fixture.tracks.forEach((track) => {
    const row = el("div", "sound-row");
    row.append(el("strong", "", track.label));
    row.append(el("span", "", track.sounding));
    rail.append(row);
  });

  rail.append(el("h2", "", "Shared Buffer"));
  rail.append(el("p", "", fixture.sharedAudioBuffer.label));
  const bufferMeta = el("div", "mini-list");
  bufferMeta.append(renderPill(`Loop ${fixture.sharedAudioBuffer.loopRange.startBeat}-${fixture.sharedAudioBuffer.loopRange.endBeat} beats`));
  bufferMeta.append(renderPill(`${fixture.sharedAudioBuffer.sliceCues.length} slice cues`));
  fixture.sharedAudioBuffer.users.forEach((user) => bufferMeta.append(renderPill(user.label)));
  rail.append(bufferMeta);

  rail.append(el("h2", "", "Transient Overlay"));
  const override = el("div", `override-card ${state.overrideVisible ? "" : "cleared"}`);
  if (state.overrideVisible) {
    override.append(el("strong", "", fixture.performanceOverride.label));
    override.append(el("span", "", transaction.source.summary));
  } else if (state.decisionOutcome === "kept") {
    override.append(el("strong", "", transaction.keep.acknowledgement));
    override.append(el("span", "", transaction.keep.detail));
  } else {
    override.append(el("strong", "", transaction.discard.acknowledgement));
    override.append(el("span", "", transaction.discard.detail));
  }
  rail.append(override);

  return rail;
}

function renderArrangementBand() {
  const band = el("section", "arrangement-band");
  const phrases = el("div", "phrase-strip");
  fixture.phrases.forEach((phrase) => {
    const item = el("article", `phrase-card ${phrase.id === fixture.transport.activePhraseID ? "active" : "queued"}`);
    item.append(el("strong", "", phrase.label));
    item.append(el("span", "", `${phrase.lengthBars} bars x ${phrase.repeats}`));
    item.append(el("span", "", `slots: ${Object.values(phrase.patternSlots).length}`));
    phrases.append(item);
  });
  band.append(phrases);

  const scene = el("div", "scene-strip");
  scene.append(el("strong", "", "Scene A/B"));
  scene.append(el("span", "", `${fixture.scenes.a.label} -> ${fixture.scenes.b.label}`));
  const slider = el("input", "crossfader");
  slider.type = "range";
  slider.min = "0";
  slider.max = "100";
  slider.value = String(Math.round(fixture.scenes.liveCrossfader.value * 100));
  scene.append(slider);
  scene.append(renderPill("live override", "hot"));
  band.append(scene);

  const mixer = el("div", "mixer-strip");
  mixer.append(el("strong", "", "Mixer Route"));
  mixer.append(el("span", "", fixture.mixer.routeSummary));
  fixture.mixer.returns.forEach((route) => mixer.append(renderPill(`${route.label} ${Math.round(route.amount * 100)}%`)));
  band.append(mixer);

  return band;
}

function renderHeader() {
  const activePhrase = fixture.phrases.find((phrase) => phrase.id === fixture.transport.activePhraseID);
  const queuedPhrase = fixture.phrases.find((phrase) => phrase.id === fixture.transport.queuedPhraseID);
  const transaction = fixture.performanceOverride.transaction;
  const header = el("header", "topbar");

  const status = el("div", "transport");
  status.append(renderPill(fixture.transport.state, "ok"));
  status.append(el("strong", "", `${fixture.transport.bpm} BPM`));
  status.append(el("span", "", `Step ${fixture.transport.step} / phrase step ${fixture.transport.phraseStep}`));
  status.append(el("span", "", `${activePhrase.label} -> ${queuedPhrase.label}`));
  header.append(status);

  const summary = el("div", "sounding-summary");
  summary.append(el("strong", "", "Sounding now"));
  summary.append(el("span", "", "drums, generated melody, audio loop, bass clip"));
  summary.append(renderPill(`${state.captureCount} captured clip${state.captureCount === 1 ? "" : "s"}`));
  const outcomeLabel = state.overrideVisible
    ? "transient changes active"
    : state.decisionOutcome === "kept"
      ? "kept to phrase/scene"
      : "authored state restored";
  summary.append(renderPill(outcomeLabel, state.overrideVisible ? "hot" : "ok"));
  header.append(summary);

  const decisions = el("div", "commit-actions");
  const keepCard = el("div", "decision-card");
  const keep = el("button", "keep", "Keep");
  keep.type = "button";
  keep.addEventListener("click", () => {
    state.overrideVisible = false;
    state.decisionOutcome = "kept";
    render();
  });
  keepCard.append(keep);
  keepCard.append(el("span", "decision-target", transaction.keep.targetLabel));
  if (state.decisionOutcome === "kept") {
    keepCard.append(el("strong", "decision-ack", transaction.keep.acknowledgement));
  }

  const discardCard = el("div", "decision-card");
  const discard = el("button", "discard", "Discard");
  discard.type = "button";
  discard.addEventListener("click", () => {
    state.overrideVisible = false;
    state.decisionOutcome = "discarded";
    render();
  });
  discardCard.append(discard);
  discardCard.append(el("span", "decision-target", transaction.discard.targetLabel));
  if (state.decisionOutcome === "discarded") {
    discardCard.append(el("strong", "decision-ack", transaction.discard.acknowledgement));
  }

  decisions.append(keepCard, discardCard);
  header.append(decisions);

  return header;
}

function exposeEvidence() {
  window.__happyAccidentWorkbench = {
    fixtureID: fixture.id,
    validation: validateScenario(fixture),
    firstViewportLabels: firstViewportLabels(fixture),
    interactionEvidence: {
      keepVisibleTarget: fixture.performanceOverride.transaction.keep.targetLabel,
      discardVisibleTarget: fixture.performanceOverride.transaction.discard.targetLabel,
      decisionOutcome: state.decisionOutcome,
      visibleAcknowledgement: state.decisionOutcome === "kept"
        ? fixture.performanceOverride.transaction.keep.acknowledgement
        : state.decisionOutcome === "discarded"
          ? fixture.performanceOverride.transaction.discard.acknowledgement
          : fixture.performanceOverride.transaction.source.label,
      captureButtons: fixture.captures.nextActions.map((action) => action.label),
      selectedTrackIDs: fixture.transport.selectedTrackIDs
    }
  };
}

function render() {
  const root = document.querySelector("#app");
  root.replaceChildren();
  root.append(renderHeader());

  const shell = el("main", "workbench-shell");
  const roster = el("aside", "panel roster");
  roster.append(el("h1", "", "Happy Accident Workbench"));
  roster.append(el("p", "muted", "Probe fixture only: one integrated view over tracks, source slots, capture, phrase, scene, performance, and mixer consequence."));
  fixture.tracks.forEach((track) => roster.append(renderTrack(track)));
  shell.append(roster);

  shell.append(renderSourceArea());
  shell.append(renderConsequenceRail());
  root.append(shell);
  root.append(renderArrangementBand());

  exposeEvidence();
}

render();
