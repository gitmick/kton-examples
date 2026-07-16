# the result is deterministic, but the test prints a VOLATILE session line (pid + wall-clock) that
# differs on every run - exactly the environment noise real test logs carry. Two runs are therefore
# NOT byte-identical (no L0), yet they agree once that line is normalized away (L1).
args <- commandArgs(trailingOnly = TRUE)
d <- read.csv(args[1])
cat(sprintf("session: pid=%d at=%s\n", Sys.getpid(), format(Sys.time())))
cat(sprintf("test-predict: yhat=%.4f PASS\n", mean(d$conc) * 1.5))
