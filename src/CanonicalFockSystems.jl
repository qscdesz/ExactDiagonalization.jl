module CanonicalFockSystems

using Base.Iterators: product
using Printf: @printf, @sprintf
using QuantumLattices: id, iscreation, periods, rank, statistics
using QuantumLattices: AbelianNumber, Combinations, DuplicatePermutations, Fock, Hilbert, Index, Metric, Operator, Operators, OperatorUnitToTuple, ParticleNumber, SpinfulParticle, Table, VectorSpace
using SparseArrays: SparseMatrixCSC, spzeros
using ..EDCore: ED, EDKind, EDMatrixRepresentation, Sector, TargetSpace

import QuantumLattices: ⊗, matrix

export BinaryBases, BinaryBasis, BinaryBasisRange, basistype, productable, sumable

# Binary bases commonly used in canonical fermionic and hardcore bosonic quantum lattice systems
@inline basistype(i::Integer) = basistype(typeof(i))
@inline basistype(::Type{T}) where {T<:Unsigned} = T
@inline basistype(::Type{Int8}) = UInt8
@inline basistype(::Type{Int16}) = UInt16
@inline basistype(::Type{Int32}) = UInt32
@inline basistype(::Type{Int64}) = UInt64
@inline basistype(::Type{Int128}) = UInt128

"""
    BinaryBasis{I<:Unsigned}

Binary basis represented by an unsigned integer.
"""
struct BinaryBasis{I<:Unsigned}
    rep::I
    BinaryBasis{I}(i::Integer) where {I<:Unsigned} = new{I}(convert(I, i))
end
@inline BinaryBasis(i::Integer) = (rep = Unsigned(i); BinaryBasis{typeof(rep)}(rep))
@inline Base.:(==)(basis₁::BinaryBasis, basis₂::BinaryBasis) = basis₁.rep == basis₂.rep
@inline Base.isequal(basis₁::BinaryBasis, basis₂::BinaryBasis) = isequal(basis₁.rep, basis₂.rep)
@inline Base.:<(basis₁::BinaryBasis, basis₂::BinaryBasis) = basis₁.rep < basis₂.rep
@inline Base.isless(basis₁::BinaryBasis, basis₂::BinaryBasis) = isless(basis₁.rep, basis₂.rep)
@inline Base.one(basis::BinaryBasis) = one(typeof(basis))
@inline Base.one(::Type{BinaryBasis{I}}) where {I<:Unsigned} = BinaryBasis(one(I))
@inline Base.zero(basis::BinaryBasis) = zero(typeof(basis))
@inline Base.zero(::Type{BinaryBasis{I}}) where {I<:Unsigned} = BinaryBasis(zero(I))
@inline Base.show(io::IO, basis::BinaryBasis) = @printf io "%s" string(basis.rep, base=2)
@inline Base.eltype(basis::BinaryBasis) = eltype(typeof(basis))
@inline Base.eltype(::Type{<:BinaryBasis}) = Int
@inline Base.IteratorSize(::Type{<:BinaryBasis}) = Base.SizeUnknown()

"""
    iterate(basis::BinaryBasis, state=nothing)

Iterate over the numbers of the occupied single-particle orbitals.
"""
function Base.iterate(basis::BinaryBasis, state=nothing)
    (pos, rep) = isnothing(state) ? (0, basis.rep) : (state[1], state[2])
    while rep>0
        pos += 1
        isodd(rep) && return (pos, (pos, rep÷2))
        rep ÷= 2
    end
    return nothing
end

"""
    one(basis::BinaryBasis, state::Integer) -> BinaryBasis

Get a new basis with the specified single-particle state occupied. 
"""
@inline Base.one(basis::BinaryBasis, state::Integer) = BinaryBasis(basis.rep | one(basis.rep)<<(state-1))

