<#
.DESCRIPTION
    Description: This script is used to configure the GUSTAV camera simulator based on the course that is to be run.

    @Author: James Savage

    Last Updated : 21-08-2023
#>

Param(
    [Array]$SERVERS,
    [String]$VM_PASSWORD,
    [String]$COURSE
)

# As the servers are passed through and seen as a string the below will split the string based on the spaces to once again make it an array
$SERVERS = $SERVERS.Split(" ").Trim()

<#
# OPTIONAL: Use the below to check and test the params recieved from TOOL.ps1 are OK
foreach ($server in $SERVERS) {
    Write-Output "SERVER: $server" | Out-File -FilePath "C:\TOOL\TOOL_Logs\GUSTAVConfig_Params.txt" -Append
}
Write-Output "VM_PASSWORD: $VM_PASSWORD" | Out-File -FilePath "C:\TOOL\TOOL_Logs\GUSTAVConfig_Params.txt" -Append
Write-Output "COURSE: $COURSE" | Out-File -FilePath "C:\TOOL\TOOL_Logs\GUSTAVConfig_Params.txt" -Append
#>

# We add the $server to the trusted host in order to connect to it
Set-Item WSMan:\localhost\Client\TrustedHosts * -Force -ErrorAction SilentlyContinue
Restart-Service WinRM

# START Transcript for GUSTAV_Configuration.ps1
Add-Content -Path "C:\TOOL\TOOL_Logs\GUSTAV_Script_Log.txt" -Value "# Servers:$SERVERS #`n# VM PW:$VM_PASSWORD #`n# Course:$COURSE #"
Start-Transcript -Path "C:\TOOL\TOOL_Logs\GUSTAV_Script_Log.txt" -IncludeInvocationHeader -Append -Force | Out-Null
$DateStart = Get-Date



# Function inside a variable for the background jobs (PS processes)
$function_Stop = {
################################################################
# FUNCTION: Stop GUSTAV
################################################################
function stopGUSTAV {
    param ($Server, $VMPassword)

    # Create a New PSSession
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

            # Setting/Getting the process 'GUSTAV.exe'
            $processName = "GUSTAV"
            $process = Get-Process -Name $processName -ErrorAction SilentlyContinue

            # Check if the process is running
            if ($process) {
                $process | Stop-Process -Force
                Write-Host "$Server`: GUSTAV was Stopped OK"
            } else {
                Write-Host "$Server`: GUSTAV was not Running"
                continue
            }

    } -ArgumentList $Server

    Write-Host "$Server`: stopGUSTAV function executed"
    Remove-PSSession -Session $NewPSSession
}
}


# Function inside a variable for the background jobs (PS processes)
$function_Start = {
################################################################
# FUNCTION: Start GUSTAV
################################################################
function startGUSTAV {
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
 
            # Start process in the user's interactive session (GUI wont launch, this starts GUSTAV to run 'in the background')
            Invoke-WmiMethod -Path win32_process -Name create -ArgumentList "C:\Program Files (x86)\Genetec\GUSTAV\GUSTAV.exe"
        
            if (Get-Process -Name "GUSTAV" -ErrorAction SilentlyContinue) {
                Write-Host "$Server`: GUSTAV Started OK"
            } else {Write-Host "$Server`: Error starting GUSTAV"}

    } -ArgumentList $Server
    
    Write-Host "$Server`: startGUSTAV function executed"
    Remove-PSSession -Session $NewPSSession
}
}


