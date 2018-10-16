#=
Type and methods to simplify data sourcing and management of the universe of tradable assets
=#

const SEPARATORS = ['/', '_', '.']

mutable struct Asset
    name::String
    props::Dict{Symbol,Symbol}
    function Asset(name::String;props::Dict{Symbol,Symbol}=Dict(:close_symb=>:Close,:trade_symb=>:Open))
        #TODO: put in a function to find default symbols
        new(name,props)
    end
end

mutable struct Universe
    assets::Vector{String}
    trade_symbols::Vector{Dict{Symbol,Symbol}}
    # tickers::Vector{Symbol}
    data::Dict{String,Temporal.TS}
    from::Dates.TimeType
    thru::Dates.TimeType
    function Universe(assets::Vector{Asset}, from::Dates.TimeType=Dates.Date(0), thru::Dates.TimeType=Dates.today())
        asset_names = Vector{String}(undef,length(assets))
        trade_symbs= Vector{Dict{Symbol,Symbol}}(undef,length(assets))
        for (i,ast) in enumerate(assets)
            @info i
            @info ast
            asset_names[i] = ast.name
            trade_symbs[i] = ast.props
        end
        data = Dict{String,Temporal.TS}()
        @inbounds for asset in asset_names
            data[asset] = Temporal.TS()
        end
        return new(asset_names, trade_symbs, data, from, thru)
    end
end

#TODO: ensure type compatibility across variables (specifically with regard to TimeTypes)
function gather!(universe::Universe; source::Function=Temporal.quandl, verbose::Bool=true)::Nothing
    t0 = Vector{Dates.Date}()
    tN = Vector{Dates.Date}()
    @inbounds for asset in universe.assets
        verbose ? print("Sourcing data for asset $asset...") : nothing
        indata = source(asset)
        push!(t0, indata.index[1])
        push!(tN, indata.index[end])
        universe.data[asset] = indata
        verbose ? print("Done.\n") : nothing
    end
    universe.from = max(minimum(t0), universe.from)
    universe.thru = min(maximum(tN), universe.thru)
    return nothing
end

#FIXME: make robust to other time types
function get_overall_index(universe::Universe)::Vector{Dates.Date}
    idx = Vector{Dates.Date}()
    for asset in universe.assets
        idx = union(idx, universe.data[asset].index)
    end
    return idx
end

#TODO: show method
