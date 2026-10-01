# Sobel verification sources

The `tb/` directory and `vectors/` manifest are the self-checking verification
inputs archived from the accepted v0.2 project. The original full regression
was run in the source workspace and is summarized in the release acceptance
report. Generated simulator binaries and logs are intentionally excluded from
the repository.

The testbenches require Icarus Verilog plus the Efinix `efx_ram10.v` simulation
model. The Efinity build uses the project under `efinity/sobel/`.
