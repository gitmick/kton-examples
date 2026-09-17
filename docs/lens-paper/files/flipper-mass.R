a <- commandArgs(trailingOnly=TRUE); d <- read.csv(a[1]); d <- d[complete.cases(d[,c("flipper_length_mm","body_mass_g")]),]
svg(a[2], 6.2, 4.3); par(mar=c(4.3,4.8,1.2,1.2))
plot(d$flipper_length_mm, d$body_mass_g, pch=19, cex=.62, col="#40506699",
     xlab="Flipper length (mm)", ylab="Body mass (g)", las=1, bty="l", cex.lab=.92, cex.axis=.86)
abline(lm(body_mass_g ~ flipper_length_mm, d), col="#1f4e79", lwd=2.4)
legend("topleft", bty="n", cex=.84, legend=sprintf("r = %+.3f", cor(d$flipper_length_mm,d$body_mass_g)))
dev.off()
