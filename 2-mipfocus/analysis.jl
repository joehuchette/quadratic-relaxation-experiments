using CSV, StatsBase, DataFrames

include("common.jl")

APPROACHES_TO_COMPARE = [
    "grb3-direct",
    "grb3-direct-shift",
    "grb3-cda",
    "grb3-nn",
    "grb3-standard-nmdt",
    "grb3-tightened-nmdt",
]

if length(ARGS) != 1 || !ispath(ARGS[1])
    error("Invalid csv path")
end
const CSV_PATH = ARGS[1]

_shifted_geomean(vals, shift) = StatsBase.geomean(vals .+ shift) - shift

df = CSV.read(CSV_PATH, DataFrame)

# Figure out the best primal objective value available in dataset
# for each instance.
df[!, :best_primal] .= 0.0
for i = 1:size(df, 1)
    row = df[i, :]
    to_slice = df[df.instance.==row.instance, :true_objective]
    best_primal_value = minimum(filter(!isnan, to_slice))
    cutoffs = unique(df[df.instance.==row.instance, :cutoff])
    @assert length(cutoffs) == 1
    cutoff = cutoffs[1]
    best_primal_value = min(best_primal_value, cutoff)
    @assert !isnan(best_primal_value)
    df.best_primal[i] = best_primal_value
end

# Add a column to record MIP gap, with respect to best primal solution in data set.
function _mip_gap(row)
    return 100 * abs(row.dual_bound - row.best_primal) / abs(row.best_primal)
end
df[!, :gap] .= 0.0
for i = 1:size(df, 1)
    df.gap[i] = _mip_gap(df[i, :])
end

# Split off problem classes based on how easy they were. We will do separate analysis
# on each problem class.
PROBLEM_CLASS_DFS = Dict()
PROBLEM_CLASS_DFS["solved"] = filter(df) do row
    instance = row.instance
    slice = df[df.instance.==row.instance, :]
    return all(slice.termination_status .== "OPTIMAL")
end

PROBLEM_CLASS_DFS["contested"] = filter(df) do row
    instance = row.instance
    slice = df[df.instance.==row.instance, :]
    return any(slice.termination_status .== "OPTIMAL") &&
           !all(slice.termination_status .== "OPTIMAL")
end

PROBLEM_CLASS_DFS["unsolved"] = filter(df) do row
    instance = row.instance
    slice = df[df.instance.==row.instance, :]
    return !any(slice.termination_status .== "OPTIMAL")
end

for (lb, ub) in [(20, 30), (40, 50), (60, 80), (90, 125)]
    PROBLEM_CLASS_DFS["$lb-$ub"] = filter(df) do row
        strs = split(row.instance, "-")
        n = parse(Int, strs[2][5:end])
        return lb <= n <= ub
    end
end

# 1. Solved instances
for (class, subset_df) in PROBLEM_CLASS_DFS
    mask = map(t -> t in APPROACHES_TO_COMPARE, subset_df.approach)
    subset_df = subset_df[mask, :]
    total_instance_count = length(unique(subset_df.instance))
    println("Class: $class ($total_instance_count instances)")
    println("="^(30))

    winners = Dict(approach => 0 for approach in APPROACHES_TO_COMPARE)
    fails = Dict(approach => 0 for approach in APPROACHES_TO_COMPARE)
    best_bound = Dict(approach => 0 for approach in APPROACHES_TO_COMPARE)
    for instance in unique(subset_df.instance)
        slice = subset_df[subset_df.instance.==instance, :]
        if Set(unique(slice.approach)) ⊉ Set(APPROACHES_TO_COMPARE)
            @show Set(unique(slice.approach))
            @show Set(APPROACHES_TO_COMPARE)
            error("Incomplete experiment in table.")
        end
        if size(slice, 1) == 0
            error("Unexpected case, aborting.")
        end
        best_solve_time = minimum(slice.solve_time_sec)
        best_gap = minimum(slice.gap)
        all_time_out = best_solve_time >= 0.99 * TIME_LIMIT
        # NOTE: This excludes ties from the tally!
        if size(slice[slice.solve_time_sec.==best_solve_time, :], 1) != 1
            @show slice
            @warn("Need to handle ties")
        end
        for approach in APPROACHES_TO_COMPARE
            sub_slice = slice[slice.approach.==approach, :]
            solve_times = sub_slice.solve_time_sec
            @assert size(solve_times, 1) == 1
            gaps = sub_slice.gap
            @assert size(gaps, 1) == 1
            solve_time = minimum(solve_times)
            gap = minimum(gaps)
            best_primal = minimum(sub_slice.best_primal)
            solver_time_out = solve_time >= 0.99 * TIME_LIMIT
            if solver_time_out
                fails[approach] += 1
            end
            if all_time_out
                if gap == best_gap
                    winners[approach] += 1
                end
            else
                if solve_time == best_solve_time
                    winners[approach] += 1
                    # break
                end
            end
            # Either attain best bound, or reach Gurobi's optimality cutoff,
            # which is 1e-4 * |primal_bound|
            # Note that the gaps are recorded in the table as percentages,
            # so we must multiply through by 100.
            if gap == best_gap || gap < 1e-4 * 100
                best_bound[approach] += 1
            end
        end
    end

    time_shift = minimum(subset_df.solve_time_sec)
    gap_shift = max(1e-4, minimum(subset_df.gap))

    for approach in APPROACHES_TO_COMPARE
        slice = subset_df[subset_df.approach.==approach, :]
        println("$approach")
        println("-"^(length(approach) + 4))
        println(
            "  * solve time: ",
            _shifted_geomean(slice.solve_time_sec, time_shift),
            " sec",
        )
        println("  * MIP gap:    ", _shifted_geomean(slice.gap, gap_shift))
        num_winners = winners[approach]
        num_fails = fails[approach]
        num_best_bound = best_bound[approach]
        println("  * Winners:    ", num_winners, " / ", total_instance_count)
        println("  * Fails:      ", num_fails, " / ", total_instance_count)
        println("  * Best bound: ", num_best_bound, " / ", total_instance_count)
    end
end