# Function inside a variable for the background jobs (PS processes)
$function_OTCConfig = {
################################################################
# FUNCTION: Turn OFF Camera(s) based on OTC Course
################################################################
function setGUSTAVCameraStatus_OTC {
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
  
            # Read the GUSTAV_config.xml file content
            $xmlContent = Get-Content -Path "C:\ProgramData\Genetec_Inc\SimulatorFiles\GustavInstanceConfigurations\DefaultConfig\ConfigFiles\GUSTAV_config.xml" -Raw

            # Convert encoded entities (i.e., from encoded &lt;Unit&gt; to decoded <Unit>)
            $xmlContent = $xmlContent -replace '&lt;', '<' -replace '&gt;', '>'

            # Load the XML content into an XML object
            $xml = [xml]$xmlContent

            # Function to enable cameras (toggle the "Started" attribute of a specific unit from the default 'true' to 'true')
            function ToggleUnitStartedAttribute_ON($unitName) {
                $unit = $xml.SelectSingleNode("//Unit[@Name='$unitName']")
                if ($unit -ne $null) {
                    $currentStatus = $unit.GetAttribute("Started")
                    if ($currentStatus -eq "true") {
                        $unit.SetAttribute("Started", "true")
                    } elseif ($currentStatus -eq "false") {
                        $unit.SetAttribute("Started", "true")
                    } 
                }
            }
            
            # Function to disable cameras are enabled (toggle the "Started" attribute of a specific unit from the default 'true' to 'false')
            function ToggleUnitStartedAttribute_OFF($unitName) {
                $unit = $xml.SelectSingleNode("//Unit[@Name='$unitName']")
                if ($unit -ne $null) {
                    $currentStatus = $unit.GetAttribute("Started")
                    if ($currentStatus -eq "true") {
                        $unit.SetAttribute("Started", "false")
                    } elseif ($currentStatus -eq "false") {
                        $unit.SetAttribute("Started", "false")
                    } 
                }
            }

            # Each camera (unit) in GUSTAV is represented below (update the list if new cameras added or cameras removed)
            # Each camera listed below will be turned ON / OFF depending on the course
            ToggleUnitStartedAttribute_OFF "AE Main"
            ToggleUnitStartedAttribute_OFF "Axis Desk"
            ToggleUnitStartedAttribute_OFF "Case"
            ToggleUnitStartedAttribute_OFF "Dumpster"
            ToggleUnitStartedAttribute_OFF "Laptop"
            ToggleUnitStartedAttribute_OFF "Office Break-In"
            ToggleUnitStartedAttribute_OFF "Overhead"
            ToggleUnitStartedAttribute_OFF "Parking 1"
            ToggleUnitStartedAttribute_OFF "Parking 2"
            ToggleUnitStartedAttribute_OFF "Reception 4th"
            ToggleUnitStartedAttribute_OFF "Training Office"
            ToggleUnitStartedAttribute_ON "Student Camera" # ON for OTC
            ToggleUnitStartedAttribute_OFF "LPR Flex Reader"
            ToggleUnitStartedAttribute_OFF "Video Analytics"
            ToggleUnitStartedAttribute_OFF "Kiwi Overview"
            ToggleUnitStartedAttribute_OFF "Analytics PeopleCounting"
            ToggleUnitStartedAttribute_OFF "Analytics ObjectDetection"
            ToggleUnitStartedAttribute_OFF "Analytics Intrusion"
            ToggleUnitStartedAttribute_OFF "Analytics PrivacyProtector"
            ToggleUnitStartedAttribute_OFF "Gardeners Dynamic"
            ToggleUnitStartedAttribute_OFF "Server Room Dynamic"
            ToggleUnitStartedAttribute_OFF "Bridge Dynamic"
            ToggleUnitStartedAttribute_OFF "CAM1 - Main Ent. Lobby"
            ToggleUnitStartedAttribute_ON "CAM2 - Reception Area" # ON for OTC
            ToggleUnitStartedAttribute_ON "CAM3 - Staff Ent. Lobby" # ON for OTC
            ToggleUnitStartedAttribute_ON "CAM4 - Office Ent." # ON for OTC
            ToggleUnitStartedAttribute_OFF "CAM5 - Server Room"
            ToggleUnitStartedAttribute_OFF "CAM6 - Carpark Camera"

            # Replace < and > within the '<XmlInfo>' element to &lt; and &gt;
            $xmlInfo = $xml.SelectNodes("//XmlInfo")
            foreach ($info in $xmlInfo) {
                $info.InnerXml = $info.InnerXml -replace '<', '&lt;' -replace '>', '&gt;'
            }

            # Save the modified content back to the XML file with correct encoding and format
            $savePath = "C:\ProgramData\Genetec_Inc\SimulatorFiles\GustavInstanceConfigurations\DefaultConfig\ConfigFiles\GUSTAV_config.xml"
            $xml.Save($savePath)
    
    } -ArgumentList $Server
    
    Write-Host "$Server`: setGUSTAVCameraStatus function executed (OTC)"
    Remove-PSSession -Session $NewPSSession
}
}


