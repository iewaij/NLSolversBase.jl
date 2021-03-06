# To pass incomplete specifications, we provide the "only_"
# family of functions. It allows the users to simply provide
# fg! for optimization or fj! for solving systems of equations
# and have NLSolversBase wrap them up properly so "F" can be
# calculated on its own and the save for partial derivatives.
# Note, that for TwiceDifferentiable we cannot provide con-
# structors if h == nothing, as that requires automatic dif-
# fferentiation of some sort.
struct InplaceObjective{DF, FDF, FGH}
    df::DF
    fdf::FDF
    fgh::FGH
end
struct NotInplaceObjective{DF, FDF, FGH}
    df::DF
    fdf::FDF
    fgh::FGH
end
# Mutating version
only_fg!(fg)   = InplaceObjective(nothing, fg,      nothing)
only_fgh!(fgh) = InplaceObjective(nothing, nothing, fgh)
only_fj!(fj)   = InplaceObjective(nothing, fj,      nothing)

# Non-mutating version
only_fg(fg)  = NotInplaceObjective(nothing, fg,      nothing)
only_fj(fj)  = NotInplaceObjective(nothing, fj,      nothing)

only_g_and_fg(g, fg) = NotInplaceObjective(g, fg, nothing)
only_j_and_fj(j, fj) = NotInplaceObjective(j, fj, nothing)

df(t::Union{InplaceObjective, NotInplaceObjective}) = t.df
fdf(t::Union{InplaceObjective, NotInplaceObjective}) = t.fdf

# Mutating version
make_f(t::InplaceObjective, x, F::Real) = x -> fdf(t)(F, nothing, x)
make_f(t::InplaceObjective, x, F) =  (F, x) -> fdf(t)(F, nothing, x)
make_df(t::InplaceObjective, x, F) = (DF, x) -> fdf(t)(nothing, DF, x)
make_fdf(t::InplaceObjective, x, F::Real) = (G, x) -> fdf(t)(F, G, x)
make_fdf(t::InplaceObjective, x, F) = fdf(t)

# Non-mutating version
# The contract with the user is that fdf returns (F, DF)
# and then we simply need to pick out the appropriate element
# of whatever fdf returns.
make_f(t::NotInplaceObjective, x, F::Real) = x -> fdf(t)(x)[1]
make_f(t::NotInplaceObjective, x, F) = (F, x) -> copyto!(F, fdf(t)(x)[1])
make_df(t::NotInplaceObjective{DF, TDF}, x, F) where {DF<:Nothing, TDF} = (DF, x) -> copyto!(DF, fdf(t)(x)[2])
make_df(t::NotInplaceObjective, x, F) = t.df
function make_fdf(t::NotInplaceObjective, x, F::Real)
    return function ffgg!(G, x)
        f, g = fdf(t)(x)
        copyto!(G, g)
        f
    end
end
function make_fdf(t::NotInplaceObjective, x, F)
    return function ffjj!(F, J, x)
        f, j = fdf(t)(x)
        copyto!(J, j)
        copyto!(F, f)
    end
end

# Constructors
function NonDifferentiable(t::Union{InplaceObjective, NotInplaceObjective}, x::AbstractArray, F::Real = real(zero(eltype(x))))
    f = make_f(t, x, F)
    NonDifferentiable(f, x, F)
end
# this would not be possible if we could mark f, g, ... as non-AbstractArrays
function NonDifferentiable(t::Union{InplaceObjective, NotInplaceObjective}, x::AbstractArray, F::AbstractArray)
    f = make_f(t, x, F)
    NonDifferentiable(f, x, F)
end


function TwiceDifferentiable(t::InplaceObjective{<: Nothing, <: Nothing, TH}, x::AbstractArray, F::Real = real(zero(eltype(x))), G::AbstractArray = similar(x), H = alloc_H(x)) where {TH}
    f   =     x  -> t.fgh(F, nothing, nothing, x)
    df  = (G, x) -> t.fgh(nothing, G, nothing, x)
    fdf = (G, x) -> t.fgh(F, G, nothing, x)
    h   = (H, x) -> t.fgh(F, nothing, H, x)
    TwiceDifferentiable(f, df, fdf, h, x, F, G, H)
end

function TwiceDifferentiable(t::InplaceObjective{<: Nothing, <: Nothing, TH}, x::AbstractVector, F::Real = real(zero(eltype(x))), G::AbstractVector = similar(x)) where {TH}

    H = alloc_H(x)
    f   =     x  -> t.fgh(F, nothing, nothing, x)
    df  = (G, x) -> t.fgh(nothing, G, nothing, x)
    fdf = (G, x) -> t.fgh(F, G, nothing, x)
    h   = (H, x) -> t.fgh(F, nothing, H, x)
    TwiceDifferentiable(f, df, fdf, h, x, F, G, H)
end
