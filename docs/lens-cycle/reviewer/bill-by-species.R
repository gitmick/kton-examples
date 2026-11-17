a <- commandArgs(trailingOnly=TRUE); d <- read.csv(a[1])
sp <- sort(unique(d$species)); col <- c("#c2571a","#1f7a6f","#7048a8"); names(col) <- sp
svg(a[2], 6.2, 4.3); par(mar=c(4.3,4.5,1.2,1.2))
plot(d$bill_length_mm, d$bill_depth_mm, type="n",
     xlab="Bill length (mm)", ylab="Bill depth (mm)", las=1, bty="l", cex.lab=.92, cex.axis=.86)
for (s in sp) { x <- d[d$species==s,]
  points(x$bill_length_mm, x$bill_depth_mm, pch=19, cex=.62, col=paste0(col[[s]],"99"))
  abline(lm(bill_depth_mm ~ bill_length_mm, x), col=col[[s]], lwd=2.4) }
legend("topright", bty="n", cex=.82, pch=19, col=col[sp],
  legend=sapply(sp, function(s){ x<-d[d$species==s,]; sprintf("%s   r = %+.3f", s, cor(x$bill_length_mm,x$bill_depth_mm)) }))
dev.off()
cat("analysis: bill depth ~ bill length, within species\n", file=a[3])
for (s in sp) { x <- d[d$species==s,]; ct <- cor.test(x$bill_length_mm,x$bill_depth_mm)
  cat(sprintf("%s: n=%d  r=%+.3f  p=%.3g\n", s, nrow(x), ct$estimate, ct$p.value), file=a[3], append=TRUE) }
