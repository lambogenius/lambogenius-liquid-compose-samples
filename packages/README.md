# packages

Save the Compose using Liquid package here:

1. Sign in at <https://lambogenius.com/app/downloads/liquid-compose>.
2. Download `Lambogenius.LiquidCompose.LogicApps.0.1.0.nupkg`. Its SHA-256 is shown next to the link.
3. Save it in this folder.

The `nuget.config` at the repository root makes this folder a package source, so every sample finds the package
here. Git ignores `.nupkg` files in this folder.

Check the file before you use it (PowerShell):

```powershell
(Get-FileHash packages/Lambogenius.LiquidCompose.LogicApps.0.1.0.nupkg -Algorithm SHA256).Hash.ToLower()
```
