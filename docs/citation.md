# Citation

If CertSDP helps your research, cite the software and the paper that motivates
the degenerate SDP certification workflow.

## Software Citation

```bibtex
@software{CertSDPjl,
  title   = {CertSDP.jl: Exact certificate compiler for SDP and SOS artifacts},
  author  = {{CertSDP contributors}},
  year    = {2026},
  version = {2.1.0},
  note    = {Software package}
}
```

If you publish a tagged archive with a DOI, cite the archived DOI in addition to
the package citation above.

After a DOI is minted, prefer the archived software citation for publications
and keep this repository citation as the development-location reference:

```bibtex
@software{CertSDPjlArchived,
  title     = {CertSDP.jl: Exact certificate compiler for SDP and SOS artifacts},
  author    = {{CertSDP contributors}},
  year      = {2026},
  version   = {2.1.0},
  doi       = {<archived-software-doi>},
  publisher = {Zenodo or equivalent archive}
}
```

## DOI Status

No DOI is minted in this repository until a public tagged archive is deposited
on Zenodo or an equivalent archive. Before adding DOI metadata:

1. tag the release after tests, docs, and the validation suite pass;
2. archive the tag;
3. update `CITATION.cff`, `codemeta.json`, README, and release notes with the
   minted DOI;
4. keep the validation report and replayable bundles linked from the release.

## Method Paper

```bibtex
@article{KolmogorovNaldiZapata2025DegenerateSDP,
  author  = {Kolmogorov, Vladimir and Naldi, Simone and Zapata, Jeferson},
  title   = {Certifying Solutions of Degenerate Semidefinite Programs},
  journal = {SIAM Journal on Optimization},
  volume  = {35},
  number  = {3},
  pages   = {1630--1654},
  year    = {2025},
  doi     = {10.1137/24M1664691}
}
```

The paper explains why rational feasible solutions need not exist for some SDP
instances and develops the hybrid symbolic-numeric incidence-system approach
that CertSDP uses as its main mathematical reference.
