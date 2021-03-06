function Redo-ModuleImport {

    [CmdletBinding()]
    [Alias("reload")]
    param()
    DynamicParam {  

        # Create a dictionary to hold any dynamic parameters
        $parameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary 

        #########################################   
        #### Dynamic Parameter 1: ModuleName ####
        #########################################
        $moduleNameParameterName = 'ModuleName'
        # Parameter Attributes
        $moduleNameParameterAttributes = New-Object System.Management.Automation.ParameterAttribute # Instantiate empty parameter attributes object for definition below
        $moduleNameParameterAttributesCollection = New-Object 'System.Collections.ObjectModel.Collection[System.Attribute]' # An array to hold any attributes assigned to this parameter
        $moduleNameParameterAttributes.Mandatory = $true # Parameter is mandatory
        $moduleNameParameterAttributes.Position = 0
        # Parameter should validate inputs on these constraints
        $moduleNameParameterValidationSet = (Get-Module -All).Name # Get a list of all loaded modules as the set of strings that can be passed in by the user
        $moduleNameParameterValidationSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute($moduleNameParameterValidationSet)
        # Add the parameter attributes object and the validation set attribute
        $moduleNameParameterAttributesCollection.Add($moduleNameParameterAttributes)
        $moduleNameParameterAttributesCollection.Add($moduleNameParameterValidationSetAttribute)
        $createModuleNameParameter = New-Object System.Management.Automation.RuntimeDefinedParameter($moduleNameParameterName, [String[]], $moduleNameParameterAttributesCollection)
        
        $parameterDictionary.Add($moduleNameParameterName, $createModuleNameParameter) # Add ModuleName to the parameter dictionary
        return $parameterDictionary

    }
    process{

        $PSBoundParameters['ModuleName'] | ForEach-Object {
            try {
                $module = Get-Module -All -Name $_
                $module | Remove-Module -Force -ErrorAction Stop
                Import-Module $module.Path -Force -ErrorAction Stop
            }
            catch {
                Write-Error -Exception $_.Exception
            }
        }

    }
    
}

function touch {
    
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $Path
    )
    process {
    
        try {
            $defaultEA = $ErrorAction
            $ErrorAction = 'Stop'
            $isNixStyle = which touch
        }
        catch {
            $isNixStyle = $false
        }
        $ErrorAction = $defaultEA

        if ($isNixStyle) {

            $Path | ForEach-Object {
                Start-Process -FilePath $isNixStyle -ArgumentList $_ -ErrorAction Continue
            }
            return
            
        }

        foreach ($item in $PSBoundParameters['Path']) {

            $checkExists = Resolve-Path $item -ErrorAction SilentlyContinue
            if ($checkExists) {
                
                try {
                    $verifyType = Get-Item -Path $checkExists.Path
                    if ($verifyType.GetType().FullName -eq 'System.IO.DirectoryInfo') {
                        [System.IO.Directory]::EnumerateFiles($verifyType.FullName) | Out-Null
                    }
                    else {
                        $touch = [System.IO.File]::Open($checkExists.Path, [System.IO.FileMode]::Open) # Update the last accessed timestamp akin to BASH
                        $touch.Close()
                    }
                }
                catch [UnauthorizedAccessException] {
                    Write-Host "Access denied." -ForegroundColor Red
                }
                catch {
                    Write-Error -Exception $_.Exception
                }

            }
            else {

                try {
                    New-Item -ItemType File -Path $item
                }
                catch {
                    Write-Error -Exception $_.Exception
                }

            }
        }

    }
    
}

function socks {
	
    [CmdletBinding(DefaultParameterSetName = 'On')]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'On')]
        [ValidateNotNullOrEmpty()]
        [String]
        $Username,

        [Parameter(Mandatory = $true, ParameterSetName = 'On')]
        [ValidateNotNullOrEmpty()]	
        [String]
        $ComputerName,

        [Parameter(ParameterSetName = 'On')]
        [ValidateNotNullOrEmpty()]	
        [String]
        $PrivateKeyFile,

        [Parameter(ParameterSetName = 'On')]
        [ValidateRange(1,65535)]
        [Int]
        $SSHPort = 22,

        [Parameter(ParameterSetName = 'On')]
        [ValidateRange(1,65535)]
        [Int]
        $TunnelPort = 1337,

        [Parameter(ParameterSetName = 'Off')]
        [Switch]
        $Off,

        [Parameter(ParameterSetName = 'Status')]
        [Switch]
        $Status
    )
    if ($env:OS -notlike '*Windows*') {
        throw "This function is designed to work only on Windows hosts at the moment."
    }
    elseif ($Off.IsPresent) {
        Set-Itemproperty -Path "HKCU:Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyServer -Value ''
	    Set-Itemproperty -Path "HKCU:Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyEnable -Value 0
        Get-CimInstance -ClassName Win32_Process | 
            Where-Object {$_.Name -eq 'ssh.exe'} | 
            Where-Object {$_.CommandLine -like '*ssh*-f -C -q -N -D*'} | 
            ForEach-Object {Stop-Process -Id $_.ProcessId -Force}
    }
    elseif ($Status.IsPresent) {
        $checkProxyUp = Get-CimInstance -ClassName Win32_Process | Where-Object {$_.Name -eq 'ssh.exe'} | Where-Object {$_.CommandLine -like '*ssh*-f -C -q -N -D*'}
        if ($checkProxyUp) { return 'Up' }
        else { return 'Down' }
    }
    else {
        $checkProxyUp = Get-CimInstance -ClassName Win32_Process | Where-Object {$_.Name -eq 'ssh.exe'} | Where-Object {$_.CommandLine -like '*ssh*-f -C -q -N -D*'}
        if ($checkProxyUp ) {
            return
        }
        else {
            Set-Itemproperty -Path "HKCU:Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyServer -Value "socks=localhost`:$TunnelPort"
            Set-Itemproperty -Path "HKCU:Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyEnable -Value 1
            if ($PrivateKeyFile) {
                Start-Process ssh -LoadUserProfile -ArgumentList "-i $PrivateKeyFile $Username@$ComputerName -p $SSHPort -f -C -q -N -D $TunnelPort" -NoNewWindow
            }
            else {
                Start-Process ssh -LoadUserProfile -ArgumentList "$Username@$ComputerName -p $SSHPort -f -C -q -N -D $TunnelPort" -NoNewWindow
            }
        }
    }

}

Write-Host "Importing module PSToolbox" -ForegroundColor Green
Import-Module PSToolbox

if ($env:OS -like '*Windows*') {

    Write-Host "Setting BitWarden CLI session key variable" -ForegroundColor Green
    Set-Item Env:\BW_SESSION -Value (Import-Clixml $env:USERPROFILE\Desktop\bitwarden-session-key.clixml | ConvertFrom-SecureString) -Force

}