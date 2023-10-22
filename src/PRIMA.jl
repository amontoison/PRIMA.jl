module PRIMA

using PRIMA_jll
const libprimac = PRIMA_jll.libprimac
include("wrappers.jl")

export bobyqa, cobyla, lincoa, newuoa, uobyqa, issuccess

using TypeUtils
using LinearAlgebra

#------------------------------------------------------------------------------
# PUBLIC INTERFACE

"""
    PRIMA.Info

is the type of the structured object used to collect various information
provided by the optimization algorithms of the `PRIMA` package.

An object, say `info`, of this type has the following properties:

    info.fx       # value of the objective function f(x) on return
    info.nf       # number of calls to the objective function
    info.status   # final status code
    info.cstrv    # amount of constraints violation, 0.0 if unconstrained
    info.nl_eq    # non-linear equality constraints, empty vector if none
    info.nl_ineq  # non-linear inequality constraints, empty vector if none

Call `issuccess(info)` or `issuccess(info.status)` to check whether algorithm
was sucessful. Call `PRIMA.reason(info)` or `PRIMA.reason(info.status)` to
retrieve a textual description of the algorithm termination.

"""
struct Info
    fx::Cdouble              # f(x) on return
    nf::Int                  # number of function calls
    status::Status           # returned status code
    cstrv::Cdouble           # amount of constraints violation
    nl_eq::Vector{Cdouble}   # non-linear equality constraints
    nl_ineq::Vector{Cdouble} # non-linear inequality constraints
    function Info(; # Mandatory keywords.
                  fx::Real,
                  nf::Integer,
                  status::Status,
                  # Optional keywords.
                  cstrv::Real = 0.0,
                  nl_eq::AbstractVector{<:Real} = Cdouble[],
                  nl_ineq::AbstractVector{<:Real} = Cdouble[])
        return new(fx, nf, status, cstrv, nl_eq, nl_ineq)
    end
end

LinearAlgebra.issuccess(info::Info) = issuccess(info.status)
LinearAlgebra.issuccess(status::Status) =

"""
    PRIMA.reason(info::PRIMA.Info) -> str
    PRIMA.reason(status::PRIMA.Status) -> str

yield a textual message explaining `info.statu` or `status`, the status code
returned by one of the PRIMA optimizers.

"""
reason(info::Info) = reason(info.status)
reason(status::Union{Integer,Status}) = unsafe_string(prima_get_rc_string(status))

"""
    PRIMA.LinearConstraints

is the type of `(A,b)`, the 2-tuple representing linear equality constraints
`A⋅x = b` or linear inequality constraints `A⋅x ≤ b` where `A` is a matrix, `x`
is the vector of variables, and `b` is a vector.

"""
const LinearConstraints = Tuple{AbstractMatrix{<:Real},AbstractVector{<:Real}}

# Default settings.
default_npt(x::AbstractVector{<:Real}) = 2*length(x) + 1
default_maxfun(x::AbstractVector{<:Real}) = 100*length(x)
default_rhobeg() = 1.0
default_rhoend(rhobeg::Real) = 1e-4*rhobeg

# The high level wrappers. First the methods, then their documentation.
for func in (:bobyqa, :newuoa, :uobyqa, :lincoa, :cobyla)
    func! = Symbol(func, "!")
    @eval begin
        function $func(f, x0::AbstractVector{<:Real}; kwds...)
            x = copyto!(Vector{Cdouble}(undef, length(x0)), x0)
            return x, $func!(f, x; kwds...)
        end
    end
end

