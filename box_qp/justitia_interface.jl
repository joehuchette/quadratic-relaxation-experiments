using Justitia
using MathOptInterface
const MOI = MathOptInterface
using QuadraticRelaxations

mutable struct BoxQPInstance <: Justitia.AbstractInstance
    model::MOI.ModelLike
    Q::Matrix{Float64}
    c::Vector{Float64}
    primal_factory::Any
    cutoff::Float64

    # ASSUMPTION: BoxQP instance is minimization
    BoxQPInstance(model::MOI.ModelLike, Q::Matrix, c::Vector, primal_factory) =
        new(model, Q, c, primal_factory, Inf)
end

function Justitia.prep_instance!(instance::BoxQPInstance)
    primal_model = MOI.instantiate(instance.primal_factory)
    MOI.copy_to(primal_model, instance.model)
    MOI.optimize!(primal_model)
    @assert MOI.get(primal_model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT
    instance.cutoff = MOI.get(primal_model, MOI.ObjectiveValue())
    return nothing
end

function _create_instance(family::String, instance::String, primal_factory, epigraph::Bool)
    Q, c = parse_box_qp(joinpath(INSTANCE_DIR, family, instance))
    return BoxQPInstance(formulate_box_qp(Q, c, epigraph = epigraph), Q, c, primal_factory)
end

struct BoxQPApproach <: Justitia.AbstractApproach
    factory::Any
    transformation::Function
end

function reformulate_with(relaxation, shift, soc_lower_bound)
    return moi_model -> QuadraticRelaxations.reformulate_quadratics(
        moi_model,
        QuadraticRelaxations.Reformulation(relaxation, shift, soc_lower_bound),
    )
end

function Justitia.build_model(
    approach::BoxQPApproach,
    instance::BoxQPInstance,
    config::Dict{String},
)
    @assert collect(keys(config)) == ["factory_config"]
    src_model = approach.transformation(instance.model)
    dest_model =
        MOI.instantiate(approach.factory(config["factory_config"], instance.cutoff))
    MOI.copy_to(dest_model, src_model, copy_names = false)
    return Justitia.MOIModel(dest_model)
end

Base.@kwdef mutable struct BoxQPResult <: Justitia.AbstractResult
    termination_status::MOI.TerminationStatusCode
    primal_status::MOI.ResultStatusCode
    solve_time_sec::Float64
    x::Union{Nothing,Vector{Float64}} = nothing
    primal_bound::Float64 = NaN
    dual_bound::Float64 = NaN
    true_objective::Float64 = NaN
    cutoff::Float64
    node_count::Int = -1
end

const _BOXQP_RESULT_FIELDS = [
    :termination_status,
    :primal_status,
    :primal_bound,
    :dual_bound,
    :true_objective,
    :cutoff,
    :solve_time_sec,
    :node_count,
]

function Justitia.CSVRecord(filename::String, ::Type{BoxQPResult})
    # Don't write feasible solution to CSV
    return Justitia.CSVRecord(
        filename,
        vcat(["instance", "approach"], [string(field) for field in _BOXQP_RESULT_FIELDS]),
    )
end

function Justitia.record_result!(
    table::Justitia.CSVRecord,
    result::BoxQPResult,
    instance_name::String,
    approach_name::String,
)
    println(
        table.fp,
        join(
            vcat(
                [instance_name, approach_name],
                [getfield(result, field) for field in _BOXQP_RESULT_FIELDS],
            ),
            ",",
        ),
    )
    return flush(table.fp)
end

function Justitia.tear_down(
    model::Justitia.MOIModel,
    instance::BoxQPInstance,
    ::Type{BoxQPResult},
)
    opt = model.opt
    result = BoxQPResult(
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
        result.true_objective = -0.5dot(x_val, instance.Q * x_val) - dot(instance.c, x_val)
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
