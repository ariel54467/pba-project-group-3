
# Select the downloaded .parquet file
arena <- arrow::read_parquet(file.choose())

# Check the number of rows and available columns
nrow(arena)
names(arena)

# Preview the first 10 records
View(head(arena, 10))