const _doc_common = """
The arguments are the objective function `f` and the initial variables `x0`
which are left unchanged on output. The objective function is called as `f(x)`
with `x` the variables, it must implement the following signature:

    f(x::Vector{Cdouble})::Real

The result of the algorithm is a 2-tuple `(x, info)` with `x` the variables and
`info` a structured object collecting other information provided by the
algorithm (see [`PRIMA.Info`](@ref)). If `issuccess(info)` is true, then the
algorithm was successful and `x` is an approximate solution of the problem.

Allowed keywords are (`n = length(x)` is the number of variables):

- `rhobeg` (default value `1.0`) is the initial radius of the trust region.

- `rhoend` (default value `1e-4*rhobeg`) is the final radius of the trust
  region used to decide whether the algorithm has converged in the variables.

- `ftarget` (default value `-Inf`) is another convergence setting. The
  algorithm is stopped as soon as `f(x) ≤ ftarget` and the status
  `PRIMA.FTARGET_ACHIEVED` is returned.

- `maxfun` (default `100n`) is the maximum number of function evaluations
  allowed for the algorithm. If the number of calls to `f(x)` exceeds this
  value, the algorithm is stopped and the status `PRIMA.MAXFUN_REACHED` is
  returned.

- `iprint` (default value `PRIMA.MSG_NONE`) sets the level of verbosity of the
   algorithm. Possible values are `PRIMA.MSG_EXIT`, `PRIMA.MSG_RHO`, or
   `PRIMA.MSG_FEVL`.
"""

const _doc_npt = """
- `npt` (default value `2n + 1`) is the number of points used to approximate
  the local behavior of the objective function and such that `n + 2 ≤ npt ≤
  (n + 1)*(n + 2)/2`. The default value corresponds to the one recommended by
  M.J.D. Powell.
"""

const _doc_bound_constraints = """
- `xl` and `xu` (default `fill(+Inf, n)` and `fill(-Inf, n)`) are the
  elementwise lower and upper bounds for the variables. Feasible variables are
  such that `xl ≤ x ≤ xu` (elementwise).
"""

const _doc_nonlinear_constraints = """
- `nonlinear_eq` (default `nothing`) may be specified with a function, say
  `c_eq`, implementing non-linear equality constraints defined by `c_eq(x) =
  0`. On return, the values of the non-linear equality constraints are given by
  `info.nl_eq` to save calling `c_eq(x)`.

- `nonlinear_ineq` (default `nothing`) may be specified with a function, say
  `c_ineq`, implementing non-linear inequality constraints defined by
  `c_ineq(x) ≤ 0`. On return, the values of the non-linear inequality
  constraints are given by `info.nl_ineq` to save calling `c_ineq(x)`.
"""

const _doc_linear_constraints = """
- `linear_eq` (default `nothing`) may be specified as a tuple `(Aₑ,bₑ)` to
  impose the linear equality constraints `Aₑ⋅x = bₑ`.

- `linear_ineq` (default `nothing`) may be specified as a tuple `(Aᵢ,bᵢ)` to
  impose the linear inequality constraints `Aᵢ⋅x ≤ bᵢ`.
"""

"""
    uobyqa(f, x0; kwds...) -> (x, fx, nf, rc)

approximately solves the unconstrained optimization problem:

    min f(x)    subject to   x ∈ ℝⁿ

by M.J.D. Powell's UOBYQA (for \"Unconstrained Optimization BY Quadratic
Approximations\") method. This algorithm is based on a trust region method
where variables are updated according to a quadratic local approximation
interpolating the objective function. No derivatives of the objective function
are needed.

$(_doc_common)

""" uobyqa

"""
    newuoa(f, x0; kwds...) -> x, info

approximately solves the unconstrained optimization problem:

    min f(x)    subject to   x ∈ ℝⁿ

by M.J.D. Powell's NEWUOA method. This algorithm is based on a trust region
method where variables are updated according to a quadratic local approximation
interpolating the objective function at a number of `npt` points. No
derivatives of the objective function are needed.

$(_doc_common)

$(_doc_npt)

""" newuoa

"""
    bobyqa(f, x0; kwds...) -> x, info

approximately solves the bound constrained optimization problem:

    min f(x)    subject to   x ∈ Ω ⊆ ℝⁿ

with

   Ω = { x ∈ ℝⁿ | xl ≤ x ≤ xu }

by M.J.D. Powell's BOBYQA (for \"Bounded Optimization BY Quadratic
Approximations\") method. This algorithm is based on a trust region method
where variables are updated according to a quadratic local approximation
interpolating the objective function at a number of `npt` points. No
derivatives of the objective function are needed.

$(_doc_common)

$(_doc_npt)

$(_doc_bound_constraints)

""" bobyqa

