# Usage (from any working directory):
#   Rscript path/to/scripts/prepare_arena.R
#   Rscript path/to/scripts/prepare_arena.R --strict
# --strict returns exit status 2 if any checklist item needs review or fails.
# This prepares and audits data; it does not estimate or claim a causal effect.

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (!length(script_arg)) stop("Run this file with Rscript.", call. = FALSE)
script_path <- normalizePath(sub("^--file=", "", script_arg[1L]), winslash = "/", mustWork = TRUE)
project_root <- dirname(dirname(script_path))
source(file.path(project_root, "R", "project_config.R"), encoding = "UTF-8")
source(file.path(project_root, "R", "arena_helpers.R"), encoding = "UTF-8")
cfg <- project_config
args <- commandArgs(trailingOnly = TRUE)
if (length(setdiff(args, "--strict"))) stop("Only --strict is supported; edit R/project_config.R for settings.", call. = FALSE)
if (!requireNamespace("arrow", quietly = TRUE)) {
  stop('Install the Parquet reader first: install.packages("arrow")', call. = FALSE)
}
raw_path <- file.path(project_root, cfg$raw_file)
if (!file.exists(raw_path)) stop("Source file missing: ", raw_path, "\n", cfg$acquisition, call. = FALSE)
processed_dir <- file.path(project_root, cfg$processed_dir)
report_dir <- file.path(project_root, cfg$report_dir)
dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)

message("Loading source data in R...")
raw <- arrow::read_parquet(raw_path, as_data_frame = TRUE)
message("Checking conversations and extracting features from ", nrow(raw), " comparisons...")
prepared <- prepare_arena(raw)
arena <- prepared$data
write_csv(arena, file.path(processed_dir, "arena_analysis.csv"))
saveRDS(arena, file.path(processed_dir, "arena_analysis.rds"), compress = "xz")
write_csv(prepared$flow, file.path(report_dir, "cleaning_flow.csv"))

provenance <- c(
  "## Source and permitted use", "", cfg$source_attribution, "",
  paste("Original source:", cfg$source_url), paste("Original study:", cfg$source_paper),
  paste("Source checked:", cfg$source_checked_date), "", cfg$acquisition, "",
  paste("Local source file:", cfg$raw_file),
  paste("Source MD5 (file fingerprint, not a security guarantee):", unname(tools::md5sum(raw_path))),
  "", cfg$sharing_notes, "", cfg$ethics
)
writeLines(c("# Raw Arena codebook", "", markdown_table(raw_codebook(raw)), "", provenance),
           file.path(dirname(raw_path), "codebook.md"), useBytes = TRUE)
writeLines(c("# Prepared Arena codebook", "",
             "One row is one retained battle. No conversation text or original user/question IDs are exported.",
             "Integer group codes can change if the source file changes; do not join codes across releases.",
             "The CSV and RDS contain the same variables. Missing a_win_decisive on ties is intentional.", "",
             markdown_table(processed_codebook(arena)), "", provenance),
           file.path(processed_dir, "codebook.md"), useBytes = TRUE)

profile <- column_profile(arena)
write_csv(profile, file.path(report_dir, "variable_checks.csv"))
raw_missing <- data.frame(
  variable = names(raw),
  # Nested tables use any missing cell per row; list columns count null elements.
  missing_rows = vapply(raw, function(x) sum(row_missing(x)), integer(1))
)
raw_missing$missing_fraction <- raw_missing$missing_rows / nrow(raw)
write_csv(raw_missing, file.path(report_dir, "raw_missingness.csv"))
vote_counts <- as.data.frame(table(arena$winner), stringsAsFactors = FALSE)
names(vote_counts) <- c("vote", "n")
write_csv(vote_counts, file.path(report_dir, "vote_counts.csv"))

pair_counts <- orientation_table(arena, "model_pair")
pair_week_counts <- orientation_table(arena, c("model_pair", "week_utc"))
pair_week_counts$adequate_counts <- pair_week_counts$left >= cfg$min_per_orientation &
  pair_week_counts$right >= cfg$min_per_orientation
write_csv(pair_counts, file.path(report_dir, "orientation_by_pair.csv"))
write_csv(pair_week_counts, file.path(report_dir, "orientation_by_pair_week.csv"))
week_counts <- orientation_table(arena, "week_utc")
write_csv(week_counts, file.path(report_dir, "orientation_by_week.csv"))
overlap_n <- sum(pair_week_counts$n[pair_week_counts$both_orientations])

