///|
/// How the hook fires (matching upstream InitHook)
pub(all) enum Hook {
  HookNone
  HookPrompt
  HookPwd
} derive(Debug, Eq)