"""
    isone(basis::BinaryBasis, state::Integer) -> Bool

Judge whether the specified single-particle state is occupied for a basis.
"""
@inline Base.isone(basis::BinaryBasis, state::Integer) = (basis.rep & one(basis.rep)<<(state-1))>0

"""
    zero(basis::BinaryBasis, state::Integer) -> BinaryBasis

Get a new basis with the specified single-particle state unoccupied.
"""
@inline Base.zero(basis::BinaryBasis, state::Integer) = BinaryBasis(basis.rep & ~(one(basis.rep)<<(state-1)))

"""
    iszero(basis::BinaryBasis, state::Integer) -> Bool

Judge whether the specified single-particle state is unoccupied for a basis.
"""
@inline Base.iszero(basis::BinaryBasis, state::Integer) = !isone(basis, state)

"""
    count(basis::BinaryBasis) -> Int
    count(basis::BinaryBasis, start::Integer, stop::Integer) -> Int

Count the number of occupied single-particle states.
"""
@inline Base.count(basis::BinaryBasis) = count(basis, 1, ndigits(basis.rep, base=2))
@inline function Base.count(basis::BinaryBasis, start::Integer, stop::Integer)
    result = 0
    for i = start:stop
        isone(basis, i) && (result += 1)
    end
    return result
end

"""
    ⊗(basis₁::BinaryBasis, basis₂::BinaryBasis) -> BinaryBasis

Get the direct product of two binary bases.
"""
@inline ⊗(basis₁::BinaryBasis, basis₂::BinaryBasis) = BinaryBasis(basis₁.rep|basis₂.rep)

"""
    BinaryBasis(states; filter=index->true)
    BinaryBasis{I}(states; filter=index->true) where {I<:Unsigned}

Construct a binary basis with the given occupied orbitals.
"""
@inline BinaryBasis(states; filter=index->true) = BinaryBasis{basistype(eltype(states))}(states; filter=filter)
function BinaryBasis{I}(states; filter=index->true) where {I<:Unsigned}
    rep, eye = zero(I), one(I)
    for (index, state) in enumerate(states)
        filter(index) && (rep += eye<<(state-1))
    end
    return BinaryBasis(rep)
end

"""
    BinaryBasisRange{I<:Unsigned} <: VectorSpace{BinaryBasis{I}}

A continuous range of binary basis.
"""
struct BinaryBasisRange{I<:Unsigned} <: VectorSpace{BinaryBasis{I}}
    slice::UnitRange{I}
end
@inline Base.issorted(::BinaryBasisRange) = true
@inline Base.length(bbr::BinaryBasisRange) = length(bbr.slice)
@inline Base.getindex(bbr::BinaryBasisRange, i::Integer) = BinaryBasis(bbr.slice[i])

"""
    BinaryBases{A<:AbelianNumber, B<:BinaryBasis, T<:AbstractVector{B}} <: Sector

A set of binary bases.
"""
struct BinaryBases{A<:AbelianNumber, B<:BinaryBasis, T<:AbstractVector{B}} <: Sector
    id::Vector{Tuple{B, A}}
    table::T
end
@inline Base.issorted(::BinaryBases) = true
@inline Base.length(bs::BinaryBases) = length(bs.table)
@inline Base.:(==)(bs₁::BinaryBases, bs₂::BinaryBases) = isequal(bs₁.id, bs₂.id)
@inline Base.isequal(bs₁::BinaryBases, bs₂::BinaryBases) = isequal(bs₁.id, bs₂.id)
@inline Base.getindex(bs::BinaryBases, i::Integer) = bs.table[i]
@inline Base.eltype(bs::BinaryBases) = eltype(typeof(bs))
@inline Base.eltype(::Type{<:BinaryBases{<:AbelianNumber, B}}) where {B<:BinaryBasis} = B
@inline Base.iterate(bs::BinaryBases, state=1) = state>length(bs) ? nothing : (bs.table[state], state+1)
function Base.repr(bs::BinaryBases)
    result = String[]
    for (states, qn) in bs.id
        push!(result, @sprintf "{2^%s: %s}" count(states) qn)
    end
    return join(result, " ⊗ ")
