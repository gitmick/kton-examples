a <- commandArgs(trailingOnly=TRUE); v <- read.csv(a[1], stringsAsFactors=FALSE)
# one row per reviewed foton: approvalsByPeople, rejects, reviewers, fourEyesPeopleOnly
r <- v[1, ]; ok <- r$fourEyesPeopleOnly == "yes"
svg(a[2], 6.2, 2.6); par(mar=c(0,0,0,0)); plot.new(); plot.window(c(0,1), c(0,1))
rect(0.02, 0.05, 0.98, 0.95, border="#d5d9e0", col="#fbfcfd")
text(0.06, 0.80, "Review FS-2026-04 · rule four-eyes.rq, anchored before anyone reviewed", adj=0, cex=.82, col="#4b5563")
text(0.06, 0.58, if (ok) "Valid: four eyes, people only" else "Not valid", adj=0, cex=1.35, font=2,
     col=if (ok) "#1f6f5c" else "#b42318")
text(0.06, 0.38, sprintf("%d approvals by declared people · %d rejects", r$approvalsByPeople, r$rejects), adj=0, cex=.9)
text(0.06, 0.20, "checked in Oxigraph over the signed records; nobody approved their own work", adj=0, cex=.78, col="#6b7280")
invisible(dev.off())
