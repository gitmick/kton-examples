# Stand-in for the NONMEM estimation step (NONMEM is proprietary and cannot run here), but this is a
# REAL, deterministic R computation over the analysis data - it actually executes and produces the
# bytes that get hashed. It prints a volatile NONMEM-style banner (stripped by the normalizer for the
# reproduction check, giving L1) followed by a deterministic parameter estimate.
args <- commandArgs(trailingOnly = TRUE)
d <- read.csv(args[1])
cat(sprintf("NONMEM 7.5.1 (stand-in)  pid=%d run at %s\n", Sys.getpid(), format(Sys.time())))  # volatile banner
cat("MINIMIZATION SUCCESSFUL\n")
cat(sprintf("OBJ=%.4f\nCL=%.4f\nV=%.4f\n", -2 * sum(log(d$DV[d$DV > 0])), mean(d$DV[d$DV > 0]), 10))
