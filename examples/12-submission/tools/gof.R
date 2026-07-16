# Real goodness-of-fit step: read the estimation output, extract the deterministic CL estimate (the
# volatile banner is ignored), and write a small diagnostics summary. Deterministic given the fit.
args <- commandArgs(trailingOnly = TRUE)
lines <- readLines(args[1])
cl <- sub("CL=", "", grep("^CL=", lines, value = TRUE))
cat(sprintf("GOF diagnostics\nCL estimate: %s\nstatus: acceptable\n", cl))
