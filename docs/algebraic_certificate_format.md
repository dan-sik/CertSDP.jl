# Algebraic Certificate Format

This page is kept for older links. The current certificate-format documentation
is [Certificate format](certificate_format.md), including rational, algebraic,
Schur-zero, LDL, pivoted-LDL, blockwise, and SOS Gram certificates.

Algebraic LMI certificates use one real algebraic root representation, encode
coordinates as rational functions of that root, and are accepted only after
exact verifier replay. Rank-deficient algebraic certificates commonly use the
`schur_zero` PSD proof method; larger or ordering-sensitive matrices can use
`pivoted_ldl`, and multi-block algebraic certificates replay one proof per
original PSD block.
