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

const SOC_LOWER_BOUND = false

const FAMILIES = ("basic", "extended", "extended2")

const INSTANCE_DIR = joinpath(ROOT_DIR, "box_qp", "data")
const OUTPUT_ROOT_DIR = joinpath(@__DIR__, "output/")

const CONFIG = FactoryConfig(TIME_LIMIT, NUM_THREADS, CPLEX_PATH)

INSTANCES = Dict{String,BoxQPInstance}()
for family in FAMILIES, instance_name in readdir(joinpath(INSTANCE_DIR, family))
    INSTANCES["$family-$instance_name"] =
        _create_instance(family, instance_name, primal_factory(CONFIG), EPIGRAPH)
end

APPROACHES = Dict{String,BoxQPApproach}()
for (s_name, shift) in [
    "eig" => QuadraticRelaxations.MinEigenvalueShift(),
    "sdp" => QuadraticRelaxations.SemidefiniteShift(Mosek.Optimizer),
]
    APPROACHES[join(["grb", "direct-shift", s_name], "-")] = BoxQPApproach(
        gurobi_direct_factory,
        reformulate_with(QuadraticRelaxations.ExactFormulation(), shift, SOC_LOWER_BOUND),
    )
    for (r_name, relaxation) in [
        "nn" => QuadraticRelaxations.NeuralNetRelaxation(NUM_LAYERS),
        "cda" => QuadraticRelaxations.CDARelaxation(NUM_LAYERS),
        "standard-nmdt" => QuadraticRelaxations.StandardNMDT(NUM_LAYERS),
        "tightened-nmdt" => QuadraticRelaxations.TightenedNMDT(NUM_LAYERS),
    ]
        APPROACHES[join(["grb", r_name, s_name], "-")] = BoxQPApproach(
            gurobi_mip_factory,
            reformulate_with(relaxation, shift, SOC_LOWER_BOUND),
        )
    end
end
