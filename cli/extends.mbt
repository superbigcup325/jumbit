///|
/// 同 core/extends.mbt：抑制 pub 类型上 Debug/Eq 派生的隐式方法提升
/// （moonc v0.10.14 起 implicit_impl_as_method 报错），公开面保持最小
#deprecated("Use `@debug.Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend QueryOptions with @debug.Debug::{to_repr}

///|
#deprecated("Use `Eq::equal` instead", skip_current_package=true)
#doc(hidden)
pub extend QueryOptions with Eq::{equal, not_equal}

///|
#deprecated("Use `@debug.Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend AddOptions with @debug.Debug::{to_repr}

///|
#deprecated("Use `Eq::equal` instead", skip_current_package=true)
#doc(hidden)
pub extend AddOptions with Eq::{equal, not_equal}

///|
#deprecated("Use `@debug.Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend InitOptions with @debug.Debug::{to_repr}

///|
#deprecated("Use `Eq::equal` instead", skip_current_package=true)
#doc(hidden)
pub extend InitOptions with Eq::{equal, not_equal}

///|
#deprecated("Use `@debug.Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend ImportOptions with @debug.Debug::{to_repr}

///|
#deprecated("Use `Eq::equal` instead", skip_current_package=true)
#doc(hidden)
pub extend ImportOptions with Eq::{equal, not_equal}

///|
#deprecated("Use `@debug.Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend DescribeOptions with @debug.Debug::{to_repr}

///|
#deprecated("Use `Eq::equal` instead", skip_current_package=true)
#doc(hidden)
pub extend DescribeOptions with Eq::{equal, not_equal}

///|
#deprecated("Use `@debug.Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend ExportOptions with @debug.Debug::{to_repr}

///|
#deprecated("Use `Eq::equal` instead", skip_current_package=true)
#doc(hidden)
pub extend ExportOptions with Eq::{equal, not_equal}

///|
#deprecated("Use `@debug.Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend StatusOptions with @debug.Debug::{to_repr}

///|
#deprecated("Use `Eq::equal` instead", skip_current_package=true)
#doc(hidden)
pub extend StatusOptions with Eq::{equal, not_equal}

///|
#deprecated("Use `@debug.Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend Command with @debug.Debug::{to_repr}

///|
#deprecated("Use `Eq::equal` instead", skip_current_package=true)
#doc(hidden)
pub extend Command with Eq::{equal, not_equal}

///|
#deprecated("Use `@debug.Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend EditOptions with @debug.Debug::{to_repr}

///|
#deprecated("Use `Eq::equal` instead", skip_current_package=true)
#doc(hidden)
pub extend EditOptions with Eq::{equal, not_equal}
