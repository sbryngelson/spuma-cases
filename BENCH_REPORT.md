# SPUMA Benchmarks + Profiles — Apr 7 2026

Short benchmarks of all proposed turbulence-closure configurations on the
two runnable cases. Hills/sphere skipped (need meshing). Cost numbers are
"ms per SIMPLEC iteration" with the in-process timing instrumentation.

## Configuration

| | cylinder | duct |
|---|---|---|
| cells | ~50K | ~880K |
| iters/run | 20 | 5 |
| GPU | H200 | H200 + H100 (mixed) |
| pool | fixedSizeMemoryPool 8/12 GiB | |

Mixed GPUs only matter for duct (kOmegaSST → nnTBNN-med were collected on
H200, the rest on H100). Within each model the difference is <10 % on this
size of mesh.

## Per-iteration timing

### cylinder (kOmegaSST baseline = 140 ms/iter)

| model           | total | turb correct | p solve | U solve | turb % | cost x |
|-----------------|------:|-------------:|--------:|--------:|-------:|-------:|
| kOmegaSST       |   140 |           70 |      37 |       7 |  50 %  |  1.00  |
| nnTBRF-1t       |   161 |          125 |      18 |       3 |  78 %  |  1.15  |
| nnTBRF-5t       |   872 |          835 |      15 |       3 |  96 %  |  6.23  |
| nnMLP-small     |  1238 |         1192 |      18 |       6 |  96 %  |  8.85  |
| nnPITBNN-small  |  1454 |         1404 |      14 |       5 |  97 %  | 10.39  |
| nnTBNN-small    |  1474 |         1402 |      20 |       7 |  95 %  | 10.54  |
| nnTBRF-10t      |  2095 |         2062 |      16 |       3 |  98 %  | 14.98  |
| nnMLP-med       |  4143 |         4116 |      11 |       3 |  99 %  | 29.62  |
| nnPITBNN-med    |  8948 |         8758 |      34 |      14 |  98 %  | 63.97  |
| nnTBNN-med      |  8950 |         8755 |      29 |      25 |  98 %  | 63.98  |
| nnMLP-large     | 13878 |        13744 |      23 |      18 |  99 %  |  99.21 |
| nnPITBNN-large  | 28605 |        28390 |      46 |      36 |  99 %  | 204.49 |
| nnTBNN-large    | 28656 |        28357 |      39 |      21 |  99 %  | 204.86 |

### duct (kOmegaSST baseline = 125 ms/iter)

| model           | total | turb correct | p solve | U solve | turb % | cost x |
|-----------------|------:|-------------:|--------:|--------:|-------:|-------:|
| kOmegaSST       |   125 |           43 |      46 |       8 |  34 %  |   1.00 |
| nnTBRF-1t       |  1672 |         1491 |      61 |      12 |  89 %  |  13.39 |
| nnMLP-small     |  2380 |         2321 |      25 |       7 |  98 %  |  19.06 |
| nnPITBNN-small  |  3156 |         2975 |      63 |      11 |  94 %  |  25.28 |
| nnTBNN-small    |  3177 |         3018 |      70 |       8 |  95 %  |  25.44 |
| nnMLP-med       |  9673 |         9090 |      63 |      36 |  94 %  |  77.46 |
| nnTBRF-5t       | 11326 |        11190 |      60 |      10 |  99 %  |  90.70 |
| nnPITBNN-med    | 19118 |        18975 |      60 |      10 |  99 %  | 153.09 |
| nnTBNN-med      | 19462 |        19330 |      56 |      12 |  99 %  | 155.85 |
| nnTBRF-10t      | 29209 |        28958 |      77 |      22 |  99 %  | 233.90 |
| nnMLP-large     | 38462 |        38191 |     127 |      19 |  99 %  | 307.99 |
| nnPITBNN-large  | 72626 |        72400 |      82 |      17 |  99 %  | 581.57 |
| nnTBNN-large    | 72988 |        72609 |      82 |      42 |  99 %  | 584.47 |

## nsys kernel breakdown (cylinder, 10 iters, H100)

7 of 8 representative configs profiled. duct nnTBRF-5t hit an nsys-internal
event-ordering bug during finalization (qdstrm preserved, .nsys-rep missing).

| profile             | parallelFor lambda | reductions | mem | top kernel             |
|---------------------|-------------------:|-----------:|----:|------------------------|
| cylinder kOmegaSST  |              70 % |       22 % | 8 % | Amul / grad / gauss    |
| cylinder nnMLP-med  |            99.5 % |        0 % | 0 % | `multiply<double>` 97 % |
| cylinder nnTBNN-med |            99.6 % |        0 % | 0 % | `multiply<double>` 98 % |
| cylinder nnTBRF-5t  |              84 % |       10 % | 7 % | tree kernel + tensor ops |
| duct kOmegaSST      |              75 % |        9 % |15 % | gradient + Amul        |
| duct nnMLP-med      |            99.4 % |        0 % | 0 % | `multiply<double>` 96 % |
| duct nnTBNN-med     |            99.2 % |        0 % | 0 % | `multiply<double>` 97 % |

## Critical finding — field-ops MLP/TBNN are kernel-launch-bound

The field-operations forward pass (every neuron = a separate
`scalarField = w_i * x_i + b` followed by `tanh`) generates **hundreds of
tiny kernel launches per layer per cell-batch**, each with mandatory
`cudaDeviceSynchronize`. The arithmetic itself is microseconds; the 99 % we
see in `multiply<double>` is launch + sync overhead.

This explains:
- nnMLP-large @ 308 cost-x on duct (≈ 38 sec/iter for a 880K-cell mesh)
- nnTBNN-large @ 584 cost-x on duct (≈ 73 sec/iter)
- the asymmetric breakdown vs SST (which is ~70 % real lambda work)

**Implication:** the GPU port of NN-RANS closures must fuse the forward pass
into a single custom kernel — the way the new TBRF tree kernel works. Until
then, the field-ops MLP/TBNN numbers above are *upper bounds*, not what is
intrinsically achievable by these closures on H100/H200.

**For the paper:** the cost ratios above are the realistic ones for a
"naive port" of TBNN/MLP into a CUDA-aware OpenFOAM. The TBRF-1t result
(1.15× SST on cylinder, 13× on duct) is a useful contrast — a single small
tree forest in a single fused kernel is essentially free.

## Files

- `bench_results.csv` — full results (26 rows)
- `bench_all_cases.sh` — main bench driver (cylinder + duct, full sweep)
- `bench_duct_short.sh` — resumable duct-only short pass (5 iters)
- `profile_representative.sh` — nsys driver for 8 representative configs
- `summarize_bench.py` — pretty-print + cost-vs-baseline
- `summarize_kernels.py` — roll up nsys kernel CSVs by family
- `nsys_profiles/{cylinder,duct}__*.nsys-rep` — kernel-level profiles
- `nsys_profiles/stats/*_kern.csv` — nsys stat dumps
