// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "superbigcup325/jumbit"

version = "0.1.1"

readme = "README.md"

repository = "https://github.com/superbigcup325/jumbit"

license = "MIT"

keywords = [ "cli", "zoxide", "directory-jumper" ]

preferred_target = "native"

description = "a MoonBit rewrite of zoxide: jump to directories in a few keystrokes"

import {
  "moonbitlang/async@0.21.2",
  "moonbitlang/x@0.5.1",
}
