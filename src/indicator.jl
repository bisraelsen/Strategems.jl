abstract type AbstractIndicator end
mutable struct Indicator <: AbstractIndicator
    fun::Function
    paramset::ParameterSet
    data::Temporal.TS
    function Indicator(fun::Function, paramset::ParameterSet)
        data = Temporal.TS()
        return new(fun, paramset, data)
    end
end

function calculate(indicator::AbstractIndicator, input::Temporal.TS)::Temporal.TS
    d = generate_dict(indicator.paramset)
    return indicator.fun(input; d...)
end

function calculate!(indicator::AbstractIndicator, input::Temporal.TS)::Nothing
   indicator.data = calculate(indicator, input)
   return nothing
end

function generate_dict(universe::Universe, indicator::Indicator)::Dict{String,Indicator}
    indicators = Dict{String,Indicator}()
    for asset in universe.assets
        local ind = Indicator(indicator.fun, indicator.paramset)
        calculate!(ind, universe.data[asset])
        indicators[asset] = ind
    end
    return indicators
end
