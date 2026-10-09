# Current Optimization Handoff

## Status

The current Tang Dynasty implementation was abandoned after place-and-route ran
for approximately three hours without completing. No new bitstream from this
attempt should be treated as validated hardware output.

## Known Video Issue

The ISP/SC500 video path has not been stabilized. After AWB experiments, the
display showed right-edge truncation. A direct demosaic 128-bit bypass caused
three horizontal image sections and severe pixel corruption, indicating that
the demosaic bus format cannot be connected directly to the DDR input. The
existing `128 -> 96 -> AWB -> 128` conversion and its AXI4-Stream timing must
be checked as one unit.

## Handoff Focus

- Verify the 24-bit RGB packing and byte order at every ISP boundary.
- Verify `tvalid`, `tuser`, and `tlast` alignment through AWB and both format converters.
- Check line-end handling for 1280 pixels, especially the final packed word.
- Reduce or pipeline large arithmetic and memory structures that prevent routing.
- Re-run synthesis and timing analysis before attempting another full route.

## Important Constraint

The generated implementation databases, logs, lock files, and bitstreams from
the failed run are intentionally not committed. They are tool outputs and may
be stale or machine-specific. The HDL and project-source changes are the
authoritative material for further optimization.
