#i64o-utilities.jl

#implement the deep copy constructor and the overwriting copy! function for ArrayNums.
Base.copy{FSS}(a::ArrayNum{FSS}) = ArrayNum{FSS}(copy(a.a))
function Base.copy!{FSS}(dest::ArrayNum{FSS}, src::ArrayNum{FSS})
  for idx = 1:__cell_length(FSS)
    @inbounds dest.a[idx] = src.a[idx]
  end
end

#bits function for hlayer output.
Base.bits{FSS}(a::ArrayNum{FSS}) = mapreduce(bits, (s1, s2) -> string(s1, s2), "", a.a)

#forwarding getindex and setindex!
Base.getindex{FSS}(a::ArrayNum{FSS}, key...) = getindex(a.a, key...)
Base.setindex!{FSS}(a::ArrayNum{FSS}, X, keys...) = setindex!(a.a, X, keys...)

doc"""
`Unums.set_bit!` sets a bit in the ArrayNum referred to by the value b, this bit
is one-indexed with the bit 1 being the most significant.  A value of zero has
undefined effects.  Useful for setting bits after shifting a non-subnormal value.
"""
function set_bit!{FSS}(a::ArrayNum{FSS}, bit::UInt16)
  a_index = ((bit - o16) >> 6) + o16
  b_index = ((bit - o16) % 64)
  @inbounds a.a[a_index] = a.a[a_index] | (0x8000_0000_0000_0000 >> b_index)
  a
end

doc"""
`Unums.set_bit` sets a bit in a UInt64, this bit is one-indexed with the top bit
being the the most significant.  A value of zero has undefined effects.  Useful
for setting bits after shifting a non-subnormal value.
"""
function set_bit(a::UInt64, bit::UInt16)
  a | (0x8000_0000_0000_0000 >> (bit - o16))
end
doc"""
`Unums.frac_set_bit!(x, bit)` sets (one-indexed) bit, which is useful for setting
bits after shifting a non-subnormal value.
"""
@fracproc set_bit bit

doc"""
`Unums.get_bit(x, bit)` returns true if the (zero-indexed) bit of x is one, false
if not.
"""
function get_bit(a::UInt64, bit::UInt16)
  (a & (t64 >> bit)) != 0
end
function get_bit{FSS}(a::ArrayNum{FSS}, bit::UInt16)
  a_index = ((bit - o16) >> 6) + o16
  b_index = ((bit - o16) % 64)
  @inbounds (a.a[a_index] & (t64 >> b_index)) != 0
end

doc"""
`Unums.copy_top(x, val)` performs the logical or of the value with the fraction
of x, or the first element in x fraction array.
"""
copy_top(a::UInt64, pattern::UInt64) = a | pattern
copy_top!{FSS}(a::ArrayNum{FSS}, pattern::UInt64) = (a[1] |= pattern)

doc"""
`Unums.frac_copy_top!(x::Unum, pattern::UInt64)` performs the logical or of the pattern
with the fraction of x, or the first element in x fraction array.
"""
@fracproc copy_top pattern


#__minimum_data_width
#calculates the minimum data width to represent the passed superint.
function __minimum_data_width{FSS}(n::ArrayNum{FSS})
  res = max(z16, max_fsize(FSS) - ctz(n))
  res == 0xFFFF ? z16 : res
end
  #explanation of formula:
  #length(a) << 6:            total bits in the array representation
  #-trailing_zeros(f):        how many zeros are at the end, we can trim those
  #-1:                        the bit representation (1000...0000) = "1" has
  #                           width 0 as per our definition.
  #max(0, ...):               bit representation of (0000...0000) = "0" also
  #                           has width 0, not width "-1".

#this is a better formula for a single-width unsigned integer representation.
__minimum_data_width(n::UInt64) = (res = max(z16, 0x003F - ctz(n)); res == 0xFFFF ? z16 : res)

#simply assign this to a hash of the array itself.
Base.hash{FSS}(n::ArrayNum{FSS}, h::UInt) = hash(n.a, h)
