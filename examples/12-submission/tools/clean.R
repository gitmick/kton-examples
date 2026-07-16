# Real data-preparation step: read the raw dataset, add the MDV column NONMEM needs, write analysis.csv.
args <- commandArgs(trailingOnly = TRUE)
d <- read.csv(args[1])
d$MDV <- as.integer(d$DV == 0)
write.csv(d, args[2], row.names = FALSE, quote = FALSE)