# Function inside a variable for the background jobs (PS processes)
$function_STCConfig = {
################################################################
# FUNCTION: Turn OFF Camera(s) based on STC Course
################################################################
function setGUSTAVCameraStatus_STC {
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
  
            # Read the GUSTAV_config.xml file content
            $xmlContent = Get-Content -Path "C:\ProgramData\Genetec_Inc\SimulatorFiles\GustavInstanceConfigurations\DefaultConfig\ConfigFiles\GUSTAV_config.xml" -Raw

            # Convert encoded entities (i.e., from encoded &lt;Unit&gt; to decoded <Unit>)
            $xmlContent = $xmlContent -replace '&lt;', '<' -replace '&gt;', '>'

            # Load the XML content into an XML object
            $xml = [xml]$xmlContent

            # Function to enable cameras (toggle the "Started" attribute of a specific unit from the default 'true' to 'true')
            function ToggleUnitStartedAttribute_ON($unitName) {
                $unit = $xml.SelectSingleNode("//Unit[@Name='$unitName']")
                if ($unit -ne $null) {
                    $currentStatus = $unit.GetAttribute("Started")
                    if ($currentStatus -eq "true") {
                        $unit.SetAttribute("Started", "true")
                    } elseif ($currentStatus -eq "false") {
                        $unit.SetAttribute("Started", "true")
                    } 
                }
            }
            
            # Function to disable cameras (toggle the "Started" attribute of a specific unit from the default 'true' to 'false')
            function ToggleUnitStartedAttribute_OFF($unitName) {
                $unit = $xml.SelectSingleNode("//Unit[@Name='$unitName']")
                if ($unit -ne $null) {
                    $currentStatus = $unit.GetAttribute("Started")
                    if ($currentStatus -eq "true") {
                        $unit.SetAttribute("Started", "false")
                    } elseif ($currentStatus -eq "false") {
                        $unit.SetAttribute("Started", "false")
                    } 
                }
            }

            # Each camera (unit) in GUSTAV is represented below (update the list if new cameras added or cameras removed)
            # Each camera listed below will be turned ON / OFF depending on the course
            ToggleUnitStartedAttribute_OFF "AE Main"
            ToggleUnitStartedAttribute_OFF "Axis Desk"
            ToggleUnitStartedAttribute_OFF "Case"
            ToggleUnitStartedAttribute_OFF "Dumpster"
            ToggleUnitStartedAttribute_OFF "Laptop"
            ToggleUnitStartedAttribute_OFF "Office Break-In"
            ToggleUnitStartedAttribute_OFF "Overhead"
            ToggleUnitStartedAttribute_OFF "Parking 1"
            ToggleUnitStartedAttribute_OFF "Parking 2"
            ToggleUnitStartedAttribute_OFF "Reception 4th"
            ToggleUnitStartedAttribute_OFF "Training Office"
            ToggleUnitStartedAttribute_OFF "Student Camera" 
            ToggleUnitStartedAttribute_OFF "LPR Flex Reader"
            ToggleUnitStartedAttribute_OFF "Video Analytics"
            ToggleUnitStartedAttribute_OFF "Kiwi Overview"
            ToggleUnitStartedAttribute_OFF "Analytics PeopleCounting"
            ToggleUnitStartedAttribute_OFF "Analytics ObjectDetection"
            ToggleUnitStartedAttribute_OFF "Analytics Intrusion"
            ToggleUnitStartedAttribute_OFF "Analytics PrivacyProtector"
            ToggleUnitStartedAttribute_OFF "Gardeners Dynamic"
            ToggleUnitStartedAttribute_OFF "Server Room Dynamic"
            ToggleUnitStartedAttribute_OFF "Bridge Dynamic"
            ToggleUnitStartedAttribute_ON "CAM1 - Main Ent. Lobby" # ON for STC
            ToggleUnitStartedAttribute_ON "CAM2 - Reception Area" # ON for STC
            ToggleUnitStartedAttribute_ON "CAM3 - Staff Ent. Lobby" # ON for STC
            ToggleUnitStartedAttribute_ON "CAM4 - Office Ent." # ON for STC
            ToggleUnitStartedAttribute_ON "CAM5 - Server Room" # ON for STC 
            ToggleUnitStartedAttribute_OFF "CAM6 - Carpark Camera"

            # Replace < and > within the '<XmlInfo>' element to &lt; and &gt;
            $xmlInfo = $xml.SelectNodes("//XmlInfo")
            foreach ($info in $xmlInfo) {
                $info.InnerXml = $info.InnerXml -replace '<', '&lt;' -replace '>', '&gt;'
            }

            # Save the modified content back to the XML file with correct encoding and format
            $savePath = "C:\ProgramData\Genetec_Inc\SimulatorFiles\GustavInstanceConfigurations\DefaultConfig\ConfigFiles\GUSTAV_config.xml"
            $xml.Save($savePath)
    
    } -ArgumentList $Server
    
    Write-Host "$Server`: setGUSTAVCameraStatus function executed (STC)"
    Remove-PSSession -Session $NewPSSession
}
}