"""
    cobyla(f, x0; kwds...) -> (x, fx, nf, rc, cstrv)

approximately solves the constrained optimization problem:

    min f(x)    subject to   x ∈ Ω ⊆ ℝⁿ

with

    Ω = { x ∈ ℝⁿ | xl ≤ x ≤ xu, Aₑ⋅x = bₑ, Aᵢ⋅x ≤ bᵢ, and c(x) ≤ 0 }

by M.J.D. Powell's COBYLA (for \"Constrained Optimization BY Linear
Approximations\") method. This algorithm is based on a trust region methood
where variables are updated according to a linear local approximation of the
objective function. No derivatives of the objective function are needed.

$(_doc_common)

$(_doc_bound_constraints)

$(_doc_linear_constraints)

$(_doc_nonlinear_constraints)

""" cobyla

"""
    lincoa(f, x0; kwds...) -> (x, fx, nf, rc, cstrv)

approximately solves the constrained optimization problem:

    min f(x)    subject to   x ∈ Ω ⊆ ℝⁿ

with

    Ω = { x ∈ ℝⁿ | xl ≤ x ≤ xu, Aₑ⋅x = bₑ, and Aᵢ⋅x ≤ bᵢ }

by M.J.D. Powell's LINCOA (for \"LINearly Constrained Optimization\") method.
This algorithm is based on a trust region methood where variables are updated
according to a quadratic local approximation of the objective function. No
derivatives of the objective function are needed.

$(_doc_common)

$(_doc_npt)

$(_doc_bound_constraints)

$(_doc_linear_constraints)

""" lincoa

"""
    PRIMA.bobyqa!(f, x; kwds...) -> info::PRIMA.Info

in-place version of [`PRIMA.bobyqa`](@ref) which to see for details. On entry,
argument `x` is a dense vector of double precision value with the initial
variables; on return, `x` is overwritten by an approximate solution.

"""
function bobyqa!(f, x::DenseVector{Cdouble};
                 xl::Union{AbstractVector{<:Real},Nothing} = nothing,
                 xu::Union{AbstractVector{<:Real},Nothing} = nothing,
                 rhobeg::Real = default_rhobeg(),
                 rhoend::Real = default_rhoend(rhobeg),
                 ftarget::Real = -Inf,
                 maxfun::Integer = default_maxfun(x),
                 npt::Integer = default_npt(x),
                 iprint::Union{Integer,Message} = MSG_NONE)
    # Check arguments and get constraints.
    n = length(x) # number of variables
    _check_rho(rhobeg, rhoend)
    _check_npt(npt, n)
    xl = _get_lower_bound(xl, n)
    xu = _get_upper_bound(xu, n)

    # References for output values.
    fx = Ref{Cdouble}(NaN) # to store f(x) on return
    nf = Ref{Cint}(0)      # to store number of function calls

    # Create wrapper to objective function and push it on top of per-thread
    # stack before calling optimizer.
    fw = ObjFun(f, n)             # wrapper to objective function
    fp = _push_objfun(bobyqa, fw) # pointer to C-callable function
    try
        # Call low-level optimizer.
        status = prima_bobyqa(fp, n, x, fx, xl, xu, nf, rhobeg, rhoend, ftarget, maxfun, npt, iprint)
        return Info(; fx = fx[], nf = nf[], status)
    finally
        _pop_objfun(fw)
    end
end

"""
    PRIMA.newuoa!(f, x; kwds...) -> info::PRIMA.Info

in-place version of [`PRIMA.newuoa`](@ref) which to see for details. On entry,
argument `x` is a dense vector of double precision value with the initial
variables; on return, `x` is overwritten by an approximate solution.

"""
function newuoa!(f, x::DenseVector{Cdouble};
                 rhobeg::Real = default_rhobeg(),
                 rhoend::Real = default_rhoend(rhobeg),
                 ftarget::Real = -Inf,
                 maxfun::Integer = default_maxfun(x),
                 npt::Integer = default_npt(x),
                 iprint::Union{Integer,Message} = MSG_NONE)
    # Check arguments.
    n = length(x) # number of variables
    _check_rho(rhobeg, rhoend)
    _check_npt(npt, n)

    # References for output values.
    fx = Ref{Cdouble}(NaN) # to store f(x) on return
    nf = Ref{Cint}(0)      # to store number of function calls

    # Create wrapper to objective function and push it on top of per-thread
    # stack before calling optimizer.
    fw = ObjFun(f, n)             # wrapper to objective function
    fp = _push_objfun(newuoa, fw) # pointer to C-callable function
    try
        # Call low-level optimizer.
        status = prima_newuoa(fp, n, x, fx, nf, rhobeg, rhoend, ftarget, maxfun, npt, iprint)
        return Info(; fx = fx[], nf = nf[], status)
    finally
        _pop_objfun(fw)
    end
