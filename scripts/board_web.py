#!/usr/bin/env python3
"""Point old local board launch commands to the authoritative SECHA task board."""

from board import HOSTED_BOARD

if __name__ == "__main__":
    print(f"The local Git task board is retired. Open {HOSTED_BOARD}")
