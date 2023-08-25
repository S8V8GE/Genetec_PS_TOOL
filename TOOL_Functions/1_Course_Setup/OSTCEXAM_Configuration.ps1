<#
.DESCRIPTION
    Description: This script is used to make each OTC-001 or STC-001 VM 'Exam Ready'.

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
    Write-Output "SERVER: $server" | Out-File -FilePath "C:\TOOL\TOOL_Logs\OTSCEXAMConfig_Params.txt" -Append
}
Write-Output "VM_PASSWORD: $VM_PASSWORD" | Out-File -FilePath "C:\TOOL\TOOL_Logs\OTSCEXAMConfig_Params.txt" -Append
#>

# We add the $server to the trusted host in order to connect to it
Set-Item WSMan:\localhost\Client\TrustedHosts * -Force -ErrorAction SilentlyContinue
Restart-Service WinRM

# START Transcript for DESKTOP_Configuration.ps1
Add-Content -Path "C:\TOOL\TOOL_Logs\OTSCEXAM_Script_Log.txt" -Value "# Servers:$SERVERS #`n# VM PW:$VM_PASSWORD #"
Start-Transcript -Path "C:\TOOL\TOOL_Logs\OTSCEXAM_Script_Log.txt" -IncludeInvocationHeader -Append -Force | Out-Null
$DateStart = Get-Date