# Function inside a variable for the background jobs (PS processes)
$function_ETCConfig = {
################################################################
# FUNCTION: Turn OFF Camera(s) based on ETC Course
################################################################
function setGUSTAVCameraStatus_ETC {
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

    # If machine is an 'S100' turn ON relevant cameras
    if ($vmNumber -ge 100 -and $vmNumber -le 199) {
        # Script block to send commands to the remote machine(s)
        $Remote = Invoke-Command -Session $NewPSSession -ScriptBlock {
            param ($Server)
  
                # Read the GUSTAV_config.xml file content
                $xmlContent = Get-Content -Path "C:\ProgramData\Genetec_Inc\SimulatorFiles\GustavInstanceConfigurations\DefaultConfig\ConfigFiles\GUSTAV_config.xml" -Raw

                # Convert encoded entities (i.e., from encoded &lt;Unit&gt; to decoded <Unit>)
                $xmlContent = $xmlContent -replace '&lt;', '<' -replace '&gt;', '>'

                # Load the XML content into an XML object
                $xml = [xml]$xmlContent

                # Function to enable cameras (toggle the "Started" attribute of a specific unit from the default 'true' to 'true')
                function ToggleUnitStartedAttribute_ON($unitName) {
                    $unit = $xml.SelectSingleNode("//Unit[@Name='$unitName']")
                    if ($unit -ne $null) {
                        $currentStatus = $unit.GetAttribute("Started")
                        if ($currentStatus -eq "true") {
                            $unit.SetAttribute("Started", "true")
                        } elseif ($currentStatus -eq "false") {
                            $unit.SetAttribute("Started", "true")
                        } 
                    }
                }
            
                # Function to disable cameras (toggle the "Started" attribute of a specific unit from the default 'true' to 'false')
                function ToggleUnitStartedAttribute_OFF($unitName) {
                    $unit = $xml.SelectSingleNode("//Unit[@Name='$unitName']")
                    if ($unit -ne $null) {
                        $currentStatus = $unit.GetAttribute("Started")
                        if ($currentStatus -eq "true") {
                            $unit.SetAttribute("Started", "false")
                        } elseif ($currentStatus -eq "false") {
                            $unit.SetAttribute("Started", "false")
                        } 
                    }
                }

                # Each camera (unit) in GUSTAV is represented below (update the list if new cameras added or cameras removed)
                # Each camera listed below will be turned ON / OFF depending on the course
                ToggleUnitStartedAttribute_OFF "AE Main"
                ToggleUnitStartedAttribute_OFF "Axis Desk"
                ToggleUnitStartedAttribute_OFF "Case"
                ToggleUnitStartedAttribute_OFF "Dumpster"
                ToggleUnitStartedAttribute_OFF "Laptop"
                ToggleUnitStartedAttribute_OFF "Office Break-In"
                ToggleUnitStartedAttribute_OFF "Overhead"
                ToggleUnitStartedAttribute_OFF "Parking 1"
                ToggleUnitStartedAttribute_OFF "Parking 2"
                ToggleUnitStartedAttribute_OFF "Reception 4th"
                ToggleUnitStartedAttribute_OFF "Training Office"
                ToggleUnitStartedAttribute_OFF "Student Camera" 
                ToggleUnitStartedAttribute_OFF "LPR Flex Reader"
                ToggleUnitStartedAttribute_OFF "Video Analytics"
                ToggleUnitStartedAttribute_OFF "Kiwi Overview"
                ToggleUnitStartedAttribute_OFF "Analytics PeopleCounting"
                ToggleUnitStartedAttribute_OFF "Analytics ObjectDetection"
                ToggleUnitStartedAttribute_OFF "Analytics Intrusion"
                ToggleUnitStartedAttribute_OFF "Analytics PrivacyProtector"
                ToggleUnitStartedAttribute_OFF "Gardeners Dynamic"
                ToggleUnitStartedAttribute_OFF "Server Room Dynamic"
                ToggleUnitStartedAttribute_OFF "Bridge Dynamic"
                ToggleUnitStartedAttribute_ON "CAM1 - Main Ent. Lobby" # ON for ETC S100 Machines Only
                ToggleUnitStartedAttribute_ON "CAM2 - Reception Area" # ON for ETC S100 Machines Only
                ToggleUnitStartedAttribute_ON "CAM3 - Staff Ent. Lobby" # ON for ETC S100 Machines Only
                ToggleUnitStartedAttribute_ON "CAM4 - Office Ent." # ON for ETC S100 Machines Only
                ToggleUnitStartedAttribute_OFF "CAM5 - Server Room"  
                ToggleUnitStartedAttribute_OFF "CAM6 - Carpark Camera"

                # Replace < and > within the '<XmlInfo>' element to &lt; and &gt;
                $xmlInfo = $xml.SelectNodes("//XmlInfo")
                foreach ($info in $xmlInfo) {
                    $info.InnerXml = $info.InnerXml -replace '<', '&lt;' -replace '>', '&gt;'
                }

                # Save the modified content back to the XML file with correct encoding and format
                $savePath = "C:\ProgramData\Genetec_Inc\SimulatorFiles\GustavInstanceConfigurations\DefaultConfig\ConfigFiles\GUSTAV_config.xml"
                $xml.Save($savePath)
    
        } -ArgumentList $Server

        Write-Host "$Server`: setGUSTAVCameraStatus function executed (ETC)"
        Remove-PSSession -Session $NewPSSession
   }
   
    # If machine is an 'S200' turn OFF all cameras
    elseif ($vmNumber -ge 200 -and $vmNumber -le 250) {
        # Script block to send commands to the remote machine(s)
        $Remote = Invoke-Command -Session $NewPSSession -ScriptBlock {
            param ($Server)
  
                # Read the GUSTAV_config.xml file content
                $xmlContent = Get-Content -Path "C:\ProgramData\Genetec_Inc\SimulatorFiles\GustavInstanceConfigurations\DefaultConfig\ConfigFiles\GUSTAV_config.xml" -Raw

                # Convert encoded entities (i.e., from encoded &lt;Unit&gt; to decoded <Unit>)
                $xmlContent = $xmlContent -replace '&lt;', '<' -replace '&gt;', '>'

                # Load the XML content into an XML object
                $xml = [xml]$xmlContent

                # Function enable cameras (toggle the "Started" attribute of a specific unit from the default 'true' to 'true')
                function ToggleUnitStartedAttribute_ON($unitName) {
                    $unit = $xml.SelectSingleNode("//Unit[@Name='$unitName']")
                    if ($unit -ne $null) {
                        $currentStatus = $unit.GetAttribute("Started")
                        if ($currentStatus -eq "true") {
                            $unit.SetAttribute("Started", "true")
                        } elseif ($currentStatus -eq "false") {
                            $unit.SetAttribute("Started", "true")
                        } 
                    }
                }
            
                # Function to disable cameras (toggle the "Started" attribute of a specific unit from the default 'true' to 'false')
                function ToggleUnitStartedAttribute_OFF($unitName) {
                    $unit = $xml.SelectSingleNode("//Unit[@Name='$unitName']")
                    if ($unit -ne $null) {
                        $currentStatus = $unit.GetAttribute("Started")
                        if ($currentStatus -eq "true") {
                            $unit.SetAttribute("Started", "false")
                        } elseif ($currentStatus -eq "false") {
                            $unit.SetAttribute("Started", "false")
                        } 
                    }
                }

                # Each camera (unit) in GUSTAV is represented below (update the list if new cameras added or cameras removed)
                # Each camera listed below will be turned ON / OFF depending on the course
                ToggleUnitStartedAttribute_OFF "AE Main"
                ToggleUnitStartedAttribute_OFF "Axis Desk"
                ToggleUnitStartedAttribute_OFF "Case"
                ToggleUnitStartedAttribute_OFF "Dumpster"
                ToggleUnitStartedAttribute_OFF "Laptop"
                ToggleUnitStartedAttribute_OFF "Office Break-In"
                ToggleUnitStartedAttribute_OFF "Overhead"
                ToggleUnitStartedAttribute_OFF "Parking 1"
                ToggleUnitStartedAttribute_OFF "Parking 2"
                ToggleUnitStartedAttribute_OFF "Reception 4th"
                ToggleUnitStartedAttribute_OFF "Training Office"
                ToggleUnitStartedAttribute_OFF "Student Camera" 
                ToggleUnitStartedAttribute_OFF "LPR Flex Reader"
                ToggleUnitStartedAttribute_OFF "Video Analytics"
                ToggleUnitStartedAttribute_OFF "Kiwi Overview"
                ToggleUnitStartedAttribute_OFF "Analytics PeopleCounting"
                ToggleUnitStartedAttribute_OFF "Analytics ObjectDetection"
                ToggleUnitStartedAttribute_OFF "Analytics Intrusion"
                ToggleUnitStartedAttribute_OFF "Analytics PrivacyProtector"
                ToggleUnitStartedAttribute_OFF "Gardeners Dynamic"
                ToggleUnitStartedAttribute_OFF "Server Room Dynamic"
                ToggleUnitStartedAttribute_OFF "Bridge Dynamic"
                ToggleUnitStartedAttribute_OFF "CAM1 - Main Ent. Lobby"
                ToggleUnitStartedAttribute_OFF "CAM2 - Reception Area" 
                ToggleUnitStartedAttribute_OFF "CAM3 - Staff Ent. Lobby" 
                ToggleUnitStartedAttribute_OFF "CAM4 - Office Ent." 
                ToggleUnitStartedAttribute_OFF "CAM5 - Server Room"  
                ToggleUnitStartedAttribute_OFF "CAM6 - Carpark Camera"

                # Replace < and > within the '<XmlInfo>' element to &lt; and &gt;
                $xmlInfo = $xml.SelectNodes("//XmlInfo")
                foreach ($info in $xmlInfo) {
                    $info.InnerXml = $info.InnerXml -replace '<', '&lt;' -replace '>', '&gt;'
                }

                # Save the modified content back to the XML file with correct encoding and format
                $savePath = "C:\ProgramData\Genetec_Inc\SimulatorFiles\GustavInstanceConfigurations\DefaultConfig\ConfigFiles\GUSTAV_config.xml"
                $xml.Save($savePath)
    
        } -ArgumentList $Server

        Write-Host "$Server`: setGUSTAVCameraStatus function executed (ETC)"
        Remove-PSSession -Session $NewPSSession
   }
   
    # If machine is not 'S100' or 'S200', bail!
    else {
       Write-Host "Ignoring $server': VM number $vmNumber is not within the specified ranges."
   }
}
}


