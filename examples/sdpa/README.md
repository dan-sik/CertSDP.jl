# SDPA Sparse Examples

These fixtures exercise the SDPA sparse frontend:

- `single_block.dat-s`: one PSD block.
- `two_blocks.dat-s`: two PSD blocks sharing variables.
- `diagonal_block.dat-s`: one SDPA diagonal block, written with negative block size.
- `mixed_blocks_decimal.dat-s`: PSD and diagonal blocks with finite decimal input.
- `empty_variable_matrices.dat-s`: variables whose coefficient matrices may be zero in some blocks.

`read_problem(path)` imports all examples as `BlockLMIProblem` through the
stable public API. Low-level SDPA helpers remain internal implementation tools.
