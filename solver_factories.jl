using MathOptInterface
const MOI = MathOptInterface
using BARON, CPLEX, Gurobi

struct FactoryConfig
    time_limit::Float64
    num_threads::Int
    cplex_path::String
end

const primal_factory(config::FactoryConfig) = MOI.OptimizerWithAttributes(
    Gurobi.Optimizer,
    MOI.TimeLimitSec() => config.time_limit,
    MOI.NumberOfThreads() => config.num_threads,
    MOI.RawParameter("NonConvex") => 2,
    MOI.RawParameter("MIPFocus") => 1,
)

# CutUp works for minimization (which we are doing)
function cplex_direct_factory(config::FactoryConfig, cutoff::Float64)
    return MOI.OptimizerWithAttributes(
        CPLEX.Optimizer,
        MOI.TimeLimitSec() => config.time_limit,
        MOI.NumberOfThreads() => config.num_threads,
        MOI.RawParameter("CPXPARAM_OptimalityTarget") => 3,
        MOI.RawParameter("CPX_PARAM_CUTUP") => cutoff,
    )
end
function cplex_mip_factory(config::FactoryConfig, cutoff::Float64)
    return MOI.OptimizerWithAttributes(
        CPLEX.Optimizer,
        MOI.TimeLimitSec() => config.time_limit,
        MOI.NumberOfThreads() => config.num_threads,
        MOI.RawParameter("CPX_PARAM_CUTUP") => cutoff,
    )
end
function gurobi_direct_factory(config::FactoryConfig, cutoff::Float64)
    return MOI.OptimizerWithAttributes(
        Gurobi.Optimizer,
        MOI.TimeLimitSec() => config.time_limit,
        MOI.NumberOfThreads() => config.num_threads,
        MOI.RawParameter("NonConvex") => 2,
        MOI.RawParameter("Cutoff") => cutoff,
    )
end
function gurobi_direct_mipfocus_factory(
    config::FactoryConfig,
    cutoff::Float64,
    mipfocus::Int,
)
    return MOI.OptimizerWithAttributes(
        Gurobi.Optimizer,
        MOI.TimeLimitSec() => config.time_limit,
        MOI.NumberOfThreads() => config.num_threads,
        MOI.RawParameter("NonConvex") => 2,
        MOI.RawParameter("MIPFocus") => mipfocus,
        MOI.RawParameter("Cutoff") => cutoff,
    )
end
function gurobi_direct_mipfocus_3_factory(config::FactoryConfig, cutoff::Float64)
    return gurobi_direct_mipfocus_factory(config, cutoff, 3)
end

function gurobi_mip_factory(config::FactoryConfig, cutoff::Float64)
    return MOI.OptimizerWithAttributes(
        Gurobi.Optimizer,
        MOI.TimeLimitSec() => config.time_limit,
        MOI.NumberOfThreads() => config.num_threads,
        MOI.RawParameter("Cutoff") => cutoff,
    )
end

function gurobi_mip_mipfocus_factory(config::FactoryConfig, cutoff::Float64, mipfocus::Int)
    return MOI.OptimizerWithAttributes(
        Gurobi.Optimizer,
        MOI.TimeLimitSec() => config.time_limit,
        MOI.NumberOfThreads() => config.num_threads,
        MOI.RawParameter("MIPFocus") => mipfocus,
        MOI.RawParameter("Cutoff") => cutoff,
    )
end
function gurobi_mip_mipfocus_3_factory(config::FactoryConfig, cutoff::Float64)
    return gurobi_mip_mipfocus_factory(config, cutoff, 3)
end

function baron_direct_factory(config::FactoryConfig, cutoff::Float64)
    return MOI.OptimizerWithAttributes(
        BARON.Optimizer,
        MOI.TimeLimitSec() => config.time_limit,
        MOI.RawParameter("threads") => config.num_threads,
        MOI.RawParameter("CplexLibName") => config.cplex_path,
        MOI.RawParameter("CutOff") => cutoff,
    )
end
