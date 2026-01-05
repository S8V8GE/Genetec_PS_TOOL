<#
.DESCRIPTION
    Description: This script is used to configure the Windows Firewall settings based on the course that is to be run.

    @Author: James Savage

    Last Updated : 05-01-2026
#>

Param(
    [Array]$SERVERS,
    [String]$VM_PASSWORD,
    [String]$COURSE,
    [String]$VMTYPE,
    [String]$COURSEDAY
)

# As the servers are passed through and seen as a string the below will split the string based on the spaces to once again make it an array
$SERVERS = $SERVERS.Split(" ").Trim()

# Same variable as in TOOL.ps1, no point passing it through as it wont change.
$allowedVMTypes = @('general', 'exam', 'trouble')

<#
# OPTIONAL: Use the below to check and test the params recieved from TOOL.ps1 are OK
foreach ($server in $SERVERS) {
    Write-Output "SERVER: $server" | Out-File -FilePath "C:\TOOL\TOOL_Logs\FirewallConfig_Params.txt" -Append
}
Write-Output "VM_PASSWORD: $VM_PASSWORD" | Out-File -FilePath "C:\TOOL\TOOL_Logs\FirewallConfig_Params.txt" -Append
Write-Output "COURSE: $COURSE" | Out-File -FilePath "C:\TOOL\TOOL_Logs\FirewallConfig_Params.txt" -Append
Write-Output "COURSEDAY: $COURSEDAY" | Out-File -FilePath "C:\TOOL\TOOL_Logs\FirewallConfig_Params.txt" -Append
Write-Output "VMTYPE: $VMTYPE" | Out-File -FilePath "C:\TOOL\TOOL_Logs\FirewallConfig_Params.txt" -Append
#>

# We add the $server to the trusted host in order to connect to it
Set-Item WSMan:\localhost\Client\TrustedHosts * -Force -ErrorAction SilentlyContinue
Restart-Service WinRM

# START Transcript for FIREWALL_Configuration.ps1
Add-Content -Path "C:\TOOL\TOOL_Logs\Firewall_Script_Log.txt" -Value "# Servers:$SERVERS #`n# VM PW:$VM_PASSWORD #`n# Course:$COURSE #`n# Day:$COURSEDAY #`n# VM Type:$VMTYPE #"
Start-Transcript -Path "C:\TOOL\TOOL_Logs\Firewall_Script_Log.txt" -IncludeInvocationHeader -Append -Force | Out-Null
$DateStart = Get-Date

$functions = {
#--------------------------------------STC-002--------------------------------------#

################################################################
# FUNCTION: Alter Firewall for all STC-002 General Use Vm's
################################################################
function STC002_GenUse_Firewall {
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

            # First, turn on Firewall and allow Netlogon Service (NP-In)
            Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
            Enable-NetFirewallRule -DisplayName "Netlogon Service (NP-In)" -ErrorAction SilentlyContinue
            Enable-NetFirewallRule -DisplayName "@netlogon.dll,-1003" -ErrorAction SilentlyContinue
            Write-Host "$Server`: Firewall turned on and Netlogon Service (NP-In) enabled"

            # Second, disable the VideoUnitControl32 and Redirector Inbound rules
            $GenetecVideoUnitControl32 = Get-NetFirewallRule | Where-Object {$_.DisplayName -LIKE "*GenetecVideoUnitControl32*"}
            $GenetecRedirector =         Get-NetFirewallRule | Where-Object {$_.DisplayName -LIKE "*GenetecRedirector*"}
    
            Disable-NetFirewallRule -DisplayName $GenetecVideoUnitControl32.DisplayName
            Disable-NetFirewallRule -DisplayName $GenetecRedirector.DisplayName
            Write-Host "$Server`: GenetecVideoUnitControl32 and GenetecRedirector Firewall rules disabled"

    } -ArgumentList $Server

    Write-Host "$Server`: STC002_GenUse_Firewall function executed"
    Remove-PSSession -Session $NewPSSession  
}


