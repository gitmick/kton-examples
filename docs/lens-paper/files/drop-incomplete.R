a <- commandArgs(trailingOnly=TRUE); d <- read.csv(a[1])
d <- d[complete.cases(d[,c("bill_length_mm","bill_depth_mm","species")]),]
write.csv(d, a[2], row.names=FALSE)
