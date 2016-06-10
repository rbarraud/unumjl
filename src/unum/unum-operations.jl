#unum-oddsandends.jl
#mathematical odds and ends

################################################################################

doc"""
  `Unums.frac_val(::UInt64)`
  `Unums.frac_val(::ArrayNum)`
  returns the integral value for a number used as a fraction.
"""
frac_val(x::UInt64) = x
function frac_val{FSS}(v::ArrayNum{FSS})
  (typeof(v) == UInt64) && return big(v)
  sum = big(0)
  for i = 1:length(v.a)
    sum += big(v.a[i]) * (big(1) << ((i - 1) * 64))
  end
  sum
end

doc"""`Unums.calculate(x::Unum)` returns a bigfloat equivalent of the unum.  NB:
currently doesn't work so well for FSS > 9"""
@universal function calculate(x::Unum)
  sign = (x.flags & UNUM_SIGN_MASK != 0) ? -1 : 1
  #the sub`normal case
  if (x.exponent == 0)
    2.0^(decode_exp(x) + 1) * sign * (frac_val(x.fraction)) / 2.0^(64 * length(x.fraction))
  else #the normalcase
    2.0^(decode_exp(x)) * sign * (1 + frac_val(x.fraction) / 2.0^(64 * length(x.fraction)))
  end
end
export calculate

################################################################################

doc"""
  `additiveinverse!` creates the additive inverse value of a unum, by flipping
  the sign.  This can be better than the `-` operator because it doesn't copy
  the unum.  A reference to the unum is returned.
"""
@universal additiveinverse!(x::Unum) = (x.flags $= UNUM_SIGN_MASK; return x)
export additiveinverse!

doc"""
  `coerce_sign!` creates the additive inverse value of a unum, by flipping
  the sign.  This can be better than the `-` operator because it doesn't copy
  the unum.  A reference to the unum is returned.
"""
@universal coerce_sign!(a::Unum, b::Unum) = (a.flags = (a.flags & ~UNUM_SIGN_MASK) | (b.flags & UNUM_SIGN_MASK); return a)

doc"""
  `abs!(::Unum)` forces the value of the unum to be positive.  Returns the
  unum for chaining purposes.
"""
@universal abs!(x::Unum) = ((x.flags &= ~UNUM_SIGN_MASK); return x)
export abs!

@universal function Base.copy!(dest::Unum, src::Unum)
  dest.fsize = src.fsize
  dest.esize = src.esize
  dest.flags = src.flags & UNUM_FLAG_MASK
  dest.exponent = src.exponent

  (FSS < 7) ? (dest.fraction = src.fraction) : (copy!(dest.fraction, src.fraction))

  return dest  #for chaining purposes
end

#=
doc"""
  Unums.match_fsize!{ESS,FSS} takes the location of fsize and moves it over to dest.

  The exponent on src should less than or equal to the exponent on dest.
"""
function match_fsize!{ESS,FSS}(src::Unum{ESS,FSS}, dest::Unum{ESS,FSS})
  src_exp::Int64 = decode_exp(src)
  dest_exp::Int64 = decode_exp(dest)
  dest.fsize = UInt16(min(src.fsize + dest_exp - src_exp, max_fsize(FSS)))
end
=#
#=
#note the difference between "more/less", and "next/prev" - next/prev refers
#to position along the number line, "more/less" refers to magnitude along the
#number line.  NB:  __bigger_exact and __smaller_exact do *not* perform checks
#on the properties of their passed values so should be used with caution.

function __outward_exact{ESS,FSS}(a::Unum{ESS,FSS})
  #set the location of the added bit:  remember that fsize is the actual length - 1
  location = (is_ulp(a)) ? a.fsize + 1 : max_fsize(FSS)
  #generate a new superint that represents what we're going to add in.
  delta = __bit_from_top(location, length(a.fraction))
  #add the delta in, making it a
  (carry, fraction) = __carried_add(z64, a.fraction, delta)

  #check the two cases.
  if (carry != 0)
    (esize, exponent) = encode_exp(decode_exp(a) + 1)
    fraction = lsh(fraction, o16)
  else
    esize = a.esize
    exponent = a.exponent
  end
  #recalculate fsize, since this is exact, we can deal with ULPs as needed.
  fsize::UInt16 = __minimum_data_width(fraction)

  Unum{ESS,FSS}(fsize, esize, a.flags & UNUM_SIGN_MASK, fraction, exponent)
end
=#

doc"""
  `Unums.resolve_degenerates!(::Unum)` checks for degeneracy in unum values,
  and resolves to "canonical" form - which means all nonzero subnormals are
  converted to normal form if possible, and exact zeros are the smallest zero.
  fsize is maximally trimmed for exact values.
"""
@universal function resolve_degenerates!(x::Unum)
  (x.exponent != 0) && return x   #kick out if our exponent is not zero.
  (x.esize == max_esize(ESS)) && return x #kick out if we're not a strange subnormal.
  if is_all_zero(x.fraction)
    is_exact(x) && return zero(typeof(x))
    return x #if we're actually zero or a zero+ulp subnormal we can't shift.
  end

  true_exponent = decode_exp(x)
  #now, count leading zeros, be prepared to shift left.
  leftshift = clz(x.fraction) + o16
  #next, shift the shadow fraction to the left appropriately.
  frac_lsh!(x, leftshift)
  true_exponent -= leftshift - o16
  exact_trim!(x)
  (x.esize, x.exponent) = encode_exp(true_exponent)

  return x
