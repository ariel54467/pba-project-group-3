# Helpers deliberately use base R; arrow is needed only to load the source file.

is_blank <- function(x) {
  is.na(x) | !nzchar(trimws(as.character(x)))
}

valid_single_turn <- function(conversation) {
  is.data.frame(conversation) &&
    all(c("role", "content") %in% names(conversation)) &&
    nrow(conversation) == 2L &&
    identical(as.character(conversation$role), c("user", "assistant")) &&
    !any(is_blank(conversation$content))
}

count_words <- function(text) {
  # Unicode letter/number sequences; internal apostrophes count as part of a word.
  # Code words are included. This is a reproducible proxy, not a model tokenizer.
  matches <- gregexpr("[\\p{L}\\p{N}]+(?:['\u2019][\\p{L}\\p{N}]+)*", text, perl = TRUE)
  vapply(matches, function(m) if (m[1L] < 0L) 0L else length(m), integer(1))
}

answer_features <- function(text) {
  stopifnot(length(text) == 1L, !is.na(text))
  text <- gsub("\r\n?", "\n", enc2utf8(text), perl = TRUE)
  lines <- strsplit(text, "\n", fixed = TRUE)[[1L]]
  outside <- rep(TRUE, length(lines))
  fence_character <- ""
  fence_width <- 0L
  code_blocks <- 0L
  for (i in seq_along(lines)) {
    # Recognize Markdown backtick and tilde fences, with at most 3 leading spaces.
    if (nzchar(fence_character)) {
      outside[i] <- FALSE
      close_pattern <- paste0("^ {0,3}", fence_character, "{", fence_width, ",}[ \\t]*$")
      if (grepl(close_pattern, lines[i], perl = TRUE)) fence_character <- ""
    } else if (grepl("^ {0,3}(`{3,}|~{3,})", lines[i], perl = TRUE)) {
      marker <- sub("^ {0,3}(`{3,}|~{3,}).*$", "\\1", lines[i], perl = TRUE)
      fence_character <- substr(marker, 1L, 1L)
      fence_width <- nchar(marker)
      outside[i] <- FALSE
      code_blocks <- code_blocks + 1L
    }
  }
  prose <- lines[outside]
  # Replace fenced lines by blanks so paragraphs on either side stay separate.
  paragraph_lines <- lines
  paragraph_lines[!outside] <- ""
  occupied <- nzchar(trimws(paragraph_lines))
  previous <- if (length(occupied)) c(FALSE, head(occupied, -1L)) else logical()
  c(
    words = count_words(text),
    paragraphs = sum(occupied & !previous),
    has_list = as.integer(any(grepl("^[ \\t]*(?:[-+*]|[0-9]+[.)])[ \\t]+\\S", prose, perl = TRUE))),
    has_heading = as.integer(any(grepl("^ {0,3}#{1,6}[ \\t]+\\S", prose, perl = TRUE))),
    code_blocks = code_blocks
  )
}

feature_table <- function(texts, suffix) {
  if (!length(texts)) stop("No answers remain after cleaning.", call. = FALSE)
  # USE.NAMES=FALSE prevents answer text becoming matrix/data-frame row names.
  values <- as.data.frame(t(vapply(texts, answer_features, numeric(5), USE.NAMES = FALSE)))
  rownames(values) <- NULL
  names(values) <- paste0(c("words", "paragraphs", "has_list", "has_heading", "code_blocks"), "_", suffix)
  values
}

