# One small analysis: do whales follow the plankton? Simulated data, one figure.
set.seed(1811)
month <- 1:24
plankton <- round(50 + 40 * sin(2 * pi * (month - 3) / 12) + rnorm(24, 0, 6), 1)
whales <- rpois(24, lambda = pmax(0.5, c(2, head(plankton, -1)) / 12))
svg("whales.svg", width = 7, height = 4.2, family = "sans")
par(mar = c(4, 4, 1, 4))
plot(month, plankton, type = "l", lwd = 2, col = "#2a9d8f",
     xlab = "month", ylab = "plankton density", bty = "n")
par(new = TRUE)
plot(month, whales, type = "h", lwd = 6, col = "#264653", axes = FALSE, xlab = "", ylab = "")
axis(4); mtext("whale sightings", side = 4, line = 2.5)
invisible(dev.off())
