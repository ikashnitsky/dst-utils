# DSTutils

**DSTutils** is an R package containing utilities for data transformation pipelines at Statistics Denmark. Currently, it provides functionality to seamlessly invoke person ID conversions (such as CPR to PERSON_ID and vice-versa) via Oracle databases directly from R.

## Installation

As this package relies on internal Statistics Denmark infrastructure (such as the `DSTdb` package and Oracle database access), it is intended for internal use.

You can install it directly from the source directory using `devtools`:

```r
# install.packages("devtools")
devtools::install_local("path/to/DSTutils")
```

## Features

- **`convert_person_id()`**: A versatile wrapper for executing Oracle procedures (e.g., `BEF_OMKOD`, `BEF_HISTORISK_ID`) to convert IDs. It handles the creation of temporary tables, running the Oracle process, and returning the converted output directly to R.
- **`add_person_id()`**: A convenience function specifically built to process a data frame containing a `PNR` column, returning the data frame with a new `PERSON_ID` column appended via a database join.

## Usage

### Adding PERSON_ID to an existing dataset
```r
library(DSTutils)

# Assuming 'my_data' is a data.frame with a 'PNR' column
converted_data <- add_person_id(my_data)
```

### Advanced Conversion via Oracle Procedures
```r
library(DSTutils)

# Convert using a specific procedure and project ID
my_converted_table <- convert_person_id(
  project_id = "D101200",
  procedure = "BEF_HISTORISK_ID",
  in_table_name = my_input_table,
  validity_date = "2021-01-01"
)
```

## Requirements

- Read/Write privileges to the `DB_PSD` database schema or relevant target database.
- Internal R packages: `DSTdb`.
- Standard dependencies: `dplyr`, `lubridate`, `DBI`, `ROracle`.