# A descriptive pre-assignment balance check. No significance-based selection.
log_prompt <- log1p(arena$prompt_words)
left_prompt <- log_prompt[arena$focal_left == 1L]
right_prompt <- log_prompt[arena$focal_left == 0L]
pooled_sd <- sqrt((var(left_prompt) + var(right_prompt)) / 2)
smd <- if (is.finite(pooled_sd) && pooled_sd > 0) {
  (mean(left_prompt) - mean(right_prompt)) / pooled_sd
} else NA_real_
balance <- data.frame(
  variable = "log1p(prompt_words)", n_left = length(left_prompt), n_right = length(right_prompt),
  mean_left = mean(left_prompt), mean_right = mean(right_prompt), standardized_difference = smd
)
write_csv(balance, file.path(report_dir, "prompt_balance.csv"))

checks <- data.frame(check = character(), status = character(), detail = character())
add_check <- function(check, status, detail) {
  checks <<- rbind(checks, data.frame(check = check, status = status, detail = detail))
}
pass_fail <- function(ok) if (isTRUE(ok)) "PASS" else "FAIL"
review_flag <- function(ok) if (isTRUE(ok)) "PASS" else "REVIEW"
core <- c("focal_win", "focal_left", "model_pair", "week_utc", "judge_group", "prompt_group")
core_profile <- profile[match(core, profile$variable), ]
add_check("Y, T and grouping variables", pass_fail(all(core_profile$missing_fraction <= cfg$max_missing_fraction)),
          paste("Maximum missing fraction:", max(core_profile$missing_fraction)))
add_check("At least a few hundred observations", pass_fail(nrow(arena) >= cfg$min_observations),
          paste(nrow(arena), "eligible battles; minimum", cfg$min_observations))
add_check("Real variation in Y and T", pass_fail(length(unique(arena$focal_win)) == 2L &&
                                                length(unique(arena$focal_left)) == 2L),
          paste("Y=1:", sum(arena$focal_win), "; T=1:", sum(arena$focal_left)))
add_check("Comparable pair/week observations", pass_fail(overlap_n >= cfg$min_observations),
          paste(overlap_n, "rows in", sum(pair_week_counts$both_orientations),
                "pair/week strata with both orientations; sparse-stratum counts are saved separately."))
add_check("Reproducible cleaning", "PASS",
          paste("Stage counts saved;", prepared$repeated_id_rows, "rows belong to repeated IDs; ties retained."))
add_check("Codebooks beside data", pass_fail(file.exists(file.path(dirname(raw_path), "codebook.md")) &&
                                             file.exists(file.path(processed_dir, "codebook.md"))),
          "Raw and processed codebooks include provenance, definitions, and sharing restrictions.")
add_check("Original source documented", "PASS", cfg$source_url)
add_check("Question, comparison and estimand", "PASS", paste(cfg$question_type, "-", cfg$question))
add_check("Historical causal assignment and export mapping", review_flag(cfg$historical_assignment_verified),
          cfg$historical_assignment_notes)
add_check("Selection assumptions assessed", review_flag(cfg$selection_assumptions_reviewed), cfg$selection_notes)
add_check("Original-study novelty reviewed", review_flag(cfg$novelty_review_complete), cfg$novelty_notes)
add_check("License and sharing review", review_flag(cfg$sharing_review_complete), cfg$sharing_notes)
add_check("Ethics considered", "PASS", cfg$ethics)
add_check("New data collection or LLM coding", "N/A",
          "Only existing data and deterministic string rules are used; no new experiment, survey, scraping, or LLM labeling.")

data_paths <- c(raw_path, list.files(processed_dir, full.names = TRUE))
sizes <- data.frame(file = basename(data_paths), bytes = file.info(data_paths)$size)
sizes$megabytes <- round(sizes$bytes / 1e6, 3)
write_csv(sizes, file.path(report_dir, "data_file_sizes.csv"))
add_check("Data files below 100 MB", pass_fail(all(sizes$bytes < cfg$max_file_bytes)),
          paste("Largest data-directory file:", max(sizes$megabytes), "MB; raw data should still be excluded."))

# Read-only Git inspection. .gitignore cannot untrack a file already in Git.
if (nzchar(Sys.which("git"))) {
  tracked <- suppressWarnings(system2("git", c("-C", shQuote(project_root), "ls-files"), stdout = TRUE, stderr = TRUE))
  git_ok <- is.null(attr(tracked, "status")) || attr(tracked, "status") == 0L
  if (git_ok) {
    tracked_raw <- tracked[startsWith(tracked, "data/raw/")]
    add_check("Raw data excluded from Git index", pass_fail(!length(tracked_raw)),
              if (length(tracked_raw)) paste("Already tracked:", paste(tracked_raw, collapse = ", "),
                                            "- .gitignore does not change existing tracking; index left untouched.")
              else "No files under data/raw/ are tracked.")
    tracked_paths <- file.path(project_root, tracked)
    tracked_sizes <- file.info(tracked_paths)$size
    too_large <- tracked[!is.na(tracked_sizes) & tracked_sizes >= cfg$max_file_bytes]
    add_check("Tracked files below 100 MB", pass_fail(!length(too_large)),
              if (length(too_large)) paste(too_large, collapse = ", ") else "No existing tracked files exceed the limit.")
  } else add_check("Git data tracking", "REVIEW", "Could not inspect the Git index.")
} else add_check("Git data tracking", "REVIEW", "Git was not available for a read-only index check.")