# Function inside a variable for the background jobs (PS processes)
$function_MCConfig = {
################################################################
# FUNCTION: Turn OFF Camera(s) based on MC-ACT Course
################################################################
function setGUSTAVCameraStatus_MC {
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
  
            # Read the GUSTAV_config.xml file content
            $xmlContent = Get-Content -Path "C:\ProgramData\Genetec_Inc\SimulatorFiles\GustavInstanceConfigurations\DefaultConfig\ConfigFiles\GUSTAV_config.xml" -Raw

            # Convert encoded entities (i.e., from encoded &lt;Unit&gt; to decoded <Unit>)
            $xmlContent = $xmlContent -replace '&lt;', '<' -replace '&gt;', '>'

            # Load the XML content into an XML object
            $xml = [xml]$xmlContent

            # Function to enable cameras (toggle the "Started" attribute of a specific unit from the default 'true' to 'true')
            function ToggleUnitStartedAttribute_ON($unitName) {
                $unit = $xml.SelectSingleNode("//Unit[@Name='$unitName']")
                if ($unit -ne $null) {
                    $currentStatus = $unit.GetAttribute("Started")
                    if ($currentStatus -eq "true") {
                        $unit.SetAttribute("Started", "true")
                    } elseif ($currentStatus -eq "false") {
                        $unit.SetAttribute("Started", "true")
                    } 
                }
            }
            
            # Function to disable cameras (toggle the "Started" attribute of a specific unit from the default 'true' to 'false')
            function ToggleUnitStartedAttribute_OFF($unitName) {
                $unit = $xml.SelectSingleNode("//Unit[@Name='$unitName']")
                if ($unit -ne $null) {
                    $currentStatus = $unit.GetAttribute("Started")
                    if ($currentStatus -eq "true") {
                        $unit.SetAttribute("Started", "false")
                    } elseif ($currentStatus -eq "false") {
                        $unit.SetAttribute("Started", "false")
                    } 
                }
            }

            # Each camera (unit) in GUSTAV is represented below (update the list if new cameras added or cameras removed)
            # Each camera listed below will be turned ON / OFF depending on the course
            ToggleUnitStartedAttribute_OFF "AE Main"
            ToggleUnitStartedAttribute_OFF "Axis Desk"
            ToggleUnitStartedAttribute_OFF "Case"
            ToggleUnitStartedAttribute_OFF "Dumpster"
            ToggleUnitStartedAttribute_OFF "Laptop"
            ToggleUnitStartedAttribute_OFF "Office Break-In"
            ToggleUnitStartedAttribute_OFF "Overhead"
            ToggleUnitStartedAttribute_OFF "Parking 1"
            ToggleUnitStartedAttribute_OFF "Parking 2"
            ToggleUnitStartedAttribute_OFF "Reception 4th"
            ToggleUnitStartedAttribute_OFF "Training Office"
            ToggleUnitStartedAttribute_OFF "Student Camera" 
            ToggleUnitStartedAttribute_OFF "LPR Flex Reader"
            ToggleUnitStartedAttribute_OFF "Video Analytics"
            ToggleUnitStartedAttribute_OFF "Kiwi Overview"
            ToggleUnitStartedAttribute_OFF "Analytics PeopleCounting"
            ToggleUnitStartedAttribute_OFF "Analytics ObjectDetection"
            ToggleUnitStartedAttribute_OFF "Analytics Intrusion"
            ToggleUnitStartedAttribute_OFF "Analytics PrivacyProtector"
            ToggleUnitStartedAttribute_OFF "Gardeners Dynamic"
            ToggleUnitStartedAttribute_OFF "Server Room Dynamic"
            ToggleUnitStartedAttribute_OFF "Bridge Dynamic"
            ToggleUnitStartedAttribute_ON "CAM1 - Main Ent. Lobby" # ON for MC-ACT
            ToggleUnitStartedAttribute_OFF "CAM2 - Reception Area" 
            ToggleUnitStartedAttribute_OFF "CAM3 - Staff Ent. Lobby" 
            ToggleUnitStartedAttribute_OFF "CAM4 - Office Ent." 
            ToggleUnitStartedAttribute_OFF "CAM5 - Server Room"  
            ToggleUnitStartedAttribute_ON "CAM6 - Carpark Camera" # ON for MC-ACT

            # Replace < and > within the '<XmlInfo>' element to &lt; and &gt;
            $xmlInfo = $xml.SelectNodes("//XmlInfo")
            foreach ($info in $xmlInfo) {
                $info.InnerXml = $info.InnerXml -replace '<', '&lt;' -replace '>', '&gt;'
            }

            # Save the modified content back to the XML file with correct encoding and format
            $savePath = "C:\ProgramData\Genetec_Inc\SimulatorFiles\GustavInstanceConfigurations\DefaultConfig\ConfigFiles\GUSTAV_config.xml"
            $xml.Save($savePath)
    
    } -ArgumentList $Server
    
    Write-Host "$Server`: setGUSTAVCameraStatus function executed (MC-ACT)"
    Remove-PSSession -Session $NewPSSession
}
}


