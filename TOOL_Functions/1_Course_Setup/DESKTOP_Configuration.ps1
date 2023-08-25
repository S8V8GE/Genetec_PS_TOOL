<#
.DESCRIPTION
    Description: This script is used to clear the desktop of each VM leaving just the Recycle Bin and then add a shortcut to 'Server Admin', 'Config Tool', and 'Security Desk'.

    @Author: James Savage

    Last Updated : 21-08-2023
#>

Param(
    [Array]$SERVERS,
    [String]$VM_PASSWORD
)

# As the servers are passed through and seen as a string the below will split the string based on the spaces to once again make it an array
$SERVERS = $SERVERS.Split(" ").Trim()

<#
# OPTIONAL: Use the below to check and test the params recieved from TOOL.ps1 are OK
foreach ($server in $SERVERS) {
    Write-Output "SERVER: $server" | Out-File -FilePath "C:\TOOL\TOOL_Logs\DesktopConfig_Params.txt" -Append
}
Write-Output "VM_PASSWORD: $VM_PASSWORD" | Out-File -FilePath "C:\TOOL\TOOL_Logs\DesktopConfig_Params.txt" -Append

#>

# We add the $server to the trusted host in order to connect to it
Set-Item WSMan:\localhost\Client\TrustedHosts * -Force -ErrorAction SilentlyContinue
Restart-Service WinRM

# START Transcript for DESKTOP_Configuration.ps1
Add-Content -Path "C:\TOOL\TOOL_Logs\Desktop_Script_Log.txt" -Value "# Servers:$SERVERS #`n# VM PW:$VM_PASSWORD #"
Start-Transcript -Path "C:\TOOL\TOOL_Logs\Desktop_Script_Log.txt" -IncludeInvocationHeader -Append -Force | Out-Null
$DateStart = Get-Date