end
function Base.show(io::IO, bs::BinaryBases)
    for (i, (states, qn)) in enumerate(bs.id)
        @printf io "{2^[%s]: %s}" join(collect(states), " ") qn
        i<length(bs.id) && @printf io "%s" " ⊗ "
    end
end
@inline Base.searchsortedfirst(b::BinaryBasis, bs::BinaryBases) = searchsortedfirst(bs.table, b)
@inline Base.searchsortedfirst(b::BinaryBasis, bs::BinaryBases{<:AbelianNumber, <:BinaryBasis, <:BinaryBasisRange}) = Int(b.rep+1)

"""
    AbelianNumber(bs::BinaryBases)

Get the Abelian quantum number of a set of binary bases.
"""
@inline AbelianNumber(bs::BinaryBases) = sum(rep->rep[2], bs.id)

"""
    ⊗(bs₁::BinaryBases, bs₂::BinaryBases) -> BinaryBases

Get the direct product of two sets of binary bases.
"""
function ⊗(bs₁::BinaryBases, bs₂::BinaryBases)
    @assert productable(bs₁, bs₂) "⊗ error: the input two sets of bases cannot be direct producted."
    table = Vector{promote_type(eltype(bs₁), eltype(bs₂))}(undef, length(bs₁)*length(bs₂))
    count = 1
    for (b₁, b₂) in product(bs₁, bs₂)
        table[count] = b₁ ⊗ b₂
        count += 1
    end
    return BinaryBases(sort!([bs₁.id; bs₂.id]; by=first), sort!(table))
end

"""
    productable(bs₁::BinaryBases, bs₂::BinaryBases) -> Bool

Judge whether two sets of binary bases could be direct producted.
"""
function productable(bs₁::BinaryBases{A₁}, bs₂::BinaryBases{A₂}) where {A₁, A₂}
    A₁==A₂ || return false
    for (irr₁, irr₂) in product(bs₁.id, bs₂.id)
        isequal(irr₁[1].rep & irr₂[1].rep, 0) || return false
    end
    return true
end

"""
    sumable(bs₁::BinaryBases, bs₂::BinaryBases) -> Bool

Judge whether two sets of binary bases could be direct summed.

Strictly speaking, two sets of binary bases could be direct summed if and only if they have no intersection. The time complexity to check the intersection is O(n log n), which costs a lot when the dimension of the binary bases is huge. It is also possible to judge whether they could be direct summed by close investigations on their ids, i.e. the single-particle states and occupation number. It turns out that this is a multi-variable pure integer linear programming problem. In the future, this function would be implemented based on this observation. At present, the direct summability should be handled by the users in priori.
"""
@inline sumable(bs₁::BinaryBases, bs₂::BinaryBases) = true

"""
    BinaryBases(states)
    BinaryBases(nstate::Integer)
    BinaryBases{A}(states) where {A<:AbelianNumber}
    BinaryBases{A}(nstate::Integer) where {A<:AbelianNumber}

Construct a set of binary bases that subject to no quantum number conservation.
"""
@inline BinaryBases(argument) = BinaryBases{ParticleNumber}(argument)
function BinaryBases{A}(nstate::Integer) where {A<:AbelianNumber}
    id = [(BinaryBasis(one(nstate):nstate), A(map(p->NaN, periods(A))...))]
    table = BinaryBasisRange(zero(basistype(nstate)):basistype(nstate)(2^nstate-1))
    return BinaryBases(id, table)
end
function BinaryBases{A}(states) where {A<:AbelianNumber}
    id = [(BinaryBasis(states), A(map(p->NaN, periods(A))...))]
    table = BinaryBasis{basistype(eltype(states))}[]
    table = table!(table, NTuple{length(states), basistype(eltype(states))}(sort!(collect(states); rev=true)))
    return BinaryBases(id, table)
