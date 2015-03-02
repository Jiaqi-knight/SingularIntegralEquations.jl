# CauchyWeight

export CauchyWeight

immutable CauchyWeight{O} <: AbstractProductSpace
    space::AbstractProductSpace
    CauchyWeight(space) = new(space)
end

order{O}(::CauchyWeight{O}) = O
domain(C::CauchyWeight)=domain(C.space)

cauchyweight(O,x,y) = O == 0 ? logabs(y-x)/π : (y-x).^(-O)/π
cauchyweight{O}(C::CauchyWeight{O},x,y) = cauchyweight(O,tocanonical(C,x,y)...)

Base.getindex{BT,S,V,O,T}(B::Operator{BT},f::ProductFun{S,V,CauchyWeight{O},T}) = PlusOperator(BandedOperator{promote_type(BT,T)}[f.coefficients[i]*B[Fun([zeros(promote_type(BT,T),i-1),one(promote_type(BT,T))],f.space.space.spaces[2])] for i=1:length(f.coefficients)])

# Principal Value Integral (Could be called PrincipalValueIntegral, but I thought that was too long)

export PrincipalValue

immutable PrincipalValue{D<:FunctionSpace,T<:Number} <: Functional{T}
    domainspace::D
end

PrincipalValue()=PrincipalValue(UnsetSpace())
PrincipalValue(dsp::FunctionSpace) = PrincipalValue{typeof(dsp),eltype(dsp)}(dsp)
promotedomainspace(::PrincipalValue,sp::FunctionSpace)=PrincipalValue(sp)

Base.convert{T}(::Type{Functional{T}},⨍::PrincipalValue)=PrincipalValue{typeof(⨍.domainspace),T}(⨍.domainspace)

domain(⨍::PrincipalValue)=domain(⨍.domainspace)
domainspace(⨍::PrincipalValue)=⨍.domainspace

getindex(::PrincipalValue{UnsetSpace},kr::Range)=error("Spaces cannot be inferred for operator")

Base.getindex{S,V,O,T}(⨍::PrincipalValue{V,T},f::ProductFun{S,V,CauchyWeight{O},T}) = Hilbert(⨍.domainspace,O)[f]
Base.getindex{S,V,SS,T}(⨍::PrincipalValue{V,T},f::ProductFun{S,V,SS,T}) = Σ(⨍.domainspace)[f]



function ProductFun{O}(f::Function,cwsp::CauchyWeight{O})
    sp = cwsp.space
    cfs = ProductFun(f,sp).coefficients
    ProductFun{typeof(sp.spaces[1]),typeof(sp.spaces[2]),typeof(cwsp),eltype(cfs[1])}(cfs,cwsp)
end

evaluate{S<:FunctionSpace,V<:FunctionSpace,O,T}(f::ProductFun{S,V,CauchyWeight{O},T},x::Range,y::Range) = evaluate(f,[x],[y])

function evaluate{S<:FunctionSpace,V<:FunctionSpace,O,T}(f::ProductFun{S,V,CauchyWeight{O},T},x,y)
    ProductFun{S,V,typeof(space(f).space),T}(f.coefficients,space(f).space)[x,y].*cauchyweight(space(f),x,y)
end

# GreensFun
#=
export GreensFun

immutable GreensFun{S<:FunctionSpace,V<:FunctionSpace,T}<:BivariateFun
    kernels::Vector{ProductFun}
#    spacex::S
#    spacey::V
#    elt::T
end

immutable GreensFun<:ApproxFun.BivariateFun
    kernels::Vector{ProductFun}
end
=#









