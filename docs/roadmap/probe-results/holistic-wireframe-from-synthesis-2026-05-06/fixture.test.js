import assert from "node:assert/strict";
import test from "node:test";
import {
  firstViewportLabels,
  scenarioInvariants,
  selectedTracks,
  validateScenario,
  workbenchFixture
} from "./fixture.js";

test("seeded scenario satisfies holistic fixture invariants", () => {
  const result = validateScenario(workbenchFixture);
  assert.equal(result.ok, true, result.failures.join(", "));
  assert.deepEqual(
    Object.values(scenarioInvariants(workbenchFixture)).every(Boolean),
    true
  );
});

test("first viewport names sounding, capture, transient, phrase, buffer, and route state", () => {
  const labels = firstViewportLabels(workbenchFixture).join(" | ");
  assert.match(labels, /Happy Accident Workbench/);
  assert.match(labels, /NOW Intro Loop/);
  assert.match(labels, /NEXT Breakdown Cue/);
  assert.match(labels, /Captured take 032/);
  assert.match(labels, /Capture Generated Clip/);
  assert.match(labels, /Capture Loop To Shared Buffer/);
  assert.match(labels, /Transient until kept/);
  assert.match(labels, /Amber Voice 4-bar loop/);
  assert.match(labels, /Drums -> Drum Bus -> Master/);
});

test("transient overlay target set matches selected tracks by stable identity", () => {
  const selectedIDs = selectedTracks(workbenchFixture).map((track) => track.id);
  assert.deepEqual(selectedIDs, workbenchFixture.performanceOverride.selectedTrackIDs);
  assert.equal(workbenchFixture.performanceOverride.owner, "runtime-session");
  assert.match(workbenchFixture.performanceOverride.keepTarget, /active phrase cells/);
  assert.match(workbenchFixture.performanceOverride.discardTarget, /clear session overlay/);
});

test("capture and buffer identities stay separate from generator recipe identity", () => {
  const captured = workbenchFixture.captures.generatedClipHistory[0];
  const buffer = workbenchFixture.sharedAudioBuffer;
  assert.notEqual(captured.id, captured.sourceGeneratorID);
  assert.notEqual(captured.id, buffer.id);
  assert.equal(captured.owner, "document-clip-pool");
  assert.equal(buffer.owner, "runtime-audio-buffer");
});
