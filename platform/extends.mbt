///|
/// Same as core/extends.mbt: suppress the implicit method lift for Debug/Eq derives on public types
/// (moonc v0.10.14 errors under implicit_impl_as_method), keeping the public surface minimal
#deprecated("Use `@debug.Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend FzfError with @debug.Debug::{to_repr}

///|
#deprecated("Use `Eq::equal` instead", skip_current_package=true)
#doc(hidden)
pub extend FzfError with Eq::{equal, not_equal}

///|
#deprecated("Use `@debug.Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend ImportRecord with @debug.Debug::{to_repr}

///|
#deprecated("Use `@debug.Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend StoreError with @debug.Debug::{to_repr}

///|
#deprecated("Use `@debug.Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend Store with @debug.Debug::{to_repr}

///|
#deprecated("Use `@debug.Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend EditorError with @debug.Debug::{to_repr}
