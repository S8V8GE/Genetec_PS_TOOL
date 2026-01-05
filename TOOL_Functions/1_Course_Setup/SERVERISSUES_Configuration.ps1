<#
.DESCRIPTION
    Description: This script is used to create 'issues' for the students depending on the course (SC-OTC-002 and STC-002), such as altering the SC admin password, altering the Server Admin password,
                 disabling the default SQL NT AUTHORITY\SYSTEM user, putting a DB into 'Single User Mode', etc.

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
    Write-Output "SERVER: $server" | Out-File -FilePath "C:\TOOL\TOOL_Logs\ServerIssuesConfig_Params.txt" -Append
}
Write-Output "VM_PASSWORD: $VM_PASSWORD" | Out-File -FilePath "C:\TOOL\TOOL_Logs\ServerIssuesConfig_Params.txt" -Append
Write-Output "COURSE: $COURSE" | Out-File -FilePath "C:\TOOL\TOOL_Logs\ServerIssuesConfig_Params.txt" -Append
Write-Output "COURSEDAY: $COURSEDAY" | Out-File -FilePath "C:\TOOL\TOOL_Logs\ServerIssuesConfig_Params.txt" -Append
Write-Output "VMTYPE: $VMTYPE" | Out-File -FilePath "C:\TOOL\TOOL_Logs\ServerIssuesConfig_Params.txt" -Append
#>

# We add the $server to the trusted host in order to connect to it
Set-Item WSMan:\localhost\Client\TrustedHosts * -Force -ErrorAction SilentlyContinue
Restart-Service WinRM

# START Transcript for SERVERISSUES_Configuration.ps1
Add-Content -Path "C:\TOOL\TOOL_Logs\ServerIssues_Script_Log.txt" -Value "# Servers:$SERVERS #`n# VM PW:$VM_PASSWORD #`n# Course:$COURSE #`n# Day:$COURSEDAY #`n# VM Type:$VMTYPE #"
Start-Transcript -Path "C:\TOOL\TOOL_Logs\ServerIssues_Script_Log.txt" -IncludeInvocationHeader -Append -Force | Out-Null
$DateStart = Get-Date


$STC002function_GenUse = {
################################################################
# FUNCTION: STC-002 General Use Server Issues                    
################################################################
function STC002_GenUse_ServerIssues {
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

            ##### STEP 1 - Change the Server Admin password and alter the Directory DB name -----------------

            # Specifying the path to the "Genetec Security Center" install in program Files (x86)
            $BasePath = "C:\Program Files (x86)"

            # Find the latest version of "Genetec Security Center" in the Start Menu (this selects the most recent version)
            $LatestVersion = Get-ChildItem -Path $BasePath | Where-Object { $_.Name -LIKE "Genetec Security Center*" } | Sort-Object Name -Descending | Select-Object -First 1

            # Combine the base path and the latest version to get the full target path 
            $serverAdmin_Password_TargetPath = $BasePath + "\" + $LatestVersion.Name + "\ConfigurationFiles\GenetecServer.gconfig"
            $serverAdmin_Directory_TargetPath = $BasePath + "\" + $LatestVersion.Name + "\ConfigurationFiles\Directory.gconfig"

            # GenetecServer.gconfig ---------------
            $xmlContent_GS = Get-Content -Path $serverAdmin_Password_TargetPath -Raw
            $xmlDocument_GS = [xml]::new()
            $xmlDocument_GS.LoadXml($xmlContent_GS)

            # Note:
            # Server Admin Hash for password '!Training1'     == 'rfc2898$ic=100000$71OmjiKyvT0=$QOAAnrBZfxt/6GeFEWf4BqwJml4AmNwY4lIuUQUKvTNt+4o7mEMc8V9oQJtlAuBk'
            # Server Admin Hash for password 'Letmein123!'    == 'rfc2898$ic=100000$71OmjiKyvT0=$6y6xbJlT7JNby8L1OjQPJKLgT+ooDdM1kRL9WOwafcopYDvWqEjxBrrY4HeiA90O'

            $newPasswordValue = 'rfc2898$ic=100000$71OmjiKyvT0=$6y6xbJlT7JNby8L1OjQPJKLgT+ooDdM1kRL9WOwafcopYDvWqEjxBrrY4HeiA90O'  # Replace with the new password

            # Update password in 'genetecServer'
            $genetecServerPasswordNode = $xmlDocument_GS.SelectSingleNode("//genetecServer/passwordHash")
            $genetecServerPasswordNode.SetAttribute("value", $newPasswordValue)
            $xmlDocument_GS.Save($serverAdmin_Password_TargetPath)  # Save the changes back to the file

            # Update password in 'console'
            $consolePasswordNode = $xmlDocument_GS.SelectSingleNode("//console/passwordHash")
            $consolePasswordNode.SetAttribute("value", $newPasswordValue)
            $xmlDocument_GS.Save($serverAdmin_Password_TargetPath)  # Save the changes back to the file

            Write-Host "$Server`: Server Admin - Password altered from `"!Training1`" to `"Letmin123!`""

            # Directory.gconfig --------------------
            $xmlContent_DIR = Get-Content -Path $serverAdmin_Directory_TargetPath -Raw
            $xmlDocument_DIR = [xml]::new()
            $xmlDocument_DIR.LoadXml($xmlContent_DIR)

            # Update 'Server' in 'Database'
            $databaseServerNode = $xmlDocument_DIR.SelectSingleNode("//Database")
            $databaseServerNode.SetAttribute("Server", "(local)\SQLExpres")
            $xmlDocument_DIR.Save($serverAdmin_Directory_TargetPath)  # Save the changes back to the file

            Write-Host "$Server`: Server Admin - Directory Database altered from `"(local)\SQLExpress`" to `"(local)\SQLExpres`""

            ##### STEP 2 - Make some 'changes' to SQL ----------------

            # Create a new object used to establish a connection to MS SQL DB's, define connection string and open connection
            $sqlConnection = New-Object System.Data.SqlClient.SqlConnection
            $sqlConnection.ConnectionString = "Server = localhost\SQLExpress; Integrated Security = true"
            $sqlConnection.Open()

            # Object used to execute SQL commands on the connected database.
            $sqlCommand = $sqlConnection.CreateCommand()

            #-------------

            # SQL: NT AUTHORITY\SYSTEM - DENY connect and DISABLE LOGIN 
            $sqlCommand.CommandText = "USE master; DENY CONNECT SQL TO [NT AUTHORITY\SYSTEM]; ALTER LOGIN [NT AUTHORITY\SYSTEM] DISABLE;"

            # Now we have the message, we need a way to send it... 
            $sqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter $sqlCommand
            $dataSet = New-Object System.Data.DataSet
            $sqlDataAdapter.fill($dataSet) | Out-Null

            Write-Host "$Server`: SQL User 'NT AUTHORITY\SYSTEM' - DENY connect and DISABLE LOGIN set successfully"

            #------------

            # SQL: Directory DB - set to 'Single User' mode 
            $sqlCommand.CommandText = "USE master; ALTER DATABASE Directory SET SINGLE_USER WITH ROLLBACK IMMEDIATE;"

            # Now we have the message, we need a way to send it... 
            $sqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter $sqlCommand
            $dataSet = New-Object System.Data.DataSet
            $sqlDataAdapter.fill($dataSet) | Out-Null

            Write-Host "$Server`: SQL Directory Database set to 'Single User' mode successfully"


            ##### STEP 3 - Stop and Disable some services --------------------

            # SERVICES: STOP & DISABLE: "GenetecWatchdog", "GenetecServer", 'MSSQL$SQLEXPRESS' 
            $svc_GWatchdog = "GenetecWatchdog"
            Get-Service -ComputerName $Server | Where-Object {$_.Name -eq $svc_GWatchdog} |  Stop-Service -Force | Out-Null
            Set-Service $svc_GWatchdog -StartupType  Disabled;
            Write-Host "$Server`: GenetecWatchdog service stopped and disabled"

            #-------------

            $svc_GServer = "GenetecServer"
            Get-Service -ComputerName $Server | Where-Object {$_.Name -eq $svc_GServer} |  Stop-Service -Force | Out-Null
            Set-Service $svc_GServer -StartupType  Disabled;
            Write-Host "$Server`: GenetecServer service stopped and disabled"

            #-------------

            $svc_SQL = 'MSSQL$SQLEXPRESS'
            Get-Service -ComputerName $Server | Where-Object {$_.Name -eq $svc_SQL} |  Stop-Service -Force |Out-Null
            Set-Service $svc_SQL -StartupType  Disabled
            Write-Host "$Server`: SQL service stopped and disabled"
    
    } -ArgumentList $Server

    Write-Host "$Server`: STC002_GenUse_ServerIssues function executed"
    Remove-PSSession -Session $NewPSSession
}
}

