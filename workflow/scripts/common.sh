#!/bin/bash

# Shared logic for the Claude CLI Alfred workflow.

# ---- JSON helpers ----

# JSON-escape STDIN, printing the result WITHOUT surrounding quotes. Uses perl
# (ships with macOS) so backslashes/quotes/newlines survive intact.
json_escape() {
    perl -0777 -pe '
        s/\\/\\\\/g;
        s/"/\\"/g;
        s/\n/\\n/g;
        s/\r/\\r/g;
        s/\t/\\t/g;
        s/[\x00-\x08\x0b\x0c\x0e-\x1f]//g;
    '
}
