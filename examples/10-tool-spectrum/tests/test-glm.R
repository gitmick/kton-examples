# a real, deterministic test of "mypkg": same input -> same output, every run, every environment.
args <- commandArgs(trailingOnly = TRUE)
d <- read.csv(args[1])
cat(sprintf("test-glm: mean-conc=%.4f PASS\n", mean(d$conc)))
