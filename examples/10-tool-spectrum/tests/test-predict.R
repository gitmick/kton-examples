# the result is deterministic, but the test prints a VOLATILE session line (pid + wall-clock) that
# differs on every run - exactly the environment noise real test logs carry. Two runs are therefore
# NOT byte-identical (no L0), yet they agree once that line is normalized away (L1).
args <- commandArgs(trailingOnly = TRUE)
nonce <- function() {  # 64 random bits, so two runs differ by construction (kton-review E7)
  con <- file("/dev/urandom", "rb", raw = TRUE); on.exit(close(con))
  paste(as.character(readBin(con, "raw", 8)), collapse = "")
}
d <- read.csv(args[1])
cat(sprintf("session: pid=%d at=%s nonce=%s\n", Sys.getpid(), format(Sys.time()), nonce()))
cat(sprintf("test-predict: yhat=%.4f PASS\n", mean(d$conc) * 1.5))
