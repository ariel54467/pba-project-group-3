# From the repository root: Rscript plot_milestone3.R
# Optional arguments: prepared CSV or RDS, then output PDF.
script <- grep("^--file=", commandArgs(FALSE), value = TRUE)
root <- dirname(normalizePath(sub("^--file=", "", script[1L])))
source(file.path(root, "R", "arena_helpers.R"))
args <- commandArgs(TRUE)
if (length(args) > 2L) stop("Usage: Rscript plot_milestone3.R [input] [output]")
input <- if (length(args)) args[1L] else file.path(root, "data/processed/arena_analysis.rds")
output <- if (length(args) == 2L) args[2L] else file.path(root, "outputs/milestone3.pdf")
aggregate_path <- file.path(root, "milestone3_figure_counts.csv")
if (file.exists(input)) {
  arena <- if (grepl("\\.csv$", input, ignore.case = TRUE)) read.csv(input) else readRDS(input)
  required <- c("focal_left", "focal_win", "is_tie", "model_pair", "week_utc")
  if (!all(required %in% names(arena)) || nrow(arena) == 0L || anyNA(arena[required])) {
    stop("Expected nonempty prepared Arena data with complete plotting variables.")
  }
  binary <- c("focal_left", "focal_win", "is_tie")
  if (!all(vapply(arena[binary], function(x) all(x %in% 0:1), logical(1))) ||
      any(arena$focal_win == 1L & arena$is_tie == 1L)) {
    stop("Invalid prepared outcome or position codes.")
  }
  side <- factor(arena$focal_left, levels = c(1, 0), labels = c("Left (A)", "Right (B)"))
  vote <- factor(ifelse(arena$is_tie == 1L, "Tie", ifelse(arena$focal_win == 1L,
                                                         "Focal win", "Opponent win")),
                 levels = c("Focal win", "Opponent win", "Tie"))
  counts <- table(vote, side)
  n <- colSums(counts)
  if (any(n == 0L)) stop("Both orientations are required.")
  strata <- orientation_table(arena, c("model_pair", "week_utc"))
  overlap <- strata$both_orientations
  tall <- as.data.frame(counts)
  names(tall) <- c("category", "group", "n")
  tall$figure <- "vote"
  tall$category <- as.character(tall$category)
  tall$group <- as.character(tall$group)
  tall <- tall[c("figure", "category", "group", "n")]
  tall <- rbind(tall, data.frame(
    figure = "overlap", category = rep(c("Pair-week groups", "Battles"), each = 2),
    group = rep(c("Both sides", "One side"), 2),
    n = c(sum(overlap), sum(!overlap), sum(strata$n[overlap]), sum(strata$n[!overlap]))
  ))
  write.csv(tall, aggregate_path, row.names = FALSE)
} else if (!length(args) && file.exists(aggregate_path)) {
  tall <- read.csv(aggregate_path)
} else {
  stop("Prepared data missing. Run scripts/prepare_arena.R first.")
}
votes <- subset(tall, figure == "vote")
votes$category <- factor(votes$category, levels = c("Focal win", "Opponent win", "Tie"))
votes$group <- factor(votes$group, levels = c("Left (A)", "Right (B)"))
counts <- xtabs(n ~ category + group, data = votes)
n <- colSums(counts)
if (any(n == 0L)) stop("Both orientations are required.")
share <- sweep(counts, 2L, n, "/") * 100
groups <- subset(tall, figure == "overlap")
groups$category <- factor(groups$category, levels = c("Pair-week groups", "Battles"))
groups$group <- factor(groups$group, levels = c("Both sides", "One side"))
overlap_counts <- xtabs(n ~ category + group, data = groups)
coverage <- 100 * prop.table(overlap_counts, 1L)

dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
pdf(output, width = 8.3, height = 10.8, title = "PBA Group 3 | Chatbot Arena")
layout(matrix(1:5), heights = c(0.94, 2.55, 1.55, 2.55, 1.55))
par(oma = c(1.4, 2, 1.6, 2), family = "sans", las = 1)
par(mar = c(0, 0, 0, 0))
plot.new()
text(0.5, 0.79, "PBA Group 3", font = 2, cex = 1.85)
text(0.5, 0.49, "Chatbot Arena", font = 2, cex = 1.85)
text(0.5, 0.21, "Examining how placement on the left relates to the chance of winning",
     cex = 0.94)
chart_margins <- c(3.15, 9, 3.2, 2)
colors <- c("#206B83", "#879AA4", "#D6BA76")

note <- function(title, lines) {
  par(mar = c(0, 2, 0.25, 2))
  plot.new()
  text(0.02, 0.92, title, adj = 0, font = 2, xpd = NA)
  wrapped <- unlist(lapply(lines, function(x) c(strwrap(x, width = 104), "")))
  text(0.02, seq(0.73, by = -0.108, length.out = length(wrapped)), wrapped,
       adj = 0, xpd = NA, cex = 1.06)
}

par(mar = chart_margins, xaxs = "i")
barplot(share, horiz = TRUE, xlim = c(0, 100), col = colors, border = NA,
        names.arg = sprintf("%s\n(n=%s)", names(n), format(n, big.mark = ",")))
title("Figure 1. Recorded votes by focal model position", line = 2.25)
mtext("Share of recorded battles (%)", side = 1, line = 2.25)
legend("top", legend = rownames(share), fill = colors, horiz = TRUE,
       bty = "n", inset = c(0, -0.12), xpd = NA, cex = 0.8)
gap <- share[1L, 1L] - share[1L, 2L]
note("What stands out", c(
  sprintf("The focal model won %.1f%% of battles on the left and %.1f%% of battles on the right (left minus right: %+.1f percentage points). Ties accounted for %.1f%% on the left and %.1f%% on the right.",
          share[1L, 1L], share[1L, 2L], gap, share[3L, 1L], share[3L, 2L]),
  "This shows how often users picked the focal model outright before accounting for the opponent and week. Retaining ties keeps the denominator aligned with the research question. The pooled gap is descriptive."
))

par(mar = chart_margins)
barplot(t(coverage), names.arg = c("Pair and week", "Battles"), horiz = TRUE, xlim = c(0, 100), col = colors[c(1, 3)], border = NA)
title("Figure 2. Overlap within model pair and calendar week", line = 2.25)
mtext("Share of groups or battles (%)", side = 1, line = 2.25)
legend("top", legend = colnames(coverage), fill = colors[c(1, 3)], horiz = TRUE,
       bty = "n", inset = c(0, -0.12), xpd = NA, cex = 0.8)
note("Why overlap matters", c(
  sprintf("The focal model appeared on both sides in %d of %d groups defined by model pair and week (%.1f%%). Those groups accounted for %s of %s battles (%.1f%%).",
          overlap_counts[1L, 1L], sum(overlap_counts[1L, ]), coverage[1L, 1L],
          format(overlap_counts[2L, 1L], big.mark = ","),
          format(sum(overlap_counts[2L, ]), big.mark = ","), coverage[2L, 1L]),
  "Groups with both orientations let us compare the same focal model against the same opponent in the same week. Groups with only one orientation cannot supply that comparison. Having both sides does not establish random assignment."
))
invisible(dev.off())
message("Wrote ", output)
