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
    JuMP.@variable(model, y <= y_max)
    JuMP.@constraint(model, y ≥ -0.5dot(x, Q * x) - dot(c, x))

    JuMP.@variable(m, t[1:n] >= 0)
    for i = 1:n
        JuMP.@constraint(m, t[i] >= x[i] - x_target[i])
        JuMP.@constraint(m, t[i] >= -x[i] + x_target[i])
    end
    JuMP.@objective(model, Min, sum(t))
    return JuMP.backend(model)
end
