# Milestone 3 figure inputs

The prepared data contain one retained battle per row. The team preparation script
filters to valid anonymous, English, single-turn comparisons and removes repeated
question IDs. It writes the full field-level codebook beside its prepared files
in `data/processed/`.

| Field | Definition |
| --- | --- |
| `focal_left` | 1 when the alphabetically first model in the pair is Model A (left), 0 when it is Model B (right). |
| `focal_win` | 1 when the focal model is the sole winner, 0 otherwise. |
| `is_tie` | 1 for a tie or both-bad vote, 0 for a decisive vote. |
| `model_pair` | The unordered pair, named using the focal model first. |
| `week_utc` | UTC calendar-week identifier used by the preparation script. |

Figure 1 divides each outcome count by the number of battles on that side.
Figure 2 groups by model pair and week. A group has both orientations when
each side has at least one battle. Group shares weight each group equally,
and battle shares weight each group by its number of battles.

Source: [LMSYS Chatbot Arena Conversations](https://huggingface.co/datasets/lmsys/chatbot_arena_conversations).
Run `Rscript scripts/prepare_arena.R`, then `Rscript plot_milestone3.R`
from the repository root. The report is written to `outputs/milestone3.pdf`.

## Shared aggregate subset

`milestone3_figure_counts.csv` contains ten aggregate counts and no individual battle
records. `figure` selects the chart, `category` is the vote outcome or unit
counted, `group` is the position or overlap status, and `n` is the count.
With the prepared battles present, the plotting script regenerates this CSV.
A checkout can also render the report directly from the checked-in counts
with `Rscript plot_milestone3.R`.