$STC002function_Trouble = {
################################################################
# FUNCTION: STC-002 Troubleshooting Server Issues                
################################################################
function STC002_Troubleshooting_ServerIssues {
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

            ##### STEP 1 - Change the Server Admin password and alter the Directory DB name --------------

            # Specifying the path to the "Genetec Security Center" install in program Files (x86)
            $BasePath = "C:\Program Files (x86)"

            # Find the latest version of "Genetec Security Center" in the Start Menu (this selects the most recent version)
            $LatestVersion = Get-ChildItem -Path $BasePath | Where-Object { $_.Name -LIKE "Genetec Security Center*" } | Sort-Object Name -Descending | Select-Object -First 1

            # Combine the base path and the latest version to get the full target path 
            $serverAdmin_Password_TargetPath = $BasePath + "\" + $LatestVersion.Name + "\ConfigurationFiles\GenetecServer.gconfig"

            # GenetecServer.gconfig --------------------------
            $xmlContent_GS = Get-Content -Path $serverAdmin_Password_TargetPath -Raw
            $xmlDocument_GS = [xml]::new()
            $xmlDocument_GS.LoadXml($xmlContent_GS)

            # Note:
            # Server Admin Hash for password '!Training1'     == 'WXjYl6TBmu55qCIK4fzxHg=='
            # Server Admin Hash for password 'Letmein123!'    == '07bFkgS3wJphoIl+ihbdNA=='

            $newPasswordValue = '07bFkgS3wJphoIl+ihbdNA=='  # Replace with the new password

            # Update password in 'genetecServer'
            $genetecServerPasswordNode = $xmlDocument_GS.SelectSingleNode("//genetecServer/password")
            $genetecServerPasswordNode.SetAttribute("password", $newPasswordValue)
            $xmlDocument_GS.Save($serverAdmin_Password_TargetPath)  # Save the changes back to the file

            # Update password in 'console'
            $consolePasswordNode = $xmlDocument_GS.SelectSingleNode("//console/password")
            $consolePasswordNode.SetAttribute("password", $newPasswordValue)
            $xmlDocument_GS.Save($serverAdmin_Password_TargetPath)  # Save the changes back to the file

            Write-Host "$Server`: Server Admin - Password altered from `"!Training1`" to `"Letmin123!`""


            ##### STEP 2 - Make some 'changes' to SQL ----------------

            # Create a new object used to establish a connection to MS SQL DB's, define connection string and open connection
            $sqlConnection = New-Object System.Data.SqlClient.SqlConnection
            $sqlConnection.ConnectionString = "Server = localhost\SQLExpress; Integrated Security = true"
            $sqlConnection.Open()

            # Object used to execute SQL commands on the connected database.
            $sqlCommand = $sqlConnection.CreateCommand()

            #----------

            # SQL: NT AUTHORITY\SYSTEM - DENY connect and DISABLE LOGIN 
            $sqlCommand.CommandText = "USE master; DENY CONNECT SQL TO [NT AUTHORITY\SYSTEM]; ALTER LOGIN [NT AUTHORITY\SYSTEM] DISABLE;"

            # Now we have the message, we need a way to send it... 
            $sqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter $sqlCommand
            $dataSet = New-Object System.Data.DataSet
            $sqlDataAdapter.fill($dataSet) | Out-Null

            Write-Host "$Server`: SQL User 'NT AUTHORITY\SYSTEM' - DENY connect and DISABLE LOGIN set successfully"

            #------------
            
            # SQL: Access Manager DB - set to 'Single User' mode 
            $sqlCommand.CommandText = "USE master; ALTER DATABASE AccessManager SET SINGLE_USER WITH ROLLBACK IMMEDIATE;"

            # Now we have the message, we need a way to send it... 
            $sqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter $sqlCommand
            $dataSet = New-Object System.Data.DataSet
            $sqlDataAdapter.fill($dataSet) | Out-Null

            Write-Host "$Server`: SQL AccessManager Database set to 'Single User' mode successfully"


            ##### STEP 3 - Stop and Disable some services ------------------

            # SERVICES: STOP & DISABLE: "GenetecWatchdog", "GenetecServer", 'MSSQL$SQLEXPRESS' 
            $svc_GWatchdog = "GenetecWatchdog"
            Get-Service -ComputerName $Server | Where-Object {$_.Name -eq $svc_GWatchdog} |  Stop-Service -Force | Out-Null
            Set-Service $svc_GWatchdog -StartupType  Disabled;
            Write-Host "$Server`: GenetecWatchdog service stopped and disabled"

            #-----------

            $svc_GServer = "GenetecServer"
            Get-Service -ComputerName $Server | Where-Object {$_.Name -eq $svc_GServer} |  Stop-Service -Force | Out-Null
            Set-Service $svc_GServer -StartupType  Disabled;
            Write-Host "$Server`: GenetecServer service stopped and disabled"

            #-----------

            $svc_SQL = 'MSSQL$SQLEXPRESS'
            Get-Service -ComputerName $Server | Where-Object {$_.Name -eq $svc_SQL} |  Stop-Service -Force |Out-Null
            Set-Service $svc_SQL -StartupType  Disabled
            Write-Host "$Server`: SQL service stopped and disabled"

    
    } -ArgumentList $Server

    Write-Host "$Server`: STC002_Troubleshooting_ServerIssues function executed"
    Remove-PSSession -Session $NewPSSession
}
}

$STC002function_ExamDay1 = {
################################################################
# FUNCTION: STC-002 Exam (DAY 1) Server Issues                   
################################################################
function STC002_Exam_Day1_ServerIssues {
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

             ##### STEP 1 - Stop and Disable the SQL service ----------------

            $svc_SQL = 'MSSQL$SQLEXPRESS'
            Get-Service -ComputerName $Server | Where-Object {$_.Name -eq $svc_SQL} |  Stop-Service -Force |Out-Null
            Set-Service $svc_SQL -StartupType  Disabled
            Write-Host "$Server`: SQL service stopped and disabled"
 
    } -ArgumentList $Server

    Write-Host "$Server`: STC002_Exam_Day1_ServerIssues function executed"
    Remove-PSSession -Session $NewPSSession
}
}

$STC002function_ExamDay2 = {
################################################################
# FUNCTION: STC-002 Exam (DAY 2) Server Issues                   
################################################################
function STC002_Exam_Day2_ServerIssues {
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

            ##### STEP 1 - Make some 'changes' to SQL ----------------

            # Create a new object used to establish a connection to MS SQL DB's, define connection string and open connection
            $sqlConnection = New-Object System.Data.SqlClient.SqlConnection
            $sqlConnection.ConnectionString = "Server = localhost\SQLExpress; Integrated Security = true"
            $sqlConnection.Open()

            # Object used to execute SQL commands on the connected database.
            $sqlCommand = $sqlConnection.CreateCommand()

            #------------

            # Note:
            # Hash for password 'blank/default'  == 'd41d8cd98f00b204e9800998ecf8427e'
            # Hash for password '!Training1'     == '1;zcvVBVeJr6SyT69i;6GPFoPQ5lD6LfTajBN42GLWmSRWl4LQdJiiK95ELe3M='
            # Hash for password 'Letmein123!'    == '1;1juT61Ud8QvBj3UE;JvjYMpKFap+LRWlvAIybfx+JvgrCe2gZerQZqaOPSPE='

            # Set the Admin SC password to Letmein123! 
            $sqlCommand.CommandText = "USE Directory; UPDATE [user] set Password = '1;1juT61Ud8QvBj3UE;JvjYMpKFap+LRWlvAIybfx+JvgrCe2gZerQZqaOPSPE=' where name = 'Admin';"

            # Now we have the message, we need a way to send it... 
            $sqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter $sqlCommand
            $dataSet = New-Object System.Data.DataSet
            $sqlDataAdapter.fill($dataSet) | Out-Null

            Write-Host "$Server`: Security Center Admin password set to `"Letmein123!`""

            #-----------

            # SQL: NT AUTHORITY\SYSTEM - DENY connect and DISABLE LOGIN 
            $sqlCommand.CommandText = "USE master; DENY CONNECT SQL TO [NT AUTHORITY\SYSTEM]; ALTER LOGIN [NT AUTHORITY\SYSTEM] DISABLE;"

            # Now we have the message, we need a way to send it... 
            $sqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter $sqlCommand
            $dataSet = New-Object System.Data.DataSet
            $sqlDataAdapter.fill($dataSet) | Out-Null

            Write-Host "$Server`: SQL User 'NT AUTHORITY\SYSTEM' - DENY connect and DISABLE LOGIN set successfully"

            #--------

            # SQL: Directory DB - set to 'Single User' mode 
            $sqlCommand.CommandText = "USE master; ALTER DATABASE Directory SET SINGLE_USER WITH ROLLBACK IMMEDIATE;"

            # Now we have the message, we need a way to send it... 
            $sqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter $sqlCommand
            $dataSet = New-Object System.Data.DataSet
            $sqlDataAdapter.fill($dataSet) | Out-Null

            Write-Host "$Server`: SQL Directory Database set to 'Single User' mode successfully"


            ##### STEP 2 - Stop and Disable some services ---------------

            # SERVICES: STOP & DISABLE: "GenetecWatchdog", "GenetecServer" 
            $svc_GWatchdog = "GenetecWatchdog"
            Get-Service -ComputerName $Server | Where-Object {$_.Name -eq $svc_GWatchdog} |  Stop-Service -Force | Out-Null
            Set-Service $svc_GWatchdog -StartupType  Disabled;
            Write-Host "$Server`: GenetecWatchdog service stopped and disabled"

            #-----------

            $svc_GServer = "GenetecServer"
            Get-Service -ComputerName $Server | Where-Object {$_.Name -eq $svc_GServer} |  Stop-Service -Force | Out-Null
            Set-Service $svc_GServer -StartupType  Disabled;
            Write-Host "$Server`: GenetecServer service stopped and disabled"
 
    } -ArgumentList $Server

    Write-Host "$Server`: STC002_Exam_Day2_ServerIssues function executed"
    Remove-PSSession -Session $NewPSSession
}
}


