# PBA Final Project — Group 3

Programming for Business Analytics · National Tsing Hua University

## Team Members

- Ariel Arella Sugandik 何玉屏 / 112006269
- Malvin Julius 陳金富/112006270
- William Tanujaya 陳德偉/112006402
- Jonathan Neville 曹德榮/113006440
- Roderick Rudiyanto 李偉權/112006462

## Topic

Does Screen Position Affect Human Preference in Chatbot Arena?

## Overview

This project studies whether the position of an AI response affects how users evaluate it. Chatbot Arena displayed two anonymous model responses side by side and asked users to vote for Model A, Model B, a tie, or “both are bad.”

**Research question:** _Among recorded anonymous English single-turn Chatbot Arena comparisons, does displaying a model's response on the left rather than the right increase its probability of being selected as the sole winner?_

This is a causal question. We hypothesize that the left response has an advantage because English readers normally begin scanning on the left, which may make that response an anchor for the comparison. The complete Milestone 2 proposal is available in [proposal.md](proposal.md).

## Data

We use the [Chatbot Arena Conversations dataset](https://huggingface.co/datasets/lmsys/chatbot_arena_conversations) released by LMSYS. The original data contain 33,000 pairwise comparisons collected from April through June 2023. After restricting the sample to valid anonymous, English, single-turn comparisons and removing repeated question IDs, the analysis sample contains 25,878 battles from April 24 through June 26, 2023 (UTC).

The unit of observation is one completed battle with one recorded human vote. The cleaned sample covers 20 models, 190 unordered model pairs, and 10,684 anonymized judge groups. Tie votes remain in the analysis.

To reproduce our analysis, set up the data as follows.

**1. Download the dataset.** From the link above, download `train-00000-of-00001-cced8514c7ed782a.parquet`, rename it `arena.parquet`, and place it in `data/raw/`. The raw dataset is intentionally excluded from Git.

**2. Install the `arrow` package**, which is required to read Parquet files:

```r
install.packages("arrow")
```

**3. Prepare and audit the data.** From the project root, run:

```r
Rscript scripts/prepare_arena.R
Rscript tests/test.R
```

The preparation script creates a local analysis file, codebooks, a cleaning-flow report, missingness checks, and model-pair orientation diagnostics. Generated data and reports are excluded from Git.

## Key Variables and Method

The treatment, `focal_left`, equals 1 when the alphabetically defined focal model occupies the Model A/left position and 0 when it occupies the Model B/right position. Defining the focal model independently of position and outcome prevents the treatment coding from depending on the vote.

The outcome, `focal_win`, equals 1 when the focal model is the sole winner and 0 when the opponent wins or the vote is either type of tie. Ties are retained because position could affect whether a user selects a tie.

The primary comparison is between the same focal model and opponent during the same calendar week, with the focal model appearing on different sides. The planned model includes model-pair and calendar-week controls, with uncertainty clustered by anonymized judge. Repeated prompts and sparse model-pair/week groups will be examined in sensitivity analyses.

The Arena documentation describes randomized model battles, and contemporaneous FastChat code sampled both orientations of each model pair symmetrically. A final causal interpretation requires verifying that this assignment procedure governed the full data-collection period and that the released Model A/Model B fields preserve the left/right interface mapping.

## Project Files

- `proposal.md`: Milestone 2 proposal
- `R/project_config.R`: research question, assumptions, paths, and audit settings
- `R/arena_helpers.R`: cleaning, feature construction, and codebook functions
- `scripts/prepare_arena.R`: reproducible preparation and pre-commit audit
- `tests/test.R`: synthetic tests for cleaning, tie handling, and position coding

## Results

The causal effect has not yet been estimated. This repository currently contains the proposal and reproducible data-preparation code; results will be added after the design is finalized.
