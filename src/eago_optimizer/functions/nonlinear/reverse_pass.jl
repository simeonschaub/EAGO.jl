# Copyright (c) 2018: Matthew Wilhelm & Matthew Stuber.
# This work is licensed under the Creative Commons Attribution-NonCommercial-
# ShareAlike 4.0 International License. To view a copy of this license, visit
# http://creativecommons.org/licenses/by-nc-sa/4.0/ or send a letter to Creative
# Commons, PO Box 1866, Mountain View, CA 94042, USA.
#############################################################################
# EAGO
# A development environment for robust and global optimization
# See https://github.com/PSORLab/EAGO.jl
#############################################################################
# src/eago_optimizer/evaluator/passes.jl
# Functions used to compute reverse pass of nonlinear functions.
#############################################################################

# maximum number to perform reverse operation on associative term by summing
# and evaluating pairs remaining terms not reversed
const MAX_ASSOCIATIVE_REVERSE = 4

# INSIDE DONE...
function reverse_plus_binary!()

    # extract values for k
    argk_index = @inbounds children_arr[k]
    argk_is_number = @inbounds numvalued[k]
    if !argk_is_number
        setk = @inbounds setstorage[argk_index]
    end

    # don't perform a reverse pass if the output was a number
    if argk_is_number
        return nothing
    end

    # get row indices
    idx1 = first(children_idx)
    idx2 = last(children_idx)

    # extract values for argument 1
    arg1_index = @inbounds children_arr[idx1]
    arg1_is_number = @inbounds numvalued[arg1_index]
    if arg1_is_number
        set1 = zero(MC{N,T})
        num1 = @inbounds numberstorage[arg1_index]
    else
        num1 = 0.0
        set1 = @inbounds setstorage[arg1_index]
    end

    # extract values for argument 2
    arg2_index = @inbounds children_arr[idx2]
    arg2_is_number = @inbounds numvalued[arg2_index]
    if arg2_is_number
        num2 = @inbounds numberstorage[arg2_index]
        set2 = zero(MC{N,T})
    else
        set2 = @inbounds setstorage[arg2_index]
        num2 = 0.0
    end

    if !arg1_is_number && arg2_is_number
        c, a, b = plus_rev(setk, set1, num2)

    elseif arg1_is_number && !arg2_is_number
        c, a, b  = plus_rev(setk, num1, set2)

    else
        c, a, b  = plus_rev(setk, set1, set2)
    end

    # empty or nan? handling here

    if is_post
        @inbounds setstorage[arg1_index] = set_value_post(x, a, lbd, ubd)
        @inbounds setstorage[arg2_index] = set_value_post(x, b, lbd, ubd)
    else
        @inbounds setstorage[arg1_index] = a
        @inbounds setstorage[arg2_index] = b
    end

    return nothing
end

function reverse_plus_narity!()
    #println("+")
    lenx = length(children_idx)
    count = 0
    child_arr_indx = children_arr[children_idx]
    for c_idx in child_arr_indx
        tmp_sum = 0.0
        @inbounds inner_chdset = numvalued[c_idx]
        if ~inner_chdset
            if count < MAX_ASSOCIATIVE_REVERSE
                for cin_idx in child_arr_indx
                    if cin_idx != c_idx
                        if @inbounds numvalued[cin_idx]
                            tmp_sum += @inbounds numberstorage[cin_idx]
                        else
                            tmp_sum += @inbounds setstorage[cin_idx]
                        end
                    end
                end
                @inbounds tmp_hold = setstorage[c_idx]
                pnew, xhold, xsum = plus_rev(parent_value, tmp_hold, tmp_sum)
                if isempty(pnew) || isempty(xhold) || isempty(xsum)
                    continue_flag = false
                    break
                end
                if isnan(pnew)
                    pnew = interval_MC(parent_value)
                end
                if isnan(xhold)
                    pnew = interval_MC(tmp_hold)
                end
                setstorage[k] = set_value_post(x_values, pnew, current_node, subgrad_tighten)
                setstorage[c_idx] = set_value_post(x_values, xhold, current_node, subgrad_tighten)
            else
                break
            end
        end
        count += 1
    end
    !continue_flag && break
    return nothing
