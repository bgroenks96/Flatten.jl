module Flatten

using FieldMetadata, Requires 
import FieldMetadata: @flattenable, @reflattenable, flattenable

export @flattenable, 
       @reflattenable, 
       flattenable, 
       flatten, 
       reconstruct, 
       retype, 
       update!, 
       metaflatten,
       fieldnameflatten, 
       parentflatten, 
       fieldtypeflatten, 
       parenttypeflatten 

function __init__()
    @require Unitful="1986cc42-f94f-5a68-af5c-568840ba703d" begin
        using Unitful
        export ulflatten, 
               ulreconstruct, 
               ulupdate!
        include("unitless.jl")
    end
end

# Generalised nested struct walker 
nested(T::Type, expr_builder, expr_combiner, funcname) = 
    nested(T, Nothing, expr_builder, expr_combiner, funcname)
nested(T::Type, P::Type, expr_builder, expr_combiner, funcname) = 
    expr_combiner(T, [Expr(:..., expr_builder(T, fn, funcname)) for fn in fieldnames(T)])

default_combiner(T, expressions) = Expr(:tuple, expressions...)


flatten_expr(T, fname, funcname) = quote
    if flattenable($T, Val{$(QuoteNode(fname))})
        $funcname(getfield(t, $(QuoteNode(fname))))
    else
        ()
    end
end

flatten_inner(T, funcname) = nested(T, flatten_expr, default_combiner, funcname)

"Flattening. Flattens a nested type to a Tuple or Vector"
flatten(::Type{V}, t) where V <: AbstractVector = V([flatten(t)...])
flatten(::Type{Tuple}, t) = flatten(t)
flatten(x::Nothing) = ()
flatten(x::Number) = (x,) 
@generated flatten(t) = flatten_inner(t, :flatten)


metaflatten_expr(T, fname, funcname) = quote
    if flattenable($T, Val{$(QuoteNode(fname))})
        $funcname(getfield(t, $(QuoteNode(fname))), func, $T, Val{$(QuoteNode(fname))})
    else
        ()
    end
end

metaflatten_inner(T::Type, funcname) = nested(T, metaflatten_expr, default_combiner, funcname)

" Tag flattening. Flattens data attached to a field by methods of a passed in function"
metaflatten(::Type{Tuple}, t, func) = metaflatten(t, func)
metaflatten(::Type{V}, t, func) where V <: AbstractVector = [metaflatten(t, func)...]

metaflatten(x::Nothing, func, P, fname) = ()
metaflatten(x::Number, func, P, fname) = (func(P, fname),)
metaflatten(xs::NTuple{N,Number}, func, P, fname) where N = map(x -> func(P, fname), xs)
metaflatten(t, func) = metaflatten(t, func, Nothing, Val{:none})
@generated metaflatten(t, func, P, fname) = metaflatten_inner(t, :metaflatten)


# # Helper functions to get field data with metaflatten
fieldname_meta(T, ::Type{Val{N}}) where N = N
fieldtype_meta(T, ::Type{Val{N}}) where N = fieldtype(T, N)
fieldparent_meta(T, ::Type{Val{N}}) where N = T.name.name
fieldparenttype_meta(T, ::Type{Val{N}}) where N = T 

fieldnameflatten(T::Type, t) = metaflatten(T, t, fieldname_meta)
fieldnameflatten(t) = fieldnameflatten(Tuple, t)  

fieldtypeflatten(T::Type, t) = metaflatten(T, t, fieldtype_meta)
fieldtypeflatten(t) = fieldtypeflatten(Tuple, t) 

parentflatten(T::Type, t) = metaflatten(T, t, fieldparent_meta)
parentflatten(t) = parentflatten(Tuple, t) 

parenttypeflatten(T::Type, t) = metaflatten(T, t, fieldparenttype_meta)
parenttypeflatten(t) = parenttypeflatten(Tuple, t)


reconstruct_expr(T, fname, funcname) = quote
    if flattenable($T, Val{$(QuoteNode(fname))})
        val, n = $funcname(getfield(t, $(QuoteNode(fname))), data, n)
        val
    else
        (getfield(t, $(QuoteNode(fname))),)
    end
end

reconstruct_combiner(T, expressions) = :(($(Expr(:call, :($T), expressions...)),), n)
reconstruct_combiner(T::Type{<:Tuple}, expressions) = :(($(Expr(:tuple, expressions...)),), n)

reconstruct_inner(::Type{T}, funcname) where T = nested(T, reconstruct_expr, reconstruct_combiner, funcname)

" Reconstruct an object from partial Tuple or Vector data and another object"
reconstruct(t, data) = reconstruct(t, data, 1)[1][1]
reconstruct(::Nothing, data, n) = (nothing,), n
reconstruct(::Number, data, n) = (data[n],), n + 1 
@generated reconstruct(t, data, n) = reconstruct_inner(t, :reconstruct)


retype_expr(T, fname, funcname) = quote
    if flattenable($T, Val{$(QuoteNode(fname))})
        val, n = $funcname(getfield(t, $(QuoteNode(fname))), data, n)
        val
    else
        (getfield(t, $(QuoteNode(fname))),)
    end
end

retype_combiner(T, expressions) = :(($(Expr(:call, :($T.name.wrapper), expressions...)),), n)
retype_combiner(T::Type{<:Tuple}, expressions) = :(($(Expr(:tuple, expressions...)),), n)

retype_inner(::Type{T}, funcname) where T = nested(T, retype_expr, retype_combiner, funcname)

" Retype an object from partial Tuple or Vector data and another object"
retype(t, data) = retype(t, data, 1)[1][1]
retype(::Nothing, data, n) = (nothing,), n
retype(::Number, data, n) = (data[n],), n + 1 
@generated retype(t, data, n) = retype_inner(t, :retype)


update_expr(T, fname, funcname) = quote
    if flattenable($T, Val{$(QuoteNode(fname))})
        val, n = $funcname(getfield(t, $(QuoteNode(fname))), data, n)
        setfield!(t, $(QuoteNode(fname)), val[1]) 
    end
    ()
end

update_combiner(T, expressions) = :($(Expr(:tuple, expressions...)); ((t,), n))

update_inner(::Type{T}, funcname) where T = nested(T, update_expr, update_combiner, funcname)

" Update a mutable object with partial Tuple or Vector data"
update!(t, data) = begin
    update!(t, data, 1)[1][1]
    t
end
update!(::Nothing, data, n) = (nothing,), n
update!(::Number, data, n) = (data[n],), n + 1 
@generated update!(t::T, data, n) where T = update_inner(T, :update!)

end # module
