
```bash
# Create mapping object
mapping = Mapping("samples.tsv")

# Get all info for a sample
sample_data = mapping["SAMPLE1"]

# Get specific attribute
treatment = mapping.get_sample_attr("SAMPLE1", "Treatment")

# Get all samples with specific attribute
treated = mapping.get_samples_by_attr("Treatment", "A")

# Iterate over samples
for sample_id in mapping:
    print(f"Processing {sample_id}")

# Check if sample exists
if "SAMPLE1" in mapping:
    print("Found sample")
```
