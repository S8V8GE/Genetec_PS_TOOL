<#
.DESCRIPTION
    Description: This script is used to copy, send and restore the relevant database(s) for any relevant courses.

    @Author: James Savage

    Last Updated : 21-08-2023
#>

Param(
    [Array]$SERVERS,
    [String]$VM_PASSWORD,
    [String]$VMTYPE,
    [String]$COURSE
)

# As the servers are passed through and seen as a string the below will split the string based on the spaces to once again make it an array
$SERVERS = $SERVERS.Split(" ").Trim()

# Same variable as in TOOL.ps1, no point passing it through as it wont change.
$allowedVMTypes = @('general', 'exam', 'trouble')

<#
# OPTIONAL: Use the below to check and test the params recieved from TOOL.ps1 are OK
foreach ($server in $SERVERS) {
    Write-Output "SERVER: $server" | Out-File -FilePath "C:\TOOL\TOOL_Logs\DATABASEConfig_Params.txt" -Append
}
Write-Output "VM_PASSWORD: $VM_PASSWORD" | Out-File -FilePath "C:\TOOL\TOOL_Logs\DATABASEConfig_Params.txt" -Append
Write-Output "COURSE: $COURSE" | Out-File -FilePath "C:\TOOL\TOOL_Logs\DATABASEConfig_Params.txt" -Append
#>

# We add the $server to the trusted host in order to connect to it
Set-Item WSMan:\localhost\Client\TrustedHosts * -Force -ErrorAction SilentlyContinue
Restart-Service WinRM

# START Transcript for DATABASE_Configuration.ps1
Add-Content -Path "C:\TOOL\TOOL_Logs\DATABASE_Script_Log.txt" -Value "# Servers:$SERVERS #`n# VM PW:$VM_PASSWORD #`n# Course:$COURSE #"
Start-Transcript -Path "C:\TOOL\TOOL_Logs\DATABASE_Script_Log.txt" -IncludeInvocationHeader -Append -Force | Out-Null
$DateStart = Get-Date


