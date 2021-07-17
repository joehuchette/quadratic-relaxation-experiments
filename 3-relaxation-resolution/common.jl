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

const EPIGRAPH = false

const SHIFT = QuadraticRelaxations.SemidefiniteShift(Mosek.Optimizer)
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
for num_layers in (2, 4, 6, 8)
    for (r_name, relaxation) in [
        "nn" => QuadraticRelaxations.NeuralNetRelaxation(num_layers),
        "cda" => QuadraticRelaxations.CDARelaxation(num_layers),
        "standard-nmdt" => QuadraticRelaxations.StandardNMDT(num_layers),
        "tightened-nmdt" => QuadraticRelaxations.TightenedNMDT(num_layers),
    ]
        APPROACHES[string("grb", "-", r_name, "-", num_layers)] = BoxQPApproach(
            gurobi_mip_factory,
            reformulate_with(relaxation, SHIFT, SOC_LOWER_BOUND),
        )
    end
end
