/*
** Copyright (C) 1993-1995, 1997-2002 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

/*
** std.h - "standard" [sic] definitions for C:
**	MR_bool, MR_TRUE, MR_FALSE, MR_min(), MR_max(), MR_streq(), etc.
*/

#ifndef MERCURY_STD_H
#define MERCURY_STD_H

#include <stdlib.h>	/* for size_t */
#include <assert.h>	/* for assert() */
#ifndef IN_GCC
  #include <ctype.h>	/* for isalnum(), etc. */
#else
#include <errno.h>
  /*
  ** When building compiler/gcc.m, we #include GCC back-end
  ** header files that include libiberty's "safe-ctype.h",
  ** and we can't include both safe-ctype.h and ctype.h,
  ** since they conflict, so include safe-ctype.h
  ** rather than ctype.h.
  */
  #include "safe-ctype.h"
#endif

/*
** The boolean type, MR_bool, with constants MR_TRUE and MR_FALSE.
**
** We use `int' rather than `char' for MR_bool, because GCC has problems
** optimizing tail calls for functions that return types smaller than `int'.
** In most cases, `int' is more efficient anyway.
** The only exception is that in some cases it is more important to optimize
** space rather than time; in those (rare) cases, you can use `MR_small_bool'
** instead of `MR_bool'.
*/
typedef	int		MR_bool;
typedef	char		MR_small_bool;

#define	MR_TRUE		1
#define	MR_FALSE	0

#define	MR_max(a, b)	((a) > (b) ? (a) : (b))
#define	MR_min(a, b)	((a) < (b) ? (a) : (b))

/*
** The ANSI C isalnum(), etc. macros require that the argument be cast to
** `unsigned char'; if you pass a signed char, the behaviour is undefined.
** Hence we define `MR_' versions of these that do the cast -- you should
** make sure to always use the `MR_' versions rather than the standard ones.
*/

#define	MR_isupper(c)		isupper((unsigned char) (c))
#define	MR_islower(c)		islower((unsigned char) (c))
#define	MR_isalpha(c)		isalpha((unsigned char) (c))
#define	MR_isalnum(c)		isalnum((unsigned char) (c))
#define	MR_isdigit(c)		isdigit((unsigned char) (c))
#define	MR_isspace(c)		isspace((unsigned char) (c))
#define	MR_isalnumunder(c)	(isalnum((unsigned char) (c)) || c == '_')

#define MR_streq(s1, s2)	(strcmp(s1, s2) == 0)
#define MR_strdiff(s1, s2)	(strcmp(s1, s2) != 0)
#define MR_strtest(s1, s2)	(strcmp(s1, s2))
#define MR_strneq(s1, s2, n)	(strncmp(s1, s2, n) == 0)
#define MR_strndiff(s1, s2, n)	(strncmp(s1, s2, n) != 0)
#define MR_strntest(s1, s2, n)	(strncmp(s1, s2, n))

#define	MR_ungetchar(c)		ungetc(c, stdin)

/*
** For speed, turn assertions off,
** unless low-level debugging is enabled.
*/
#ifdef MR_LOWLEVEL_DEBUG
  #define MR_assert(ASSERTION)	assert(ASSERTION)
#else
  #define MR_assert(ASSERTION)	((void)0)
#endif

/*---------------------------------------------------------------------------*/

#ifdef EINTR
  #define MR_is_eintr(x)	((x) == EINTR)
#else
  #define MR_is_eintr(x)	MR_FALSE
#endif

/*---------------------------------------------------------------------------*/

/*
** MR_VARIABLE_SIZED -- what to put between the []s when declaring
**			a variable length array at the end of a struct.
**
** The preferred values, if the compiler understands them, convey to the
** implementation that the array has a variable length. The default value
** is the maximum length of the variable-length arrays that we construct,
** since giving too small a value may lead the compiler to use inappropriate
** optimizations (e.g. using small offsets to index into the array).
** At the moment, we use variable length arrays that are indexed by
** closure argument numbers or by type parameter numbers. We therefore
** use a default MR_VARIABLE_SIZED value that is at least as big as
** both MR_MAX_VIRTUAL_REG and MR_PSEUDOTYPEINFO_MAX_VAR.
*/

