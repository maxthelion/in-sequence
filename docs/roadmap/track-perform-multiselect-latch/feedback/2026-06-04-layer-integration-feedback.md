# Track Perform Layer Integration Feedback

- recorded: 2026-06-04 16:38 BST
- source: product-owner screenshot feedback
- feature: Track Perform Multi-Select And Latch
- current issue: post-merge UI regression / wrong integration shape

## Feedback

The Track Perform rework moved Fill and Repeat into a top-level Perform Layer area, but it did not integrate them with the layer UI that was already present. The resulting surface appears to have replaced the existing layers with isolated Pattern, Fill, and Repeat buttons.

That is not the intended shape. Fill and Repeat should be integrated into the existing layer grammar, preserving the other available layers and the existing UI model. They should not become a separate mode strip that discards the rest of the layer system.

## Expected Direction

- Preserve the existing layer UI and its existing layers.
- Add Fill and Repeat as additional/selectable layers within that same grammar.
- Do not remove or hide other layers as a side effect of adding performance layers.
- The Track Perform card content should respond to the active layer, but the layer selector itself should remain coherent with the existing app-wide track/layer model.
- The fix should avoid creating a parallel layer system just for Track Perform.

## Process Note

This is a post-merge feature-follow-up. The prior correction captured the right high-level intent, but the implementation carried it through too narrowly and lost integration with existing UI context.