$functions = {

################################################################
# FUNCTION: Clear all .lnk from each Desktop
################################################################
function clear_Desktop {
    param ($Server, $VMPassword)

    # We Create a New PSSession
    $User_Name = "Training"
    $Pass = ConvertTo-SecureString -AsPlainText $VMPassword -Force
    $Cred = New-Object System.Management.Automation.PSCredential($User_Name, $pass)

    $NewPSSession = New-PSSession -ComputerName $Server -Credential $Cred -ErrorVariable RemoteSessionError -ErrorAction SilentlyContinue
    
    if($RemoteSessionError){
        Write-Host "$Server`: Unable to connect to the VM with the password: $VMPassword"
        return
    }

    # Script block to send commands to the remote machine(s)
    $Remote = Invoke-Command -Session $NewPSSession -ScriptBlock {
        param ($Server)

            # Paths to where desktop shortcuts are located (Chrome and Edge are located in public)
            $DesktopPaths = @("C:\Users\Training\Desktop\", "C:\Users\Public\Desktop")

            $WScript = New-Object -ComObject WScript.Shell

            # Looking for any and all .lnk files on the desktop to remove
            foreach ($DesktopPath in $DesktopPaths) {
                $ShortcutsToDelete = Get-ChildItem -Path $DesktopPath -Filter "*.lnk" -Recurse

                foreach ($shortcut in $ShortcutsToDelete) {
                    $shellLink = $WScript.CreateShortcut($shortcut.FullName)
                    $targetPath = $shellLink.TargetPath

                    # Check if the shortcut points to a file (Leaf) and not a directory (Container) and remove it
                    if (Test-Path $targetPath -Type Leaf) {
                        Remove-Item -Path $shortcut.FullName -Force
                    }
                }
        }

        Write-Host "$Server`: Desktop Shortcuts Removed"

    } -ArgumentList $Server

    Write-Host "$Server`: clear_Desktop function executed"
    Remove-PSSession -Session $NewPSSession  
}


################################################################
# FUNCTION: Add SC Shortcuts to the Desktop
################################################################
function addShortcuts_Desktop {
    param ($Server, $VMPassword)

    # We Create a New PSSession
    $User_Name = "Training"
    $Pass = ConvertTo-SecureString -AsPlainText $VMPassword -Force
    $Cred = New-Object System.Management.Automation.PSCredential($User_Name, $pass)

    $NewPSSession = New-PSSession -ComputerName $Server -Credential $Cred -ErrorVariable RemoteSessionError -ErrorAction SilentlyContinue
    
    if($RemoteSessionError){
        Write-Host "$Server`: Unable to connect to the VM with the password: $VMPassword"
        return
    }

    # Script block to send commands to the remote machine(s)
    $Remote = Invoke-Command -Session $NewPSSession -ScriptBlock {
        param ($Server)

            # Specifying the path and name of the new shortcuts
            $SA_ShortcutPath = "C:\Users\Training\Desktop\Server Admin.url"
            $CT_ShortcutPath = "C:\Users\Training\Desktop\Config Tool.lnk"
            $SD_ShortcutPath = "C:\Users\Training\Desktop\Security Desk.lnk"


            # Specifying the path to the "Genetec Security Center" install in program Files (x86)
            $BasePath = "C:\Program Files (x86)"

            # Specifying the name of the folder for "Genetec Security Center" (with wildcard to match any version as may be multiple)
            $FolderName = "Genetec Security Center*"

            # Find the latest version of "Genetec Security Center" in the Start Menu (this selects the most recent version)
            $LatestVersion = Get-ChildItem -Path $BasePath -Filter $FolderName -Directory | Sort-Object Name -Descending | Select-Object -First 1

            # Combine the base path and the latest version to get the full target path for the shortcuts 
            $SA_TargetPath = $BasePath + "\" + $LatestVersion.Name +"\Genetec Server Admin.url"
            $CT_TargetPath = $BasePath + "\" + $LatestVersion.Name +"\ConfigTool.exe"
            $SD_TargetPath = $BasePath + "\" + $LatestVersion.Name +"\SecurityDesk.exe"


            # Create a Shell object to work with the Windows Shell
            $shell = New-Object -ComObject WScript.Shell

            # Create the new shortcut
            $SA_shortcut = $shell.CreateShortcut($SA_ShortcutPath)
            $CT_shortcut = $shell.CreateShortcut($CT_ShortcutPath)
            $SD_shortcut = $shell.CreateShortcut($SD_ShortcutPath)

            # Set the properties of the shortcut
            $SA_shortcut.TargetPath = $SA_TargetPath
            $CT_shortcut.TargetPath = $CT_TargetPath
            $SD_shortcut.TargetPath = $SD_TargetPath

            # Save the shortcut
            $SA_shortcut.Save()
            $CT_shortcut.Save()
            $SD_shortcut.Save()

            # Clean up COM objects
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($SA_shortcut) | Out-Null
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($CT_shortcut) | Out-Null
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($SD_shortcut) | Out-Null
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell) | Out-Null

            Write-Host "$Server`: Desktop Shortcuts Added"

    } -ArgumentList $Server

    Write-Host "$Server`: addShortcuts_Desktop function executed"
    Remove-PSSession -Session $NewPSSession  
}
}



################################################################
# Script Execution
################################################################


foreach($Server in $SERVERS){
    Start-Job -Name $Server -InitializationScript $functions -ScriptBlock {clear_Desktop -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
    Start-Job -Name $Server -InitializationScript $functions -ScriptBlock {addShortcuts_Desktop -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
}


# Waiting for each job to finish before moving on
foreach($Server in $SERVERS){
    Receive-Job -Name $Server -Wait -AutoRemoveJob -ErrorAction SilentlyContinue
}


# END Transcript for DESKTOP_Configuration.ps1 and exit the script
$DateEnd = Get-Date
($DateEnd - $DateStart).TotalSeconds
Stop-Transcript | Out-Null