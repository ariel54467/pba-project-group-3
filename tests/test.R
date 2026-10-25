
# Run: Rscript tests/test.R
# Tests use synthetic data and never read or print real conversation content.
script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
root <- dirname(dirname(normalizePath(sub("^--file=", "", script_arg[1L]), winslash = "/")))
source(file.path(root, "R", "arena_helpers.R"), encoding = "UTF-8")

# Swapping slots preserves the focal model and winner but reverses treatment.
original <- derive_position("alpha", "beta", "model_a")
swapped <- derive_position("beta", "alpha", "model_b")
stopifnot(original$focal_model == swapped$focal_model,
          original$model_pair == swapped$model_pair,
          original$focal_win == swapped$focal_win,
          original$focal_left == 1L, swapped$focal_left == 0L)
ties <- derive_position(c("alpha", "beta"), c("beta", "alpha"), c("tie", "tie (bothbad)"))
stopifnot(all(ties$focal_win == 0L), all(ties$is_tie == 1L),
          all(is.na(ties$a_win_decisive)), identical(ties$is_both_bad, c(0L, 1L)))
stopifnot(inherits(try(derive_position("alpha", "beta", "unexpected"), silent = TRUE), "try-error"))

# Markdown inside code is not a prose heading or list.
code_only <- answer_features("```python\n# comment\n- fake list\n```\nPlain text.")
stopifnot(code_only[["has_heading"]] == 0L, code_only[["has_list"]] == 0L,
          code_only[["code_blocks"]] == 1L, code_only[["paragraphs"]] == 1L)
markdown <- answer_features("# Title\r\n\r\n- item\r\n2. next\r\n\r\n~~~r\r\nx <- 1\r\n~~~")
stopifnot(markdown[["has_heading"]] == 1L, markdown[["has_list"]] == 1L,
          markdown[["code_blocks"]] == 1L, markdown[["paragraphs"]] == 2L,
          count_words("Don't count punctuation!!!") == 3L,
          count_words("\u00e9lan \u4e2d\u6587 123") == 3L,
          answer_features("")[["words"]] == 0L)
wide_fence <- answer_features("````\n```\n# still code\n````\n1. real list")
stopifnot(wide_fence[["code_blocks"]] == 1L, wide_fence[["has_heading"]] == 0L,
          wide_fence[["has_list"]] == 1L)

conversation <- function(prompt = "Shared prompt", answer = "A useful answer") {
  data.frame(role = c("user", "assistant"), content = c(prompt, answer))
}
stopifnot(valid_single_turn(conversation()), !valid_single_turn(conversation(answer = " ")),
          !valid_single_turn(data.frame(content = "missing role")))

# Exercise duplicates, empty answers, mismatched prompts, metadata, and ties.
n <- 9L
fixture <- data.frame(
  question_id = c("good", "tie", "duplicate", "duplicate", "empty", "mismatch", "two_turn", "hidden", "foreign"),
  model_a = rep("alpha", n), model_b = rep("beta", n),
  winner = c("model_a", "tie (bothbad)", rep("model_b", n - 2L)),
  judge = rep("source_user", n), turn = c(rep(1L, 6), 2L, 1L, 1L),
  anony = c(rep(TRUE, 7), FALSE, TRUE), language = c(rep("English", 8), "French"),
  tstamp = rep(1682899200, n), stringsAsFactors = FALSE
)
fixture$conversation_a <- replicate(n, conversation(), simplify = FALSE)
fixture$conversation_b <- replicate(n, conversation(), simplify = FALSE)
fixture$conversation_a[[5]] <- conversation(answer = NA_character_)
fixture$conversation_b[[6]] <- conversation(prompt = "Different prompt")
result <- prepare_arena(fixture)
stopifnot(nrow(result$data) == 2L, result$repeated_id_rows == 2L,
          identical(result$data$focal_win, c(1L, 0L)),
          result$data$is_tie[2] == 1L,
          sum(result$flow$removed) + nrow(result$data) == n,
          length(unique(result$data$prompt_group)) == 1L,
          !any(c("question_id", "judge", "conversation_a", "conversation_b") %in% names(result$data)),
          identical(rownames(result$data), c("1", "2")),
          nrow(processed_codebook(result$data)) == ncol(result$data))
structured <- data.frame(a = c(1, 2))
structured$nested <- data.frame(b = c(NA_real_, 3))
stopifnot(identical(row_missing(structured), c(TRUE, FALSE)))
orientation <- orientation_table(rbind(original, swapped), "model_pair")
stopifnot(orientation$left == 1L, orientation$right == 1L, orientation$both_orientations)
message("All synthetic preparation and position-coding checks passed.")
