# A real, deterministic unit test of the "pmxtools" package. Reads a fixture, prints a PASS line.
# If a second arg "banner" is given, it first prints a VOLATILE session line (like a NONMEM/R banner),
# so that test's two runs are not byte-identical and only match after the normalizer strips it (L1).
args <- commandArgs(trailingOnly = TRUE)
d <- read.csv(args[1])
if (length(args) >= 2 && args[2] == "banner")
  cat(sprintf("session: pid=%d at=%s\n", Sys.getpid(), format(Sys.time())))
cat(sprintf("%s: value=%.4f PASS\n", tools::file_path_sans_ext(basename(args[1])), sum(d$x)))