#
# A new ProductFun constructor for bivariate functions on Intervals
# defined as the difference of their arguments.
#
function ProductFun{U<:PolynomialSpace,V<:PolynomialSpace}(f::Function,u::Union(U,JacobiWeight{U}),v::Union(V,JacobiWeight{V}),method::Symbol=:symmetric)
    du,dv = domain(u),domain(v)
    @assert length(du) == length(dv)
    T,spf = eltype(du),Chebyshev([du.a+dv.a,du.b+dv.b])
    ff = Fun(x->f(-x/2,x/2),spf)
    c = chop(coefficients(ff),maxabs(coefficients(ff))*100eps(T))
    N = length(c)

    if N ≤ 3000
        if N ≤ 3 N=3;pad!(c,3) end
        X = zeros(T,N,N)
        chebyshevaddition!(c,X)
        cspu,cspv = canonicalspace(u),canonicalspace(v)
        [X[1:N+1-k,k] = coefficients(vec(X[1:N+1-k,k]),cspu,u) for k=1:N]
        [X[k,1:N+1-k] = coefficients(vec(X[k,1:N+1-k]),cspv,v) for k=1:N]
        return ProductFun(X,u⊗v)
    else
        return ProductFun((x,y)->x==y?ff[zero(T)]:f(x,y),u⊗v,N,N)
    end
end

function chebyshevaddition!{T<:Number}(c::Vector{T},X::Matrix{T})
    N = length(c)
    un = one(T)
    C1,C2 = zeros(T,N,N),zeros(T,N,N)

    C1[1,1] = un
    cn = c[1]

    X[1,1] += cn*C1[1,1]

    C2[2,1] = -un/2
    C2[1,2] = un/2
    cn = c[2]

    X[2,1] += cn*C2[2,1]
    X[1,2] += cn*C2[1,2]

    C1[1,1] = -un/2
    C1[3,1] = un/4
    C1[2,2] = -un
    C1[1,3] = un/4
    cn = c[3]

    X[1,1] += cn*C1[1,1]
    X[3,1] += cn*C1[3,1]
    X[2,2] += cn*C1[2,2]
    X[1,3] += cn*C1[1,3]

    @inbounds for n=4:N
        #
        # There are 11 unique recurrence relationships for the coefficients. The main recurrence is:
        #
        # C[i,j,n] = (C[i,j+1,n-1]+C[i,j-1,n-1]-C[i+1,j,n-1]-C[i-1,j,n-1])/2 - C[i,j,n-2],
        #
        # and the other 10 come from shutting some terms off if they are out of bounds,
        # or for the row C[2,1:n,n] or column C[1:n,2,n] terms are turned on. This follows from
        # the reflection of Chebyshev polynomials: 2T_m(x)T_n(x) = T_{m+n}(x) + T_|m-n|(x).
        # For testing of stability, they should always be equal to:
        # C[1:n,1:n,n] = coefficients(ProductFun((x,y)->cos((n-1)*acos((y-x)/2)))).
        #
        C2[1,1] = (C1[1,2]-C1[2,1])/2 - C2[1,1]
        C2[2,1] = (C1[2,2]-C1[3,1])/2 - C1[1,1] - C2[2,1]
        C2[n,1] = C1[n-1,1]/(-2)
        C2[1,2] = (C1[1,3]-C1[2,2])/2 + C1[1,1] - C2[1,2]
        C2[2,2] = (C1[2,3]-C1[3,2])/2 + C1[2,1] - C1[1,2] - C2[2,2]
        C2[1,n] = C1[1,n-1]/2
        for k=n-2:-2:3
            C2[k,1] = (C1[k,2]-C1[k-1,1]-C1[k+1,1])/2 - C2[k,1]
            C2[1,k] = (C1[1,k+1]+C1[1,k-1]-C1[2,k])/2 - C2[1,k]
        end
        for k=n-1:-2:3
            C2[k,2] = (C1[k,3]-C1[k-1,2]-C1[k+1,2])/2 + C1[k,1] - C2[k,2]
            C2[2,k] = (C1[2,k+1]+C1[2,k-1]-C1[3,k])/2 - C1[1,k] - C2[2,k]
        end
        for j=n:-1:3,i=n-j+1:-2:3
            C2[i,j] = (C1[i,j+1]+C1[i,j-1]-C1[i+1,j]-C1[i-1,j])/2 - C2[i,j]
        end

        cn = c[n]
        for j=n:-1:1,i=n-j+1:-2:1
            X[i,j] += cn*C2[i,j]
        end

        for j=1:n,i=1:n-j+1
            C1[i,j],C2[i,j] = C2[i,j],C1[i,j]
        end
    end