# Function inside a variable for the background jobs (PS processes)
$function_OtherConfig = {
################################################################
# FUNCTION: Turn OFF Camera(s) based on Other Course
################################################################
function setGUSTAVCameraStatus_Other {
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
  
            # Read the GUSTAV_config.xml file content
            $xmlContent = Get-Content -Path "C:\ProgramData\Genetec_Inc\SimulatorFiles\GustavInstanceConfigurations\DefaultConfig\ConfigFiles\GUSTAV_config.xml" -Raw

            # Convert encoded entities (i.e., from encoded &lt;Unit&gt; to decoded <Unit>)
            $xmlContent = $xmlContent -replace '&lt;', '<' -replace '&gt;', '>'

            # Load the XML content into an XML object
            $xml = [xml]$xmlContent
            
            # Function ensure Cameras are Disabled (toggle the "Started" attribute of a specific unit from the default 'true' to 'false')
            function ToggleUnitStartedAttribute_OFF($unitName) {
                $unit = $xml.SelectSingleNode("//Unit[@Name='$unitName']")
                if ($unit -ne $null) {
                    $currentStatus = $unit.GetAttribute("Started")
                    if ($currentStatus -eq "true") {
                        $unit.SetAttribute("Started", "false")
                    } elseif ($currentStatus -eq "false") {
                        $unit.SetAttribute("Started", "false")
                    } 
                }
            }

            # Each camera (unit) in GUSTAV is represented below (update the list if new cameras added or cameras removed)
            # Each camera listed below will be turned ON / OFF depending on the course
            ToggleUnitStartedAttribute_OFF "AE Main"
            ToggleUnitStartedAttribute_OFF "Axis Desk"
            ToggleUnitStartedAttribute_OFF "Case"
            ToggleUnitStartedAttribute_OFF "Dumpster"
            ToggleUnitStartedAttribute_OFF "Laptop"
            ToggleUnitStartedAttribute_OFF "Office Break-In"
            ToggleUnitStartedAttribute_OFF "Overhead"
            ToggleUnitStartedAttribute_OFF "Parking 1"
            ToggleUnitStartedAttribute_OFF "Parking 2"
            ToggleUnitStartedAttribute_OFF "Reception 4th"
            ToggleUnitStartedAttribute_OFF "Training Office"
            ToggleUnitStartedAttribute_OFF "Student Camera" 
            ToggleUnitStartedAttribute_OFF "LPR Flex Reader"
            ToggleUnitStartedAttribute_OFF "Video Analytics"
            ToggleUnitStartedAttribute_OFF "Kiwi Overview"
            ToggleUnitStartedAttribute_OFF "Analytics PeopleCounting"
            ToggleUnitStartedAttribute_OFF "Analytics ObjectDetection"
            ToggleUnitStartedAttribute_OFF "Analytics Intrusion"
            ToggleUnitStartedAttribute_OFF "Analytics PrivacyProtector"
            ToggleUnitStartedAttribute_OFF "Gardeners Dynamic"
            ToggleUnitStartedAttribute_OFF "Server Room Dynamic"
            ToggleUnitStartedAttribute_OFF "Bridge Dynamic"
            ToggleUnitStartedAttribute_OFF "CAM1 - Main Ent. Lobby" 
            ToggleUnitStartedAttribute_OFF "CAM2 - Reception Area" 
            ToggleUnitStartedAttribute_OFF "CAM3 - Staff Ent. Lobby" 
            ToggleUnitStartedAttribute_OFF "CAM4 - Office Ent." 
            ToggleUnitStartedAttribute_OFF "CAM5 - Server Room"  
            ToggleUnitStartedAttribute_OFF "CAM6 - Carpark Camera"

            # Replace < and > within the '<XmlInfo>' element to &lt; and &gt;
            $xmlInfo = $xml.SelectNodes("//XmlInfo")
            foreach ($info in $xmlInfo) {
                $info.InnerXml = $info.InnerXml -replace '<', '&lt;' -replace '>', '&gt;'
            }

            # Save the modified content back to the XML file with correct encoding and format
            $savePath = "C:\ProgramData\Genetec_Inc\SimulatorFiles\GustavInstanceConfigurations\DefaultConfig\ConfigFiles\GUSTAV_config.xml"
            $xml.Save($savePath)
    
    } -ArgumentList $Server
    
    Write-Host "$Server`: setGUSTAVCameraStatus function executed (Other)"
    Remove-PSSession -Session $NewPSSession
}
}



