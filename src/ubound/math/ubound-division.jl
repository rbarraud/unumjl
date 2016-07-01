#ubound-division.jl

#division on ubounds.

################################################################################
## division

@universal function udiv(a::Ubound, b::Unum)
  aln = is_negative(a.lower)
  ahn = is_negative(a.upper)
  bn = is_negative(b)

  (aln != ahn) && return (bn ? B(a.upper / b, a.lower / b) : B(a.lower / b, a.upper / b))

  bn ? resolve_utype!(a.upper / b, a.lower / b) : resolve_utype!(a.lower / b, a.upper / b)
end

@universal function udiv(a::Unum, b::Ubound)
  bln = is_negative(b.lower)

  #if the dividend straddles, then we have nan.
  (bln != is_negative(b.upper)) && return nan(U)

  if (is_negative(a) != bln)
    lower_result = resolve_lower(a / b.lower)
    upper_result = resolve_upper(a / b.upper)
    resolve_utype!(lower_result, upper_result)
  else
    lower_result = resolve_lower(a / b.upper)
    upper_result = resolve_upper(a / b.lower)
    resolve_utype!(lower_result, upper_result)
  end
end

@universal function udiv(a::Ubound, b::Ubound)
  signcode::UInt16 = 0
  is_negative(a.lower) && (signcode += 1)
  is_negative(a.upper) && (signcode += 2)
  is_negative(b.lower) && (signcode += 4)
  is_negative(b.upper) && (signcode += 8)

  if (signcode == 0) #everything is positive
    lower_result = resolve_lower(a.lower / b.upper)
    upper_result = resolve_upper(a.upper / b.lower)
    resolve_utype!(lower_result, upper_result)
  elseif (signcode == 1) #only a.lowbound is negative
    B(a.lower / b.lower, a.upper / b.lower)
  #signcode 2 is not possible
  elseif (signcode == 3) #a is negative and b is positive
    lower_result = resolve_lower(a.upper / b.lower)
    upper_result = resolve_upper(a.lower / b.upper)
    resolve_utype!(lower_result, upper_result)
  elseif (signcode == 4) #only b.lowbound is negative
    #b straddles zero so we'll output NaN
    return nan(U)
  elseif (signcode == 5) #a.lowbound and b.lowbound are negative
    #b straddles zero so we'll output NaN
    return nan(U)
  #signcode 6 is not possible
  elseif (signcode == 7) #only b.highbound is positive
    #b straddles zero so we'll output NaN
    return nan(U)
  #signcode 8, 9, 10, 11 are not possible
  elseif (signcode == 12) #b is negative, a is positive
    lower_result = resolve_lower(a.upper / b.lower)
    upper_result = resolve_upper(a.lower / b.upper)
    resolve_utype!(lower_result, upper_result)
  elseif (signcode == 13) #b is negative, a straddles
    B(a.upper / b.upper, a.lower / b.upper)
  #signcode 14 is not possible
  elseif (signcode == 15) #everything is negative
    lower_result = resolve_lower(a.lower / b.upper)
    upper_result = resolve_upper(a.upper / b.lower)
    resolve_utype!(lower_result, upper_result)
  else
    throw(ArgumentError("error dividing ubounds $a and $b, throws invalid signcode $signcode."))
  end
end