# Function inside a variable for the background jobs (PS processes)
$function_MC_DB = {
################################################################
# FUNCTION: Restore the Mission Control Database
################################################################
function restoreDatabase_ATC001_GeneralUse {
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

    # Specifying the path to the "Genetec Security Center" install in program Files (x86)
    $BasePath = "C:\TOOL\TOOL_DBs\ACT001_GeneralUse"

    # Find the latest version of "Genetec Security Center" in the Start Menu (this selects the most recent version)
    $LatestVersion = Get-ChildItem -Path $BasePath | Sort-Object Name -Descending | Select-Object -First 1

    # Combine the base path and the latest version to get the full target path for the shortcuts 
    $ACT001_GeneralUseDB_TargetPath = $BasePath + "\" + $LatestVersion.Name

    # Copy the backup file in the download folder and send to the other VMs
    Copy-Item -Path $ACT001_GeneralUseDB_TargetPath -Destination "C:\" -ToSession $NewPSSession -ErrorAction SilentlyContinue -Force

    # Script block to send commands to the remote machine(s)
    $Remote = Invoke-Command -Session $NewPSSession -ScriptBlock {
        param ($Server)

            # Want to check that the file is copied OK. --------
            $dbFile = Get-ChildItem -Path C:\*.bak
            if ($dbFile) {
                # If file copied OK continue
                Write-Host $Server`: "Database Copied OK"
            } else {
                # If file not copied OK, exit the script execution
                Write-Host "$Server`: Database Not Copied, exiting script execution"
                return
            }
            # ----------
 
            # Set the SC admin password to !Training1 -------------
            # Create a new object used to establish a connection to MS SQL DB's, define connection string and open connection
            $sqlConnection = New-Object System.Data.SqlClient.SqlConnection
            $sqlConnection.ConnectionString = "Server = localhost\SQLExpress; Integrated Security = true"
            $sqlConnection.Open()

            # Object used to execute SQL commands on the connected database.
            $sqlCommand = $sqlConnection.CreateCommand()

            # Note:
            # Hash for password 'blank/default'  == 'd41d8cd98f00b204e9800998ecf8427e'
            # Hash for password '!Training1'     == '1;zcvVBVeJr6SyT69i;6GPFoPQ5lD6LfTajBN42GLWmSRWl4LQdJiiK95ELe3M='
            # Hash for password 'Letmein123!'    == '1;1juT61Ud8QvBj3UE;JvjYMpKFap+LRWlvAIybfx+JvgrCe2gZerQZqaOPSPE='

            # Set the password to !Training1 
            $sqlCommand.CommandText = "USE Directory; UPDATE [user] set Password = '1;zcvVBVeJr6SyT69i;6GPFoPQ5lD6LfTajBN42GLWmSRWl4LQdJiiK95ELe3M=' where name = 'Admin';"

            # Now we have the message, we need a way to send it... 
            $sqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter $sqlCommand
            $dataSet = New-Object System.Data.DataSet
            $sqlDataAdapter.fill($dataSet) | Out-Null

            Write-Host "$Server`: SC admin password set to !Training1"
            # -------------
    
            # Restore the backup copied to the VM --------
            Import-Module SecurityCenter
            # Used to enter an SC session (user name, plus config tool password and server admin password);
            $SCsession = New-SCSession -ComputerName $Server -User "Admin" -DirectoryPassword "!Training1" -GenetecServerPassword "!Training1" | Enter-SCSession | Out-Null

            Restore-SCDirectoryDatabase -BackupFileName $dbFile

            Write-Host "$Server`: $dbFile restored OK"

            Exit-SCSession -Session $SCsession
            # ---------------

            Write-Host "$Server`: Starting sleep for 60 seconds to allow the Directory to restart."
            Start-Sleep -Seconds 60
            Write-Host "$Server`: Sleep finished, the Directory has restarted."

            # Used to enter another SC session (as the Directory will have restarted);
            Import-Module SecurityCenter
            $SCsession2 = New-SCSession -ComputerName $Server -User "Admin" -DirectoryPassword "!Training1" -GenetecServerPassword "!Training1" | Enter-SCSession | Out-Null

            # Deleting 'VideoUnits' and 'GhostCamera' Entities -----
             # Video files from the 'D Drive' need to be removed...
            Remove-Item -Path D:\VideoArchives\Archiver\* -Force -Recurse -ErrorAction Ignore
        
            # Create a new object used to establish a connection to MS SQL DB's, defining a connection string and opening a connection
            $sqlConnection = New-Object System.Data.SqlClient.SqlConnection
            $sqlConnection.ConnectionString = "Server = localhost\SQLExpress; Integrated Security = true"
            $sqlConnection.Open()

            # Object used to execute SQL commands on the connected database.
            $sqlCommand = $sqlConnection.CreateCommand()

            # Looping through Video File DB and deleting all references of the cameras
            for ($i=0; $i -lt 31; $i++) {
    
                # SQL command to clear out "dbo.VideoFile 1-31"
                $sqlCommand.CommandText = "USE Archiver; DELETE FROM [dbo].[VideoFile$i];"
    
                # Now we have the message, we need a way to send it... 
                $sqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter $sqlCommand
                $dataSet = New-Object System.Data.DataSet
                $sqlDataAdapter.fill($dataSet) | Out-Null
            }
            Start-Sleep -Seconds 10

            # After a 10 second wait (enough time for the 'GhostCamera' to appear), we nuke it/them (we dont get rid of CAM1 and CAM2 which I use in my SC backup file that is restored                    
            Get-SCEntities -Type Cameras | Where-Object { $_.Name -notlike 'CAM1*' -and $_.Name -notlike 'CAM2*' } | Remove-SCVideoUnit -ErrorAction SilentlyContinue | Out-Null
        
            Write-Host "$Server`: All GhostCameras deleted."
            # ----------

            # Alter video units ip's----------
            Start-Sleep -Seconds 2
            $VideoUnits = Get-SCEntities -t VideoUnits -f All

            # Use regular expression to extract the numeric part
            $numericPart = $Server -replace '^\D*(\d+).*', '$1'

            # Convert the extracted value to an integer
            $serverIP = [int]$numericPart

            foreach ($videoUnit in $VideoUnits) {
                # Video Unit IP needs to be set to the machine IP address (cant use 127.0.0.1)
                $videoUnit.IPAddress = "192.168.100.$serverIP" 
                Set-SCVideoUnit $videoUnit
                $videoUnitName = $videoUnit.Name
                $videoUnitIPAddress = $videoUnit.IPAddress
                Write-Host "$Server`: $videoUnitName IP set to $videoUnitIPAddress"
            }
            # ---------------

            # Alter Rabbit MQ server hostname --------
            $newHostName = $Server

            $incidentManagerRole = Get-SCRoles -Type IncidentManager | Get-SCRole
            $incidentManagerRole.SpecificXml = $incidentManagerRole.SpecificXml -replace '(<Hostname>)[^<]*(</Hostname>)', "`$1$newHostname`$2"

            Set-SCRole $incidentManagerRole
            Write-Host "$Server`: Incident Manager RabbitMQ server updated"
            # ---------------

            #TESTING
            Start-Sleep -Seconds 5
            $VideoUnits = Get-SCEntities -t VideoUnits -f All

            foreach ($videoUnit in $VideoUnits) {
                # Video Unit IP needs to be set to 'specific settings' it should then alter its Public IP and go back to DHCP, without this the camera will stay offline... very annoying!!
                $videoUnit.Dhcp = $false 
                Set-SCVideoUnit $videoUnit
                $videoUnitName = $videoUnit.Name
                $videoUnitDhcp = $videoUnit.Dhcp
                Write-Host "$Server`: $videoUnitName DHCP set to $videoUnitDhcp"
            }

            Exit-SCSession -Session $SCsession2

    } -ArgumentList $Server

    Write-Host "$Server`: restoreDatabase_ATC001_GeneralUse function executed"
    Remove-PSSession -Session $NewPSSession  
}
}