$OTC002function_GenUseDay1 = {
################################################################
# FUNCTION: OTC-002 General Use (DAY 1) Server Issues           
################################################################
function OTC002_GenUse_Day1_ServerIssues {
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

    # If machine is an 'S100', do this...
    if ($vmNumber -ge 100 -and $vmNumber -le 199) {
        # Script block to send commands to the remote machine(s)
        $Remote = Invoke-Command -Session $NewPSSession -ScriptBlock {
            param ($Server)
  
                ##### STEP 1 - Change the Server Admin password --------------

                # Specifying the path to the "Genetec Security Center" install in program Files (x86)
                $BasePath = "C:\Program Files (x86)"

                # Find the latest version of "Genetec Security Center" in the Start Menu (this selects the most recent version)
                $LatestVersion = Get-ChildItem -Path $BasePath | Where-Object { $_.Name -LIKE "Genetec Security Center*" } | Sort-Object Name -Descending | Select-Object -First 1

                # Combine the base path and the latest version to get the full target path 
                $serverAdmin_Password_TargetPath = $BasePath + "\" + $LatestVersion.Name + "\ConfigurationFiles\GenetecServer.gconfig"

                # GenetecServer.gconfig ---------------
                $xmlContent_GS = Get-Content -Path $serverAdmin_Password_TargetPath -Raw
                $xmlDocument_GS = [xml]::new()
                $xmlDocument_GS.LoadXml($xmlContent_GS)

                # Note:
                # Server Admin Hash for password '!Training1'     == 'rfc2898$ic=100000$71OmjiKyvT0=$QOAAnrBZfxt/6GeFEWf4BqwJml4AmNwY4lIuUQUKvTNt+4o7mEMc8V9oQJtlAuBk'
                # Server Admin Hash for password 'Letmein123!'    == 'rfc2898$ic=100000$71OmjiKyvT0=$6y6xbJlT7JNby8L1OjQPJKLgT+ooDdM1kRL9WOwafcopYDvWqEjxBrrY4HeiA90O'

                $newPasswordValue = 'rfc2898$ic=100000$71OmjiKyvT0=$6y6xbJlT7JNby8L1OjQPJKLgT+ooDdM1kRL9WOwafcopYDvWqEjxBrrY4HeiA90O'  # Replace with the new password

                # Update password in 'genetecServer'
                $genetecServerPasswordNode = $xmlDocument_GS.SelectSingleNode("//genetecServer/passwordHash")
                $genetecServerPasswordNode.SetAttribute("value", $newPasswordValue)
                $xmlDocument_GS.Save($serverAdmin_Password_TargetPath)  # Save the changes back to the file

                # Update password in 'console'
                $consolePasswordNode = $xmlDocument_GS.SelectSingleNode("//console/passwordHash")
                $consolePasswordNode.SetAttribute("value", $newPasswordValue)
                $xmlDocument_GS.Save($serverAdmin_Password_TargetPath)  # Save the changes back to the file

                Write-Host "$Server`: Server Admin - Password altered from `"!Training1`" to `"Letmin123!`""


                ##### STEP 2 - Make some 'changes' to SQL ------------

                # Create a new object used to establish a connection to MS SQL DB's, define connection string and open connection
                $sqlConnection = New-Object System.Data.SqlClient.SqlConnection
                $sqlConnection.ConnectionString = "Server = localhost\SQLExpress; Integrated Security = true"
                $sqlConnection.Open()

                # Object used to execute SQL commands on the connected database.
                $sqlCommand = $sqlConnection.CreateCommand()

                #-----------
            
                # SQL: Directory DB - set to 'Single User' mode 
                $sqlCommand.CommandText = "USE master; ALTER DATABASE Directory SET SINGLE_USER WITH ROLLBACK IMMEDIATE;"

                # Now we have the message, we need a way to send it... 
                $sqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter $sqlCommand
                $dataSet = New-Object System.Data.DataSet
                $sqlDataAdapter.fill($dataSet) | Out-Null

                Write-Host "$Server`: SQL Directory Database set to 'Single User' mode successfully"


                ##### STEP 3 - Stop and Disable some services ----------------

                # SERVICES: STOP & DISABLE: "GenetecWatchdog", "GenetecServer" 
                $svc_GWatchdog = "GenetecWatchdog"
                Get-Service -ComputerName $Server | Where-Object {$_.Name -eq $svc_GWatchdog} |  Stop-Service -Force | Out-Null
                Set-Service $svc_GWatchdog -StartupType  Disabled;
                Write-Host "$Server`: GenetecWatchdog service stopped and disabled"

                #-----------

                $svc_GServer = "GenetecServer"
                Get-Service -ComputerName $Server | Where-Object {$_.Name -eq $svc_GServer} |  Stop-Service -Force | Out-Null
                Set-Service $svc_GServer -StartupType  Disabled;
                Write-Host "$Server`: GenetecServer service stopped and disabled"
    
        } -ArgumentList $Server

        Write-Host "$Server`: OTC002_GenUse_Day1_ServerIssues function executed (S100 Branch)"
        Remove-PSSession -Session $NewPSSession
   }
   
    # If machine is an 'S200', do this...
    elseif ($vmNumber -ge 200 -and $vmNumber -le 250) {
        # Script block to send commands to the remote machine(s)
        $Remote = Invoke-Command -Session $NewPSSession -ScriptBlock {
            param ($Server)
  
                ##### STEP 1 - Change the 'expansion' server to a 'Main Server' -----------            
                
                # Used to enter another SC session (as the Directory will have restarted);
                Import-Module SecurityCenter
                $SCsession = New-SCSession -ComputerName $Server -User "Admin" -DirectoryPassword "!Training1" -GenetecServerPassword "!Training1" | Enter-SCSession | Out-Null               
                
                $serverAdmin = Get-SCServerAdmin 

                $myServerAdmin = Get-SCServerAdmin
                $myServerAdmin.GenetecServer_General_IsMainServer = $true
                Set-SCServerAdmin $myServerAdmin

                Write-Host "$Server`: Altered the server from 'Expansion' to 'Main'"
               
                Exit-SCSession
  
                ##### STEP 2 - Stop and Disable some services -------------
                Start-Sleep -Seconds 30 # Allow Directory to restart after changing it from 'expansion server' to 'main server' - dont want to corrupt any files!

                # SERVICES: STOP & DISABLE: "GenetecWatchdog", "GenetecServer" 
                $svc_GWatchdog = "GenetecWatchdog"
                Get-Service -ComputerName $Server | Where-Object {$_.Name -eq $svc_GWatchdog} |  Stop-Service -Force | Out-Null
                Set-Service $svc_GWatchdog -StartupType  Disabled;
                Write-Host "$Server`: GenetecWatchdog service stopped and disabled"

                #-----------

                $svc_GServer = "GenetecServer"
                Get-Service -ComputerName $Server | Where-Object {$_.Name -eq $svc_GServer} |  Stop-Service -Force | Out-Null
                Set-Service $svc_GServer -StartupType  Disabled;
                Write-Host "$Server`: GenetecServer service stopped and disabled"
    
        } -ArgumentList $Server

        Write-Host "$Server`: OTC002_GenUse_Day1_ServerIssues function executed (S200 Branch)"
        Remove-PSSession -Session $NewPSSession
   }
   
    # If machine is not 'S100' or 'S200', bail!
    else {
       Write-Host "Ignoring $Server`: VM number $vmNumber is not within the specified ranges."
   }
}
}