end

#=
@gen_code function __inward_ulp!{ESS,FSS}(x::Unum{ESS,FSS})
  @code quote
    is_strange_subnormal(x) && __resolve_subnormal!(x)
    if is_frac_zero(x)
      #deal with subnormal.
      is_exp_zero(x) && (sss!(x, x.flags & UNUM_SIGN_MASK); return x)
      current_exponent = decode_exp(x)
      (x.esize, x.exponent) = ((current_exponent == min_exponent(ESS)) ? (z16, z64) : encode_exp(decode_exp(x) - 1))
    end
    x.flags |= UNUM_UBIT_MASK
  end
  if (FSS < 7)
    @code :(x.fraction -= bottom_bit(max_fsize(FSS)); x)
  else
    @code :(prev_val!(x.fraction); x)
  end
end

function make_min_ulp!{ESS,FSS}(x::Unum{ESS,FSS})
  x.fsize = max_fsize(FSS)
  x.flags |= UNUM_UBIT_MASK
  x
end

function __outward_exact!{ESS,FSS}(x::Unum{ESS,FSS})
  promoted::Bool = __add_ubit_frac!(x)
  promoted && ((x.esize, x.exponent) = (encode_exp(decode_exp(x) + 1)))
  x.flags &= ~UNUM_UBIT_MASK
  x
end

doc"""`upper_ulp!(::Unum)` converts to the unum which is the ulp immediatel above itit."""
function upper_ulp!{ESS,FSS}(x::Unum{ESS,FSS})
  is_zero(x) && return pos_sss!(x)
  return is_positive(x) ? make_min_ulp!(x) : __inward_ulp!(x)
end

doc"""`lower_ulp!(::Unum)` converts to the unum which is the ulp immediately below it."""
function lower_ulp!{ESS,FSS}(x::Unum{ESS,FSS})
  is_zero(x) && return neg_sss!(x)
  return is_positive(x) ? __inward_ulp!(x) : make_min_ulp!(x)
end

doc"""`upper_exact!(::Unum)` converts to the unum which is the exact number that upper bounds it."""
function upper_exact!{ESS,FSS}(x::Unum{ESS,FSS})
  __is_nan_or_inf(x) && (nan!(x); return)
  is_exact(x) && return x
  return is_negative(x) ? make_exact!(x) : __outward_exact!(x)
end

doc"""`lower_exact!(::Unum)` converts to the unum which is the exact number that upper bounds it."""
function lower_exact!{ESS,FSS}(x::Unum{ESS,FSS})
  __is_nan_or_inf(x) && (nan!(x); return)
  is_exact(x) && return x
  return is_negative(x) ? __outward_exact!(x) : make_exact!(x)
end
=#

################################################################################
## sophisticated exactitude functions.

doc"""
  `Unums.outward_ulp!(::Unum)` returns the smallest-width ulp immediately above the
  current unum.  If this is exact, it simply trips the ulp flag with the biggest fsize.
  If it's inexact, it bumps to the outer-bound exact and moves the size of the ulp
  far out.
"""
@universal function outward_ulp!(x::Unum)
  resolve_degenerates!(x)
  if is_exact(x)
    x.fsize = max_fsize(FSS)
    make_ulp!(x::Unum)
  end
  return add_bit_and_set_ulp!(x, x.fsize, max_fsize(FSS))
end

@universal function inward_ulp!(x::Unum)
  resolve_degenerates!(x)
  if is_frac_zero(x)
    #then, we're zero or a zeroish ulp, so kill it with fire.
    is_exp_zero(x) && return nan!(x)
    #let's find out what's up here.
    _exp = decode_exp(x)
    if _exp == min_exponent(ESS)
      x.esize = max_esize(ESS)
      x.exponent = z64
    else
      (x.esize, x.exponent) = encode_exp(_exp - 1)
    end
    return make_ulp!(frac_all!(x))
  end
  frac_sub_ubit!(x, max_fsize(FSS))
  return x
end

################################################################################
## dumb exactitude functions.

doc"""`Unums.make_exact(::Unum)` forces the ubit of a unum to be 0."""
@universal make_exact!(x::Unum) = (x.flags &= ~UNUM_UBIT_MASK; x)

doc"""`Unums.make_ulp(::Unum)` forces the ubit of a unum to be 1."""
@universal make_ulp!(x::Unum) = (x.flags |= UNUM_UBIT_MASK; x)

################################################################################
## carry resolution

doc"""
  `Unums.resolve_carry!(carry::UInt64, ::Unum, exponent::Int64)` resolves a
  carry (invisible bit) value that may exceed one after calculation events.
  You should pass this function an exponent value that will be returned,
  appropriately modified.
"""
@universal function resolve_carry!(carry::UInt64, x::Unum, exponent::Int64)
  leftzeroes = clz(carry)
  if (leftzeroes < 0x003F) #less than 63 zeroes
    shift = 0x003F - leftzeroes
    rsh_and_set_ubit!(x, shift)
    #now copy the bits over from the carried segment.
    frac_copy_top!(x, (((o64 << shift) - o64) & carry) << (leftzeroes + o16))
    exponent += shift
  end
  (exponent > max_exponent(ESS)) && mmr!(x)  #set it to mmr, if the exponent is too large.
  (x.esize, x.exponent) = encode_exp(exponent)
end
