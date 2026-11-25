# One small analysis: do whales follow the plankton? Simulated data, one figure.
# The figure is written as SVG text, not through a graphics device: a device's bytes depend on the
# machine's cairo and fonts, and a rerun anywhere has to give the same bytes (L0).
set.seed(1811)
month <- 1:24
plankton <- round(50 + 40 * sin(2 * pi * (month - 3) / 12) + rnorm(24, 0, 6), 1)
whales <- rpois(24, lambda = pmax(0.5, c(2, head(plankton, -1)) / 12))

f <- function(v) sprintf("%.1f", v)
L <- 60; R <- 444; T <- 16; B <- 250                       # the plot area in a 504 x 302 figure
pmax_ <- 20 * ceiling(max(plankton) / 20); wmax <- max(2, 2 * ceiling(max(whales) / 2))
x <- function(m) L + (m - 1) / 23 * (R - L)
yp <- function(v) B - v / pmax_ * (B - T)
yw <- function(v) B - v / wmax * (B - T)
pticks <- seq(0, pmax_, by = 20); wticks <- seq(0, wmax, by = 2); mticks <- c(1, 6, 12, 18, 24)

svg <- c(
  '<svg xmlns="http://www.w3.org/2000/svg" width="504" height="302" viewBox="0 0 504 302" font-family="sans-serif" font-size="11">',
  '<rect width="504" height="302" fill="#ffffff"/>',
  '<g stroke="#264653" stroke-width="6">',
  sprintf('<line x1="%s" y1="%s" x2="%s" y2="%s"/>', f(x(month)), f(B), f(x(month)), f(yw(whales))),
  '</g>',
  sprintf('<polyline fill="none" stroke="#2a9d8f" stroke-width="2" points="%s"/>',
          paste(f(x(month)), f(yp(plankton)), sep = ",", collapse = " ")),
  '<g stroke="#333333" fill="none">',
  sprintf('<path d="M%s %s H%s M%s %s V%s M%s %s V%s"/>', f(L), f(B), f(R), f(L), f(T), f(B), f(R), f(T), f(B)),
  '</g>',
  '<g fill="#333333" text-anchor="middle">',
  sprintf('<text x="%s" y="%s">%d</text>', f(x(mticks)), f(B + 16), mticks),
  sprintf('<text x="%s" y="%s">month</text>', f((L + R) / 2), f(B + 36)),
  '</g>',
  '<g fill="#333333" text-anchor="end">',
  sprintf('<text x="%s" y="%s">%d</text>', f(L - 6), f(yp(pticks) + 4), pticks),
  '</g>',
  '<g fill="#333333" text-anchor="start">',
  sprintf('<text x="%s" y="%s">%d</text>', f(R + 6), f(yw(wticks) + 4), wticks),
  '</g>',
  sprintf('<text x="16" y="%s" fill="#2a9d8f" text-anchor="middle" transform="rotate(-90 16 %s)">plankton density</text>',
          f((T + B) / 2), f((T + B) / 2)),
  sprintf('<text x="490" y="%s" fill="#264653" text-anchor="middle" transform="rotate(90 490 %s)">whale sightings</text>',
          f((T + B) / 2), f((T + B) / 2)),
  '</svg>')
con <- file("whales.svg", "wb"); writeLines(svg, con); close(con)