end

#
# ProductFun constructors for functions on periodic intervals.
#

#
# Suppose we are interested in K(ϕ-θ). Then, K(⋅) is periodic
# whether it's viewed as bivariate or univariate.
#
function ProductFun{S<:Fourier,T,U<:Fourier,V<:Fourier}(f::Fun{S,T},u::U,v::V)
    df,du,dv = domain(f),domain(u),domain(v)
    @assert df == du == dv && isa(df,PeriodicInterval)
    c = coefficients(f)
    N = length(c)
    X = zeros(T,N,N)
    X[1,1] += c[1]
    @inbounds for i=2:2:N-1
        X[i,i] += c[i+1]
        X[i+1,i] += c[i]
        X[i,i+1] -= c[i]
        X[i+1,i+1] += c[i+1]
    end
    if mod(N,2)==0 X[N,N-1],X[N-1,N] = c[N],-c[N] end
    ProductFun(X,u⊗v)
end

function ProductFun{S<:CosSpace,T,U<:Fourier,V<:Fourier}(f::Fun{S,T},u::U,v::V)
    df,du,dv = domain(f),domain(u),domain(v)
    @assert df == du == dv && isa(df,PeriodicInterval)
    c = coefficients(f)
    N = 2length(c)-1
    X = zeros(T,N,N)
    X[1,1] += c[1]
    @inbounds for i=2:2:N
        X[i,i] += c[i/2+1]
        X[i+1,i+1] += c[i/2+1]
    end
    ProductFun(X,u⊗v)
end

function ProductFun{S<:SinSpace,T,U<:Fourier,V<:Fourier}(f::Fun{S,T},u::U,v::V)
    df,du,dv = domain(f),domain(u),domain(v)
    @assert df == du == dv && isa(df,PeriodicInterval)
    c = coefficients(f)
    N = 2length(c)+1
    X = zeros(T,N,N)
    @inbounds for i=2:2:N
        X[i+1,i] += c[i/2]
        X[i,i+1] -= c[i/2]
    end
    ProductFun(X,u⊗v)
end

function ProductFun{S<:Laurent,T,U<:Laurent,V<:Laurent}(f::Fun{S,T},u::U,v::V)
    df,du,dv = domain(f),domain(u),domain(v)
    @assert df == du == dv && isa(df,PeriodicInterval)
    c = coefficients(f)
    N = length(c)
    X = mod(N,2) == 0 ? zeros(T,N+1,N) : zeros(T,N,N)
    X[1,1] += c[1]
    @inbounds for i=2:2:N-1
        X[i+1,i] += c[i]
        X[i,i+1] += c[i+1]
    end
    if mod(N,2)==0 X[N+1,N] = c[N] end
    ProductFun(X,u⊗v)
end

function ProductFun{S<:Taylor,T,U<:Laurent,V<:Laurent}(f::Fun{S,T},u::U,v::V)
    df,du,dv = domain(f),domain(u),domain(v)
    @assert df == du == dv && isa(df,PeriodicInterval)
    c = coefficients(f)
    N = 2length(c)-1
    X = zeros(T,N-1,N)
    X[1,1] += c[1]
    @inbounds for i=2:2:N-1
        X[i,i+1] += c[i/2+1]
    end
    ProductFun(X,u⊗v)
end

function ProductFun{S<:Hardy{false},T,U<:Laurent,V<:Laurent}(f::Fun{S,T},u::U,v::V)
    df,du,dv = domain(f),domain(u),domain(v)
    @assert df == du == dv && isa(df,PeriodicInterval)
    c = coefficients(f)
    N = 2length(c)
    X = zeros(T,N+1,N)
    @inbounds for i=2:2:N
        X[i+1,i] += c[i/2]
    end
    ProductFun(X,u⊗v)
end