derive_position <- function(model_a, model_b, winner) {
  stopifnot(length(model_a) == length(model_b), length(model_a) == length(winner))
  if (any(is_blank(model_a) | is_blank(model_b)) || any(model_a == model_b)) {
    stop("Position coding requires two different, nonmissing model names.", call. = FALSE)
  }
  allowed <- c("model_a", "model_b", "tie", "tie (bothbad)")
  if (anyNA(winner) || any(!winner %in% allowed)) stop("Unknown vote category.", call. = FALSE)
  models <- sort(unique(c(model_a, model_b)), method = "radix")
  focal_left <- as.integer(match(model_a, models) < match(model_b, models))
  focal <- ifelse(focal_left == 1L, model_a, model_b)
  opponent <- ifelse(focal_left == 1L, model_b, model_a)
  focal_win <- as.integer((focal_left == 1L & winner == "model_a") |
                         (focal_left == 0L & winner == "model_b"))
  tied <- winner %in% c("tie", "tie (bothbad)")
  data.frame(
    focal_model = focal,
    opponent_model = opponent,
    model_pair = paste(focal, opponent, sep = " vs "),
    focal_left = focal_left,
    focal_win = focal_win,
    is_tie = as.integer(tied),
    is_both_bad = as.integer(winner == "tie (bothbad)"),
    # Auxiliary original-project outcome. Never treat ties as B wins.
    a_win_decisive = ifelse(tied, NA_integer_, as.integer(winner == "model_a")),
    stringsAsFactors = FALSE
  )
}

prepare_arena <- function(raw) {
  required <- c("question_id", "model_a", "model_b", "winner", "judge",
                "conversation_a", "conversation_b", "turn", "anony", "language", "tstamp")
  absent <- setdiff(required, names(raw))
  if (length(absent)) stop("Missing source columns: ", paste(absent, collapse = ", "), call. = FALSE)
  if (!is.numeric(raw$tstamp)) stop("tstamp must contain Unix seconds.", call. = FALSE)

  # Each row is a battle, not two independently sampled responses.
  keep <- rep(TRUE, nrow(raw))
  flow <- data.frame(step = "Raw rows", before = nrow(raw), removed = 0L, remaining = nrow(raw))
  retain <- function(condition, label) {
    condition[is.na(condition)] <- FALSE
    before <- sum(keep)
    keep <<- keep & condition
    flow <<- rbind(flow, data.frame(step = label, before = before,
                                    removed = before - sum(keep), remaining = sum(keep)))
  }
  retain(!is_blank(raw$question_id), "Nonmissing question ID")
  # Some IDs have different votes/turns. Do not arbitrarily keep first or last.
  repeated <- duplicated(raw$question_id) | duplicated(raw$question_id, fromLast = TRUE)
  retain(!repeated, "Exclude every occurrence of repeated question IDs")
  retain(raw$anony %in% TRUE, "Anonymous comparisons")
  retain(tolower(trimws(raw$language)) == "english", "English language tag")
  retain(raw$turn == 1L, "Single-turn metadata")
  retain(!is_blank(raw$model_a) & !is_blank(raw$model_b) & raw$model_a != raw$model_b,
         "Two known, distinct models")
  retain(raw$winner %in% c("model_a", "model_b", "tie", "tie (bothbad)"), "Recognized vote, including ties")
  retain(!is_blank(raw$judge) & is.finite(raw$tstamp), "Available judge and timestamp")

  structurally_valid <- rep(FALSE, nrow(raw))
  idx <- which(keep)
  structurally_valid[idx] <- vapply(raw$conversation_a[idx], valid_single_turn, logical(1)) &
    vapply(raw$conversation_b[idx], valid_single_turn, logical(1))
  retain(structurally_valid, "Both sides have one nonempty user/assistant exchange")
  same_prompt <- rep(FALSE, nrow(raw))
  idx <- which(keep)
  same_prompt[idx] <- vapply(idx, function(i) {
    identical(enc2utf8(raw$conversation_a[[i]]$content[1L]),
              enc2utf8(raw$conversation_b[[i]]$content[1L]))
  }, logical(1))
  retain(same_prompt, "Exactly the same prompt on both sides")
  if (!any(keep)) stop("No eligible comparisons remain. Inspect the source data.", call. = FALSE)
  x <- raw[keep, ]
  prompts <- vapply(x$conversation_a, function(z) enc2utf8(z$content[1L]), character(1))
  answers_a <- vapply(x$conversation_a, function(z) enc2utf8(z$content[2L]), character(1))
  answers_b <- vapply(x$conversation_b, function(z) enc2utf8(z$content[2L]), character(1))
  dates <- as.Date(as.POSIXct(x$tstamp, origin = "1970-01-01", tz = "UTC"), tz = "UTC")
  week_start <- dates - (as.integer(format(dates, "%u")) - 1L)
  normalized_prompt <- trimws(gsub("[[:space:]]+", " ", prompts, perl = TRUE))
  position <- derive_position(x$model_a, x$model_b, x$winner)
  data <- cbind(
    data.frame(
      battle_id = seq_len(nrow(x)),
      judge_group = match(x$judge, unique(x$judge)),
      prompt_group = match(normalized_prompt, unique(normalized_prompt)),
      date_utc = as.character(dates), week_utc = as.character(week_start),
      model_a = x$model_a, model_b = x$model_b, winner = x$winner,
      prompt_words = count_words(prompts), stringsAsFactors = FALSE
    ),
    position, feature_table(answers_a, "a"), feature_table(answers_b, "b")
  )
  data$log_words_diff <- log1p(data$words_a) - log1p(data$words_b)
  for (feature in c("paragraphs", "has_list", "has_heading", "code_blocks")) {
    data[[paste0(feature, "_diff")]] <- data[[paste0(feature, "_a")]] - data[[paste0(feature, "_b")]]
  }
  rownames(data) <- NULL
  list(data = data, flow = flow, repeated_id_rows = sum(repeated))
}