$OTC002function_GenUseDay2 = {
################################################################
# FUNCTION: OTC-002 General Use (DAY 2) Server Issues           
################################################################
function OTC002_GenUse_Day2_ServerIssues {
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
  
                ##### STEP 1 - Alter the SC Admin password --------------
                
                # Set the SC admin password to !Training1 ---------------
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
                $sqlCommand.CommandText = "USE Directory; UPDATE [user] set Password = '1;1juT61Ud8QvBj3UE;JvjYMpKFap+LRWlvAIybfx+JvgrCe2gZerQZqaOPSPE=' where name = 'Admin';"

                # Now we have the message, we need a way to send it... 
                $sqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter $sqlCommand
                $dataSet = New-Object System.Data.DataSet
                $sqlDataAdapter.fill($dataSet) | Out-Null

                Write-Host "$Server`: SC admin password set to Letmein123!"
                # ---------------
 
                ##### STEP 2 - Alter the default SQL logon ------------

                # SQL: NT AUTHORITY\SYSTEM - DENY connect and DISABLE LOGIN 
                $sqlCommand.CommandText = "USE master; DENY CONNECT SQL TO [NT AUTHORITY\SYSTEM]; ALTER LOGIN [NT AUTHORITY\SYSTEM] DISABLE;"

                # Now we have the message, we need a way to send it... 
                $sqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter $sqlCommand
                $dataSet = New-Object System.Data.DataSet
                $sqlDataAdapter.fill($dataSet) | Out-Null

                Write-Host "$Server`: SQL User 'NT AUTHORITY\SYSTEM' - DENY connect and DISABLE LOGIN set successfully"

                #---------------

                ##### STEP 3 - Stop and Disable the SQL service --------------

                # SERVICES: STOP & DISABLE: 'MSSQL$SQLEXPRESS' 
                $svc_SQL = 'MSSQL$SQLEXPRESS'
                Get-Service -ComputerName $Server | Where-Object {$_.Name -eq $svc_SQL} |  Stop-Service -Force |Out-Null
                Set-Service $svc_SQL -StartupType  Disabled
                Write-Host "$Server`: SQL service stopped and disabled"

        } -ArgumentList $Server

        Write-Host "$Server`: OTC002_GenUse_Day2_ServerIssues function executed (S100 Branch)"
        Remove-PSSession -Session $NewPSSession
   }
   
    # If machine is not 'S100'
    else {
       Write-Host "$Server`: For the OTC002_GenUse_Day2_ServerIssues Function, only 'S100' machines are altered"
   }
}
}

$OTC002function_GenUseDay3 = {
################################################################
# FUNCTION: OTC-002 General Use (DAY 3) Server Issues           
################################################################
function OTC002_GenUse_Day3_ServerIssues {
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
                
                ##### STEP 1 - At this point I have no idea what the students will have there passwords for Server Admin and SC admin user set to, so alter them both to !Training1 ------------
                             
                ##### Change the Server Admin password --------------

                # Specifying the path to the "Genetec Security Center" install in program Files (x86)
                $BasePath = "C:\Program Files (x86)"

                # Find the latest version of "Genetec Security Center" in the Start Menu (this selects the most recent version)
                $LatestVersion = Get-ChildItem -Path $BasePath | Where-Object { $_.Name -LIKE "Genetec Security Center*" } | Sort-Object Name -Descending | Select-Object -First 1

                # Combine the base path and the latest version to get the full target path 
                $serverAdmin_Password_TargetPath = $BasePath + "\" + $LatestVersion.Name + "\ConfigurationFiles\GenetecServer.gconfig"

                # GenetecServer.gconfig ---------------
                $xmlContent_GS = Get-Content -Path $serverAdmin_Password_TargetPath -Raw
                $xmlDocument_GS = [xml]::new()
                $xmlDocument_GS.LoadXml($xmlContent_GS)

                # Note:
                # Server Admin Hash for password '!Training1'     == 'rfc2898$ic=100000$71OmjiKyvT0=$QOAAnrBZfxt/6GeFEWf4BqwJml4AmNwY4lIuUQUKvTNt+4o7mEMc8V9oQJtlAuBk'
                # Server Admin Hash for password 'Letmein123!'    == 'rfc2898$ic=100000$71OmjiKyvT0=$6y6xbJlT7JNby8L1OjQPJKLgT+ooDdM1kRL9WOwafcopYDvWqEjxBrrY4HeiA90O'

                $newPasswordValue = 'rfc2898$ic=100000$71OmjiKyvT0=$QOAAnrBZfxt/6GeFEWf4BqwJml4AmNwY4lIuUQUKvTNt+4o7mEMc8V9oQJtlAuBk'  # Replace with the new password

                # Update password in 'genetecServer'
                $genetecServerPasswordNode = $xmlDocument_GS.SelectSingleNode("//genetecServer/passwordHash")
                $genetecServerPasswordNode.SetAttribute("value", $newPasswordValue)
                $xmlDocument_GS.Save($serverAdmin_Password_TargetPath)  # Save the changes back to the file

                # Update password in 'console'
                $consolePasswordNode = $xmlDocument_GS.SelectSingleNode("//console/passwordHash")
                $consolePasswordNode.SetAttribute("value", $newPasswordValue)
                $xmlDocument_GS.Save($serverAdmin_Password_TargetPath)  # Save the changes back to the file

                Write-Host "$Server`: Server Admin - Password altered from `"Unknown`" to `"!Training1`""           
                
                ##### Change the SC Admin password --------------

                # Create a new object used to establish a connection to MS SQL DB's, define connection string and open connection
                $sqlConnection = New-Object System.Data.SqlClient.SqlConnection
                $sqlConnection.ConnectionString = "Server = localhost\SQLExpress; Integrated Security = true"
                $sqlConnection.Open()

                # Object used to execute SQL commands on the connected database.
                $sqlCommand = $sqlConnection.CreateCommand()

                #----------

                # Note:
                # Hash for password 'blank/default'  == 'd41d8cd98f00b204e9800998ecf8427e'
                # Hash for password '!Training1'     == '1;zcvVBVeJr6SyT69i;6GPFoPQ5lD6LfTajBN42GLWmSRWl4LQdJiiK95ELe3M='
                # Hash for password 'Letmein123!'    == '1;1juT61Ud8QvBj3UE;JvjYMpKFap+LRWlvAIybfx+JvgrCe2gZerQZqaOPSPE='

                # Set the Admin SC password to !Training1 
                $sqlCommand.CommandText = "USE Directory; UPDATE [user] set Password = '1;zcvVBVeJr6SyT69i;6GPFoPQ5lD6LfTajBN42GLWmSRWl4LQdJiiK95ELe3M=' where name = 'Admin';"

                # Now we have the message, we need a way to send it... 
                $sqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter $sqlCommand
                $dataSet = New-Object System.Data.DataSet
                $sqlDataAdapter.fill($dataSet) | Out-Null

                Write-Host "$Server`: Security Center Admin User - Password altered from `"unknown`" to `"!Training1`""

                #---------
                
                ##### STEP 2 - Alter the Media Router port from 554 to 555 -----------             
                
                Import-Module SecurityCenter

                # Used to enter an SC session (user name, plus config tool password and server admin password);
                $SCsession = New-SCSession -ComputerName $Server -User "Admin" -DirectoryPassword "!Training1" -GenetecServerPassword "!Training1" | Enter-SCSession | Out-Null

                $getMediaRouter = Get-SCRoles -Type StreamManagement
    
                $mediaRouter = Get-SCRole $getMediaRouter

                $mediaRouter.RtspPort = 555

                Set-SCRole $mediaRouter

                Exit-SCSession -Session $SCsession               
                
                Write-Host "$Server`: Media Router Role RTSP Port altered from 554 to 555."
                
                #--------
                
                ##### STEP 3 - Alter Server Admins 'Network (Private Port)' from 5500 to 550 ------------              
                
                # Specifying the path to the "Genetec Security Center" install in program Files (x86)
                $BasePath = "C:\Program Files (x86)"

                # Find the latest version of "Genetec Security Center" in the Start Menu (this selects the most recent version)
                $LatestVersion = Get-ChildItem -Path $BasePath | Where-Object { $_.Name -LIKE "Genetec Security Center*" } | Sort-Object Name -Descending | Select-Object -First 1

                # Combine the base path and the latest version to get the full target path 
                $serverAdmin_Password_TargetPath = $BasePath + "\" + $LatestVersion.Name + "\ConfigurationFiles\GenetecServer.gconfig"

                # GenetecServer.gconfig ---------------
                $xmlContent = Get-Content -Path $serverAdmin_Password_TargetPath -Raw
                $xmlDocument = [xml]::new()
                $xmlDocument.LoadXml($xmlContent)

                $newserverPortValue = 550

                # Update port value in 'serverPort'
                $genetecServerserverPortNode = $xmlDocument.SelectSingleNode("//genetecServer")
                $genetecServerserverPortNode.SetAttribute("serverPort", $newserverPortValue)
                $xmlDocument.Save($serverAdmin_Password_TargetPath)  # Save the changes back to the file

                # Genetec Server Service must be restarted for changes to take effect
                Restart-Service -Name GenetecServer | Out-Null

                Write-Host "$Server`: Server Admin - 'Network (Private Port)' changed from 5500 to 550, Genetec Server Service restarted"                  

        } -ArgumentList $Server

        Write-Host "$Server`: OTC002_GenUse_Day3_ServerIssues function executed (S100 Branch)"
        Remove-PSSession -Session $NewPSSession
   }
   
    # If machine is not 'S100'
    else {
       Write-Host "$Server`: For the OTC002_GenUse_Day3_ServerIssues Function, only 'S100' machines are altered"
   }
}
}