end

"""
    PRIMA.uobyqa!(f, x; kwds...) -> info::PRIMA.Info

in-place version of [`PRIMA.uobyqa`](@ref) which to see for details. On entry,
argument `x` is a dense vector of double precision value with the initial
variables; on return, `x` is overwritten by an approximate solution.

"""
function uobyqa!(f, x::DenseVector{Cdouble};
                 rhobeg::Real = default_rhobeg(),
                 rhoend::Real = default_rhoend(rhobeg),
                 ftarget::Real = -Inf,
                 maxfun::Integer = default_maxfun(x),
                 iprint::Union{Integer,Message} = MSG_NONE)
    # Check arguments.
    n = length(x) # number of variables
    _check_rho(rhobeg, rhoend)

    # References for output values.
    fx = Ref{Cdouble}(NaN) # to store f(x) on return
    nf = Ref{Cint}(0)      # to store number of function calls

    # Create wrapper to objective function and push it on top of per-thread
    # stack before calling optimizer.
    fw = ObjFun(f, n)             # wrapper to objective function
    fp = _push_objfun(uobyqa, fw) # pointer to C-callable function
    try
        # Call low-level optimizer.
        status = prima_uobyqa(fp, n, x, fx, nf, rhobeg, rhoend, ftarget, maxfun, iprint)
        return Info(; fx = fx[], nf = nf[], status)
    finally
        _pop_objfun(fw)
    end
end

"""
    PRIMA.cobyla!(f, x; kwds...) -> info::PRIMA.Info

in-place version of [`PRIMA.cobyla`](@ref) which to see for details. On entry,
argument `x` is a dense vector of double precision value with the initial
variables; on return, `x` is overwritten by an approximate solution.

"""
function cobyla!(f, x::DenseVector{Cdouble};
                 rhobeg::Real = default_rhobeg(),
                 rhoend::Real = default_rhoend(rhobeg),
                 ftarget::Real = -Inf,
                 maxfun::Integer = default_maxfun(x),
                 iprint::Union{Integer,Message} = MSG_NONE,
                 xl::Union{AbstractVector{<:Real},Nothing} = nothing,
                 xu::Union{AbstractVector{<:Real},Nothing} = nothing,
                 linear_ineq::Union{LinearConstraints,Nothing} = nothing,
                 linear_eq::Union{LinearConstraints,Nothing} = nothing,
                 nonlinear_ineq = nothing,
                 nonlinear_eq = nothing)
    # Check arguments and get constraints.
    n = length(x) # number of variables
    _check_rho(rhobeg, rhoend)
    xl = _get_lower_bound(xl, n)
    xu = _get_upper_bound(xu, n)
    nl_eq, c_nl_eq = _get_nonlinear_constraints(nonlinear_eq, x, "equality")
    nl_ineq, c_nl_ineq = _get_nonlinear_constraints(nonlinear_ineq, x, "inequality")
    A_eq, b_eq = _get_linear_constraints(linear_eq, n)
    A_ineq, b_ineq = _get_linear_constraints(linear_ineq, n)

    # Alocate vector to store all non-linear constraints (the non-linear
    # equalities being implemented as 2 inequalities each).
    nl_all = Vector{Cdouble}(undef, 2*length(nl_eq) + length(nl_ineq))

    # References for output values.
    cstrv = Ref{Cdouble}(NaN)     # to store constraint violation
    fx = Ref{Cdouble}(NaN)        # to store f(x) on return
    nf = Ref{Cint}(0)             # to store number of function calls

    # Create wrapper to objective function and push it on top of per-thread
    # stack before calling optimizer.
    fw = ObjFun(f, n, c_nl_eq, length(nl_eq), c_nl_ineq, length(nl_ineq))
    fp = _push_objfun(cobyla, fw) # pointer to C-callable function
    try
        # Call low-level optimizer.
        status = prima_cobyla(length(nl_all), fp, n, x, fx, cstrv, nl_all,
                              length(b_ineq), A_ineq, b_ineq,
                              length(b_eq), A_eq, b_eq,
                              xl, xu, nf, rhobeg, rhoend, ftarget, maxfun, iprint)
        # Unpack constraints.
        if length(nl_eq) > 0
            i = firstindex(nl_all)
            for j in eachindex(nl_eq)
                nl_eq[j] = nl_all[i]
                i += 2
            end
        end
        if length(nl_ineq) > 0
            i = firstindex(nl_all) + 2*length(nl_eq)
            for j in eachindex(nl_ineq)
                nl_ineq[j] = nl_all[i]
                i += 1
            end
        end
        return Info(; fx = fx[], nf = nf[], status, cstrv = cstrv[], nl_eq, nl_ineq)
    finally
        _pop_objfun(fw)
    end