# Function inside a variable for the background jobs (PS processes)
$function_STC2_GenUse_DB = {
################################################################
# FUNCTION: Restore the SC-STC-002 General Use Database
################################################################
function restoreDatabase_STC002_GeneralUse {
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

    # Specifying the path to the "Genetec Security Center" install in program Files (x86)
    $BasePath = "C:\TOOL\TOOL_DBs\STC002_GeneralUse"

    # Find the latest version of "Genetec Security Center" in the Start Menu (this selects the most recent version)
    $LatestVersion = Get-ChildItem -Path $BasePath | Sort-Object Name -Descending | Select-Object -First 1

    # Combine the base path and the latest version to get the full target path for the shortcuts 
    $STC002_GeneralUseDB_TargetPath = $BasePath + "\" + $LatestVersion.Name

    # Copy the backup file in the download folder and send to the other VMs
    Copy-Item -Path $STC002_GeneralUseDB_TargetPath -Destination "C:\" -ToSession $NewPSSession -ErrorAction SilentlyContinue -Force

    # Script block to send commands to the remote machine(s)
    $Remote = Invoke-Command -Session $NewPSSession -ScriptBlock {
        param ($Server)

            # Want to check that the file is copied OK. ----------------------
            $dbFile = Get-ChildItem -Path C:\*.bak
            if ($dbFile) {
                # If file copied OK continue
                Write-Host $Server`: "Database Copied OK"
            } else {
                # If file not copied OK, exit the script execution
                Write-Host "$Server`: Database Not Copied, exiting script execution"
                return
            }
            # --------------------------
 
            # Set the SC admin password to !Training1 ----------------------------
            # Create a new object used to establish a connection to MS SQL DB's, define connection string and open connection
            $sqlConnection = New-Object System.Data.SqlClient.SqlConnection
            $sqlConnection.ConnectionString = "Server = localhost\SQLExpress; Integrated Security = true"
            $sqlConnection.Open()

            # Object used to execute SQL commands on the connected database.
            $sqlCommand = $sqlConnection.CreateCommand()

            # Note:
            # Hash for password 'blank/default'  == 'd41d8cd98f00b204e9800998ecf8427e'
            # Hash for password '!Training1'     == '1;zcvVBVeJr6SyT69i;6GPFoPQ5lD6LfTajBN42GLWmSRWl4LQdJiiK95ELe3M='
            # Hash for password 'Letmein123!'    == '1;1juT61Ud8QvBj3UE;JvjYMpKFap+LRWlvAIybfx+JvgrCe2gZerQZqaOPSPE='

            # Set the password to !Training1 
            $sqlCommand.CommandText = "USE Directory; UPDATE [user] set Password = '1;zcvVBVeJr6SyT69i;6GPFoPQ5lD6LfTajBN42GLWmSRWl4LQdJiiK95ELe3M=' where name = 'Admin';"

            # Now we have the message, we need a way to send it... 
            $sqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter $sqlCommand
            $dataSet = New-Object System.Data.DataSet
            $sqlDataAdapter.fill($dataSet) | Out-Null

            Write-Host "$Server`: SC admin password set to !Training1"
            # ----------------------------------
    
            # Restore the backup copied to the VM -----------------------
            Import-Module SecurityCenter

            # Used to enter an SC session (user name, plus config tool password and server admin password);
            $SCsession = New-SCSession -ComputerName $Server -User "Admin" -DirectoryPassword "!Training1" -GenetecServerPassword "!Training1" | Enter-SCSession | Out-Null

            Restore-SCDirectoryDatabase -BackupFileName $dbFile

            Write-Host "$Server`: $dbFile restored OK"

            Exit-SCSession -Session $SCsession
            # -------------------------------

    } -ArgumentList $Server

    Write-Host "$Server`: restoreDatabase_STC2_GeneralUse function executed"
    Remove-PSSession -Session $NewPSSession  
}
}