################################################################
# Script Execution
################################################################
if($COURSE -EQ "otc")
{
    foreach($Server in $SERVERS){
        Start-Job -Name $Server -InitializationScript $function_Stop -ScriptBlock {stopGUSTAV -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
        Start-Job -Name $Server -InitializationScript $function_OTCConfig -ScriptBlock {setGUSTAVCameraStatus_OTC -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
        Start-Job -Name $Server -InitializationScript $function_Start -ScriptBlock {startGUSTAV -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
    }
}

elseif($COURSE -EQ "stc")
{
    foreach($Server in $SERVERS){
        Start-Job -Name $Server -InitializationScript $function_Stop -ScriptBlock {stopGUSTAV -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
        Start-Job -Name $Server -InitializationScript $function_STCConfig -ScriptBlock {setGUSTAVCameraStatus_STC -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
        Start-Job -Name $Server -InitializationScript $function_Start -ScriptBlock {startGUSTAV -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
    }
}

elseif($COURSE -EQ "etc")
{
    foreach($Server in $SERVERS){
        Start-Job -Name $Server -InitializationScript $function_Stop -ScriptBlock {stopGUSTAV -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
        Start-Job -Name $Server -InitializationScript $function_ETCConfig -ScriptBlock {setGUSTAVCameraStatus_ETC -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
        Start-Job -Name $Server -InitializationScript $function_Start -ScriptBlock {startGUSTAV -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
    }
}

elseif($COURSE -EQ "mc")
{
    foreach($Server in $SERVERS){
        Start-Job -Name $Server -InitializationScript $function_Stop -ScriptBlock {stopGUSTAV -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
        Start-Job -Name $Server -InitializationScript $function_MCConfig -ScriptBlock {setGUSTAVCameraStatus_MC -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
        Start-Job -Name $Server -InitializationScript $function_Start -ScriptBlock {startGUSTAV -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
    }
}

else # for courses 'other' i.e., 'otc2', 'stc2'
{
    foreach($Server in $SERVERS){
        Start-Job -Name $Server -InitializationScript $function_Stop -ScriptBlock {stopGUSTAV -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
        Start-Job -Name $Server -InitializationScript $function_OtherConfig -ScriptBlock {setGUSTAVCameraStatus_Other -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
        Start-Job -Name $Server -InitializationScript $function_Start -ScriptBlock {startGUSTAV -Server $args[0] -VMPassword $args[1]} -ArgumentList @($Server, $VM_PASSWORD)
    }
}


# Waiting for each job to finish before moving on
foreach($Server in $SERVERS){
    Receive-Job -Name $Server -Wait -AutoRemoveJob -ErrorAction SilentlyContinue
}


# END Transcript for GUSTAV_Configuration.ps1 and exit the script
$DateEnd = Get-Date
($DateEnd - $DateStart).TotalSeconds
Stop-Transcript | Out-Null