# Used for objectives and solvers where the gradient and Hessian is available/exists
mutable struct TwiceDifferentiable{T,TDF,TH,TX} <: AbstractObjective
    f
    df
    fdf
    h
    F::T
    DF::TDF
    H::TH
    x_f::TX
    x_df::TX
    x_h::TX
    f_calls::Vector{Int}
    df_calls::Vector{Int}
    h_calls::Vector{Int}
end
# compatibility with old constructor
function TwiceDifferentiable(f, g, fg, h, x::TX, F::T = real(zero(eltype(x))), G::TG = similar(x), H::TH = alloc_H(x); inplace = true) where {T, TG, TH, TX}
    x_f, x_df, x_h = x_of_nans(x), x_of_nans(x), x_of_nans(x)

    g! = df!_from_df(g, F, inplace)
    fg! = fdf!_from_fdf(fg, F, inplace)
    h! = h!_from_h(h, F, inplace)

    TwiceDifferentiable{T,TG,TH,TX}(f, g!, fg!, h!,
                                        copy(F), similar(G), copy(H),
                                        x_f, x_df, x_h,
                                        [0,], [0,], [0,])
end

function TwiceDifferentiable(f, g, h,
                             x::AbstractVector{TX},
                             F::Real = real(zero(eltype(x))),
                             G = similar(x),
                             H = alloc_H(x); inplace = true) where {TX}

    g! = df!_from_df(g, F, inplace)
    h! = h!_from_h(h, F, inplace)

    fg! = make_fdf(x, F, f, g!)

    return TwiceDifferentiable(f, g!, fg!, h!, x, F, G, H)
end



function TwiceDifferentiable(f, g,
                             x_seed::AbstractVector{T},
                             F::Real = real(zero(T)); autodiff = :finite, inplace = true) where T
    n_x = length(x_seed)

    g! = df!_from_df(g, F, inplace)

    fg! = make_fdf(x_seed, F, f, g!)

    if autodiff == :finite
        # TODO: Create / request Hessian functionality in DiffEqDiffTools?
        #       (Or is it better to use the finite difference Jacobian of a gradient?)
        # TODO: Allow user to specify Val{:central}, Val{:forward}, :Val{:complex}
        jcache = DiffEqDiffTools.JacobianCache(x_seed, Val{:central})
        function h!(storage, x)
            DiffEqDiffTools.finite_difference_jacobian!(storage, g!, x, jcache)
            return
        end
    elseif autodiff == :forward
        hcfg = ForwardDiff.HessianConfig(f, similar(x_seed))
        h! = (out, x) -> ForwardDiff.hessian!(out, f, x, hcfg)
    else
        error("The autodiff value $(autodiff) is not supported. Use :finite or :forward.")
    end
    TwiceDifferentiable(f, g!, fg!, h!, x_seed, F)
end

TwiceDifferentiable(d::NonDifferentiable, x_seed::AbstractVector{T} = d.x_f, F::Real = real(zero(T)); autodiff = :finite) where {T<:Real} =
    TwiceDifferentiable(d.f, x_seed, F; autodiff = autodiff)

function TwiceDifferentiable(d::OnceDifferentiable, x_seed::AbstractVector{T} = d.x_f,
                             F::Real = real(zero(T)); autodiff = :finite) where T<:Real
    if autodiff == :finite
        # TODO: Create / request Hessian functionality in DiffEqDiffTools?
        #       (Or is it better to use the finite difference Jacobian of a gradient?)
        # TODO: Allow user to specify Val{:central}, Val{:forward}, :Val{:complex}
        jcache = DiffEqDiffTools.JacobianCache(x_seed, Val{:central})
        function h!(storage, x)
            DiffEqDiffTools.finite_difference_jacobian!(storage, d.df, x, jcache)
            return
        end
    elseif autodiff == :forward
        hcfg = ForwardDiff.HessianConfig(d.f, similar(gradient(d)))
        h! = (out, x) -> ForwardDiff.hessian!(out, d.f, x, hcfg)
    else
        error("The autodiff value $(autodiff) is not supported. Use :finite or :forward.")
    end
    return TwiceDifferentiable(d.f, d.df, d.fdf, h!, x_seed, F, gradient(d))
end

function TwiceDifferentiable(f, x::AbstractVector, F::Real = real(zero(eltype(x)));
                             autodiff = :finite, inplace = true)
    if autodiff == :finite
        # TODO: Allow user to specify Val{:central}, Val{:forward}, Val{:complex}
        gcache = DiffEqDiffTools.GradientCache(x, x, Val{:central})
        function g!(storage, x)
            DiffEqDiffTools.finite_difference_gradient!(storage, f, x, gcache)
            return
        end
        function fg!(storage::Vector, x::Vector)
            g!(storage, x)
            return f(x)
        end
        # TODO: Allow user to specify Val{:central}, Val{:forward}, :Val{:complex}
        function h!(storage::Matrix, x::Vector)
            # TODO: Wait to use DiffEqDiffTools until they introduce the Hessian feature
            Calculus.finite_difference_hessian!(f, x, storage)
            return
        end
    elseif autodiff == :forward
        gcfg = ForwardDiff.GradientConfig(f, x)
        g! = (out, x) -> ForwardDiff.gradient!(out, f, x, gcfg)

        fg! = (out, x) -> begin
            gr_res = DiffResults.DiffResult(zero(eltype(x)), out)
            ForwardDiff.gradient!(gr_res, f, x, gcfg)
            DiffResults.value(gr_res)
        end

        hcfg = ForwardDiff.HessianConfig(f, x)
        h! = (out, x) -> ForwardDiff.hessian!(out, f, x, hcfg)
    else
        error("The autodiff value $(autodiff) is not supported. Use :finite or :forward.")
    end
    TwiceDifferentiable(f, g!, fg!, h!, x, F)
end
