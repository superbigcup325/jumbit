// 由一次性转译工具生成（源：上游 templates/xonsh.txt），勿手改。
// 重命名：zoxide→jumbit、__zoxide_→__jumbit_、_ZO_→_JB_、z#→j#；Windows 分支已丢弃。

///|
/// xonsh 模板渲染（自上游 templates/xonsh.txt 转译：zoxide→jumbit、_ZO_→_JB_；勿手改）
pub fn render_xonsh(
  cmd : String?,
  hook : Hook,
  echo : Bool,
  resolve_symlinks : Bool,
) -> String {
  let sb = StringBuilder()
  let section : String = "# =============================================================================\n#"
  let not_configured : String = "# -- not configured --"
  sb.write_string(
    "\n\n# pylint: disable=missing-module-docstring\n\nimport builtins  # pylint: disable=unused-import\nimport os\nimport os.path\nimport subprocess\nimport sys\nimport typing\n\nimport xonsh.dirstack  # type: ignore # pylint: disable=import-error\nimport xonsh.environ  # type: ignore # pylint: disable=import-error\n\n",
  )
  sb.write_string(section)
  sb.write_string(
    "\n# Utility functions for jumbit.\n#\n\n\ndef __jumbit_bin() -> str:\n    \"\"\"Finds and returns the location of the jumbit binary.\"\"\"\n    jumbit = typing.cast(str, xonsh.environ.locate_binary(\"jumbit\"))\n    if jumbit is None:\n        jumbit = \"jumbit\"\n    return jumbit\n\n\ndef __jumbit_env() -> dict[str, str]:\n    \"\"\"Returns the current environment.\"\"\"\n    return builtins.__xonsh__.env.detype()  # type: ignore  # pylint:disable=no-member\n\n\ndef __jumbit_pwd() -> str:\n    \"\"\"pwd based on the value of _JB_RESOLVE_SYMLINKS.\"\"\"",
  )
  if resolve_symlinks {
    sb.write_string("\n    pwd = os.getcwd()")
  } else {
    sb.write_string(
      "\n    pwd = __jumbit_env().get(\"PWD\")\n    if pwd is None:\n        raise RuntimeError(\"$PWD not found\")",
    )
  }
  sb.write_string(
    "\n    return pwd\n\n\ndef __jumbit_cd(path: str | bytes | None = None) -> None:\n    \"\"\"cd + custom logic based on the value of _JB_ECHO.\"\"\"\n    if path is None:\n        args = []\n    elif isinstance(path, bytes):\n        args = [path.decode(\"utf-8\")]\n    else:\n        args = [path]\n    _, exc, _ = xonsh.dirstack.cd(args)\n    if exc is not None:\n        raise RuntimeError(exc)",
  )
  if echo {
    sb.write_string("\n    print(__jumbit_pwd())")
  }
  sb.write_string(
    "\n\n\nclass ZoxideSilentException(Exception):\n    \"\"\"Exit without complaining.\"\"\"\n\n\ndef __jumbit_errhandler(\n    func: typing.Callable[[list[str]], None],\n) -> typing.Callable[[list[str]], int]:\n    \"\"\"Print exception and exit with error code 1.\"\"\"\n\n    def wrapper(args: list[str]) -> int:\n        try:\n            func(args)\n            return 0\n        except ZoxideSilentException:\n            return 1\n        except Exception as exc:  # pylint: disable=broad-except\n            print(f\"jumbit: {exc}\", file=sys.stderr)\n            return 1\n\n    return wrapper\n\n\n",
  )
  sb.write_string(section)
  sb.write_string("\n# Hook configuration for jumbit.\n#\n\n")
  if hook is HookNone {
    sb.write_string("\n")
    sb.write_string(not_configured)
  } else {
    sb.write_string(
      "\n# Initialize hook to add new entries to the database.\nif \"__jumbit_hook\" not in globals():\n",
    )
    if hook is HookPrompt {
      sb.write_string(
        "\n    @builtins.events.on_post_prompt  # type: ignore  # pylint:disable=no-member",
      )
    } else if hook is HookPwd {
      sb.write_string(
        "\n    @builtins.events.on_chdir  # type: ignore  # pylint:disable=no-member",
      )
    }
    sb.write_string(
      "\n    def __jumbit_hook(**_kwargs: typing.Any) -> None:\n        \"\"\"Hook to add new entries to the database.\"\"\"\n        pwd = __jumbit_pwd()\n        jumbit = __jumbit_bin()\n        subprocess.run(\n            [jumbit, \"add\", \"--\", pwd],\n            check=False,\n            env=__jumbit_env(),\n        )\n",
    )
  }
  sb.write_string("\n\n")
  sb.write_string(section)
  sb.write_string(
    "\n# When using jumbit with --no-cmd, alias these internal functions as desired.\n#\n\n\n@__jumbit_errhandler\ndef __jumbit_z(args: list[str]) -> None:\n    \"\"\"Jump to a directory using only keywords.\"\"\"\n    if args == []:\n        __jumbit_cd()\n    elif args == [\"-\"]:\n        __jumbit_cd(\"-\")\n    elif len(args) == 1 and os.path.isdir(args[0]):\n        __jumbit_cd(args[0])\n    else:\n        try:\n            jumbit = __jumbit_bin()\n            cmd = subprocess.run(\n                [jumbit, \"query\", \"--exclude\", __jumbit_pwd(), \"--\"] + args,\n                check=True,\n                env=__jumbit_env(),\n                stdout=subprocess.PIPE,\n            )\n        except subprocess.CalledProcessError as exc:\n            raise ZoxideSilentException() from exc\n\n        result = cmd.stdout[:-1]\n        __jumbit_cd(result)\n\n\n@__jumbit_errhandler\ndef __jumbit_zi(args: list[str]) -> None:\n    \"\"\"Jump to a directory using interactive search.\"\"\"\n    try:\n        jumbit = __jumbit_bin()\n        cmd = subprocess.run(\n            [jumbit, \"query\", \"-i\", \"--\"] + args,\n            check=True,\n            env=__jumbit_env(),\n            stdout=subprocess.PIPE,\n        )\n    except subprocess.CalledProcessError as exc:\n        raise ZoxideSilentException() from exc\n\n    result = cmd.stdout[:-1]\n    __jumbit_cd(result)\n\n\n",
  )
  sb.write_string(section)
  sb.write_string("\n# Commands for jumbit. Disable these using --no-cmd.\n#")
  match cmd {
    Some(cmd) => {
      sb.write_string("\n\nbuiltins.aliases[\"")
      sb.write_string(cmd)
      sb.write_string(
        "\"] = __jumbit_z  # type: ignore  # pylint:disable=no-member\nbuiltins.aliases[\"",
      )
      sb.write_string(cmd)
      sb.write_string(
        "i\"] = __jumbit_zi  # type: ignore  # pylint:disable=no-member",
      )
    }
    None => {
      sb.write_string("\n\n")
      sb.write_string(not_configured)
    }
  }
  sb.write_string("\n\n")
  sb.write_string(section)
  sb.write_string(
    "\n# To initialize jumbit, add this to your configuration (usually ~/.xonshrc):\n#\n# execx($(jumbit init xonsh), 'exec', __xonsh__.ctx, filename='jumbit')\n",
  )
  sb.to_string()
}
