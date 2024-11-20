#!/bin/bash

# Check if the coverage report file is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <coverage-report-file>"
    exit 1
fi

coverage_file=$1

# Initialize an empty array to hold the file paths
files=()

# Read the coverage report file line by line
while IFS= read -r line; do
    # Skip the first line (mode: set)
    if [[ $line == mode* ]]; then
        continue
    fi

    # Extract the file path from the line
    file_path=$(echo $line | cut -d':' -f1)

    # Skip files in the vendor directory
    if [[ $file_path == vendor/** ]]; then
        continue
    fi

    # Add the file path to the array if it's not already present
    if [[ ! " ${files[@]} " =~ " ${file_path} " ]]; then
        files+=("$file_path")
    fi
done < "$coverage_file"

# Convert the array to a JSON array
json_array=$(printf '%s\n' "${files[@]}" | jq -R . | jq -s .)

# Write the JSON array to the output
echo "$json_array"