end
function table!(table, states::NTuple{N}) where N
    for poses in DuplicatePermutations{N}((false, true))
        push!(table, BinaryBasis(states; filter=index->poses[index]))
    end
    return table
end

"""
    BinaryBases(states, nparticle::Integer)
    BinaryBases(nstate::Integer, nparticle::Integer)
    BinaryBases{A}(states, nparticle::Integer; kwargs...) where {A<:AbelianNumber}
    BinaryBases{A}(nstate::Integer, nparticle::Integer; kwargs...) where {A<:AbelianNumber}

Construct a set of binary bases that preserves the particle number conservation.
"""
@inline BinaryBases(argument, nparticle::Integer) = BinaryBases{ParticleNumber}(argument, nparticle)
@inline BinaryBases{A}(nstate::Integer, nparticle::Integer; kwargs...) where {A<:AbelianNumber} = BinaryBases{A}(one(nstate):nstate, nparticle; kwargs...)
function BinaryBases{A}(states, nparticle::Integer; kwargs...) where {A<:AbelianNumber}
    kwargs = (kwargs..., N=nparticle)
    id = [(BinaryBasis(states), A(map(fieldname->getfield(kwargs, fieldname), fieldnames(A))...))]
    table = BinaryBasis{basistype(eltype(states))}[]
    table!(table, NTuple{length(states), basistype(eltype(states))}(sort!(collect(states); rev=true)), Val(nparticle))
    return BinaryBases(id, table)
end
function table!(table, states::Tuple, ::Val{N}) where N
    for poses in Combinations{N}(states)
        push!(table, BinaryBasis{eltype(states)}(poses))
    end
    return reverse!(table)
end

# CSC-formed sparse matrix representation of an operator
"""
    matrix(op::Operator, braket::NTuple{2, BinaryBases}, table; dtype=valtype(op)) -> SparseMatrixCSC{dtype, Int}
    matrix(ops::Operators, braket::NTuple{2, BinaryBases}, table; dtype=valtype(eltype(ops))) -> SparseMatrixCSC{dtype, Int}

Get the CSC-formed sparse matrix representation of an operator.

Here, `table` specifies the order of the operator ids.
"""
function matrix(op::Operator, braket::NTuple{2, BinaryBases}, table; dtype=valtype(op))
    bra, ket = braket[1], braket[2]
    ndata, intermediate = 1, zeros(ket|>eltype, rank(op)+1)
    data, indices, indptr = zeros(dtype, length(ket)), zeros(Int, length(ket)), zeros(Int, length(ket)+1)
    sequences = NTuple{rank(op), Int}(table[op[i]] for i in reverse(1:rank(op)))
    iscreations = NTuple{rank(op), Bool}(iscreation(index) for index in reverse(id(op)))
    for i = 1:length(ket)
        flag = true
        indptr[i] = ndata
        intermediate[1] = ket[i]
        for j = 1:rank(op)
            isone(intermediate[j], sequences[j])==iscreations[j] && (flag = false; break)
            intermediate[j+1] = iscreations[j] ? one(intermediate[j], sequences[j]) : zero(intermediate[j], sequences[j])
        end
        if flag
            nsign = 0
            statistics(eltype(op))==:f && for j = 1:rank(op)
                nsign += count(intermediate[j], 1, sequences[j]-1)
            end
            index = searchsortedfirst(intermediate[end], bra)
            if index<=length(bra) && bra[index]==intermediate[end]
                indices[ndata] = index
                data[ndata] = op.value*(-1)^nsign
                ndata += 1
            end
        end
    end
    indptr[end] = ndata
    return SparseMatrixCSC(length(bra), length(ket), indptr, indices[1:ndata-1], data[1:ndata-1])
end
function matrix(ops::Operators, braket::NTuple{2, BinaryBases}, table; dtype=valtype(eltype(ops)))
    result = spzeros(dtype, length(braket[1]), length(braket[2]))
    for op in ops
        result += matrix(op, braket, table; dtype=dtype)
    end
    return result