#if __STDC_VERSION__ >= 199901	/* January 1999 */
  /* Use C9X-style variable-length arrays. */
  #define	MR_VARIABLE_SIZED	/* nothing */
#elif defined(__GNUC__)
  /* Use GNU-style variable-length arrays */
  #define	MR_VARIABLE_SIZED	0
#else
  /* Just fake it by pretending that the array has a fixed size */
  #define	MR_VARIABLE_SIZED	1024
#endif

/*---------------------------------------------------------------------------*/

/*
** Macros for inlining.
**
** Inlining is treated differently by C++, C99, and GNU C.
** We also need to make it work for C89, which doesn't have
** any explicit support for inlining.
**
** To make a function inline, you should declare it as either
** `MR_INLINE', `MR_EXTERN_INLINE', or `MR_STATIC_INLINE'.
** You should not use `extern' or `static' in combination with these macros.
**
** `MR_STATIC_INLINE' should be used for functions that are defined and
** used only in a single translation unit (i.e. a single C source file).
**
** If the inline function is to be used from more than one translation unit,
** then the function definition (not just declaration) should go in
** a header file, and you should use either MR_INLINE or MR_EXTERN_INLINE;
** the difference between these two is explained below.
**
** MR_INLINE creates an inline definition of the function, and
** if needed it also creates an out-of-line definition of the function
** for the current translation unit, in case the function can't be inlined
** (e.g. because the function's address was taken, or because the
** file is compiled with the C compiler's optimizations turned off.)
** For C++, these definitions will be shared between different
** compilation units, but for C, each compilation unit that needs
** an out-of-line definition will gets its own definition.
** Generally that is not much of a problem, but if the C compiler
** doesn't optimize away such out-of-line definitions when they're
** not needed, this can get quite bad.
**
** MR_EXTERN_INLINE creates an inline definition of the function,
** but it does NOT guarantee to create an out-of-line definition,
** even if one might be needed.  You need to explicitly provide
** an out-of-line definition for the function in one of the C files.
** This should be done using the MR_OUTLINE_DEFN(decl,body) macro,
** e.g. `MR_OUTLINE_DEFN(int foo(int x), { return x; })'.
**
** The advantage of MR_EXTERN_INLINE is that it is more code-space-efficient,
** especially in the case where you are compiling with C compiler optimizations
** turned off.
**
** It is OK to take the address of an inline function,
** but you should not assume that the address of a function declared
** MR_INLINE or MR_EXTERN_INLINE will be the same in all translation units.
*/

#if defined(__cplusplus)
  /* C++ */
  #define MR_STATIC_INLINE		static inline
  #define MR_INLINE			inline
  #define MR_EXTERN_INLINE		inline
  #define MR_OUTLINE_DEFN(DECL,BODY)
#elif defined(__GNUC__) 
  /* GNU C */
  #define MR_STATIC_INLINE		static __inline__
  #define MR_INLINE			static __inline__
  #define MR_EXTERN_INLINE		extern __inline__
  #define MR_OUTLINE_DEFN(DECL,BODY)	DECL BODY
#elif __STDC_VERSION__ >= 199901
  /* C99 */
  #define MR_STATIC_INLINE		static inline
  #define MR_INLINE			static inline
  #define MR_EXTERN_INLINE		inline
  #define MR_OUTLINE_DEFN(DECL,BODY)	extern DECL;
#else
  /* C89 */
  #define MR_STATIC_INLINE		static
  #define MR_INLINE			static
  #define MR_EXTERN_INLINE		static
  #define MR_OUTLINE_DEFN(DECL,BODY)
#endif

/*---------------------------------------------------------------------------*/

/* A macro for declaring functions that never return */

#if __GNUC__
  #define MR_NO_RETURN __attribute__((noreturn))
#else
  #define MR_NO_RETURN
#endif

/*---------------------------------------------------------------------------*/