row_missing <- function(x) {
  # Arrow structs become nested data frames, which complete.cases cannot flatten.
  if (is.data.frame(x)) {
    if (!ncol(x)) return(rep(FALSE, nrow(x)))
    return(Reduce(`|`, lapply(x, row_missing)))
  }
  if (is.list(x)) return(vapply(x, is.null, logical(1)))
  if (is.character(x)) return(is_blank(x))
  is.na(x)
}

orientation_table <- function(data, groups) {
  key <- do.call(paste, c(data[groups], sep = "\034"))
  pieces <- split(seq_len(nrow(data)), key)
  result <- lapply(pieces, function(i) {
    cbind(data[i[1L], groups, drop = FALSE],
          data.frame(n = length(i), left = sum(data$focal_left[i] == 1L),
                     right = sum(data$focal_left[i] == 0L)))
  })
  result <- do.call(rbind, result)
  rownames(result) <- NULL
  result$left_fraction <- result$left / result$n
  result$both_orientations <- result$left > 0L & result$right > 0L
  result
}

column_profile <- function(data) {
  do.call(rbind, lapply(names(data), function(name) {
    x <- data[[name]]
    missing <- if (is.character(x)) is_blank(x) else is.na(x)
    finite <- if (is.numeric(x)) x[is.finite(x)] else numeric()
    data.frame(variable = name, type = paste(class(x), collapse = "/"),
               missing_n = sum(missing), missing_fraction = mean(missing),
               distinct_nonmissing = length(unique(x[!missing])),
               minimum = if (length(finite)) min(finite) else NA_real_,
               maximum = if (length(finite)) max(finite) else NA_real_)
  }))
}

write_csv <- function(data, path) {
  utils::write.csv(data, path, row.names = FALSE, na = "", fileEncoding = "UTF-8")
}

markdown_table <- function(data) {
  clean <- function(x) gsub("[\r\n]", " ", gsub("|", "/", as.character(x), fixed = TRUE))
  rows <- apply(data, 1L, function(x) paste(clean(x), collapse = " | "))
  c(paste(names(data), collapse = " | "), paste(rep("---", ncol(data)), collapse = " | "), rows)
}

