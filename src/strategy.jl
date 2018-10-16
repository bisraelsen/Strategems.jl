#=
Type definition and methods containing the overarching backtesting object fueling the engine
=#
import Random

mutable struct Strategy
    universe::Universe
    indicator::AbstractIndicator
    rules::Tuple{Vararg{Rule}}
    portfolio::Portfolio
    results::Results
    function Strategy(universe::Universe,
                      indicator::AbstractIndicator,
                      rules::Tuple{Vararg{Rule}},
                      portfolio::Portfolio=Portfolio(universe))
        return new(universe, indicator, rules, portfolio, Results())
    end
end

function generate_trades(strat::Strategy; verbose::Bool=true)::Dict{String,Temporal.TS}
    all_trades = Dict{String,Temporal.TS}()
    for asset in strat.universe.assets
        verbose ? print("Generating trades for asset $asset...") : nothing
        trades = Temporal.TS(falses(size(strat.universe.data[asset],1), length(strat.rules)),
                    strat.universe.data[asset].index)
        local indicator_data = calculate(strat.indicator, strat.universe.data[asset])
        for (i,rule) in enumerate(strat.rules);
            vals = rule.trigger.fun(indicator_data)
            trades[:,i] = vals
        end
        all_trades[asset] = trades
        verbose ? print("Done.\n") : nothing
    end
    return all_trades
end

function generate_trades!(strat::Strategy; args...)::Nothing
    strat.results.trades = generate_trades(strat; args...)
    return nothing
end

function backtest(strat::Strategy; verbose::Bool=true)::Dict{String,Temporal.TS{Float64}}
    if isempty(strat.results.trades)
        generate_trades!(strat, verbose=verbose)
    end
    result = Dict{String,Temporal.TS}()
    for (asset,opn_cls) in zip(strat.universe.assets,strat.universe.trade_symbols)
        verbose ? print("Running backtest for asset $asset...") : nothing
        trades = strat.results.trades[asset].values
        N = size(trades, 1)
        summary_ts = strat.universe.data[asset]
        #TODO: add setindex! method for TS objects using Symbol and Vector to assign inplace
        #TODO: generalize this logic to incorporate order types
        #FIXME: generalize this logic to use the actual rules (this is a temporary quickfix)

        # grab the right columns from the asset
        px_trade = opn_cls[:trade_symb]
        px_close = opn_cls[:close_symb]

        # useful errors if the trade/close symbols are not found
        if !(px_trade ∈ summary_ts.fields)
            error("The key $px_trade, is not in $asset.\n the data has the following fields:\n $(summary_ts.fields)")
        end
        if !(px_close ∈ summary_ts.fields)
            error("The key $px_close, is not in $asset.\n the data has the following fields:\n $(summary_ts.fields)")
        end

        trade_price = summary_ts[px_trade].values
        close_price = summary_ts[px_close].values
        pos = zeros(Float64, N)
        pnl = zeros(Float64, N)
        do_trade = false
        for t in 2:N
            for (i,rule) in enumerate(strat.rules)
                if trades[t-1,i] != 0
                    do_trade = true
                    #TODO: fill out this logic with the various order types
                    order_side = rule.action in (long,buy) ? 1 : rule.action in (short,sell) ? -1 : 0
                    #TODO: add logic here for the int vs. float argument type to order function
                    (order_qty,) = rule.args
                    #if isa(order_qty, Int); else FIXME: portfolio adjustment logic; end
                    pos[t] = order_qty * order_side
                    pnl[t] = pos[t] * (close_price[t] - trade_price[t])
                end
            end
            if !do_trade
                pos[t] = pos[t-1]
                pnl[t] = pos[t] * (close_price[t]-close_price[t-1])
            end
            do_trade = false
        end
        summary_ts = [summary_ts Temporal.TS([pos pnl cumsum(pnl)], summary_ts.index, [:Pos,:PNL,:CumPNL])]
        result[asset] = summary_ts
        verbose ? print("Done.\n") : nothing
    end
    return result
end

function backtest!(strat::Strategy; args...)::Nothing
    strat.results.backtest = backtest(strat; args...)
    return nothing
end

Base.copy(strat::Strategy) = Strategy(strat.universe, strat.indicator, strat.rules)

#TODO: more meaningful progres information
#TODO: parallel processing
#TODO: streamline this so that it doesnt run so slow (seems to be recompiling at each run)
function optimize(strat::Strategy; samples::Int=0, seed::Int=0, verbose::Bool=true, summary_fun::Function=cum_pnl, args...)::Matrix
    strat_save = copy(strat)
    n_runs = get_n_runs(strat.indicator.paramset)
    idx_samples::Vector{Int} = collect(1:n_runs)
    if samples > 0
        Random.seed!(seed)
        idx_samples = rand(idx_samples, samples)
    else
        samples = n_runs
    end
    combos = get_param_combos(strat.indicator.paramset, n_runs=n_runs)[idx_samples,:]
    result = zeros(samples)
    for (run, combo) in enumerate(idx_samples)
        verbose ? println("Run $run/$samples") : nothing
        strat.indicator.paramset.arg_defaults = combo
        generate_trades!(strat, verbose=false)
        backtest!(strat, verbose=false; args...)
        result[run] = summary_fun(strat.results.backtest)
    end
    # prevent out-of-scope alteration of strat object
    strat = strat_save
    return result
end

# TODO: implement function to edit results member of strat in place
function optimize!(strat::Strategy; samples::Int=0, seed::Int=0, verbose::Bool=true, summary_fun::Function=cum_pnl, args...)::Nothing
    n_runs = get_n_runs(strat.indicator.paramset)
    idx_samples::Vector{Int} = collect(1:n_runs)
    if samples > 0
        if seed >= 0
            Random.seed!(seed)
        end
        idx_samples = rand(idx_samples, samples)
    else
        samples = n_runs
    end
    combos = get_param_combos(strat.indicator.paramset, n_runs=n_runs)[idx_samples,:]
    strat.results.optimization = zeros(samples,1)
    for (run, combo) in enumerate([combos[i,:] for i in 1:size(combos,1)])
        verbose ? println("Run $run/$samples") : nothing
        strat.indicator.paramset.arg_defaults = combo
        generate_trades!(strat, verbose=false)
        backtest!(strat, verbose=false; args...)
        strat.results.optimization[run] = summary_fun(strat.results)
    end
    strat.results.optimization = [combos strat.results.optimization]
    return nothing
end
