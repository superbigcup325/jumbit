// 由一次性转译工具生成（源：上游 templates/powershell.txt），勿手改。
// 重命名：zoxide→jumbit、__zoxide_→__jumbit_、_ZO_→_JB_、z#→j#；Windows 分支已丢弃。

///|
/// powershell 模板渲染（自上游 templates/powershell.txt 转译：zoxide→jumbit、_ZO_→_JB_；勿手改）
pub fn render_powershell(
  cmd : String?,
  hook : Hook,
  echo : Bool,
  _resolve_symlinks : Bool,
) -> String {
  let sb = StringBuilder()
  let section : String = "# =============================================================================\n#"
  let not_configured : String = "# -- not configured --"
  sb.write_string("\n\n")
  sb.write_string(section)
  sb.write_string(
    "\n# Utility functions for jumbit.\n#\n\n# Call jumbit binary, returning the output as UTF-8.\nfunction global:__jumbit_bin {\n    $encoding = [Console]::OutputEncoding\n    try {\n        [Console]::OutputEncoding = [System.Text.Utf8Encoding]::new()\n        $result = jumbit @args\n        return $result\n    } finally {\n        [Console]::OutputEncoding = $encoding\n    }\n}\n\n# pwd based on jumbit's format.\nfunction global:__jumbit_pwd {\n    $cwd = Microsoft.PowerShell.Management\\Get-Location\n    if ($cwd.Provider.Name -eq \"FileSystem\") {\n        $cwd.ProviderPath\n    }\n}\n\n# cd + custom logic based on the value of _JB_ECHO.\nfunction global:__jumbit_cd($dir, $literal) {\n    $dir = if ($literal) {\n        if ($null -eq $dir) {\n            Microsoft.PowerShell.Management\\Set-Location\n        } else {\n            Microsoft.PowerShell.Management\\Set-Location -LiteralPath $dir -Passthru -ErrorAction Stop\n        }\n    } else {\n        if ($dir -eq '-' -and ($PSVersionTable.PSVersion -lt 6.1)) {\n            Microsoft.PowerShell.Utility\\Write-Error \"cd - is not supported below PowerShell 6.1. Please upgrade your version of PowerShell.\"\n        }\n        elseif ($dir -eq '+' -and ($PSVersionTable.PSVersion -lt 6.2)) {\n            Microsoft.PowerShell.Utility\\Write-Error \"cd + is not supported below PowerShell 6.2. Please upgrade your version of PowerShell.\"\n        }\n        else {\n            Microsoft.PowerShell.Management\\Set-Location -Path $dir -Passthru -ErrorAction Stop\n        }\n    }",
  )
  if echo {
    sb.write_string(
      "\n    Microsoft.PowerShell.Utility\\Write-Output $dir.Path",
    )
  }
  sb.write_string("\n}\n\n")
  sb.write_string(section)
  sb.write_string("\n# Hook configuration for jumbit.\n#\n\n")
  if hook is HookNone {
    sb.write_string("\n")
    sb.write_string(not_configured)
  } else {
    sb.write_string("\n")
    if hook is HookPrompt {
      sb.write_string(
        "\n# Hook to add new entries to the database.\nfunction global:__jumbit_hook {\n    $result = __jumbit_pwd\n    if ($null -ne $result) {\n        jumbit add \"--\" $result\n    }\n}",
      )
    } else if hook is HookPwd {
      sb.write_string(
        "\n# Hook to add new entries to the database.\n$global:__jumbit_oldpwd = __jumbit_pwd\nfunction global:__jumbit_hook {\n    $result = __jumbit_pwd\n    if ($result -ne $global:__jumbit_oldpwd) {\n        if ($null -ne $result) {\n            jumbit add \"--\" $result\n        }\n        $global:__jumbit_oldpwd = $result\n    }\n}",
      )
    }
    sb.write_string(
      "\n\n# Initialize hook.\n$global:__jumbit_hooked = (Microsoft.PowerShell.Utility\\Get-Variable __jumbit_hooked -ErrorAction Ignore -ValueOnly)\nif ($global:__jumbit_hooked -ne 1) {\n    $global:__jumbit_hooked = 1\n    $global:__jumbit_prompt_old = $function:prompt\n\n    function global:prompt {\n        if ($null -ne $__jumbit_prompt_old) {\n            & $__jumbit_prompt_old\n        }\n        $null = __jumbit_hook\n    }\n}",
    )
  }
  sb.write_string("\n\n")
  sb.write_string(section)
  sb.write_string(
    "\n# When using jumbit with --no-cmd, alias these internal functions as desired.\n#\n\n# Jump to a directory using only keywords.\nfunction global:__jumbit_z {\n    if ($args.Length -eq 0) {\n        __jumbit_cd $null $true\n    }\n    elseif ($args.Length -eq 1 -and ($args[0] -eq '-' -or $args[0] -eq '+')) {\n        __jumbit_cd $args[0] $false\n    }\n    elseif ($args.Length -eq 1 -and (Microsoft.PowerShell.Management\\Test-Path -PathType Container -LiteralPath $args[0])) {\n        __jumbit_cd $args[0] $true\n    }\n    elseif ($args.Length -eq 1 -and (Microsoft.PowerShell.Management\\Test-Path -PathType Container -Path $args[0] )) {\n        __jumbit_cd $args[0] $false\n    }\n    else {\n        $result = __jumbit_pwd\n        if ($null -ne $result) {\n            $result = __jumbit_bin query --exclude $result \"--\" @args\n        }\n        else {\n            $result = __jumbit_bin query \"--\" @args\n        }\n        if ($LASTEXITCODE -eq 0) {\n            __jumbit_cd $result $true\n        }\n    }\n}\n\n# Jump to a directory using interactive search.\nfunction global:__jumbit_zi {\n    $result = __jumbit_bin query -i \"--\" @args\n    if ($LASTEXITCODE -eq 0) {\n        __jumbit_cd $result $true\n    }\n}\n\n",
  )
  sb.write_string(section)
  sb.write_string("\n# Commands for jumbit. Disable these using --no-cmd.\n#")
  match cmd {
    Some(cmd) => {
      sb.write_string("\n\nMicrosoft.PowerShell.Utility\\Set-Alias -Name ")
      sb.write_string(cmd)
      sb.write_string(
        " -Value __jumbit_z -Option AllScope -Scope Global -Force\nMicrosoft.PowerShell.Utility\\Set-Alias -Name ",
      )
      sb.write_string(cmd)
      sb.write_string(
        "i -Value __jumbit_zi -Option AllScope -Scope Global -Force",
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
    "\n# To initialize jumbit, add this to your configuration (find it by running\n# `echo $profile` in PowerShell):\n#\n# Invoke-Expression (& { (jumbit init powershell | Out-String) })\n",
  )
  sb.to_string()
}
