a <- commandArgs(trailingOnly=TRUE)
d <- read.csv(a[1], check.names=FALSE)
d$animal_name <- NULL; d$ring_id <- NULL
write.csv(d, a[2], row.names=FALSE, na="NA", quote=FALSE)
