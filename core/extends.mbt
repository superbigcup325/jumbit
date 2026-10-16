///|
/// A `derive(Debug, Eq)` on a public type implicitly lifts `to_repr`/`equal`/`not_equal` into
/// ordinary methods (moonc v0.10.14 errors under `implicit_impl_as_method`). This repo has no call sites for
/// them, so they are declared deprecated to suppress the lift: the public surface stays minimal, and a trait shape is the way if ever needed
/// （`@debug.Debug::to_repr(x)` / `Eq::equal(a, b)`）
#deprecated("Use `@debug.Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend CodecError with @debug.Debug::{to_repr}

///|
#deprecated("Use `@debug.Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend Database with @debug.Debug::{to_repr}

///|
#deprecated("Use `@debug.Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend Dir with @debug.Debug::{to_repr}

///|
#deprecated("Use `@debug.Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend PlaintextError with @debug.Debug::{to_repr}

///|
#deprecated("Use `@debug.Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend GlobError with @debug.Debug::{to_repr}

///|
#deprecated("Use `Eq::equal` instead", skip_current_package=true)
#doc(hidden)
pub extend GlobError with Eq::{equal, not_equal}

///|
#deprecated("Use `@debug.Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LocatedDir with @debug.Debug::{to_repr}

///|
#deprecated("Use `@debug.Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend AtuinTsError with @debug.Debug::{to_repr}

///|
#deprecated("Use `Eq::equal` instead", skip_current_package=true)
#doc(hidden)
pub extend AtuinTsError with Eq::{equal, not_equal}
