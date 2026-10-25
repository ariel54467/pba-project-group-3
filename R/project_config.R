# Run from the project root: Rscript scripts/prepare_arena.R
# Install the only required package once: install.packages("arrow")
# Nothing in this project stages, commits, pushes, scrapes, or collects new votes.

project_config <- list(
  raw_file = "data/raw/arena.parquet",
  processed_dir = "data/processed",
  report_dir = "outputs/precommit",
  min_observations = 300L,
  max_missing_fraction = 0.05,
  max_file_bytes = 100000000,
  min_per_orientation = 20L,
  question_type = "causal",
  question = paste(
    "Among recorded anonymous English single-turn Chatbot Arena comparisons,",
    "does displaying a model's response on the left rather than the right",
    "increase its probability of being selected as the sole winner?"
  ),
  comparison = paste(
    "Compare the same focal model against the same opponent when the focal",
    "model appears on the left versus the right, accounting for calendar week.",
    "The focal model is the first model name in bytewise alphabetical order,",
    "chosen without using position, answer characteristics, or the vote."
  ),
  outcome = "focal_win: 1 for a sole focal-model win; 0 for a loss or either tie category.",
  treatment = "focal_left: 1 when the focal model is model_a; 0 when it is model_b.",
  estimand = paste(
    "Average change in the probability of a focal-model sole win when its",
    "position is switched from right to left (and its opponent switches left to right),",
    "for model pairs and periods with both orientations in the retained sample."
  ),
  proposed_method = paste(
    "Use one row per battle; compare left/right focal win rates within unordered",
    "model-pair and calendar-week strata. For estimation, prespecify a linear",
    "probability model with pair and week fixed effects and uncertainty clustered",
    "by anonymized judge; check repeated-prompt dependence as a sensitivity analysis.",
    "Do not control for answer length/formatting in the primary position model",
    "because answers are generated after assignment. Retain all tie votes."
  ),
  identification = paste(
    "Requires a verified side-assignment mechanism independent of potential votes",
    "within model pair and period, and correct mapping of model_a/model_b to left/right.",
    "Pair/week controls and balance checks cannot themselves prove randomization.",
    "Selection into voting, the released dataset, and single-turn conversations",
    "must not create position-dependent selection. The release lacks non-voters,",
    "so that assumption is not directly testable. Browser layout/device is unobserved."
  ),
  # Set these only after recording actual evidence in the notes below.
  # They are deliberately not inferred from a balanced sample or a small p-value.
  historical_assignment_verified = FALSE,
  historical_assignment_notes = paste(
    "The 2023 LMSYS blog describes randomized model battles. FastChat snapshot",
    "78fa7b4 (2023-06-24), add_text, samples ordered model pairs with equal weights",
    "for (a,b) and (b,a); its UI labels state 0 as left/Model A and state 1 as right/Model B.",
    "Establish deployed versions during April-June 2023 and verify export orientation.",
    "A repository snapshot alone",
    "does not establish the deployed assignment mechanism for every observation."
  ),
  novelty_review_complete = FALSE,
  novelty_notes = paste(
    "Zheng et al. (2023), section 3.3, studies position bias of LLM judges using",
    "MT-Bench. The proposed question concerns human votes in the released Arena",
    "data. This is a candidate distinction, not a verified novelty claim; review",
    "the full original study, appendices, and accompanying analysis before committing."
  ),
  selection_assumptions_reviewed = FALSE,
  selection_notes = "Assess voting/release/single-turn selection and the limited target population.",
  sharing_review_complete = FALSE,
  sharing_notes = paste(
    "Default to sharing code only. Generated data remain ignored by Git.",
    "Review attribution, noncommercial restrictions, model terms, and privacy",
    "before distributing even the derived subset."
  ),
  source_url = "https://huggingface.co/datasets/lmsys/chatbot_arena_conversations",
  source_paper = "https://arxiv.org/html/2306.05685v4",
  assignment_source = "https://www.lmsys.org/blog/2023-05-03-arena/",
  historical_code = paste0(
    "https://github.com/lm-sys/FastChat/blob/",
    "78fa7b4e5663b616b37ac5af1d92e4586f3dbcd8/",
    "fastchat/serve/gradio_block_arena_anony.py"
  ),
  source_checked_date = "2026-10-25",
  source_attribution = paste(
    "LMSYS; Zheng et al. (2023), Judging LLM-as-a-Judge with MT-Bench and Chatbot Arena.",
    "Prompts: CC-BY-4.0. Model outputs: CC-BY-NC-4.0, per the dataset card."
  ),
  acquisition = paste(
    "Use the original LMSYS Hugging Face dataset, accept its access conditions",
    "yourself, download the train Parquet file, and save it as data/raw/arena.parquet.",
    "No Kaggle mirror, scraping, survey, experiment, or LLM labeling is used."
  ),
  ethics = paste(
    "The study could help improve evaluation interfaces; overgeneralized findings",
    "could unfairly affect model rankings or encourage interface manipulation.",
    "Do not identify users or quote potentially sensitive conversation content.",
    "The subset excludes prompts, responses, original question IDs, and original",
    "judge labels. Integer grouping IDs are pseudonyms, not guaranteed anonymity.",
    "Results concern this 2023 volunteer sample, not current model quality or all users."
  )
)