end

function reverse_multiply_binary!()

    # extract values for k
    argk_index = @inbounds children_arr[k]
    argk_is_number = @inbounds numvalued[k]
    if !argk_is_number
        setk = @inbounds setstorage[argk_index]
    end

    # don't perform a reverse pass if the output was a number
    if argk_is_number
        return nothing
    end

    # get row indices
    idx1 = first(children_idx)
    idx2 = last(children_idx)

    # extract values for argument 1
    arg1_index = @inbounds children_arr[idx1]
    arg1_is_number = @inbounds numvalued[arg1_index]
    if arg1_is_number
        set1 = zero(MC{N,T})
        num1 = @inbounds numberstorage[arg1_index]
    else
        num1 = 0.0
        set1 = @inbounds setstorage[arg1_index]
    end

    # extract values for argument 2
    arg2_index = @inbounds children_arr[idx2]
    arg2_is_number = @inbounds numvalued[arg2_index]
    if arg2_is_number
        num2 = @inbounds numberstorage[arg2_index]
        set2 = zero(MC{N,T})
    else
        set2 = @inbounds setstorage[arg2_index]
        num2 = 0.0
    end

    if !arg1_is_number && arg2_is_number
        c, a, b = mult_rev(setk, set1, num2)

    elseif arg1_is_number && !arg2_is_number
        c, a, b = mult_rev(setk, num1, set2)

    else
        c, a, b = mult_rev(setk, set1, set2)
    end

    # empty or nan? handling here

    if is_post
        @inbounds setstorage[arg1_index] = set_value_post(x, a, lbd, ubd)
        @inbounds setstorage[arg2_index] = set_value_post(x, b, lbd, ubd)
    else
        @inbounds setstorage[arg1_index] = a
        @inbounds setstorage[arg2_index] = b
    end

    return nothing
end

function reverse_multiply_narity!()
    tmp_mlt = 1.0
    chdset = true
    count = 0
    child_arr_indx = children_arr[children_idx]
    for c_idx in child_arr_indx
        if count < MAX_ASSOCIATIVE_REVERSE
            if ~numvalued[c_idx]
                tmp_mlt = 1.0
                for cin_idx in child_arr_indx
                    if cin_idx != c_idx
                        @inbounds chdset = numvalued[cin_idx]
                        if chdset
                            @inbounds tmp_mlt *= numberstorage[cin_idx]
                        else
                            @inbounds tmp_mlt *= setstorage[cin_idx]
                        end
                    end
                end
                @inbounds chdset = numvalued[c_idx]
                if chdset
                    @inbounds pnew, xhold, xprd = mul_rev(parent_value, numberstorage[c_idx], tmp_mlt)
                else
                    @inbounds pnew, xhold, xprd = mul_rev(parent_value, setstorage[c_idx], tmp_mlt)
                end
                if isempty(pnew) || isempty(xhold) || isempty(xprd)
                    continue_flag = false
                    break
                end
                if isnan(pnew)
                    pnew = interval_MC(parent_value)
                end
                if isnan(xhold)
                    xhold = interval_MC(setstorage[c_idx])
                end
                setstorage[k] = set_value_post(x_values,  pnew, current_node, subgrad_tighten)
                setstorage[c_idx] = set_value_post(x_values, xhold, current_node, subgrad_tighten)
                count += 1
            end
        else
            break
        end
    end
    return nothing
end