end

"""
    PRIMA.lincoa!(f, x; kwds...) -> info::PRIMA.Info

in-place version of [`PRIMA.lincoa`](@ref) which to see for details. On entry,
argument `x` is a dense vector of double precision value with the initial
variables; on return, `x` is overwritten by an approximate solution.

"""
function lincoa!(f, x::DenseVector{Cdouble};
                 rhobeg::Real = default_rhobeg(),
                 rhoend::Real = default_rhoend(rhobeg),
                 ftarget::Real = -Inf,
                 maxfun::Integer = default_maxfun(x),
                 npt::Integer = default_npt(x),
                 iprint::Union{Integer,Message} = MSG_NONE,
                 xl::Union{AbstractVector{<:Real},Nothing} = nothing,
                 xu::Union{AbstractVector{<:Real},Nothing} = nothing,
                 linear_ineq::Union{LinearConstraints,Nothing} = nothing,
                 linear_eq::Union{LinearConstraints,Nothing} = nothing)
    # Check arguments and get constraints.
    n = length(x) # number of variables
    _check_rho(rhobeg, rhoend)
    _check_npt(npt, n)
    xl = _get_lower_bound(xl, n)
    xu = _get_upper_bound(xu, n)
    A_eq, b_eq = _get_linear_constraints(linear_eq, n)
    A_ineq, b_ineq = _get_linear_constraints(linear_ineq, n)

    # References for output values.
    cstrv = Ref{Cdouble}(NaN) # to store constraint violation
    fx = Ref{Cdouble}(NaN)    # to store f(x) on return
    nf = Ref{Cint}(0)         # to store number of function calls

    # Create wrapper to objective function and push it on top of per-thread
    # stack before calling optimizer.
    fw = ObjFun(f, n)             # wrapper to objective function
    fp = _push_objfun(lincoa, fw) # pointer to C-callable function
    try
        # Call low-level optimizer.
        status = prima_lincoa(fp, n, x, fx, cstrv,
                              length(b_ineq), A_ineq, b_ineq,
                              length(b_eq), A_eq, b_eq,
                              xl, xu,
                              nf, rhobeg, rhoend, ftarget, maxfun, npt, iprint)
        return Info(; fx = fx[], nf = nf[], status, cstrv = cstrv[])
    finally
        _pop_objfun(fw)
    end
end

#------------------------------------------------------------------------------
# PRIVATE METHODS AND TYPES

