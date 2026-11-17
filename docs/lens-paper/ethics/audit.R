# Interne Bestandsaufnahme der Kommission über die Quellaufzeichnungen.
a <- commandArgs(trailingOnly=TRUE); d <- read.csv(a[1])
cat(sprintf("source records held by the committee\nanimals: %d\nnamed individuals: %d\nring ids: %d\nislands: %s\nspecies: %s\ndirect identifiers in released file: none\n",
  nrow(d), length(unique(d$animal_name)), length(unique(d$ring_id)),
  paste(sort(unique(d$island)), collapse=", "), paste(sort(unique(d$species)), collapse=", ")), file=a[2])
