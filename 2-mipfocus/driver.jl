include("common.jl")

const OUTPUT_DIR = joinpath(OUTPUT_ROOT_DIR, string(Dates.now()))
mkdir(OUTPUT_DIR)

const VERSION_PATH = joinpath(OUTPUT_DIR, "version.txt")
const RESULT_PATH = joinpath(OUTPUT_DIR, "result.csv")
const STDOUT_PATH = joinpath(OUTPUT_DIR, "stdout.txt")
const STDERR_PATH = joinpath(OUTPUT_DIR, "stderr.txt")

results_table = Justitia.CSVRecord(RESULT_PATH, BoxQPResult)

open(STDOUT_PATH, "w") do out
    open(STDERR_PATH, "w") do err
        redirect_stdout(out) do
            redirect_stderr(err) do
                Justitia.run_experiments!(
                    results_table,
                    INSTANCES,
                    APPROACHES,
                    BoxQPResult,
                    config = Dict("factory_config" => CONFIG),
                )
            end
        end
    end
end