processed_codebook <- function(data) {
  descriptions <- c(
    battle_id = "Sequential local battle ID; one row per comparison, not per answer.",
    judge_group = "Local integer for the source anonymized judge; use for clustered uncertainty. Not a verified person ID.",
    prompt_group = "Local integer for identical prompts after whitespace normalization; case preserved. Not a semantic topic label.",
    date_utc = "Vote timestamp converted to UTC calendar date, YYYY-MM-DD.",
    week_utc = "Monday starting the UTC week of the vote; proposed calendar control.",
    model_a = "Source model_a, provisionally the left/Model A slot; verify export mapping.",
    model_b = "Source model_b, provisionally the right/Model B slot; verify export mapping.",
    winner = "Original vote: model_a, model_b, tie, or tie (bothbad).",
    prompt_words = "Count of Unicode letter/number sequences in the common user prompt; internal apostrophes retained.",
    focal_model = "First of the two model names in bytewise alphabetical order, independent of vote and slot.",
    opponent_model = "The other model in the battle.",
    model_pair = "Unordered pair encoded as focal_model vs opponent_model; proposed grouping/control.",
    focal_left = "T: 1 if focal model occupies model_a; 0 if it occupies model_b. Left/right interpretation requires source verification.",
    focal_win = "Y: 1 if focal model is the sole winner; 0 for opponent win, tie, or both bad. Ties are retained.",
    is_tie = "1 for either tie category; 0 for decisive votes.",
    is_both_bad = "1 for tie (bothbad); 0 otherwise.",
    a_win_decisive = "Auxiliary: 1 for model_a win, 0 for model_b win, NA for either tie. Not the causal primary outcome.",
    log_words_diff = "log(1 + words_a) minus log(1 + words_b); exploratory original-topic feature.",
    paragraphs_diff = "paragraphs_a minus paragraphs_b.",
    has_list_diff = "has_list_a minus has_list_b; values -1, 0, 1.",
    has_heading_diff = "has_heading_a minus has_heading_b; values -1, 0, 1.",
    code_blocks_diff = "code_blocks_a minus code_blocks_b."
  )
  features <- c(
    words = "Unicode letter/number word sequences, including words inside code; not token count.",
    paragraphs = "Nonempty line runs separated by blank lines, excluding fenced code; a paragraph proxy.",
    has_list = "1 if an unordered (-,+,*) or numbered Markdown list marker occurs outside fenced code; 0 otherwise.",
    has_heading = "1 if an ATX Markdown heading (# through ######) occurs outside fenced code; 0 otherwise. Setext/HTML headings are not detected.",
    code_blocks = "Number of opening Markdown fences (backticks or tildes, length >=3); an unclosed fence still counts. Indented/HTML code is not detected."
  )
  for (side in c("a", "b")) {
    for (feature in names(features)) {
      descriptions[paste0(feature, "_", side)] <- paste("Response", toupper(side), "-", features[[feature]])
    }
  }
  if (any(!names(data) %in% names(descriptions))) stop("A derived variable has no codebook entry.", call. = FALSE)
  data.frame(variable = names(data), type = vapply(data, function(x) class(x)[1L], character(1)),
             description = unname(descriptions[names(data)]))
}

raw_codebook <- function(raw) {
  descriptions <- c(
    question_id = "Source comparison/question identifier; repeated IDs exist and all their rows are excluded.",
    model_a = "Model name for source slot A.", model_b = "Model name for source slot B.",
    winner = "Human vote: model_a, model_b, tie, or tie (bothbad).",
    judge = "Anonymized source judge identifier; never exported verbatim.",
    conversation_a = "Nested role/content message table for A, including user and assistant text; kept local.",
    conversation_b = "Nested role/content message table for B, including user and assistant text; kept local.",
    turn = "Number of conversation turns according to the release.",
    anony = "Whether the vote was anonymous according to the release.",
    language = "Source-detected conversation language; not manually verified.",
    tstamp = "Unix timestamp in seconds for the recorded vote.",
    openai_moderation = "Nested moderation categories, scores, and flagged status; not used to exclude rows.",
    toxic_chat_tag = "Nested source toxicity classifier outputs; not used to exclude rows."
  )
  absent <- setdiff(names(raw), names(descriptions))
  descriptions[absent] <- "Unexpected source field; inspect before use."
  data.frame(variable = names(raw), type = vapply(raw, function(x) class(x)[1L], character(1)),
             description = unname(descriptions[names(raw)]))
}