"""
    PRIMA.ObjFun(f, n)

builds an object to wrap a multi-variate user-defined objective function
`f: ℝⁿ → ℝ` with `n` the number of variables.

    PRIMA.ObjFun(n, f, c_eq, n_eq, c_ineq, n_ineq)

builds an object to wrap a multi-variate user-defined objective function `f: ℝⁿ
→ ℝ` with `n` the number of variables and the `n_eq` and `n_ineq` non-linear
equality and inequality constraints:

    c_eq(x) = 0
    c_ineq(x) ≤ 0

Objective function object `objfun` has the following fields:

    objfun.f        # callable implementing user-defined objective function
    objfun.n        # number of variables
    objfun.c_eq     # callable implementing non-linear equalities as `c_eq(x) = 0`
    objfun.n_eq     # number of non-linear equalities
    objfun.c_ineq   # callable implementing non-linear inequalities as `c_ineq(x) ≤ 0`
    objfun.n_ineq   # number of non-linear inequalities

See also [`PRIMA.call`](@ref) and [`PRIMA.call!`](@ref).

"""
struct ObjFun{F,E,I}
    f::F        # callable implementing user-defined objective function
    n::Int      # number of variables
    c_eq::E     # callable implementing non-linear equalities as `c_eq(x) = 0`
    n_eq::Int   # number of non-linear equalities
    c_ineq::I   # callable implementing non-linear inequalities as `c_ineq(x) ≤ 0`
    n_ineq::Int # number of non-linear inequalities
end

unconstrained(x::AbstractVector{T}) where {T} = NullVector{T}()

ObjFun(f::F, n::Integer) where {F} = ObjFun(f, n, unconstrained, 0, unconstrained, 0)

"""
    PRIMA.call(f::ObjFun, x::DenseVector{Cdouble}) -> fx

yields value of objective function `f(x)` for variables `x`.

The default method may be extended by specializing on the type of `f`. It is
guaranteed that:

    length(x)  = f.n

holds.

See also [`PRIMA.ObjFun`](@ref) and [`PRIMA.call!`](@ref).

"""
function call(f::ObjFun, x::DenseVector{Cdouble})
    length(x) == f.n || throw(DimensionMismatch(
        "invalid number of variables"))
    return f.f(x)
end

"""
    PRIMA.call!(f::ObjFun, x::DenseVector{Cdouble}, cx::DenseVector{Cdouble}) -> fx

yields value of objective function `f(x)` for variables `x` and overwrites `cx`
with the values `c(x)` coresponding to the non-linear inequality constraints
`c(x) ≤ 0`.

The default method may be extended by specializing on the type of `f`. It is
guaranteed that:

    length(x)  = f.n
    length(cx) = 2*f.n_eq + f.n_ineq

both hold. The second equality is because non-linear equality constraints are
equivalent to two non-linear equality constraints: `c_eq(x) = 0` is rewritten
as `c_eq(x) ≤ 0` and `-c_eq(x) ≤ 0`.

See also [`PRIMA.ObjFun`](@ref) and [`PRIMA.call`](@ref).

"""
function call!(f::ObjFun, x::DenseVector{Cdouble}, cx::DenseVector{Cdouble})
    length(x) == f.n || throw(DimensionMismatch(
        "invalid number of variables"))
    i = firstindex(cx) - 1
    if f.n_eq != 0
        c_eq = f.c_eq(x)::Union{Real,AbstractVector{<:Real}}
        length(c_eq) == f.n_eq || throw(DimensionMismatch(
            "invalid number of equalities"))
        for j in eachindex(c_eq)
            cx[i += 1] =  c_eq[j]
            cx[i += 1] = -c_eq[j]
        end
    end
    if f.n_ineq != 0
        c_ineq = f.c_ineq(x)::Union{Real,AbstractVector{<:Real}}
        length(c_ineq) == f.n_ineq || throw(DimensionMismatch(
            "invalid number of inequalities"))
        for j in eachindex(c_ineq)
            cx[i += 1] = c_ineq[j]
        end
    end
    return f.f(x)
end

# Computation of objective function and non-linear constraints, if any, is done
# in several stages:
#
# 1. `_objfun` retrieves the objective function;
#
# 2. `unsafe_call` wraps pointers to the variables and the constraints, if any,
#    into Julia arrays;
#
# 3. `call` or `call!` execute the user-defined functions implementing the
#    objective function and the non-linear constraints.
#
# The motivations are (i) to dispatch as soon as possible on code depending on
# the type of the user-defined Julia functions and (ii) to make possible to
# extend `call` or `call!` at the last stage .

