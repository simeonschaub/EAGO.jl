# Copyright (c) 2018: Matthew Wilhelm & Matthew Stuber.
# This code is licensed under MIT license (see LICENSE.md for full details)
#############################################################################
# EAGO
# A development environment for robust and global optimization
# See https://github.com/PSORLab/EAGO.jl
#############################################################################
# src/eago_optimizer/evaluator/passes.jl
# Functions used to compute forward pass of nonlinear functions which include:
# set_value_post, overwrite_or_intersect, forward_pass_kernel, associated blocks
#############################################################################

f_init!(::Type{Relax}, g::AbstractDG, b::RelaxCache) = nothing

function _var_set(::Type{MC{N,T}}, i::Int, x_cv::S, x_cc::S, l::S, u::S) where {N,T,S}
    v = seed_gradient(i, Val(N))
    return MC{N,T}(x_cv, x_cc, Interval{S}(l, u), v, v, false)
end

function fprop!(::Type{Relax}, ::Type{Variable}, g::AbstractDG, b::RelaxCache{V}, k::Int) where V
    i = _first_index(g, k)
    x = _val(b, i)
    z = _var_set(V, _rev_sparsity(g, i, k), x, x, _lbd(b, i), _ubd(b, i))
    if _first_eval(b)
        z = z ∩ _interval(b, k)
    end
    _store_set!(b, z, k)
    return
end

function expand_set(::Type{MC{N2,T}}, x::MC{N1,T}, fsparse::Vector{Int},
                    subsparse::Vector{Int}, cv_buffer::Vector{S},
                    cc_buffer::Vector{S}) where {N1, N2, S, T<:RelaxTag}

    cvg = x.cv_grad
    ccg = x.cc_grad
    xcount = 1
    xcurrent = subsparse[1]
    for i = 1:N2
        if fsparse[i] === xcurrent
            cv_buffer[i] = cvg[xcount]
            cc_buffer[i] = ccg[xcount]
            xcount += 1
            if xcount <= N1
                xcurrent = subsparse[xcount]
            else
                break
            end
        else
            cv_buffer[i] = zero(S)
        end
    end
    cv_grad = SVector{N2,Float64}(cv_buffer)
    cc_grad = SVector{N2,Float64}(cc_buffer)
    return MC{N2,T}(x.cv, x.cc, x.Intv, cv_grad, cc_grad, x.cnst)
end

function fprop!(::Type{Relax}, ::Type{Subexpression}, g::AbstractDG, c::RelaxCache{V}, k::Int) where V
    d = _subexpression_value(c, _first_index(g, k))
    z = expand_set(V, d.set[1], _sparsity(g, k), _sparsity(sub), c.cv_buffer, c.cc_buffer)
    _store_set!(c, z, k)
    return
end

function set_value_post(z::MC{N,T}, v::VariableValues{S}, s::Vector{Int}, ϵ::Float64) where {N,T<:RelaxTag,S}
    lower = z.cv
    upper = z.cc
    lower_refinement = true
    upper_refinement = true
    @inbounds for i = 1:N
        cv_val = z.cv_grad[i]
        cc_val = z.cc_grad[i]
        i_sol = s[i]
        x_z = v.x[i_sol]
        lower_bound = v.lbd[i_sol]
        upper_bound = v.ubd[i_sol]
        if lower_refinement
            if cv_val > zero(S)
                if isinf(lower_bound)
                    !upper_refinement && break
                    lower_refinement = false
                else
                    lower += cv_val*(lower_bound - x_z)
                end
            else
                if isinf(upper_bound)
                    !upper_refinement && break
                    lower_refinement = false
                else
                    lower += cv_val*(upper_bound - x_z)
                end
            end
        end
        if upper_refinement
            if cc_val > zero(S)
                if isinf(lower_bound)
                    !lower_refinement && break
                    upper_refinement = false
                else
                    upper += cc_val*(upper_bound - x_z)
                end
            else
                if isinf(upper_bound)
                    !lower_refinement && break
                    upper_refinement = false
                else
                    upper += cc_val*(lower_bound - x_z)
                end
            end
        end
    end

    if lower_refinement && (z.Intv.lo + ϵ > lower)
        lower = z.Intv.lo
    elseif !lower_refinement
        lower = z.Intv.lo
    else
        lower -= ϵ
    end

    if upper_refinement && (z.Intv.hi - ϵ < upper)
        upper = z.Intv.hi
    elseif !upper_refinement
        upper = z.Intv.hi
    else
        upper += ϵ
    end

    return MC{N,T}(z.cv, z.cc, Interval{Float64}(lower, upper), z.cv_grad, z.cc_grad, z.cnst)
end

"""
$(FUNCTIONNAME)

Intersects the new set valued operator with the prior and performs affine bound tightening

- First forward pass: `is_post` should be set by user option, `is_intersect` should be false
  so that the tape overwrites existing values, and the `interval_intersect` flag could be set
  to either value.
- Forward CP pass (assumes same reference point): `is_post` should be set by user option,
  `is_intersect` should be true so that the tape intersects with  existing values, and the
  `interval_intersect` flag should be false.
- Forward CP pass (assumes same reference point): `is_post` should be set by user option,
  `is_intersect` should be true so that the tape intersects with existing values, and the
  `interval_intersect` flag should be false.
- Subsequent forward passes at new points: is_post` should be set by user option,
  `is_intersect` should be true so that the tape intersects with existing values, and the
  `interval_intersect` flag should be `true` as predetermined interval bounds are valid but
   the prior values may correspond to different points of evaluation.
"""
function _cut(x::V, lastx::V, v::VariableValues, ϵ::S, s::Vector{Int},
              post::Bool, cut::Bool, cut_interval::Bool) where {V,S}

    if post && cut && cut_interval
        return set_value_post(x ∩ lastx.Intv, v, s, ϵ)
    elseif post && cut && !cut_interval
        return set_value_post(x ∩ lastx, v, s, ϵ)
    elseif post && !cut
        return set_value_post(x, v, s, ϵ)
    elseif !post && cut && cut_interval
        return x ∩ lastx.Intv
    elseif !post && cut && !cut_interval
        return x ∩ lastx
    end
    return x