# Function inside a variable for the background jobs (PS processes)
$function_STC2_Troubleshooting_DB = {
################################################################
# FUNCTION: Restore the SC-STC-002 Troubleshooting Database
################################################################
function restoreDatabase_STC002_Troubleshooting {
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

    # Specifying the path to the "Genetec Security Center" install in program Files (x86)
    $BasePath = "C:\TOOL\TOOL_DBs\STC002_Troubleshooting"

    # Find the latest version of "Genetec Security Center" in the Start Menu (this selects the most recent version)
    $LatestVersion = Get-ChildItem -Path $BasePath | Sort-Object Name -Descending | Select-Object -First 1

    # Combine the base path and the latest version to get the full target path for the shortcuts 
    $STC002_TroubleshootingDB_TargetPath = $BasePath + "\" + $LatestVersion.Name

    # Copy the backup file in the download folder and send to the other VMs
    Copy-Item -Path $STC002_TroubleshootingDB_TargetPath -Destination "C:\" -ToSession $NewPSSession -ErrorAction SilentlyContinue -Force

    # Script block to send commands to the remote machine(s)
    $Remote = Invoke-Command -Session $NewPSSession -ScriptBlock {
        param ($Server)

            # Want to check that the file is copied OK. --------------------
            $dbFile = Get-ChildItem -Path C:\*.bak
            if ($dbFile) {
                # If file copied OK continue
                Write-Host $Server`: "Database Copied OK"
            } else {
                # If file not copied OK, exit the script execution
                Write-Host "$Server`: Database Not Copied, exiting script execution"
                return
            }
            # ---------------------
 
            # Set the SC admin password to !Training1 ------------------
            # Create a new object used to establish a connection to MS SQL DB's, define connection string and open connection
            $sqlConnection = New-Object System.Data.SqlClient.SqlConnection
            $sqlConnection.ConnectionString = "Server = localhost\SQLExpress; Integrated Security = true"
            $sqlConnection.Open()

            # Object used to execute SQL commands on the connected database.
            $sqlCommand = $sqlConnection.CreateCommand()

            # Note:
            # Hash for password 'blank/default'  == 'd41d8cd98f00b204e9800998ecf8427e'
            # Hash for password '!Training1'     == '1;zcvVBVeJr6SyT69i;6GPFoPQ5lD6LfTajBN42GLWmSRWl4LQdJiiK95ELe3M='
            # Hash for password 'Letmein123!'    == '1;1juT61Ud8QvBj3UE;JvjYMpKFap+LRWlvAIybfx+JvgrCe2gZerQZqaOPSPE='

            # Set the password to !Training1 
            $sqlCommand.CommandText = "USE Directory; UPDATE [user] set Password = '1;zcvVBVeJr6SyT69i;6GPFoPQ5lD6LfTajBN42GLWmSRWl4LQdJiiK95ELe3M=' where name = 'Admin';"

            # Now we have the message, we need a way to send it... 
            $sqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter $sqlCommand
            $dataSet = New-Object System.Data.DataSet
            $sqlDataAdapter.fill($dataSet) | Out-Null

            Write-Host "$Server`: SC admin password set to !Training1"
            # -------------------------------
    
            # Restore the backup copied to the VM --------------------
            Import-Module SecurityCenter

            # Used to enter an SC session (user name, plus config tool password and server admin password);
            $SCsession = New-SCSession -ComputerName $Server -User "Admin" -DirectoryPassword "!Training1" -GenetecServerPassword "!Training1" | Enter-SCSession | Out-Null

            Restore-SCDirectoryDatabase -BackupFileName $dbFile

            Write-Host "$Server`: $dbFile restored OK"

            Exit-SCSession -Session $SCsession
            # ----------------------------------------

    } -ArgumentList $Server

    Write-Host "$Server`: restoreDatabase_STC2_Troubleshooting function executed"
    Remove-PSSession -Session $NewPSSession  
}
}


