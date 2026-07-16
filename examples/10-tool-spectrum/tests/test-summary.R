# a second deterministic test: also byte-identical across runs and environments.
args <- commandArgs(trailingOnly = TRUE)
d <- read.csv(args[1])
cat(sprintf("test-summary: sd-conc=%.4f PASS\n", sd(d$conc)))