$OTC002function_ExamDay1 = {
################################################################
# FUNCTION: OTC-002 Exam (DAY 1) Server Issues                  
################################################################
function OTC002_Exam_Day1_ServerIssues {
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
  
                ##### STEP 1 - Change the Server Admin password --------------

                # Specifying the path to the "Genetec Security Center" install in program Files (x86)
                $BasePath = "C:\Program Files (x86)"

                # Find the latest version of "Genetec Security Center" in the Start Menu (this selects the most recent version)
                $LatestVersion = Get-ChildItem -Path $BasePath | Where-Object { $_.Name -LIKE "Genetec Security Center*" } | Sort-Object Name -Descending | Select-Object -First 1

                # Combine the base path and the latest version to get the full target path 
                $serverAdmin_Password_TargetPath = $BasePath + "\" + $LatestVersion.Name + "\ConfigurationFiles\GenetecServer.gconfig"

                # GenetecServer.gconfig ---------------
                $xmlContent_GS = Get-Content -Path $serverAdmin_Password_TargetPath -Raw
                $xmlDocument_GS = [xml]::new()
                $xmlDocument_GS.LoadXml($xmlContent_GS)

                # Note:
                # Server Admin Hash for password '!Training1'     == 'rfc2898$ic=100000$71OmjiKyvT0=$QOAAnrBZfxt/6GeFEWf4BqwJml4AmNwY4lIuUQUKvTNt+4o7mEMc8V9oQJtlAuBk'
                # Server Admin Hash for password 'Letmein123!'    == 'rfc2898$ic=100000$71OmjiKyvT0=$6y6xbJlT7JNby8L1OjQPJKLgT+ooDdM1kRL9WOwafcopYDvWqEjxBrrY4HeiA90O'

                $newPasswordValue = 'rfc2898$ic=100000$71OmjiKyvT0=$6y6xbJlT7JNby8L1OjQPJKLgT+ooDdM1kRL9WOwafcopYDvWqEjxBrrY4HeiA90O'  # Replace with the new password

                # Update password in 'genetecServer'
                $genetecServerPasswordNode = $xmlDocument_GS.SelectSingleNode("//genetecServer/passwordHash")
                $genetecServerPasswordNode.SetAttribute("value", $newPasswordValue)
                $xmlDocument_GS.Save($serverAdmin_Password_TargetPath)  # Save the changes back to the file

                # Update password in 'console'
                $consolePasswordNode = $xmlDocument_GS.SelectSingleNode("//console/passwordHash")
                $consolePasswordNode.SetAttribute("value", $newPasswordValue)
                $xmlDocument_GS.Save($serverAdmin_Password_TargetPath)  # Save the changes back to the file

                Write-Host "$Server`: Server Admin - Password altered from `"!Training1`" to `"Letmin123!`""


                ##### STEP 2 - Make some 'changes' to SQL -----------

                # Create a new object used to establish a connection to MS SQL DB's, define connection string and open connection
                $sqlConnection = New-Object System.Data.SqlClient.SqlConnection
                $sqlConnection.ConnectionString = "Server = localhost\SQLExpress; Integrated Security = true"
                $sqlConnection.Open()

                # Object used to execute SQL commands on the connected database.
                $sqlCommand = $sqlConnection.CreateCommand()

                #-------
            
                # SQL: Directory DB - set to 'Single User' mode 
                $sqlCommand.CommandText = "USE master; ALTER DATABASE Directory SET SINGLE_USER WITH ROLLBACK IMMEDIATE;"

                # Now we have the message, we need a way to send it... 
                $sqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter $sqlCommand
                $dataSet = New-Object System.Data.DataSet
                $sqlDataAdapter.fill($dataSet) | Out-Null

                Write-Host "$Server`: SQL Directory Database set to 'Single User' mode successfully"


                ##### STEP 3 - Stop and Disable some services ------------

                # SERVICES: STOP & DISABLE: "GenetecWatchdog", "GenetecServer" 
                $svc_GWatchdog = "GenetecWatchdog"
                Get-Service -ComputerName $Server | Where-Object {$_.Name -eq $svc_GWatchdog} |  Stop-Service -Force | Out-Null
                Set-Service $svc_GWatchdog -StartupType  Disabled;
                Write-Host "$Server`: GenetecWatchdog service stopped and disabled"

                #-------

                $svc_GServer = "GenetecServer"
                Get-Service -ComputerName $Server | Where-Object {$_.Name -eq $svc_GServer} |  Stop-Service -Force | Out-Null
                Set-Service $svc_GServer -StartupType  Disabled;
                Write-Host "$Server`: GenetecServer service stopped and disabled"
    
        } -ArgumentList $Server

        Write-Host "$Server`: OTC002_Exam_Day1_ServerIssues function executed (S100 Branch)"
        Remove-PSSession -Session $NewPSSession
   }
   
    # If machine is an 'S200' create an outbound block rule for TCP 5500
    elseif ($vmNumber -ge 200 -and $vmNumber -le 250) {
        # Script block to send commands to the remote machine(s)
        $Remote = Invoke-Command -Session $NewPSSession -ScriptBlock {
            param ($Server)

                ##### STEP 1 - Change the Server Admin password --------------

                # Specifying the path to the "Genetec Security Center" install in program Files (x86)
                $BasePath = "C:\Program Files (x86)"

                # Find the latest version of "Genetec Security Center" in the Start Menu (this selects the most recent version)
                $LatestVersion = Get-ChildItem -Path $BasePath | Where-Object { $_.Name -LIKE "Genetec Security Center*" } | Sort-Object Name -Descending | Select-Object -First 1

                # Combine the base path and the latest version to get the full target path 
                $serverAdmin_Password_TargetPath = $BasePath + "\" + $LatestVersion.Name + "\ConfigurationFiles\GenetecServer.gconfig"

                # GenetecServer.gconfig ---------------
                $xmlContent_GS = Get-Content -Path $serverAdmin_Password_TargetPath -Raw
                $xmlDocument_GS = [xml]::new()
                $xmlDocument_GS.LoadXml($xmlContent_GS)

                # Note:
                # Server Admin Hash for password '!Training1'     == 'rfc2898$ic=100000$71OmjiKyvT0=$QOAAnrBZfxt/6GeFEWf4BqwJml4AmNwY4lIuUQUKvTNt+4o7mEMc8V9oQJtlAuBk'
                # Server Admin Hash for password 'Letmein123!'    == 'rfc2898$ic=100000$71OmjiKyvT0=$6y6xbJlT7JNby8L1OjQPJKLgT+ooDdM1kRL9WOwafcopYDvWqEjxBrrY4HeiA90O'

                $newPasswordValue = 'rfc2898$ic=100000$71OmjiKyvT0=$6y6xbJlT7JNby8L1OjQPJKLgT+ooDdM1kRL9WOwafcopYDvWqEjxBrrY4HeiA90O'  # Replace with the new password

                # Update password in 'genetecServer'
                $genetecServerPasswordNode = $xmlDocument_GS.SelectSingleNode("//genetecServer/passwordHash")
                $genetecServerPasswordNode.SetAttribute("value", $newPasswordValue)
                $xmlDocument_GS.Save($serverAdmin_Password_TargetPath)  # Save the changes back to the file

                # Update password in 'console'
                $consolePasswordNode = $xmlDocument_GS.SelectSingleNode("//console/passwordHash")
                $consolePasswordNode.SetAttribute("value", $newPasswordValue)
                $xmlDocument_GS.Save($serverAdmin_Password_TargetPath)  # Save the changes back to the file

                Write-Host "$Server`: Server Admin - Password altered from `"!Training1`" to `"Letmin123!`""
  
                ##### STEP 2 - Change the 'expansion' server to a 'Main Server' -----            
                Start-Sleep -Seconds 5

                Import-Module SecurityCenter

                # Used to enter an SC session (as the Directory will have restarted);
                $SCsession = New-SCSession -ComputerName $Server -User "Admin" -DirectoryPassword "!Training1" -GenetecServerPassword "Letmein123!" | Enter-SCSession | Out-Null               
                
                $serverAdmin = Get-SCServerAdmin 

                $myServerAdmin = Get-SCServerAdmin
                $myServerAdmin.GenetecServer_General_IsMainServer = $true
                Set-SCServerAdmin $myServerAdmin

                Write-Host "$Server`: Altered the server from 'Expansion' to 'Main'"
               
                Exit-SCSession
  
                ##### STEP 3 - Stop and Disable some services -----
                Start-Sleep -Seconds 30 # Allow Directory to restart after changing it from 'expansion server' to 'main server' - dont want to corrupt any files!

                # SERVICES: STOP & DISABLE: "GenetecWatchdog", "GenetecServer" 
                $svc_GWatchdog = "GenetecWatchdog"
                Get-Service -ComputerName $Server | Where-Object {$_.Name -eq $svc_GWatchdog} |  Stop-Service -Force | Out-Null
                Set-Service $svc_GWatchdog -StartupType  Disabled;
                Write-Host "$Server`: GenetecWatchdog service stopped and disabled"

                #------

                $svc_GServer = "GenetecServer"
                Get-Service -ComputerName $Server | Where-Object {$_.Name -eq $svc_GServer} |  Stop-Service -Force | Out-Null
                Set-Service $svc_GServer -StartupType  Disabled;
                Write-Host "$Server`: GenetecServer service stopped and disabled"
    
        } -ArgumentList $Server

        Write-Host "$Server`: OTC002_Exam_Day1_ServerIssues function executed (S200 Branch)"
        Remove-PSSession -Session $NewPSSession
   }
   
    # If machine is not 'S100' or 'S200', bail!
    else {
       Write-Host "Ignoring $Server`: VM number $vmNumber is not within the specified ranges."
   }
}
}