/*
** MR_CALL:
** A macro for specifying the calling convention to use
** for C functions generated by the MLDS back-end
** (and for builtins such as unification which must use
** the same calling convention).
** This can expand to whatever implementation-specific magic 
** is required to tell the C compiler to use a different
** calling convention.
**
** If MR_USE_REGPARM is defined, and we're using gcc on x86,
** then we use a non-standard but more efficient calling
** convention that passes parameters in registers.
** Otherwise we just use the default C calling convention.
**
** Any changes here (e.g. adding additional calling conventions,
** or adding support for other C compilers or other processors)
** should be reflected in the mangled grade name produced by
** runtime/mercury_grade.h.
**
** It might be slightly more efficient to use __regparm__(3) rather than
** __regparm__(2), but GCC won't do tail-call optimization for calls via
** function pointers if we use __regparm__(3), since there may be no spare
** caller-save registers to hold the function pointer.  Tail call
** optimization is more likely to be important than squeezing the last 1%
** in performance.
*/
#if defined(MR_USE_REGPARM) && defined(__GNUC__) && defined(__i386__)
  #define MR_CALL __attribute__((__stdcall__, __regparm__(2)))
#else
  #define MR_CALL
#endif

/*---------------------------------------------------------------------------*/

/*
** C preprocessor tricks.
*/

/* convert a macro to a string */
#define MR_STRINGIFY(x)		MR_STRINGIFY_2(x)
#define MR_STRINGIFY_2(x)	#x

/* paste some macros together */
#define MR_PASTE2(a,b)			MR_PASTE2_2(a,b)
#define MR_PASTE2_2(a,b)		a##b
#define MR_PASTE3(a,b,c)		MR_PASTE3_2(a,b,c)
#define MR_PASTE3_2(a,b,c)		a##b##c
#define MR_PASTE4(a,b,c,d)		MR_PASTE4_2(a,b,c,d)
#define MR_PASTE4_2(a,b,c,d)		a##b##c##d
#define MR_PASTE5(a,b,c,d,e)		MR_PASTE5_2(a,b,c,d,e)
#define MR_PASTE5_2(a,b,c,d,e)		a##b##c##d##e
#define MR_PASTE6(a,b,c,d,e,f)		MR_PASTE6_2(a,b,c,d,e,f)
#define MR_PASTE6_2(a,b,c,d,e,f)	a##b##c##d##e##f
#define MR_PASTE7(a,b,c,d,e,f,g)	MR_PASTE7_2(a,b,c,d,e,f,g)
#define MR_PASTE7_2(a,b,c,d,e,f,g)	a##b##c##d##e##f##g
#define MR_PASTE8(a,b,c,d,e,f,g,h)	    MR_PASTE8_2(a,b,c,d,e,f,g,h)
#define MR_PASTE8_2(a,b,c,d,e,f,g,h)	    a##b##c##d##e##f##g##h
#define MR_PASTE9(a,b,c,d,e,f,g,h,i)	    MR_PASTE9_2(a,b,c,d,e,f,g,h,i)
#define MR_PASTE9_2(a,b,c,d,e,f,g,h,i)	    a##b##c##d##e##f##g##h##i
#define MR_PASTE10(a,b,c,d,e,f,g,h,i,j)	    MR_PASTE10_2(a,b,c,d,e,f,g,h,i,j)
#define MR_PASTE10_2(a,b,c,d,e,f,g,h,i,j)   a##b##c##d##e##f##g##h##i##j

/*
** MR_CHECK_EXPR_TYPE(expr, type):
** This macro checks that the given expression has a type
** which is compatible with (assignable to) the specified type,
** forcing a compile error if it does not.
** It does not evaluate the expression.
** Note that the specified type must be a complete type,
** i.e. it must not be a pointer to a struct which has
** not been defined.
**
** This macro is useful for defining type-safe function-like macros.
**
** The implementation of this macro looks like it dereferences
** a null pointer, but because that code is inside sizeof(), it will
** not get executed; the compiler will instead just check that it is
** type-correct.
*/
#define MR_CHECK_EXPR_TYPE(expr, type) \
	((void) sizeof(*(type *)NULL = (expr)))

/*---------------------------------------------------------------------------*/

#define MR_SORRY(msg) MR_fatal_error("Sorry, not yet implemented: " msg);

/*---------------------------------------------------------------------------*/

#endif /* not MERCURY_STD_H */
