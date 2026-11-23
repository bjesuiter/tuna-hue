# Website color

Author colors in OKLCH, including palette tokens, gradient interpolation, and shader palettes. Convert shader colors to Display P3 only at WebGL output. Use the CSS scene when that output is unavailable.

# Website layout

Use one framed surface per content group. Keep content inside cards unframed, including code blocks and screenshot wrappers. The agent prompt in the Install page’s “Let your agent build from source” section may have its own border inside the card. Use spacing and typography for hierarchy. Keep visible focus indicators on interactive elements.

# Website tokens

Take spacing, type sizes, weights, radii and page/card padding from the tokens in `SiteLayout.astro` (`--space-*`, `--text-*`, `--weight-*`, `--page-block`, `--card-pad`). Use the global `h1`–`h3` styles, `.page-content` for a page's top-level wrapper, `.card` for framed surfaces, `.label` for small mono labels, and `.pill` for every pill-shaped button or link.