$OTC002function_ExamDay2 = {
################################################################
# FUNCTION: OTC-002 Exam (DAY 2) Server Issues                  
################################################################
function OTC002_Exam_Day2_ServerIssues {
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

                ##### STEP 1 - Get the Archiver Role and create SQL object for altering DB's ---------

                # Create a new object used to establish a connection to MS SQL DB's, define connection string and open connection
                $sqlConnection = New-Object System.Data.SqlClient.SqlConnection
                $sqlConnection.ConnectionString = "Server = localhost\SQLExpress; Integrated Security = true"
                $sqlConnection.Open()

                # Object used to execute SQL commands on the connected database.
                $sqlCommand = $sqlConnection.CreateCommand()

                # Set the Admin SC password to !Training1 
                $sqlCommand.CommandText = "USE Directory; UPDATE [user] set Password = '1;zcvVBVeJr6SyT69i;6GPFoPQ5lD6LfTajBN42GLWmSRWl4LQdJiiK95ELe3M=' where name = 'Admin';"

                # Now we have the message, we need a way to send it... 
                $sqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter $sqlCommand
                $dataSet = New-Object System.Data.DataSet
                $sqlDataAdapter.fill($dataSet) | Out-Null

                Write-Host "$Server`: Security Center Admin User - Password altered from `"unknown`" to `"!Training1`""
                                
                Import-Module SecurityCenter
                
                $SCsession = New-SCSession -ComputerName $Server -User "Admin" -DirectoryPassword "!Training1" -GenetecServerPassword "!Training1" | Enter-SCSession | Out-Null
                
                $myArc = Get-SCRoles -Type Archiver | Get-SCRole
                
                
                ##### STEP 2 - Set the Archiver encryption to none ----------------------------------
                $myArc.EncryptionType = "none" # Default is SRTP_InTransit
                Set-SCRole $myArc

                Write-Host "$Server`: Archiver encryption set to 'none'"


                ##### STEP 3 - Set the Archiver recording from 30 days to 4 days --------------------
                $myArc.BackupRetentionPeriod = 4 # Default is 30
                Set-SCRole $myArc

                Write-Host "$Server`: Archiver continuous recording set from 30 to 4 days"


                ##### STEP 4 - Lower the Archiver minimum free disk space from 2048 to 75000 ---------
                $myArcAgent = $myArc.PrimaryArchiverId #this gives GUID of GenetecArchiverAgent32.exe
                $diskGroups = Get-SCArchiverAgentDiskGroup -ArchiverAgentId $myArcAgent
                $diskDrives = $diskGroups.Drives

                foreach($drive in $diskDrives)
                {
                    if($drive.FilePath -eq "C:\")
                    {
                        $drive.MinDriveSpace = 75000 # Default is 2048
                    }
                }

                Set-SCArchiverAgentDiskGroup -ArchiverAgentId $myArcAgent -DiskGroup $diskGroups | Out-Null

                Write-Host "$Server`: Archiver minimum free disk space altered from 2048 to 75000"


                ##### STEP 5 - Alter the Media Router DB name -----------
                $getMediaRouter = Get-SCRoles -Type StreamManagement
    
                $mediaRouter = Get-SCRole $getMediaRouter

                $mediaRouter.DatabaseInstance = "(local)\SQIExpress"

                Set-SCRole $mediaRouter

                Write-Host "$Server`: Media Router DB set to '(local)\SQIExpress'"


                ##### STEP 6 - Alter a cameras connection type to Multicast --------
                # Selecting a 'random' camera (not true, just selecting the first one it sees!)
                $camera = Get-SCEntities -Type Cameras -Filter All
                $randomCamera = $camera[0]
                $getRandomCamera = Get-SCEntity -EntityId $randomCamera.Id

                # Getting the first stream from the camera H.264-1, which is the default stream used
                $streamsOnCamera = Get-SCCameraStreams -CameraId $getRandomCamera.Id
                $firstStream = $streamsOnCamera[0]

                # Altering the 'Connection Type' of the first (default) camera stream 
                $stmOnCamera = Get-SCEntity $firstStream.Id
                $stmOnCamera.ConfiguredConnection = "Multicast" #Default is "BestAvailable"
                Set-SCEntity $stmOnCamera

                Write-Host "$Server`: Camera 'Connection Type' set to Multicast"


                ##### STEP 7 - Alter the 'Azure' network to Multicast -------
                # Get the 'Azure' network
                $network = Get-SCEntities -Type Networks | Where-Object { $_.Name -notlike "Default*" }
                $azureNetwork = Get-SCNetwork -NetworkId $network.Id

                # Set the 'Azure' network to Multicast
                $azureNetwork.SupportedTransports = "Multicast" # Default is 'UnicastUdp'
                Set-SCNetwork $azureNetwork

                Write-Host "$Server`: Azure Network 'Capabilities' set to Multicast"


                ##### STEP 8 - Deactivate the Health Monitor role -------
                # Get the Health Monitor role
                $getHealthMonitor = Get-SCRoles -Type HealthMonitoring
                $healthMonitor = Get-SCRole $getHealthMonitor

                #Deactive the Health Monitor role
                $healthMonitor.Disabled = $true # Default is $false
                Set-SCRole $healthMonitor

                Write-Host "$Server`: Health Monitor role deactivated"


                ##### STEP 9 - Alter the user created in the administrators user groups password and remove from the group ---
                # Get the user created in the administrators user group
                $userGroups = Get-SCEntities -Type UserGroups | Where-Object { $_.Name -like "Administrators" }
                $administratorUsers = Get-SCUserGroupMembers -UserGroupId $userGroups.Id 
                $filteredUsers = $administratorUsers | Where-Object { $_.Name -ne "Admin" -and $_.Name -ne "Service"  }
                $user = $filteredUsers.Name

                # Set the users password (that the student created) to Letmein123! 
                $sqlCommand.CommandText = "USE Directory; UPDATE [user] set Password = '1;1juT61Ud8QvBj3UE;JvjYMpKFap+LRWlvAIybfx+JvgrCe2gZerQZqaOPSPE=' where name = '$user';"

                # Now we have the message, we need a way to send it... 
                $sqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter $sqlCommand
                $dataSet = New-Object System.Data.DataSet
                $sqlDataAdapter.fill($dataSet) | Out-Null

                Write-Host "$Server`: Security Center User '$user' - Password altered from `"unknown`" to `"Letmein123!`""

                # Remove the user created in the administrators user group
                Remove-SCUserUserGroups -UserId $filteredUsers.Id -UserGroupId $userGroups.Id

                Write-Host "$Server`: Security Center User '$user' - removed from the User Group `"Administrators`""


                ##### STEP 10 - Alter the 'Supervisor' user created in the 'Supervisors' user groups password and Deny privilege to view live footage --------
                # Get the user created in the 'Supervisor' user group
                $userGroups = Get-SCEntities -Type UserGroups | Where-Object { $_.Name -like "*perv*" } #LOL
                $user = Get-SCUserGroupMembers -UserGroupId $userGroups.Id
                $userName = $user.Name

                # Get the 'View Live Video' privilege ID
                $getPrivilegeIds = Get-SCEnum -Enum PrivilegeIds 
                $getLiveVideoPrivilegeId = $getPrivilegeIds | Where-Object { $_.Description -like "View live video" }
                $liveVideoPrivilegeId = $getLiveVideoPrivilegeId.Id

                # Change the privilege from Granted to Denied
                $getUserPrivileges = Get-SCUserPrivileges -UserId $user.Id 
                $getUserLiveVideoPrivilege = $getUserPrivileges | Where-Object { $_.Id -eq $liveVideoPrivilegeId }
                Set-SCUserPrivileges -UserId $user.Id -PrivilegeId $getUserLiveVideoPrivilege.Id -PrivilegeState "Denied" | Out-Null

                Write-Host "$Server`: Security Center '$userName' User - 'View Live Video' privilege altered from Granted to Denied"

                Exit-SCSession -Session $SCsession

                # Set the users password (that the student created) to Letmein123! 
                $sqlCommand.CommandText = "USE Directory; UPDATE [user] set Password = '1;1juT61Ud8QvBj3UE;JvjYMpKFap+LRWlvAIybfx+JvgrCe2gZerQZqaOPSPE=' where name = '$userName';"

                # Now we have the message, we need a way to send it... 
                $sqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter $sqlCommand
                $dataSet = New-Object System.Data.DataSet
                $sqlDataAdapter.fill($dataSet) | Out-Null

                Write-Host "$Server`: Security Center '$userName' User - Password altered from `"unknown`" to `"Letmein123!`""


                ##### STEP 11 - Alter the Archiver RTSP port to 554 --------
                # SQL: Directory DB - alter the Archivers RTSP port from 555 to 554 (so it clashes with the Media Router) 
                $sqlCommand.CommandText = "USE Directory; UPDATE dbo.Agent SET Info2 = REPLACE(Info2, 'Rtsp&gt;555&lt;', 'Rtsp&gt;554&lt;') WHERE Info2 LIKE '%Rtsp&gt;555&lt;%';"

                # Now we have the message, we need a way to send it... 
                $sqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter $sqlCommand
                $dataSet = New-Object System.Data.DataSet
                $sqlDataAdapter.fill($dataSet) | Out-Null

                Write-Host "$Server`: Archiver RTSP port altered from 555 to 554, now restarting Genetec Server Service"

                Restart-Service -Name "GenetecServer" | Out-Null


                ##### STEP 12 - Stop and Disable SQL service -------------
                # SERVICES: STOP & DISABLE: 'MSSQL$SQLEXPRESS' 
                $svc_SQL = 'MSSQL$SQLEXPRESS'
                Get-Service -ComputerName $Server | Where-Object {$_.Name -eq $svc_SQL} |  Stop-Service -Force |Out-Null
                Set-Service $svc_SQL -StartupType  Disabled

                Write-Host "$Server`: SQL service stopped and disabled"
    
        } -ArgumentList $Server

        Write-Host "$Server`: OTC002_Exam_Day2_ServerIssues function executed (S100 Branch)"
        Remove-PSSession -Session $NewPSSession
   }
   
    # If machine is not 'S100'
    else {
       Write-Host "$Server`: For the OTC002_Exam_Day2_ServerIssues Function, only 'S100' machines are altered"
   }
}
}