# C-callable objective function for problems with no non-linear constraints
# (for other algorithms than COBYLA).
function _objfun(x_ptr::Ptr{Cdouble}, # (input) variables
                 f_ptr::Ptr{Cdouble}) # (output) function value
    # Retrieve objective function object and dispatch on its type to compute
    # f(x).
    f = last(_objfun_stack[Threads.threadid()])
    unsafe_store!(f_ptr, unsafe_call(f, x_ptr))
    return nothing
end

# C-callable objective function for for problems with non-linear constraints
# (for COBYLA algorithm).
function _objfun(x_ptr::Ptr{Cdouble}, # (input) variables
                 f_ptr::Ptr{Cdouble}, # (output) function value
                 c_ptr::Ptr{Cdouble}) # (output) constraints
    # Retrieve objective function object and dispatch on its type to compute
    # f(x) and the non-linear constraints.
    f = last(_objfun_stack[Threads.threadid()])
    unsafe_store!(f_ptr, unsafe_call(f, x_ptr, c_ptr))
    return nothing
end

function unsafe_call(f::ObjFun, x_ptr::Ptr{Cdouble})
    x = unsafe_wrap(Array, x_ptr, f.n)
    return as(Cdouble, call(f, x))
end

function unsafe_call(f::ObjFun, x_ptr::Ptr{Cdouble}, c_ptr::Ptr{Cdouble})
    x = unsafe_wrap(Array, x_ptr, f.n)
    c = unsafe_wrap(Array, c_ptr, 2*f.n_eq + f.n_ineq)
    return as(Cdouble, call!(f, x, c))
end

# Global variable storing the per-thread stacks of objective functions indexed
# by thread identifier and then by execution order. On start of an
# optimization, an object linked to the user-defined objective function is
# pushed. This object is popped out of the stack on return of the optimization
# call, whatever happens. It is therefore necessary to wrap the call to the
# optimization method in a `try-finally` clause.
const _objfun_stack = Vector{Vector{ObjFun}}(undef, 0)

# Private function `_get_objfun_stack` yields the stack of objective functions
# for the caller thread.
function _get_objfun_stack()
    i = Threads.threadid()
    while length(_objfun_stack) < i
        push!(_objfun_stack, Vector{ObjFun}(undef, 0))
    end
    return _objfun_stack[i]
end

# Private functions `_push_objfun` and `_pop_objfun` are to be used in a
# `try-finally` clause as explained above.
function _push_objfun(algorithm, fw::ObjFun)
    _objfun_ptr(::Any) =
        @cfunction(_objfun, Cvoid, (Ptr{Cdouble}, Ptr{Cdouble}))
    _objfun_ptr(::typeof(cobyla)) =
        @cfunction(_objfun, Cvoid, (Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cdouble}))
    push!(_get_objfun_stack(), fw)
    return _objfun_ptr(algorithm)
end

function _pop_objfun(fw::ObjFun)
    stack = _get_objfun_stack()
    last(stack) === fw || error(
        "objective function is not the last one in the caller thread stask")
    resize!(stack, length(stack) - 1)
    return nothing
end

function _check_rho(rhobeg, rhoend)
    isfinite(rhobeg) && rhobeg > zero(rhobeg) || throw(ArgumentError(
        "`rhobeg` must be finite and positive"))
    isfinite(rhoend) && rhoend ≥ zero(rhoend) || throw(ArgumentError(
        "`rhoend` must be finite and non-negative"))
    rhoend ≤ rhobeg|| throw(ArgumentError(
        "`rhoend` must be less or equal `rhobeg`"))
    nothing
end

function _check_npt(npt::Integer, n::Integer)
    n + 2 ≤ npt ≤ (n + 1)*(n + 2)/2 || throw(ArgumentError(
        "`n + 2 ≤ npt ≤ (n + 1)*(n + 2)/2` must hold"))
    nothing
end

@static if !isdefined(Base, :Returns)
    struct Returns{T}
        value::T
    end
    (obj::Returns)(args...; kwds...) = obj.value
end