################################################################
# FUNCTION: Alter Firewall for all STC-002 Troubleshooting Vm's
################################################################
function STC002_TroubleShooting_Firewall {
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
                
            # First, turn on Firewall and allow Netlogon Service (NP-In)
            Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
            Enable-NetFirewallRule -DisplayName "Netlogon Service (NP-In)" -ErrorAction SilentlyContinue
            Enable-NetFirewallRule -DisplayName "@netlogon.dll,-1003" -ErrorAction SilentlyContinue
            Write-Host "$Server`: Firewall turned on and Netlogon Service (NP-In) enabled"

            # Second, delete all inbound rules related to port 5500
            $GenetecServer =   Get-NetFirewallRule | Where-Object {$_.DisplayName -LIKE "*GenetecServer"}
            $Port5500_TCP =    Get-NetFirewallRule | Where-Object {$_.DisplayName -LIKE "*5500 - TCP*"}
            $Port5500_UDP =    Get-NetFirewallRule | Where-Object {$_.DisplayName -LIKE "*5500 - UDP*"}
    
            Remove-NetFirewallRule -DisplayName $GenetecServer.DisplayName
            Remove-NetFirewallRule -DisplayName $Port5500_TCP.DisplayName
            Remove-NetFirewallRule -DisplayName $Port5500_UDP.DisplayName
            Write-Host "$Server`: GenetecServer, 5500-TCP, and 5500-UDP Firewall rules deleted"

    } -ArgumentList $Server

    Write-Host "$Server`: STC002_TroubleShooting_Firewall function executed (Other)"
    Remove-PSSession -Session $NewPSSession  
}


#--------------------------------------OTC-002--------------------------------------#

################################################################
# FUNCTION: Alter Firewall for all OTC-002 Vm's (Day 1)
################################################################
function OTC002_AllVMs_Day1_Firewall {
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
                
            # All VM's Day 1 = Just turn on Firewall and allow Netlogon (100 and 200)
            Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
            Enable-NetFirewallRule -DisplayName "Netlogon Service (NP-In)" -ErrorAction SilentlyContinue
            Enable-NetFirewallRule -DisplayName "@netlogon.dll,-1003" -ErrorAction SilentlyContinue
            Write-Host "$Server`: Firewall turned on and Netlogon Service (NP-In) enabled"

    } -ArgumentList $Server

    Write-Host "$Server`: OTC002_AllVMs_Day1_Firewall function executed (Other)"
    Remove-PSSession -Session $NewPSSession  
}


################################################################
# FUNCTION: Alter Firewall for OTC-002 Gen Use Vm's (VM1 Day 3)
################################################################
function OTC002_GenUse_Day3_VM1_Firewall {
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

    # The below is to handle the machine based on if it is an 'S100' or an 'S200'
    $vmNumber = $server -replace '.*-S(\d+)', '$1'
    $vmNumber = [int]$vmNumber

    # If machine is an 'S100' delete the GenetecRedirector Firewall rule
    if ($vmNumber -ge 100 -and $vmNumber -le 199) {
        # Script block to send commands to the remote machine(s)
        $Remote = Invoke-Command -Session $NewPSSession -ScriptBlock {
            param ($Server)
  
                # VM S100 range = General Use - VM1 - Day 3 = DELETE GenetecRedirector (inbound)
                $GenetecRedirector = Get-NetFirewallRule | Where-Object {$_.DisplayName -LIKE "*GenetecRedirector*"}
    
                Remove-NetFirewallRule -DisplayName $GenetecRedirector.DisplayName
                Write-Host "$Server`: GenetecRedirector Firewall rule deleted"
    
        } -ArgumentList $Server

        Write-Host "$Server`: OTC002_Exam_Day3_Firewall function executed (S100 Branch)"
        Remove-PSSession -Session $NewPSSession
   
   } -ArgumentList $Server

    Write-Host "$Server`: OTC002_GenUse_Day3_VM1_Firewall function executed (Other)"
    Remove-PSSession -Session $NewPSSession  
}


