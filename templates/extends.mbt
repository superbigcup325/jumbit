///|
/// 同 core/extends.mbt：抑制 pub 类型上 Debug/Eq 派生的隐式方法提升
/// （moonc v0.10.14 起 implicit_impl_as_method 报错），公开面保持最小
#deprecated("Use `@debug.Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend Hook with @debug.Debug::{to_repr}

///|
#deprecated("Use `Eq::equal` instead", skip_current_package=true)
#doc(hidden)
pub extend Hook with Eq::{equal, not_equal}
