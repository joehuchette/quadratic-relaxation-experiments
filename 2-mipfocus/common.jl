using QuadraticRelaxations

using Mosek, MosekTools

using Dates

const ROOT_DIR = joinpath(@__DIR__, "..")
include(joinpath(ROOT_DIR, "local_config.jl"))
include(joinpath(ROOT_DIR, "solver_factories.jl"))
include(joinpath(ROOT_DIR, "box_qp/util.jl"))
include(joinpath(ROOT_DIR, "box_qp/justitia_interface.jl"))

const TIME_LIMIT = 10 * 60.0
const NUM_THREADS = 1

const NUM_LAYERS = 3
const EPIGRAPH = false

const SHIFT = QuadraticRelaxations.SemidefiniteShift(Mosek.Optimizer)
const SOC_LOWER_BOUND = false

const FAMILIES = ("basic", "extended", "extended2")

const INSTANCE_DIR = joinpath(ROOT_DIR, "box_qp", "data")

const CONFIG = FactoryConfig(TIME_LIMIT, NUM_THREADS, CPLEX_PATH)

INSTANCES = Dict{String,BoxQPInstance}()
for family in FAMILIES, instance_name in readdir(joinpath(INSTANCE_DIR, family))
    INSTANCES["$family-$instance_name"] =
        _create_instance(family, instance_name, primal_factory(CONFIG), EPIGRAPH)
end

APPROACHES = Dict{String,BoxQPApproach}()
for (t_name, transformation) in [
    "direct" => identity,
    "direct-shift" =>
        reformulate_with(QuadraticRelaxations.ExactFormulation(), SHIFT, SOC_LOWER_BOUND),
]
    APPROACHES[string("grb3", "-", t_name)] =
        BoxQPApproach(gurobi_direct_mipfocus_3_factory, transformation)
end

for (r_name, relaxation) in [
    "nn" => QuadraticRelaxations.NeuralNetRelaxation(NUM_LAYERS),
    "cda" => QuadraticRelaxations.CDARelaxation(NUM_LAYERS),
    "standard-nmdt" => QuadraticRelaxations.StandardNMDT(NUM_LAYERS),
    "tightened-nmdt" => QuadraticRelaxations.TightenedNMDT(NUM_LAYERS),
]
    APPROACHES[string("grb3", "-", r_name)] = BoxQPApproach(
        gurobi_direct_mipfocus_3_factory,
        reformulate_with(relaxation, SHIFT, SOC_LOWER_BOUND),
    )
end