################################################################
# Script Execution
################################################################
if($COURSE -EQ "mc")
{
    foreach($Server in $SERVERS){
        Start-Job -Name $Server -InitializationScript $function_MC_DB -ScriptBlock {restoreDatabase_ATC001_GeneralUse -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
    }
}

elseif($COURSE -EQ "stc2" -AND $VMTYPE -EQ "general")
{
    foreach($Server in $SERVERS){
        Start-Job -Name $Server -InitializationScript $function_STC2_GenUse_DB -ScriptBlock {restoreDatabase_STC002_GeneralUse -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
    }
}

elseif($COURSE -EQ "stc2" -AND $VMTYPE -EQ "trouble")
{
    foreach($Server in $SERVERS){
        Start-Job -Name $Server -InitializationScript $function_STC2_Troubleshooting_DB -ScriptBlock {restoreDatabase_STC002_Troubleshooting -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
    }
}

else 
{
    Write-Host "Database_Configuration.ps1: Execution of script skipped, Database restore is only configured for MC-ACT-001 and STC-002 (General Use and Troubleshooting) courses."
}


# Waiting for each job to finish before moving on
foreach($Server in $SERVERS){
    Receive-Job -Name $Server -Wait -AutoRemoveJob -ErrorAction SilentlyContinue
}


# END Transcript for DATABASE_Configuration.ps1 and exit the script
$DateEnd = Get-Date
($DateEnd - $DateStart).TotalSeconds
Stop-Transcript | Out-Null