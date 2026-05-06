import assert from "node:assert/strict";
import test from "node:test";
import {
  bufferCaptureOwnership,
  firstViewportLabels,
  performanceTransitionLabels,
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

test("performance transaction models keep and discard owner transitions explicitly", () => {
  const transaction = workbenchFixture.performanceOverride.transaction;
  const labels = performanceTransitionLabels(workbenchFixture);

  assert.equal(labels.sourceOwner, "runtime-session");
  assert.deepEqual(transaction.keep.destinationOwners, ["document-phrase-cells", "document-scene-state"]);
  assert.deepEqual(transaction.discard.restorationOwners, [
    "document-phrase-cells",
    "document-scene-state",
    "audio-graph-mixer-state"
  ]);
  assert.match(labels.keepTarget, /active phrase cells \+ Scene A\/B blend/);
  assert.match(labels.keepAcknowledgement, /committed to NOW Intro Loop phrase cells and Scene A\/B blend/);
  assert.match(labels.discardTarget, /authored phrase\/scene\/mixer restore point/);
  assert.match(labels.discardAcknowledgement, /session overlay cleared and authored phrase\/scene\/mixer restored/);
});

test("capture and buffer identities stay separate from generator recipe identity", () => {
  const captured = workbenchFixture.captures.generatedClipHistory[0];
  const buffer = workbenchFixture.sharedAudioBuffer;
  const ownership = bufferCaptureOwnership(workbenchFixture);

  assert.notEqual(captured.id, captured.sourceGeneratorID);
  assert.notEqual(captured.id, buffer.id);
  assert.equal(captured.owner, "document-clip-pool");
  assert.equal(buffer.owner, "runtime-audio-buffer");
  assert.equal(ownership.runtimeOwner, "runtime-audio-buffer");
  assert.equal(ownership.documentOwner, "document-buffer-reference");
  assert.match(ownership.runtimeLabel, /sample memory/);
  assert.match(ownership.documentLabel, /buffer ID, loop range, and slice cues/);
});

class FakeElement {
  constructor(tagName) {
    this.tagName = tagName.toLowerCase();
    this.children = [];
    this.className = "";
    this.dataset = {};
    this.style = {};
    this.eventListeners = {};
    this._textContent = "";
    this.classList = {
      add: (...names) => {
        const existing = this.className ? this.className.split(/\s+/) : [];
        this.className = [...new Set([...existing, ...names])].join(" ");
      }
    };
  }

  append(...nodes) {
    nodes.forEach((node) => {
      if (node !== undefined && node !== null) {
        this.children.push(node);
      }
    });
  }

  replaceChildren(...nodes) {
    this.children = [];
    this.append(...nodes);
  }

  addEventListener(eventName, handler) {
    this.eventListeners[eventName] = handler;
  }

  click() {
    this.eventListeners.click?.();
  }

  set textContent(value) {
    this._textContent = value;
  }

  get textContent() {
    return [
      this._textContent,
      ...this.children.map((child) => child.textContent ?? String(child))
    ].join(" ");
  }
}

function findElements(root, predicate, results = []) {
  if (predicate(root)) {
    results.push(root);
  }
  root.children.forEach((child) => {
    if (child instanceof FakeElement) {
      findElements(child, predicate, results);
    }
  });
  return results;
}

async function renderAppInstance(name) {
  const root = new FakeElement("div");
  globalThis.document = {
    createElement: (tagName) => new FakeElement(tagName),
    querySelector: (selector) => {
      assert.equal(selector, "#app");
      return root;
    }
  };
  globalThis.window = {};

  await import(`./app.js?fixture-test=${name}-${Date.now()}`);
  return { root, window: globalThis.window };
}

function clickButton(root, label) {
  const button = findElements(root, (node) => node.tagName === "button" && node.textContent.trim() === label)[0];
  assert.ok(button, `Expected visible ${label} button`);
  button.click();
}

test("rendered workbench exposes visible keep target and committed acknowledgement", async () => {
  const { root, window } = await renderAppInstance("keep");

  assert.match(root.textContent, /Keep target: active phrase cells \+ Scene A\/B blend/);
  assert.match(root.textContent, /Discard target: authored phrase\/scene\/mixer restore point/);

  clickButton(root, "Keep");

  assert.match(root.textContent, /Kept: committed to NOW Intro Loop phrase cells and Scene A\/B blend/);
  assert.doesNotMatch(root.textContent, /Discarded: session overlay cleared/);
  assert.equal(window.__happyAccidentWorkbench.interactionEvidence.decisionOutcome, "kept");
});

test("rendered workbench exposes visible discard target and restored acknowledgement", async () => {
  const { root, window } = await renderAppInstance("discard");

  assert.match(root.textContent, /Keep target: active phrase cells \+ Scene A\/B blend/);
  assert.match(root.textContent, /Discard target: authored phrase\/scene\/mixer restore point/);

  clickButton(root, "Discard");

  assert.match(root.textContent, /Discarded: session overlay cleared and authored phrase\/scene\/mixer restored/);
  assert.doesNotMatch(root.textContent, /Kept: committed to NOW Intro Loop/);
  assert.equal(window.__happyAccidentWorkbench.interactionEvidence.decisionOutcome, "discarded");
});
