
function Gui-OpenExplorer () {
    param (
        [Parameter(Mandatory = $TRUE)]
        [string] $Path = $(throw "Path param is null!")
    )
    if (Directory-Exists-And-Is-Directory -Path $Path) {
        Log-Debug "explorer $Path".ToLower()
        explorer $Path
    }
}