# Null-array to represent missing argument. It is sufficient to implement the abstract
# array API plus the Base.unsafe_convert method.
struct NullArray{T,N} <: AbstractArray{T,N} end
const NullVector{T} = NullArray{T,1}
const NullMatrix{T} = NullArray{T,2}
Base.length(::NullArray{T,N}) where {T,N} = 0
Base.size(::NullArray{T,N}) where {T,N} = ntuple(Returns(0), Val(N))
Base.axes(::NullArray{T,N}) where {T,N} = ntuple(Returns(Base.OneTo(0)), Val(N))
Base.unsafe_convert(::Type{Ptr{S}}, ::NullArray{T,N}) where {T,N,S<:Union{Cvoid,T}} = Ptr{S}(0)

# FIXME: Matrix A of linear constraints is in row-major order (this is imposed
# by the C interface which transposes the matrix A).
_get_linear_constraints(::Nothing, n::Integer) =
    NullMatrix{Cdouble}(), NullVector{Cdouble}()
function _get_linear_constraints(Ab::LinearConstraints, n::Integer)
    A, b = Ab
    Base.has_offset_axes(A) && error(
        "matrix `A` of linear constraints must have 1-based indices")
    Base.has_offset_axes(b) && error(
        "vector `b` of linear constraints must have 1-based indices")
    m = length(b) # number of constraints
    size(A) == (m,n) || throw(DimensionMismatch(
        "matrix `A` of linear constraints has incompatible dimensions"))
    T = Cdouble
    # FIXME: Like in FORTRAN, Julia matrices are in column-major storage order,
    # but we must transpose the matrix A in linear constraints because we call
    # the FORTRAN code through a C interface which conisder that matrices are
    # in row-major storage. As a result, the matrix `A` will be transposed
    # twice. This isn't a big issue for a small number of variables and
    # constraints, but it's not completely satisfactory either.
    A_ = Matrix{T}(undef, n, m)
    @inbounds for i ∈ 1:m
        for j ∈ 1:n
            A_[j,i] = A[i,j]
        end
    end
    b_ = _dense_array(T, b)
    return A_, b_
end

# Yield (v,c) with v a vector to store the constraints on output (possibly an
# empty vector if there are no constraints), and c the callable object
# implementing the constraints.
_get_nonlinear_constraints(::Nothing, x::AbstractArray, str::AbstractString) =
    Cdouble[], unconstrained
_get_nonlinear_constraints(c::Tuple{Integer,Any}, x::AbstractArray, str::AbstractString) =
    Vector{Cdouble}(undef, c[1]), c[2]
_get_nonlinear_constraints(c::Tuple{Any,Integer}, x::AbstractArray, str::AbstractString) =
    _get_nonlinear_constraints(reverse(c), x, str)
function _get_nonlinear_constraints(c::Any, x::AbstractArray, str::AbstractString)
    # If c(x) does not yield a result convertible into a vector of double precisions
    # values, an error will be thrown to the caller.
    cx = c(x)
    cx isa Real && return [as(Cdouble, cx)], c
    cx isa AbstractVector{<:Real} && return as(Vector{Cdouble}, cx), c
    throw(ArgumentError(string("method implementing non-linear ", str,
                               " constraints must return a real or a vector of reals")))
end

for (uplo, def) in ((:lower, typemin),
                    (:upper, typemax))
    func = Symbol("_get_$(uplo)_bound")
    @eval begin
        $func(::Nothing, n::Integer) = fill($def(Cdouble), n)
        function $func(b::AbstractVector, n::Integer)
            Base.has_offset_axes(b) && error(
                $("$uplo bound must have 1-based indices"))
            length(b) == n || throw(DimensionMismatch(string(
                $("$uplo bound must have "), n, " elements")))
            return _dense_array(Cdouble, b)
        end
    end
end

# Yields an array with given element type and which can be safely passed to a C
# function (i.e. it has contiguous elements in memory).
_dense_array(::Type{T}, A::DenseArray{T,N}) where {T,N} = A
_dense_array(::Type{T}, A::AbstractArray{<:Any,N}) where {N,T} = convert(Array{T,N}, A)

end