$OTC002function_ExamDay3 = {
################################################################
# FUNCTION: OTC-002 Exam (DAY 3) Server Issues
################################################################
function OTC002_Exam_Day3_ServerIssues {
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
  
                ##### STEP 1 - Create SQL object for altering DB's --------

                # Create a new object used to establish a connection to MS SQL DB's, define connection string and open connection
                $sqlConnection = New-Object System.Data.SqlClient.SqlConnection
                $sqlConnection.ConnectionString = "Server = localhost\SQLExpress; Integrated Security = true"
                $sqlConnection.Open()

                # Object used to execute SQL commands on the connected database.
                $sqlCommand = $sqlConnection.CreateCommand()

                # Set the Admin SC password to !Training1 
                $sqlCommand.CommandText = "USE Directory; UPDATE [user] set Password = '1;zcvVBVeJr6SyT69i;6GPFoPQ5lD6LfTajBN42GLWmSRWl4LQdJiiK95ELe3M=' where name = 'Admin';"

                # Now we have the message, we need a way to send it... 
                $sqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter $sqlCommand
                $dataSet = New-Object System.Data.DataSet
                $sqlDataAdapter.fill($dataSet) | Out-Null

                Write-Host "$Server`: Security Center Admin User - Password altered from `"unknown`" to `"!Training1`""
                # -----------


                ##### STEP 2 - Set the Media Routers RTSP port from 554 to 555 -------
                Import-Module SecurityCenter
                $SCsession = New-SCSession -ComputerName $Server -User "Admin" -DirectoryPassword "!Training1" -GenetecServerPassword "!Training1" | Enter-SCSession | Out-Null
                
                $getMediaRouter = Get-SCRoles -Type StreamManagement
    
                $mediaRouter = Get-SCRole $getMediaRouter

                $mediaRouter.RtspPort = 555 #default is 554

                Set-SCRole $mediaRouter

                Write-Host "$Server`: Media Router RTSP port altered from 554 to 555"
                # ------------ 


                ##### STEP 3 - Alter each VideoUnits authentication to default (instead of specific) --------
                # Selecting all video units
                $videoUnits = Get-SCEntities -Type VideoUnits  -Filter All

                foreach ($videoUnit in $videoUnits) {
                    $videoUnitName = $videoUnit.Name

                    $videoUnit.UseDefaultCredentials = $true
                    Set-SCEntity $videoUnit

                    Write-Host "$Server`: $videoUnitName 'Authentication' set to 'use default logon' instead of 'specific'"
                }
                # ---------


                ##### STEP 4 - Alter the 'Supervisor' user created in the 'Supervisors' user groups password and Deny privilege to view live footage -----
                # Get the user created in the 'Supervisor' user group
                $userGroups = Get-SCEntities -Type UserGroups | Where-Object { $_.Name -like "*perv*" } #LOL
                $user = Get-SCUserGroupMembers -UserGroupId $userGroups.Id

                $userName = $user.Name
                $userID = $user.Id

                $getUser = Get-SCUser -UserId $userID 

                # Get the 'Change Workspace' privilege ID
                $getPrivilegeIds = Get-SCEnum -Enum PrivilegeIds 
                $getChangeWorkspacePrivilegeId = $getPrivilegeIds | Where-Object { $_.Description -like "Change workspace" }
                $changeWorkspacePrivilegeId = $getChangeWorkspacePrivilegeId.Id

                # Change the privilege from Granted to Denied
                $getUserPrivileges = Get-SCUserPrivileges -UserId $user.Id 
                $getUserChangeWorkspacePrivilege = $getUserPrivileges | Where-Object { $_.Id -eq $changeWorkspacePrivilegeId }
                Set-SCUserPrivileges -UserId $user.Id -PrivilegeId $changeWorkspacePrivilegeId -PrivilegeState "Denied" | Out-Null

                Write-Host "$Server`: Security Center '$userName' User - 'Change Workspace' privilege altered from Granted to Denied"

                Exit-SCSession -Session $SCsession
                # ------------


                ##### STEP 5 - Create 'Orphan Files' for the Archiver (students need to use 'Video File Analyzer' tool to fix) ------

                # Looping through Video File DB and deleting all references of the cameras
                for ($i=0; $i -lt 31; $i++) {
    
                    # SQL command to clear out "dbo.VideoFile 1-31"
                    $sqlCommand.CommandText = "USE Archiver; DELETE FROM [dbo].[VideoFile$i];"
    
                    # Now we have the message, we need a way to send it... 
                    $sqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter $sqlCommand
                    $dataSet = New-Object System.Data.DataSet
                    $sqlDataAdapter.fill($dataSet) | Out-Null
                }

                Write-Host "$Server`: Orphan Files created for the Archiver Role (students need to use 'Video File Analyzer' tool to fix)"
                # ---------


                ##### STEP 6 - Alter the default SQL logon ------------
                # SQL: NT AUTHORITY\SYSTEM - DENY connect and DISABLE LOGIN 
                $sqlCommand.CommandText = "USE master; DENY CONNECT SQL TO [NT AUTHORITY\SYSTEM]; ALTER LOGIN [NT AUTHORITY\SYSTEM] DISABLE;"

                # Now we have the message, we need a way to send it... 
                $sqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter $sqlCommand
                $dataSet = New-Object System.Data.DataSet
                $sqlDataAdapter.fill($dataSet) | Out-Null

                Write-Host "$Server`: SQL User 'NT AUTHORITY\SYSTEM' - DENY connect and DISABLE LOGIN set successfully"
                # ---------- 


                ##### STEP 7 - Delete the Archiver cache so video unit 'use default logon' sticks ----
                # Get the path location   
                $BasePath = "C:\Program Files (x86)"
                $Pattern = "Genetec Security Center (\d+\.\d+)"

                # Find the latest version of "Genetec Security Center" in the Start Menu
                $LatestVersion = Get-ChildItem -Path $BasePath |
                                 Where-Object { $_ -match $Pattern } |
                                 Sort-Object { [Version]::new($Matches[1]) } |
                                 Select-Object -Last 1

                # Combine the base path and the latest version to get the full target path for the shortcuts 
                $archiverCacheFolder = $BasePath + "\" + $LatestVersion + "\Archiver\Cache"

                # delete the Archiver cache folder - This will be rebuilt - without this the video units will switch back to 'specific'!
                Remove-Item $archiverCacheFolder -Recurse -Force
    
        } -ArgumentList $Server

        Write-Host "$Server`: OTC002_Exam_Day3_ServerIssues function executed (S100 Branch)"
        Remove-PSSession -Session $NewPSSession
   }
   
    # If machine is not 'S100'
    else {
       Write-Host "$Server`: For the OTC002_Exam_Day3_ServerIssues Function, only 'S100' machines are altered"
   }
}
}

