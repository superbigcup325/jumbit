///|
/// pub 类型上的 `derive(Debug, Eq)` 会把 `to_repr`/`equal`/`not_equal` 隐式提升为
/// 普通方法（moonc v0.10.14 起 `implicit_impl_as_method` 报错）。本仓无这些方法的
/// 调用点，故显式声明为 deprecated 抑制提升：公开面保持最小，需要时走 trait 形态
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
