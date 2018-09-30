#=
methods for handling backtest results of strategy objects
=#

mutable struct Results
    trades::Dict{String,Temporal.TS}
    backtest::Dict{String,Temporal.TS{Float64}}
    optimization::Matrix{Float64}
    function Results(trades::Dict{String,Temporal.TS}=Dict{String,Temporal.TS}(),
                     backtest::Dict{String,Temporal.TS{Float64}}=Dict{String,Temporal.TS{Float64}}(),
                     optimization::Matrix{Float64}=Matrix{Float64}(0,0))
        return new(trades, backtest, optimization)
    end
end