# This function created to ensure all New-SCSession's dont have an issue with passwords, God only knows what passwords the students will set!
#I wrote this but don't use it... Nice.
$passwordResetFunction = {
################################################################
# FUNCTION: Set the Server Admin and Config Tool password to !Training1
################################################################
function passwordReset {
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

    # If machine is an 'S100' reset both Server Admin and SC Admin passwords
    if ($vmNumber -ge 100 -and $vmNumber -le 199) {
        # Script block to send commands to the remote machine(s)
        $Remote = Invoke-Command -Session $NewPSSession -ScriptBlock {
            param ($Server)

                ##### STEP 1 - Change the Server Admin password --------------

                # Specifying the path to the "Genetec Security Center" install in program Files (x86)
                $BasePath = "C:\Program Files (x86)"

                # Find the latest version of "Genetec Security Center" in the Start Menu (this selects the most recent version)
                $LatestVersion = Get-ChildItem -Path $BasePath | Where-Object { $_.Name -LIKE "Genetec Security Center*" } | Sort-Object Name -Descending | Select-Object -First 1

                # Combine the base path and the latest version to get the full target path 
                $serverAdmin_Password_TargetPath = $BasePath + "\" + $LatestVersion.Name + "\ConfigurationFiles\GenetecServer.gconfig"

                # GenetecServer.gconfig ---------------
                $xmlContent_GS = Get-Content -Path $serverAdmin_Password_TargetPath -Raw
                $xmlDocument_GS = [xml]::new()
                $xmlDocument_GS.LoadXml($xmlContent_GS)

                # Note:
                # Server Admin Hash for password '!Training1'     == 'rfc2898$ic=100000$71OmjiKyvT0=$QOAAnrBZfxt/6GeFEWf4BqwJml4AmNwY4lIuUQUKvTNt+4o7mEMc8V9oQJtlAuBk'
                # Server Admin Hash for password 'Letmein123!'    == 'rfc2898$ic=100000$71OmjiKyvT0=$6y6xbJlT7JNby8L1OjQPJKLgT+ooDdM1kRL9WOwafcopYDvWqEjxBrrY4HeiA90O'

                $newPasswordValue = 'rfc2898$ic=100000$71OmjiKyvT0=$QOAAnrBZfxt/6GeFEWf4BqwJml4AmNwY4lIuUQUKvTNt+4o7mEMc8V9oQJtlAuBk'  # Replace with the new password

                # Update password in 'genetecServer'
                $genetecServerPasswordNode = $xmlDocument_GS.SelectSingleNode("//genetecServer/passwordHash")
                $genetecServerPasswordNode.SetAttribute("value", $newPasswordValue)
                $xmlDocument_GS.Save($serverAdmin_Password_TargetPath)  # Save the changes back to the file

                # Update password in 'console'
                $consolePasswordNode = $xmlDocument_GS.SelectSingleNode("//console/passwordHash")
                $consolePasswordNode.SetAttribute("value", $newPasswordValue)
                $xmlDocument_GS.Save($serverAdmin_Password_TargetPath)  # Save the changes back to the file

                Write-Host "$Server`: Server Admin - Password altered to !Training1"
                
                #---------------------

                ##### STEP 2 - Alter the SC Admin password ------------------
                
                # Set the SC admin password to !Training1 -------------------
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

                Write-Host "$Server`: SC Admin - Password altered to !Training1"
                # ---------------------

        } -ArgumentList $Server

        Write-Host "$Server`: passwordReset function executed (S100 Branch)"
        Remove-PSSession -Session $NewPSSession
   }
   
    # If machine is not 'S100' just reset Server Admin password
    else {

        ##### STEP 1 - Change the Server Admin password --------------

        # Specifying the path to the "Genetec Security Center" install in program Files (x86)
        $BasePath = "C:\Program Files (x86)"

        # Find the latest version of "Genetec Security Center" in the Start Menu (this selects the most recent version)
        $LatestVersion = Get-ChildItem -Path $BasePath | Where-Object { $_.Name -LIKE "Genetec Security Center*" } | Sort-Object Name -Descending | Select-Object -First 1

        # Combine the base path and the latest version to get the full target path 
        $serverAdmin_Password_TargetPath = $BasePath + "\" + $LatestVersion.Name + "\ConfigurationFiles\GenetecServer.gconfig"

        # GenetecServer.gconfig ---------------
        $xmlContent_GS = Get-Content -Path $serverAdmin_Password_TargetPath -Raw
        $xmlDocument_GS = [xml]::new()
        $xmlDocument_GS.LoadXml($xmlContent_GS)

        # Note:
        # Server Admin Hash for password '!Training1'     == 'rfc2898$ic=100000$71OmjiKyvT0=$QOAAnrBZfxt/6GeFEWf4BqwJml4AmNwY4lIuUQUKvTNt+4o7mEMc8V9oQJtlAuBk'
        # Server Admin Hash for password 'Letmein123!'    == 'rfc2898$ic=100000$71OmjiKyvT0=$6y6xbJlT7JNby8L1OjQPJKLgT+ooDdM1kRL9WOwafcopYDvWqEjxBrrY4HeiA90O'

        $newPasswordValue = 'rfc2898$ic=100000$71OmjiKyvT0=$QOAAnrBZfxt/6GeFEWf4BqwJml4AmNwY4lIuUQUKvTNt+4o7mEMc8V9oQJtlAuBk'  # Replace with the new password

        # Update password in 'genetecServer'
        $genetecServerPasswordNode = $xmlDocument_GS.SelectSingleNode("//genetecServer/passwordHash")
        $genetecServerPasswordNode.SetAttribute("value", $newPasswordValue)
        $xmlDocument_GS.Save($serverAdmin_Password_TargetPath)  # Save the changes back to the file

        # Update password in 'console'
        $consolePasswordNode = $xmlDocument_GS.SelectSingleNode("//console/passwordHash")
        $consolePasswordNode.SetAttribute("value", $newPasswordValue)
        $xmlDocument_GS.Save($serverAdmin_Password_TargetPath)  # Save the changes back to the file

        Write-Host "$Server`: Server Admin - Password altered to !Training1 (NOTE: For the passwordReset function, only 'S100 - Main Server' SC Admin passwords are altered"
   }
}
}



################################################################
# Script Execution - STC002
################################################################
if($COURSE -EQ "stc2" -AND $VMTYPE -EQ "general")
{
    foreach($Server in $SERVERS){
        Start-Job -Name $Server -InitializationScript $STC002function_GenUse -ScriptBlock {STC002_GenUse_ServerIssues -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
    }
}

elseif($COURSE -EQ "stc2" -AND $VMTYPE -EQ "trouble")
{
    foreach($Server in $SERVERS){
        Start-Job -Name $Server -InitializationScript $STC002function_Trouble -ScriptBlock {STC002_Troubleshooting_ServerIssues -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
    }
}

elseif($COURSE -EQ "stc2" -AND $VMTYPE -EQ "exam" -AND $COURSEDAY -EQ "1")
{
    foreach($Server in $SERVERS){
        Start-Job -Name $Server -InitializationScript $STC002function_ExamDay1 -ScriptBlock {STC002_Exam_Day1_ServerIssues -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
    }
}

elseif($COURSE -EQ "stc2" -AND $VMTYPE -EQ "exam" -AND $COURSEDAY -EQ "2")
{
    foreach($Server in $SERVERS){
        Start-Job -Name $Server -InitializationScript $STC002function_ExamDay2 -ScriptBlock {STC002_Exam_Day2_ServerIssues -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
    }
}

################################################################
# Script Execution - OTC002
################################################################
elseif($COURSE -EQ "otc2" -AND $VMTYPE -EQ "general" -AND $COURSEDAY -EQ "1")
{
    foreach($Server in $SERVERS){
        Start-Job -Name $Server -InitializationScript $OTC002function_GenUseDay1 -ScriptBlock {OTC002_GenUse_Day1_ServerIssues -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
    }
}

elseif($COURSE -EQ "otc2" -AND $VMTYPE -EQ "general" -AND $COURSEDAY -EQ "2")
{
    foreach($Server in $SERVERS){
        Start-Job -Name $Server -InitializationScript $OTC002function_GenUseDay2 -ScriptBlock {OTC002_GenUse_Day2_ServerIssues -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
    }
}

elseif($COURSE -EQ "otc2" -AND $VMTYPE -EQ "general" -AND $COURSEDAY -EQ "3")
{
    foreach($Server in $SERVERS){
        Start-Job -Name $Server -InitializationScript $OTC002function_GenUseDay3 -ScriptBlock {OTC002_GenUse_Day3_ServerIssues -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
    }
}

elseif($COURSE -EQ "otc2" -AND $VMTYPE -EQ "exam" -AND $COURSEDAY -EQ "1")
{
    foreach($Server in $SERVERS){
        Start-Job -Name $Server -InitializationScript $OTC002function_ExamDay1 -ScriptBlock {OTC002_Exam_Day1_ServerIssues -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
    }
}

elseif($COURSE -EQ "otc2" -AND $VMTYPE -EQ "exam" -AND $COURSEDAY -EQ "2")
{
    foreach($Server in $SERVERS){
        Start-Job -Name $Server -InitializationScript $OTC002function_ExamDay2 -ScriptBlock {OTC002_Exam_Day2_ServerIssues -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
    }
}

elseif($COURSE -EQ "otc2" -AND $VMTYPE -EQ "exam" -AND $COURSEDAY -EQ "3")
{
    foreach($Server in $SERVERS){
        Start-Job -Name $Server -InitializationScript $OTC002function_ExamDay3 -ScriptBlock {OTC002_Exam_Day3_ServerIssues -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
    }
}
else 
{
    Write-Host "SERVERISSUES_Configuration.ps1: Execution of script skipped, Server Issues are only configured for OTC-002 and STC-002 courses."
}


# Waiting for each job to finish before moving on
foreach($Server in $SERVERS){
    Receive-Job -Name $Server -Wait -AutoRemoveJob -ErrorAction SilentlyContinue
}


# END Transcript for SERVERISSUES_Configuration.ps1 and exit the script
$DateEnd = Get-Date
($DateEnd - $DateStart).TotalSeconds
Stop-Transcript | Out-Null
