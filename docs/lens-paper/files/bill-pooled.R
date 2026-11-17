a <- commandArgs(trailingOnly=TRUE); d <- read.csv(a[1])
ct <- cor.test(d$bill_length_mm, d$bill_depth_mm)
svg(a[2], 6.2, 4.3); par(mar=c(4.3,4.5,1.2,1.2))
plot(d$bill_length_mm, d$bill_depth_mm, pch=19, cex=.62, col="#40506699",
     xlab="Bill length (mm)", ylab="Bill depth (mm)", las=1, bty="l", cex.lab=.92, cex.axis=.86)
abline(lm(bill_depth_mm ~ bill_length_mm, d), col="#1f4e79", lwd=2.4)
legend("topright", bty="n", cex=.84, legend=sprintf("r = %+.3f", ct$estimate))
dev.off()
cat(sprintf("analysis: bill depth ~ bill length, all animals pooled\nn: %d\nr: %+.3f\np: %.3g\n",
    nrow(d), ct$estimate, ct$p.value), file=a[3])
