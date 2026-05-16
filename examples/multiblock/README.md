# Multi-Block Examples

These examples exercise blockwise rational certification.

```bash
bin/certsdp certify examples/sdpa/two_blocks.dat-s \
  --solution examples/multiblock/sdpa_two_blocks_solution.json \
  --out /tmp/certsdp-two-blocks-cert.json

bin/certsdp verify --strict /tmp/certsdp-two-blocks-cert.json
bin/certsdp inspect /tmp/certsdp-two-blocks-cert.json
```

`schema_three_blocks.json` is the same workflow using the public block problem
schema instead of SDPA sparse input. `jump_two_constraints.jl` extracts two
affine PSD constraints from JuMP/MOI and certifies the shared rational point
blockwise.