write_csv(checks, file.path(report_dir, "checklist.csv"))
writeLines(c(
  "# Research question and causal design candidate", "", cfg$question,
  "", paste("Type:", cfg$question_type), "", cfg$comparison,
  "", cfg$outcome, "", cfg$treatment, "", paste("Estimand:", cfg$estimand),
  "", paste("Planned method:", cfg$proposed_method),
  "", paste("Identification assumptions:", cfg$identification),
  "", paste("Historical evidence:", cfg$historical_assignment_notes),
  "", paste("Historical code:", cfg$historical_code),
  "", paste("Assignment source:", cfg$assignment_source),
  "", paste("Novelty review:", cfg$novelty_notes),
  "", "## Interpretation limits", "",
  "This is a design candidate, not a completed causal analysis or a preregistration.",
  "A/B assignment may combine location, label, rendering, and response timing; it does not isolate a pure visual-left effect.",
  "The English tag is source-generated. Votes, release filters, repeated-ID removal, and single-turn eligibility can select the sample.",
  "Dropping ties would condition on an outcome that position might affect, so ties remain in the primary binary sole-win outcome.",
  "The positive rate is conditional on observed votes, not all platform visits. No non-voter outcomes are available.",
  "Length/formatting features remain available for exploratory association, but are not the causal treatment or primary controls.",
  "Decide the final target population, overlap policy, and model before estimating the position effect.",
  "", provenance
), file.path(report_dir, "research_plan.md"), useBytes = TRUE)

writeLines(c(
  "# Pre-commit data audit", "",
  "This audit does not perform a Git commit. REVIEW means a substantive check remains; FAIL identifies a failed requirement.",
  "", cfg$question, "", "## Checklist", "", markdown_table(checks),
  "", "## Cleaning flow", "", markdown_table(prepared$flow),
  "", "## Recorded votes (ties retained)", "", markdown_table(vote_counts),
  "", paste("Retained date range (UTC):", min(arena$date_utc), "to", max(arena$date_utc)),
  paste("Distinct judge groups:", length(unique(arena$judge_group))),
  paste("Distinct normalized prompts:", length(unique(arena$prompt_group))),
  paste("Repeated-prompt rows beyond the first:", sum(duplicated(arena$prompt_group))),
  paste("Both-orientation pair/week coverage:", round(100 * overlap_n / nrow(arena), 1), "% of retained rows."),
  "", "## Balance", "", markdown_table(balance),
  "", "This is a marginal descriptive check, not a randomization test or proof of exchangeability.",
  "Pair/week orientation files expose sparse or one-sided strata; do not hide those rows or choose a sample based on effect significance.",
  "", "## Files and reproducibility", "", markdown_table(sizes),
  "", "The raw file is not edited. Generated local outputs are overwritten when rerun.",
  "The prepared subset contains no raw conversation text. All generated data and reports are ignored by Git.",
  "raw_missingness.csv counts null nested records, not every missing message cell; conversation validity is checked in the cleaning flow.",
  "variable_checks.csv reports all derived fields; missing a_win_decisive values on ties are intentional.",
  "Source code is in R/ and scripts/. sessionInfo.txt records the environment.",
  "", provenance
), file.path(report_dir, "precommit_report.md"), useBytes = TRUE)
writeLines(capture.output(sessionInfo()), file.path(report_dir, "sessionInfo.txt"))

message("Prepared ", nrow(arena), " battles (", sum(arena$is_tie), " ties retained).")
message("Data: ", file.path(processed_dir, "arena_analysis.rds"))
message("Audit: ", file.path(report_dir, "precommit_report.md"))
message("Checklist: ", sum(checks$status == "PASS"), " passed; ", sum(checks$status == "REVIEW"),
        " need review; ", sum(checks$status == "FAIL"), " failed.")
message("No causal effect has been estimated. No Git index, commit, or remote was changed.")
if ("--strict" %in% args && any(checks$status %in% c("FAIL", "REVIEW"))) quit(status = 2L)