end

"""
    EDKind(::Type{<:Hilbert{<:Fock}})

The kind of the exact diagonalization method applied to a canonical quantum Fock lattice system.
"""
@inline EDKind(::Type{<:Hilbert{<:Fock}}) = EDKind(:FED)

"""
    Metric(::EDKind{:FED}, ::Hilbert{<:Fock}) -> OperatorUnitToTuple

Get the index-to-tuple metric for a canonical quantum Fock lattice system.
"""
@inline @generated Metric(::EDKind{:FED}, ::Hilbert{<:Fock}) = OperatorUnitToTuple(:spin, :site, :orbital)

"""
    Sector(hilbert::Hilbert{<:Fock}, quantumnumber::Nothing=nothing; table=Table(hilbert, Metric(EDKind(hilbert), hilbert)), basistype=UInt) -> BinaryBases
    Sector(hilbert::Hilbert{<:Fock}, quantumnumber::ParticleNumber; table=Table(hilbert, Metric(EDKind(hilbert), hilbert)), basistype=UInt) -> BinaryBases
    Sector(hilbert::Hilbert{<:Fock}, quantumnumber::SpinfulParticle; table=Table(hilbert, Metric(EDKind(hilbert), hilbert)), basistype=UInt) -> BinaryBases

Construct the binary bases of a Hilbert space with the specified quantum number.
"""
function Sector(hilbert::Hilbert{<:Fock}, quantumnumber::Nothing=nothing; table=Table(hilbert, Metric(EDKind(hilbert), hilbert)), basistype=UInt)
    states = Set{basistype}(table[Index(site, iid)] for (site, internal) in hilbert for iid in internal)
    return BinaryBases(states)
end
function Sector(hilbert::Hilbert{<:Fock}, quantumnumber::ParticleNumber; table=Table(hilbert, Metric(EDKind(hilbert), hilbert)), basistype=UInt)
    @assert !isnan(quantumnumber.N) "Sector error: particle number is NaN."
    states = Set{basistype}(table[Index(site, iid)] for (site, internal) in hilbert for iid in internal)
    return BinaryBases{ParticleNumber}(states, Int(quantumnumber.N))
end
function Sector(hilbert::Hilbert{<:Fock}, quantumnumber::SpinfulParticle; table=Table(hilbert, Metric(EDKind(hilbert), hilbert)), basistype=UInt)
    @assert all(internal->internal.nspin==2, values(hilbert)) "Sector error: only for spin-1/2 systems."
    @assert !isnan(quantumnumber.Sz) "Sector error: Sz is NaN."
    spindws = Set{basistype}(table[Index(site, iid)] for (site, internal) in hilbert for iid in internal if iid.spin==-1//2)
    spinups = Set{basistype}(table[Index(site, iid)] for (site, internal) in hilbert for iid in internal if iid.spin==+1//2)
    if isnan(quantumnumber.N)
        id = [(BinaryBasis([spindws..., spinups...]), quantumnumber)]
        table = BinaryBasis{basistype}[]
        for nup in max(Int(2*quantumnumber.Sz), 0):min(length(spinups)+Int(2*quantumnumber.Sz), length(spinups))
            ndw = nup-Int(2*quantumnumber.Sz)
            append!(table, BinaryBases(spindws, ndw) ⊗ BinaryBases(spinups, nup))
        end
        return BinaryBases(id, sort!(table)::Vector{BinaryBasis{basistype}})
    else
        ndw, nup = Int(quantumnumber.N/2-quantumnumber.Sz), Int(quantumnumber.N/2+quantumnumber.Sz)
        return BinaryBases{SpinfulParticle}(spindws, ndw; Sz=-0.5) ⊗ BinaryBases{SpinfulParticle}(spinups, nup; Sz=0.5)
    end
end

end # module