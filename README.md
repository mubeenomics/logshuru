# logshuru

logshuru is a versatile logging utility for Bash, inspired by Python’s [loguru](https://github.com/Delgan/loguru).
It provides structured and color-coded log messages with contextual details like timestamps, source file, and line number.
You can use it as a standalone CLI tool or source it as a library in your scripts, making it ideal for both small shell scripts and production pipelines.
With 8 configurable log levels, level filtering, and zero dependencies, logshuru helps bring clarity and consistency to your Bash logging.

## Table of Contents

- [Features](#features)
- [Installation](#installation)
  - [Requirements](#requirements)
  - [Quick Install](#quick-install)
- [Usage](#usage)
  - [As a CLI Tool](#as-a-cli-tool)
  - [As a Library](#as-a-library)
- [Output Format](#output-format)
- [Log Levels](#log-levels)
  - [Using Environment Variable](#using-environment-variable)
  - [Using set\_log\_level Function](#using-set_log_level-function)
  - [Get Current Log Level](#get-current-log-level)
- [Examples](#examples)
  - [Basic Script with Logging](#basic-script-with-logging)
  - [Error Handling](#error-handling)
  - [Production vs Development](#production-vs-development)
- [Configuration](#configuration)
  - [Default Log Level](#default-log-level)
  - [Colors](#colors)
- [Contributing](#contributing)
- [Acknowledgments](#acknowledgments)

## Features

- **Colored Output** - Beautiful, color-coded log levels for easy visual parsing
- **Contextual Information** - Automatic inclusion of timestamp, file, function, and line number
- **8 Log Levels** - From TRACE to CRITICAL for granular control
- **Level Filtering** - Control what gets logged with configurable minimum log levels
- **Dual Mode** - Use as a CLI tool or source as a library in your scripts
- **Zero Dependencies** - Pure Bash with no external requirements

## Installation

### Requirements

- Bash 4.0 or later
- A terminal that supports ANSI color codes

### Quick Install

```bash
# Download the script
curl -O https://raw.githubusercontent.com/mubeenomics/logshuru/main/logshuru.sh

# Make it executable
chmod +x logshuru.sh

# Move to your PATH for system-wide access
sudo mv logshuru.sh /usr/local/bin/logshuru
```

## Usage

### As a CLI Tool

```bash
# Basic usage
logshuru INFO "Application started"
logshuru ERROR "Failed to connect to database"
logshuru SUCCESS "Operation completed successfully"

# View help
logshuru --help

# Check version
logshuru --version
```

### As a Library

Source the script in your Bash scripts to use the logging functions:

```bash
#!/bin/bash

# Source logshuru
source logshuru

# Use the log function
log INFO "Starting processing..."
log DEBUG "Processing item: $item"
log SUCCESS "Processing completed"
log ERROR "Something went wrong!"
```

## Output Format

Each log entry includes:

```text
2025-10-01 14:32:45.123 | INFO | script.sh:main:42 - Your message here
└──────────┬──────────┘  └──┬─┘  └───────┬───────┘  └────────┬────────┘
       Timestamp          Level    Source Location        Message
```

## Log Levels

logshuru supports 8 log levels (in ascending order of severity):

| Level        | Color          | Description                  |
| ------------ | -------------- | ---------------------------- |
| **TRACE**    | Cyan (Bold)    | Detailed tracing information |
| **DEBUG**    | Blue (Bold)    | Debugging messages           |
| **PROCESS**  | Purple (Bold)  | Process-level messages       |
| **INFO**     | White (Bold)   | General information          |
| **SUCCESS**  | Green (Bold)   | Successful operations        |
| **WARNING**  | Yellow (Bold)  | Warning conditions           |
| **ERROR**    | Red (Bold)     | Error messages               |
| **CRITICAL** | Red Background | Critical conditions          |

### Using Environment Variable

```bash
# Only show WARNING and above (WARNING, ERROR, CRITICAL)
export LOG_LEVEL="WARNING"

logshuru INFO "This won't be shown"
logshuru ERROR "This will be shown"
```

### Using set_log_level Function

```bash
#!/bin/bash

# Source logshuru
source logshuru

# Set minimum log level to DEBUG
set_log_level "DEBUG"

# Use the log function
log TRACE "This won't be shown"
log DEBUG "This will be shown"
log INFO "This will also be shown"
```

### Get Current Log Level

```bash
#!/bin/bash

# Source logshuru
source logshuru

# Get current log level
current_level=$(get_log_level)
echo "Current log level: $current_level"
```

## Examples

### Basic Script with Logging

```bash
#!/bin/bash

# Source logshuru
source logshuru

log INFO "Script started"

# Set log level
set_log_level "DEBUG"

# Loop with logging and conditional warning
for i in {1..3}; do
    log DEBUG "Processing iteration $i"
        if [ $i -eq 2 ]; then
            log WARNING "Halfway through processing"
        fi
done

log SUCCESS "Script completed successfully"
```

### Error Handling

```bash
#!/bin/bash

# Source logshuru
source logshuru

# Define a function with logging and error handling
perform_operation() {
    log PROCESS "Starting critical operation"

    if ! command_that_might_fail; then
        log ERROR "Operation failed"
        return 1
    fi

    log SUCCESS "Operation succeeded"
    return 0
}

# Run the function with loggin and exit on failure
if ! perform_operation; then
    log CRITICAL "Fatal error occurred, exiting"
    exit 1
fi
```

### Production vs Development

```bash
#!/bin/bash

# Source logshuru
source logshuru

# Set different log levels based on environment
if [ "$ENVIRONMENT" = "production" ]; then
    set_log_level "WARNING"
else
    set_log_level "DEBUG"
fi

# Use the log function
log DEBUG "Detailed debugging information"
log INFO "Application initialized"
log ERROR "This appears in both environments"
```

## Configuration

### Default Log Level

The default log level is `PROCESS`. You can change this by:

1. Setting the `LOG_LEVEL` environment variable before running your script
2. Calling `set_log_level` after sourcing the script

### Colors

Colors are defined using ANSI escape codes and work on most modern terminals. If you need to disable colors, you can redirect output through `sed` or modify the `COLORS` array in the script.

## Contributing

Contributions are welcome! Please feel free to submit a pull request.

## Acknowledgments

Inspired by the excellent [loguru](https://github.com/Delgan/loguru) library for Python.