function reverse_minus!()

    # extract values for k
    argk_index = @inbounds children_arr[k]
    argk_is_number = @inbounds numvalued[k]
    if !argk_is_number
        setk = @inbounds setstorage[argk_index]
    end

    # don't perform a reverse pass if the output was a number
    if argk_is_number
        return nothing
    end

    # get row indices
    idx1 = first(children_idx)
    idx2 = last(children_idx)

    # extract values for argument 1
    arg1_index = @inbounds children_arr[idx1]
    arg1_is_number = @inbounds numvalued[arg1_index]
    if arg1_is_number
        set1 = zero(MC{N,T})
        num1 = @inbounds numberstorage[arg1_index]
    else
        num1 = 0.0
        set1 = @inbounds setstorage[arg1_index]
    end

    # extract values for argument 2
    arg2_index = @inbounds children_arr[idx2]
    arg2_is_number = @inbounds numvalued[arg2_index]
    if arg2_is_number
        num2 = @inbounds numberstorage[arg2_index]
        set2 = zero(MC{N,T})
    else
        set2 = @inbounds setstorage[arg2_index]
        num2 = 0.0
    end

    if !arg1_is_number && arg2_is_number
        c, a, b = minus_rev(setk, set1, num2)

    elseif arg1_is_number && !arg2_is_number
        c, a, b = minus_rev(setk, num1, set2)

    else
        c, a, b = minus_rev(setk, set1, set2)
    end

    # empty or nan? handling here

    if is_post
        @inbounds setstorage[arg1_index] = set_value_post(x, a, lbd, ubd)
        @inbounds setstorage[arg2_index] = set_value_post(x, b, lbd, ubd)
    else
        @inbounds setstorage[arg1_index] = a
        @inbounds setstorage[arg2_index] = b
    end

    return nothing
end

function reverse_power!()

    # extract values for k
    argk_index = @inbounds children_arr[k]
    argk_is_number = @inbounds numvalued[k]
    if !argk_is_number
        setk = @inbounds setstorage[argk_index]
    end

    # don't perform a reverse pass if the output was a number
    if argk_is_number
        return nothing
    end

    # get row indices
    idx1 = first(children_idx)
    idx2 = last(children_idx)

    # extract values for argument 1
    arg1_index = @inbounds children_arr[idx1]
    arg1_is_number = @inbounds numvalued[arg1_index]
    if arg1_is_number
        set1 = zero(MC{N,T})
        num1 = @inbounds numberstorage[arg1_index]
    else
        num1 = 0.0
        set1 = @inbounds setstorage[arg1_index]
    end

    # extract values for argument 2
    arg2_index = @inbounds children_arr[idx2]
    arg2_is_number = @inbounds numvalued[arg2_index]
    if arg2_is_number
        num2 = @inbounds numberstorage[arg2_index]
        set2 = zero(MC{N,T})
    else
        set2 = @inbounds setstorage[arg2_index]
        num2 = 0.0
    end

    if !arg1_is_number && arg2_is_number
        c, a, b = power_rev(setk, set1, num2)

    elseif arg1_is_number && !arg2_is_number
        c, a, b = power_rev(setk, num1, set2)

    else
        c, a, b = power_rev(setk, set1, set2)
    end

    # empty or nan? handling here

    if is_post
        @inbounds setstorage[arg1_index] = set_value_post(x, a, lbd, ubd)
        @inbounds setstorage[arg2_index] = set_value_post(x, b, lbd, ubd)
    else
        @inbounds setstorage[arg1_index] = a
        @inbounds setstorage[arg2_index] = b
    end

    return nothing
end

function reverse_divide!()

    # extract values for k
    argk_index = @inbounds children_arr[k]
    argk_is_number = @inbounds numvalued[k]
    if !argk_is_number
        setk = @inbounds setstorage[argk_index]
    end

    # don't perform a reverse pass if the output was a number
    if argk_is_number
        return nothing
    end

    # get row indices
    idx1 = first(children_idx)
    idx2 = last(children_idx)

    # extract values for argument 1
    arg1_index = @inbounds children_arr[idx1]
    arg1_is_number = @inbounds numvalued[arg1_index]
    if arg1_is_number
        set1 = zero(MC{N,T})
        num1 = @inbounds numberstorage[arg1_index]
    else
        num1 = 0.0
        set1 = @inbounds setstorage[arg1_index]
    end

    # extract values for argument 2
    arg2_index = @inbounds children_arr[idx2]
    arg2_is_number = @inbounds numvalued[arg2_index]
    if arg2_is_number
        num2 = @inbounds numberstorage[arg2_index]
        set2 = zero(MC{N,T})
    else
        set2 = @inbounds setstorage[arg2_index]
        num2 = 0.0
    end

    if !arg1_is_number && arg2_is_number
        c, a, b = power_rev(setk, set1, num2)

    elseif arg1_is_number && !arg2_is_number
        c, a, b = power_rev(setk, num1, set2)

    else
        c, a, b = power_rev(setk, set1, set2)
    end

    # empty or nan? handling here

    if is_post
        @inbounds setstorage[arg1_index] = set_value_post(x, a, lbd, ubd)
        @inbounds setstorage[arg2_index] = set_value_post(x, b, lbd, ubd)
    else
        @inbounds setstorage[arg1_index] = a
        @inbounds setstorage[arg2_index] = b
    end

    return nothing
