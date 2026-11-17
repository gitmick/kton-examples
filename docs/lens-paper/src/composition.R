a <- commandArgs(trailingOnly=TRUE); d <- read.csv(a[1])
tb <- table(d$island, d$species)
svg(a[2], 6.2, 3.6); par(mar=c(4.2,4.6,1.2,7.5), xpd=TRUE)
barplot(t(tb), beside=TRUE, las=1, col=c("#c2571a","#1f7a6f","#7048a8"), border=NA,
        ylab="Animals", cex.names=.86, cex.axis=.86, cex.lab=.92)
legend("topright", inset=c(-.22,0), bty="n", cex=.82, fill=c("#c2571a","#1f7a6f","#7048a8"), colnames(tb))
dev.off()
