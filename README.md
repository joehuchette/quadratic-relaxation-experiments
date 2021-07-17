# quadratic-relaxation-experiments
Code accompaniment for ["Compact mixed-integer programming relaxations in quadratic optimization"](https://arxiv.org/abs/2011.08823)

## Set-up

1. [Download and install Julia](https://julialang.org/downloads/).
2. Download the required solvers: BARON, CPLEX, Gurobi, Mosek. Each is a commercial license that requires a license to run properly.
3. Install the equisite Julia packages. This can be done by launching Julia and running:
```jl
import Pkg
Pkg.add("JuMP")
Pkg.add("BARON")
Pkg.add("CPLEX")
Pkg.add("Gurobi")
Pkg.add("Mosek")
Pkg.add("MosekTools")
Pkg.add(url = "https://github.com/joehuchette/Justitia.jl.git")
Pkg.add(url = "https://github.com/joehuchette/QuadraticRelaxations.jl.git")
```
4. Configure ``local_config.jl``. Namely, you will need to set the Julia variable such to point to the path of the CPLEX shared library.

## Driver instructions

For Table 3, run:
```jl
julia 1-box-qp/driver.jl
julia 1-box-qp/analysis [PATH_TO_RESULTS]
```

For Table 4, run:
```jl
julia 2-mipfocus/driver.jl
julia 2-mipfocus/analysis [PATH_TO_RESULTS]
```

For Table 5, run:
```jl
julia 3-relaxation-resolution/driver.jl
julia 3-relaxation-resolution/analysis [PATH_TO_RESULTS]
```

For Table 6, run:
```jl
julia 4-shift/driver.jl
julia 4-shift/analysis [PATH_TO_RESULTS]
```

For Table 8, run:
```jl
julia 5-qcqp/driver.jl
julia 5-qcqp/analysis [PATH_TO_RESULTS]
```

In each, `PATH_TO_RESULTS` should point to the `results.csv` created by the experiment. This will live in `[EXPERIMENT_DIRECTORY]/output/[YEAR]-[MONTH]-[DAY]T[HOUR]:[MINUTE]:[SECOND]` folder, where the timestamp will correspond to the time in which the driver started execution.

The above commands will run the experiments in serial. To parallelize the individual trials across `NUM_THREADS` on your machine, for each of the above replace

```jl
julia [EXPERIMENT_DIRECTORY]/driver.jl
```

with

```jl
julia --threads [NUM_THREADS] [EXPERIMENT_DIRECTORY]/driver.jl
```