end

function reverse_univariate!()
    op = nod.index
    child_idx = children_arr[adj.colptr[k]]
    @inbounds child_value = setstorage[child_idx]
    @inbounds parent_value = setstorage[k]
    pnew, cnew = eval_univariate_set_reverse(op, parent_value, child_value)
    if (isempty(pnew) || isempty(cnew))
        continue_flag = false
        break
    end
    if isnan(pnew)
        pnew = interval_MC(parent_value)
    end
    if isnan(cnew)
        cnew = interval_MC(child_value)
    end
    @inbounds setstorage[child_idx] = set_value_post(x_values, cnew, current_node, subgrad_tighten)
    @inbounds setstorage[k] = set_value_post(x_values, pnew, current_node, subgrad_tighten)

    return nothing
end

"""
$(TYPEDSIGNATURES)
"""
function reverse_pass_kernel(setstorage::Vector{T}, numberstorage, numvalued, subexpression_isnum,
                             subexpr_values_set, nd::Vector{JuMP.NodeData}, adj, x_values, current_node::NodeBB,
                             subgrad_tighten::Bool) where T

    @assert length(setstorage) >= length(nd)
    @assert length(numberstorage) >= length(nd)
    @assert length(numvalued) >= length(nd)

    children_arr = rowvals(adj)
    N = length(x_values)

    tmp_hold = zero(T)
    continue_flag = true

    for k = 1:length(nd)

        @inbounds nod = nd[k]
        ntype = nod.nodetype
        nvalued = @inbounds numvalued[k]

        if ntype == JuMP._Derivatives.VALUE      || ntype == JuMP._Derivatives.LOGIC     ||
           ntype == JuMP._Derivatives.COMPARISON || ntype == JuMP._Derivatives.PARAMETER ||
           ntype == JuMP._Derivatives.EXTRA
           continue

        elseif nod.nodetype == JuMP._Derivatives.VARIABLE
            op = nod.index
            @inbounds current_node.lower_variable_bounds[op] = setstorage[k].Intv.lo
            @inbounds current_node.upper_variable_bounds[op] = setstorage[k].Intv.hi

        elseif nod.nodetype == JuMP._Derivatives.SUBEXPRESSION
            #=
            @inbounds isnum = subexpression_isnum[nod.index]
            if ~isnum
                @inbounds subexpr_values_set[nod.index] = setstorage[k]
            end          # DONE
            =#

        elseif nvalued
            continue

        elseif nod.nodetype == JuMP._Derivatives.CALL
            op = nod.index
            parent_index = nod.parent
            @inbounds children_idx = nzrange(adj,k)
            @inbounds parent_value = setstorage[k]
            n_children = length(children_idx)

            # SKIPS USER DEFINE OPERATORS NOT BRIDGED INTO JuMP Tree Representation
            if op >= JuMP._Derivatives.USER_OPERATOR_ID_START
                continue

            # :+
            elseif op === 1
                if n_children === 2
                    reverse_plus_binary!()
                else
                    reverse_plus_narity!()
                end

            # :-
            elseif op === 2
                reverse_minus!()

            elseif op === 3 # :*
                if n_children === 2
                    reverse_multiply_binary!()
                else
                    reverse_multiply_narity!()
                end

             # :^
            elseif op === 4
                reverse_power!()

            # :/
            elseif op === 5
                reverse_divide!()

            elseif op == 6 # ifelse
                continue
            end

        # assumes that child is set-valued and thus parent is set-valued (since isnumber already checked)
        elseif nod.nodetype == JuMP._Derivatives.CALLUNIVAR
            reverse_univariate!()

        end

        !continue_flag && break
    end

    return continue_flag
end
