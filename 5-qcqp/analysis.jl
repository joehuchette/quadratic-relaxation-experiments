using CSV, StatsBase, DataFrames

include("common.jl")

APPROACHES_TO_COMPARE = [
    "brn-direct",
    "grb-direct",
    "brn-direct-shift",
    "grb-direct-shift",
    "grb-cda",
    "grb-nn",
    "grb-standard-nmdt",
    "grb-tightened-nmdt",
]

if length(ARGS) != 1 || !ispath(ARGS[1])
    error("Invalid csv path")
end
const CSV_PATH = ARGS[1]

_shifted_geomean(vals, shift) = StatsBase.geomean(vals .+ shift) - shift

df = CSV.read(CSV_PATH, DataFrame)

# Figure out the best primal objective value available in dataset
# # for each instance.
df[!, :best_primal] .= 0.0
for i = 1:size(df, 1)
    row = df[i, :]
    cutoff_slice = df[df.instance.==row.instance, :cutoff]
    cutoffs = unique(cutoff_slice)
    @assert length(cutoffs) == 1
    cutoff = cutoffs[1]
    primal_values =
        df[(df.instance.==row.instance).&contains.(df.approach, "direct"), :primal_bound]
    best_primal_value = minimum(filter(!isnan, primal_values))
    @assert !isnan(best_primal_value)
    df.best_primal[i] = min(cutoff, best_primal_value)
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
opt_or_obj_limit(slice) =
    (slice.termination_status .== "OPTIMAL") .|
    (slice.termination_status .== "OBJECTIVE_LIMIT")
PROBLEM_CLASS_DFS = Dict()
PROBLEM_CLASS_DFS["solved"] = filter(df) do row
    instance = row.instance
    slice = df[df.instance.==row.instance, :]
    return all(opt_or_obj_limit(slice))
end

PROBLEM_CLASS_DFS["contested"] = filter(df) do row
    instance = row.instance
    slice = df[df.instance.==row.instance, :]
    return any(opt_or_obj_limit(slice)) && !all(opt_or_obj_limit(slice))
end

PROBLEM_CLASS_DFS["unsolved"] = filter(df) do row
    instance = row.instance
    slice = df[df.instance.==row.instance, :]
    return !any(opt_or_obj_limit(slice))
end

# 1. Solved instances
for (class, subset_df) in PROBLEM_CLASS_DFS
    mask = map(t -> t in APPROACHES_TO_COMPARE, subset_df.approach)
    subset_df = subset_df[mask, :]
    total_instance_count = length(unique(subset_df.instance))
    println("Class: $class ($total_instance_count instances)")
    println("="^(30))
    if total_instance_count == 0
        continue
    end

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
            # which is 1e-4 * |primal_bound|.
            # Note that the gaps are recorded in the table as percentages,
            # so we must multiply through by 100.
            if gap == best_gap || gap < 1e-4 * abs(best_primal) * 100
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
