///|
/// hook 触发方式（对齐上游 InitHook）
pub(all) enum Hook {
  HookNone
  HookPrompt
  HookPwd
} derive(Debug, Eq)