$functions = {

################################################################
# FUNCTION: Get the VM's ready for the exam OTC-001 and STC-001
################################################################
function deleteMostEntities {
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

            Import-Module SecurityCenter

            # Valid SC Entities to delete
            $validEntityTypes = @(
                'Alarms', 'Areas', 'Cardholders', 'Credentials', 'Doors', 'Elevators', 
                'Units', 'Visitors', 'Zones', 'Macros', 'UserTasks', 'ThreatLevels', 
                'Badges', 'Sequences', 'TilePlugins', 'MlpiRules', 'ScheduledTasks', 'InterfaceModules', 
                'TransferGroups', 'TileLayouts', 'Contact', 'Workstation', 'Endpoint'
            )

            # SQL Connection String ---------------------------------------------------------------------------------------------------#
              # Create a new object used to establish a connection to MS SQL DB's, defining a connection string and opening a connection
            $sqlConnection = New-Object System.Data.SqlClient.SqlConnection
            $sqlConnection.ConnectionString = "Server = localhost\SQLExpress; Integrated Security = true"
            $sqlConnection.Open()

            # Object used to execute SQL commands on the connected database.
            $sqlCommand = $sqlConnection.CreateCommand()


            # Resetting Directory Admin password and entering an SC PS Session----------------------------------------------------------#
              # SQL command to set the Directory password to !Training1'. 
            $sqlCommand.CommandText = "USE Directory; UPDATE [dbo].[user] set Password = '1;zcvVBVeJr6SyT69i;6GPFoPQ5lD6LfTajBN42GLWmSRWl4LQdJiiK95ELe3M=' where name = 'Admin';"

            # Now we have the message, we need a way to send it... 
            $sqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter $sqlCommand
            $dataSet = New-Object System.Data.DataSet
            $sqlDataAdapter.fill($dataSet) | Out-Null
            Write-Host "$Server`: Directory admin password set to !Training1."

            # Used to enter an SC session (user name, plus config tool password and server admin password);
            $SCsession = New-SCSession -ComputerName $Server -User "Admin" -DirectoryPassword "!Training1" -GenetecServerPassword "!Training1" | Enter-SCSession


            # Deleting SC Entities ------------------------------------------------------------------------------------------------------#
              # Making sure to close any active alarms, they will be the first entity type to be deleted
            Invoke-SCAlarmForceAckAll -ErrorAction SilentlyContinue

            # Remove all entities within the $validEntityTypes array
            ForEach ($EntityType in $validEntityTypes) {
                Get-SCEntities -Type $EntityType | Remove-SCEntity #-ErrorAction SilentlyContinue | Out-Null
            }

            # The below are the 'fragile' entity types not included within the $validEntityTypes array
            # Run them without Where-Object and lots of entities you dont want removed, are removed (and some things break)... trust me.
            Get-SCEntities -Type 'UserGroups' | Where-Object {$_.Name -ne "Administrators"} | Where-Object {$_.Name -ne "Patroller users"} | Where-Object {$_.Name -ne "AutoVu operators"} | Remove-SCEntity -ErrorAction SilentlyContinue | Out-Null
            Get-SCEntities -Type 'Users' | Where-Object {$_.Name -ne "Admin"} | Where-Object {$_.Name -ne "AutoVu"} | Where-Object {$_.Name -ne "Service"} | Where-Object {$_.Name -ne "Patroller"} | Remove-SCEntity -ErrorAction SilentlyContinue | Out-Null
            Get-SCEntities -Type 'AccessRules' | Where-Object {$_.Name -ne "All open rule"} | Where-Object {$_.Name -ne "Lockdown rule"} | Remove-SCEntity -ErrorAction SilentlyContinue | Out-Null
            Get-SCEntities -Type 'CardholderGroups' | Where-Object {$_.Name -ne "All cardholders"} | Where-Object {$_.Name -ne "Visitors"} | Remove-SCEntity -ErrorAction SilentlyContinue | Out-Null
            Get-SCEntities -Type 'Partitions' | Where-Object {$_.Name -ne "System"} | Remove-SCEntity -ErrorAction SilentlyContinue | Out-Null
            Get-SCEntities -Type 'Schedules' | Where-Object {$_.Name -ne "Always"} | Remove-SCEntity -ErrorAction SilentlyContinue | Out-Null
            Get-SCEntities -Type 'Maps' | Where-Object {$_.Name -ne "Security Desk map"} | Remove-SCEntity -ErrorAction SilentlyContinue | Out-Null
            Get-SCEntities -Type 'HardwareUnits' | Where-Object {$_.Name -ne "XML import"} | Remove-SCEntity -ErrorAction SilentlyContinue | Out-Null
            Write-Host "$Server`: All entities deleted."

            # Deleting 'Event 2 Actions' Entities -----------------------------------------------------------------------------------------#
              # SQL command to delete 'Event 2 Actions' from the SC system'. 
            $sqlCommand.CommandText = "USE Directory; DELETE FROM [dbo].[Event2Action];"

            # Now we have the message, we need a way to send it... 
            $sqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter $sqlCommand
            $dataSet = New-Object System.Data.DataSet
            $sqlDataAdapter.fill($dataSet) | Out-Null
            Write-Host "$Server`: All 'Event2Actions' deleted."

            # Deleting 'VideoUnits' and 'GhostCamera' Entities -----------------------------------------------------------------------------#
              # Deleting VideoUnits creates Ghost cameras. Deleting the Ghost camera without deleting the SQL database entry will make it reappear, we need the 'Ghostbusters'...
              # ...Which, although 'I aint afraid of no ghost', sadly isnt an option, instead we loop through all the Video File data table 0 to 31 and 'clear it out'
            Get-SCEntities -Type 'VideoUnits' | Remove-SCVideoUnit -ErrorAction SilentlyContinue | Out-Null
            Start-Sleep -Seconds 3

            # Video files from the 'D Drive' should already be deleted by calling 'Remove-SCVideoUnit', but just incase...
            Remove-Item -Path D:\VideoArchives\Archiver\* -Force -Recurse -ErrorAction Ignore

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

            # After a 10 second wait (enough time for the 'GhostCamera' to appear), we nuke it/them                    
            Get-SCEntities -Type Cameras | Remove-SCVideoUnit -ErrorAction SilentlyContinue | Out-Null
            Write-Host "$Server`: All 'Cameras', 'VideoUnits', and 'Ghost Cameras' deleted."

            # Deleting 'Custom Events' Entities -----------------------------------------------------------------------------------------#
              # SQL command to delete 'Custom Events' from the SC system'.
              # Note that the 'custom event' will stay visible in Config Tool until you log out and in...
            $sqlCommand.CommandText = "USE Directory; DELETE FROM [dbo].[CustomEvent];"

            # Now we have the message, we need a way to send it... 
            $sqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter $sqlCommand
            $dataSet = New-Object System.Data.DataSet
            $sqlDataAdapter.fill($dataSet) | Out-Null
            Write-Host "$Server`: All 'CustomEvent's deleted."

            Write-Host "$Server`: Restarting the GenetecServer service."
            # ... Restart Gentec Server Service 
            Restart-Service -Name "GenetecServer" | Out-Null

            # Script exit ------------------------------------------------------------------------------------------------------------------#
            Write-Host "$Server`: Everything deleted, once the GenetecServer service has restarted the server is exam ready!"
       
            Exit-SCSession -Session $SCsession

    } -ArgumentList $Server

    Write-Host "$Server`: deleteMostEntities function executed"
    Remove-PSSession -Session $NewPSSession  
}

}



################################################################
# Script Execution
################################################################

foreach($Server in $SERVERS){
    Start-Job -Name $Server -InitializationScript $functions -ScriptBlock {deleteMostEntities -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
}


# Waiting for each job to finish before moving on
foreach($Server in $SERVERS){
    Receive-Job -Name $Server -Wait -AutoRemoveJob -ErrorAction SilentlyContinue
}


# END Transcript for OSTCEXAM_Configuration.ps1 and exit the script
$DateEnd = Get-Date
($DateEnd - $DateStart).TotalSeconds
Stop-Transcript | Out-Null