end

for (f, F) in ((:fprop_2!, +), (:fprop_2!, *), (:fprop_2!, min), (:fprop_2!, max),
               (:fprop!, -), (:fprop!, /))
    @eval function ($f)(::Type{Relax}, ::typeof($F), g::AbstractDG, b::RelaxCache{V,S}, k::Int) where {V,S}
        x = _child(g, 1, k)
        y = _child(g, 2, k)
        x_is_num = _is_num(b, x)
        y_is_num = _is_num(b, y)
        if !x_is_num && y_is_num
            z = ($F)(_set(b, x), _num(b, y))
        elseif x_is_num && !y_is_num
            z = ($F)(_num(b, x), _set(b, y))
        else
            z = ($F)(_set(b, x), _set(b, y))
        end
        z = _cut(z, _set(b,k), b.v, b.ϵ_sg, _sparsity(g, k), false, b.cut, b.cut_interval)
        _store_set!(b, z, k)
        return
    end
end
for (F, SV, NV) in ((+, :(zero(V)), :(zero(S))),
                    (*, :(one(V)), :(one(S))),
                    (min, :(inf(V)), :(typemax(S))),
                    (max, :(-inf(V)), :(typemin(S))))
    @eval function fprop_n!(::Type{Relax}, ::typeof($F), g::AbstractDG, b::RelaxCache{V,S}, k::Int) where {V,S}
        z = $SV
        znum = $NV
        for i in _children(g, k)
            if _is_num(b, i)
                znum = ($F)(znum, _num(b, i))
                continue
            end
            z = ($F)(z, _set(b, i))
        end
        z = ($F)(z, znum)
        z = _cut(z, _set(b, k), b.v, b.ϵ_sg, _sparsity(g, k), false, b.cut, b.cut_interval)
        _store_set!(b, z, k)
        return
    end
end
for F in (+, *, min, max)
    @eval function fprop!(::Type{Relax}, ::typeof($F), g::AbstractDG, b::RelaxCache{V,S}, k::Int) where {V,S}
        n = _arity(g, k)
        if n == 2
            return fprop_2!(Relax, $F, g, b, k)
        end
        fprop_n!(Relax, $F, g, b, k)
    end
end
function fprop!(::Type{Relax}, ::typeof(^), g::AbstractDG, b::RelaxCache{V,S}, k::Int) where {V,S}
    x = _child(g, 1, k)
    y = _child(g, 2, k)
    x_is_num = is_num(b, x)
    y_is_num = is_num(b, y)
    if y_is_num && isone(_num(b, y))
        _store_set!(b, _set(b, x), k)
    elseif y_is_num && iszero(_num(b, y))
        _store_set!(b, zero(V), k)
    else
        if !x_is_num && y_is_num
            z = _set(b, x)^_num(b, y)
        elseif x_is_num && !y_is_num
            z = _num(b, x)^_set(b, x)
        elseif !x_is_num && !y_is_num
            z = _set(b, x)^_set(b, x)
        end
        z = _cut(z, _set(b, k), b.v, 0.0, _sparsity(g,k), b.is_post, b.cut, b.cut_interval)
        _store_set!(b, z, k)
    end
    return
end
function fprop!(::Type{Relax}, ::typeof(user), g::AbstractDG, b::RelaxCache{V,S}, k::Int) where {V,S}
    f = _user_univariate_operator(g, _index(g, k))
    x = _set(b, _child(g, 1, k))
    z = _cut(f(x), _set(b, k), b.v, zero(S), _sparsity(g, k), b.is_post, b.cut, b.cut_interval)
    _store_set!(b, z, k)
    return
end
function fprop!(::Type{Relax}, ::typeof(usern), g::AbstractDG, b::RelaxCache{V,S}, k::Int) where {V,S}
    mv = _user_multivariate_operator(g, _index(g, k))
    n = _arity(g, k)
    set_input = _set_input(b, n)
    i = 1
    for c in _children(g, k)
        if _is_num(b, c)
            x = _num(b, c)
            if !isinf(x)
                @inbounds set_input[i] = V(x)
            end
        else
            @inbounds set_input[i] = _set(b, c)
        end
        i += 1
    end
    z = MOI.eval_objective(mv, set_input)
    z = _cut(z, _set(b, k), b.v, zero(V), _sparsity(g,k), b.post, b.cut, b.cut_interval)
    _store_set!(b, z, k)
    return
end

#=
TODO: Univariates
for F in univariate()
    @eval function fprop!(::Type{Relax}, ::typeof($F), g::DAG, b::RelaxCache{V}, k::Int) where V

        z = eval_univariate_set(op, b.set[i])
        b.set[k] = _cut(z, b.set[k], b.v, 0.0, g.sparsity[k], b.is_post, b.cut, b.cut_interval)
        return
    end
end
=#
