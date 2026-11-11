///|
/// How the hook fires (matching upstream InitHook)
#derive(Debug, Eq)
pub(all) enum Hook {
  HookNone
  HookPrompt
  HookPwd
}
