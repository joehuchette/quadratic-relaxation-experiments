using JuMP

using LinearAlgebra

function formulate_nearest_good_box_qp(
    Q::Matrix,
    c::Vector,
    y_max::Float64,
    x_target::Vector{Float64},
)
    n = length(c)
    @assert n == size(Q, 1) == size(Q, 2)
    model = JuMP.Model()
    JuMP.@variable(model, 0 ≤ x[1:n] ≤ 1)
    JuMP.@constraint(model, -0.5dot(x, Q * x) - dot(c, x) ≤ y_max)

    JuMP.@variable(model, t[1:n] >= 0)
    for i = 1:n
        JuMP.@constraint(model, t[i] >= x[i] - x_target[i])
        JuMP.@constraint(model, t[i] >= -x[i] + x_target[i])
    end
    JuMP.@objective(model, Min, sum(t))
    return JuMP.backend(model)
end

using Justitia
using MathOptInterface
const MOI = MathOptInterface
using QuadraticRelaxations

const MULTIPLICATIVE_FACTOR_TO_OPTIMAL = 0.95

mutable struct NearestGoodBoxQPInstance <: Justitia.AbstractInstance
    box_qp_model::MOI.ModelLike
    Q::Matrix{Float64}
    c::Vector{Float64}
    primal_factory::Any
    nearest_good_model::MOI.ModelLike
    y_max::Float64
    cutoff::Float64

    # ASSUMPTION: BoxQP instance is minimization
    NearestGoodBoxQPInstance(
        box_qp_model::MOI.ModelLike,
        Q::Matrix{Float64},
        c::Vector{Float64},
        primal_factory,
    ) = new(box_qp_model, Q, c, primal_factory)
end

function Justitia.prep_instance!(instance::NearestGoodBoxQPInstance)
    let primal_model = MOI.instantiate(instance.primal_factory)
        MOI.copy_to(primal_model, instance.box_qp_model)
        MOI.optimize!(primal_model)
        @assert MOI.get(primal_model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT
        instance.y_max = MOI.get(primal_model, MOI.ObjectiveValue())
        @assert instance.y_max < 0
    end
    instance.nearest_good_model = formulate_nearest_good_box_qp(
        instance.Q,
        instance.c,
        MULTIPLICATIVE_FACTOR_TO_OPTIMAL * instance.y_max,
        0.5 * ones(length(instance.c)),
    )
    let primal_model = MOI.instantiate(instance.primal_factory)
        MOI.copy_to(primal_model, instance.nearest_good_model)
        MOI.optimize!(primal_model)
        if MOI.get(primal_model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT
            instance.cutoff = MOI.get(primal_model, MOI.ObjectiveValue())
        else
            instance.cutoff = 1e30
        end
    end
    return nothing
end

function _create_nearest_good_instance(family::String, instance::String, primal_factory)
    Q, c = parse_box_qp(joinpath(INSTANCE_DIR, family, instance))
    return NearestGoodBoxQPInstance(formulate_box_qp(Q, c), Q, c, primal_factory)
end

function Justitia.build_model(
    approach::BoxQPApproach,
    instance::NearestGoodBoxQPInstance,
    config::Dict{String},
)
    @assert collect(keys(config)) == ["factory_config"]
    src_model = approach.transformation(instance.nearest_good_model)
    dest_model =
        MOI.instantiate(approach.factory(config["factory_config"], instance.cutoff))
    MOI.copy_to(dest_model, src_model, copy_names = false)
    return Justitia.MOIModel(dest_model)
end

Base.@kwdef mutable struct NearestGoodBoxQPResult <: Justitia.AbstractResult
    termination_status::MOI.TerminationStatusCode
    primal_status::MOI.ResultStatusCode
    solve_time_sec::Float64
    x::Union{Nothing,Vector{Float64}} = nothing
    primal_bound::Float64 = NaN
    dual_bound::Float64 = NaN
    cutoff::Float64
    node_count::Int = -1
end

const _NEAREST_GOOD_BOXQP_RESULT_FIELDS = [
    :termination_status,
    :primal_status,
    :primal_bound,
    :dual_bound,
    :cutoff,
    :solve_time_sec,
    :node_count,
]

function Justitia.CSVRecord(filename::String, ::Type{NearestGoodBoxQPResult})
    # Don't write feasible solution to CSV
    return Justitia.CSVRecord(
        filename,
        vcat(
            ["instance", "approach"],
            [string(field) for field in _NEAREST_GOOD_BOXQP_RESULT_FIELDS],
        ),
    )
end

function Justitia.record_result!(
    table::Justitia.CSVRecord,
    result::NearestGoodBoxQPResult,
    instance_name::String,
    approach_name::String,
)
    println(
        table.fp,
        join(
            vcat(
                [instance_name, approach_name],
                [getfield(result, field) for field in _NEAREST_GOOD_BOXQP_RESULT_FIELDS],
            ),
            ",",
        ),
    )
    return flush(table.fp)
end

function Justitia.tear_down(
    model::Justitia.MOIModel,
    instance::NearestGoodBoxQPInstance,
    ::Type{NearestGoodBoxQPResult},
)
    opt = model.opt
    result = NearestGoodBoxQPResult(
        termination_status = MOI.get(opt, MOI.TerminationStatus()),
        primal_status = MOI.get(opt, MOI.PrimalStatus()),
        solve_time_sec = MOI.get(opt, MOI.SolveTime()),
        cutoff = instance.cutoff,
    )
    if result.primal_status == MOI.FEASIBLE_POINT
        num_vars = MOI.get(opt, MOI.NumberOfVariables())
        all_var_vals =
            [MOI.get(opt, MOI.VariablePrimal(), MOI.VariableIndex(i)) for i = 1:num_vars]
        result.x = all_var_vals
        n = length(instance.c)
        @assert n == size(instance.Q, 1) == size(instance.Q, 2)
        x_val = all_var_vals[1:n]
    end
    try
        primal_bound = MOI.get(opt, MOI.ObjectiveValue())
        result.primal_bound = primal_bound
    catch ArgumentError
        @warn "Primal bound not available; proceeding anyway."
    end
    try
        dual_bound = MOI.get(opt, MOI.ObjectiveBound())
        result.dual_bound = dual_bound
    catch ArgumentError
        @warn "Dual bound not available; proceeding anyway."
    end
    try
        node_count = MOI.get(opt, MOI.NodeCount())
        result.node_count = node_count
    catch ArgumentError
        @warn "Node count not available; proceeding anyway."
    end
    return result
end