################################################################
# FUNCTION: Alter Firewall for OTC-002 Exam Vm's (VM1&2 Day 3)
################################################################
function OTC002_Exam_Day3_Firewall {
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

    # The below is to handle the machine based on if it is an 'S100' or an 'S200'
    $vmNumber = $server -replace '.*-S(\d+)', '$1'
    $vmNumber = [int]$vmNumber

    # If machine is an 'S100' delete the GenetecRedirector Firewall rule
    if ($vmNumber -ge 100 -and $vmNumber -le 199) {
        # Script block to send commands to the remote machine(s)
        $Remote = Invoke-Command -Session $NewPSSession -ScriptBlock {
            param ($Server)
  
                # VM S100 range = Delete GenetecRedirector Firewall rule
                $GenetecRedirector = Get-NetFirewallRule | Where-Object {$_.DisplayName -LIKE "*GenetecRedirector*"}
    
                Remove-NetFirewallRule -DisplayName $GenetecRedirector.DisplayName
                Write-Host "$Server`: GenetecRedirector Firewall rule deleted"

                # Second, delete all inbound rules related to port 5500
                $GenetecServer =   Get-NetFirewallRule | Where-Object {$_.DisplayName -LIKE "*GenetecServer"}
                $Port5500_TCP =    Get-NetFirewallRule | Where-Object {$_.DisplayName -LIKE "*5500 - TCP*"}
                $Port5500_UDP =    Get-NetFirewallRule | Where-Object {$_.DisplayName -LIKE "*5500 - UDP*"}
    
                Remove-NetFirewallRule -DisplayName $GenetecServer.DisplayName
                Remove-NetFirewallRule -DisplayName $Port5500_TCP.DisplayName
                Remove-NetFirewallRule -DisplayName $Port5500_UDP.DisplayName
                Write-Host "$Server`: GenetecServer, 5500-TCP, and 5500-UDP Firewall rules deleted"

                New-NetFirewallRule -DisplayName "TCP 5500" -Direction Outbound -LocalPort 5500 -Protocol TCP -Action Block
                Write-Host "$Server`: Outbound Firewall rule blocking TCP 5500 created"
    
        } -ArgumentList $Server

        Write-Host "$Server`: OTC002_Exam_Day3_Firewall function executed (S100 Branch)"
        Remove-PSSession -Session $NewPSSession
   }
}
}


################################################################
# Script Execution
################################################################
if($COURSE -EQ "stc2" -AND $VMTYPE -EQ "general")
{
    foreach($Server in $SERVERS){
        Start-Job -Name $Server -InitializationScript $functions -ScriptBlock {STC002_GenUse_Firewall -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
    }
}

elseif($COURSE -EQ "stc2" -AND $VMTYPE -EQ "trouble")
{
    foreach($Server in $SERVERS){
        Start-Job -Name $Server -InitializationScript $functions -ScriptBlock {STC002_TroubleShooting_Firewall -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
    }
}

elseif($COURSE -EQ "otc2" -AND $COURSEDAY -EQ "1" -AND $allowedVMTypes -CONTAINS $VMTYPE)
{
    foreach($Server in $SERVERS){
        Start-Job -Name $Server -InitializationScript $functions -ScriptBlock {OTC002_AllVMs_Day1_Firewall -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
    }
}

elseif($COURSE -EQ "otc2" -AND $COURSEDAY -EQ "3" -AND $VMTYPE -EQ "general")
{
    foreach($Server in $SERVERS){
        Start-Job -Name $Server -InitializationScript $functions -ScriptBlock {OTC002_GenUse_Day3_VM1_Firewall -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
    }
}

elseif($COURSE -EQ "otc2" -AND $COURSEDAY -EQ "3" -AND $VMTYPE -EQ "exam")
{
    foreach($Server in $SERVERS){
        Start-Job -Name $Server -InitializationScript $functions -ScriptBlock {OTC002_Exam_Day3_Firewall -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
    }
}
else 
{
    Write-Host "Firewall_Configuration.ps1: Execution of script skipped, Firewall is only configured for OTC-002 (Day 1 and Day 3) and STC-002 courses."
}


# Waiting for each job to finish before moving on
foreach($Server in $SERVERS){
    Receive-Job -Name $Server -Wait -AutoRemoveJob -ErrorAction SilentlyContinue
}


# END Transcript for Firewall_Configuration.ps1 and exit the script
$DateEnd = Get-Date
($DateEnd - $DateStart).TotalSeconds
Stop-Transcript | Out-Null
