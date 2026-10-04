# Core pipeline verification sources

This directory contains the source testbenches, Python reference tools, and
the reproducible manifest needed to understand the accepted core pipeline.
Generated simulator executables, temporary logs, rendered PNG/NumPy vectors,
and Efinity work directories are excluded. Durable verification and build
reports are archived under the v0.3 release directory.

The original full regression was run in the source project before acceptance.
Reproduction requires Efinity's `efx_ram10.v`, Icarus Verilog v12, and Python
with Pillow/NumPy.
