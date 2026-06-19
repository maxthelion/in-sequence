# Kit Step Grid: 16 Steps + Bar Pager, Names To The Left

Raw product-owner bugs:

> drum kit step sequencer should be limited to 16 steps and use the same
> underlying primitives as the normal track view. We need to import a bar select
> mechanism to page through the steps.
> Let's have the name of each drum part to the left, rather than on top to show
> more rows of drums.

Interpretation for build:

- The kit matrix step grid is **fixed at 16 columns** with a **bar pager**
  (1–16 / 17–32 …) to page through bars. Remove the 16/32 width toggle.
- Reuse the **same step primitives as the normal track view**. The bar pager
  already exists in the single-part editor — bring it up to the matrix.
- Each part **name sits to the LEFT** of its row (not on top) so more part rows
  fit.
</content>
