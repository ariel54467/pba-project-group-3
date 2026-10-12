# PBA Final Project — Group 3

Programming for Business Analytics · National Tsing Hua University

## Team Members

- Ariel Arella Sugandik 何玉屏 / 112006269
- Malvin Julius 陳金富/112006270
- William Tanujaya 陳德偉/112006402
- Jonathan Neville 曹德榮/113006440
- Roderick Rudiyanto 李偉權/112006462

## Topic

What Makes an AI Answer Win?

## Overview
This project investigates how the length and formatting of AI-generated answers relate to human preference. We will analyze pairs of AI responses to the same prompt and the human votes indicating which response was preferred.

**Our central research question is:**
    _"How are answer length and formatting associated with human preference, after accounting for which AI models produced the answers?"_

The analysis will focus on English, single-turn conversations. We will extract features such as word count, paragraph count, bullet lists, headings, and code blocks, then use logistic regression to examine their relationship with preference. We will also evaluate whether these features improve predictions on held-out data beyond using model identities alone.

## Data

We use the [Chatbot Arena Conversations dataset](https://huggingface.co/datasets/lmsys/chatbot_arena_conversations)
released by LMSYS. It contains 33,000 pairwise comparisons in which two anonymous
models answered the same prompt and a human voted for the better response.

To reproduce our analysis, set up the data as follows.

**1. Download the dataset.** From the link above, download
`train-00000-of-00001-cced8514c7ed782a.parquet` and place it in `data/raw/`.

**2. Install the `arrow` package**, which is required to read Parquet files:

```r
install.packages("arrow")
```

## Method

_To be completed._

## Results

_To be completed._
