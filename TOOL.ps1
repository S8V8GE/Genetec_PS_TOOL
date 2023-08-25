<#
    Description:   A customised T_O_O_L (Toolkit for Operational Optimization and Learning) to setup VM's based on the course being delivered, and also to grade exam servers for OTC-001, STC-001, and ETC-001 (no need to auto grade OTC-002, STC-002, CID-002, MC-ACT-001 etc. as overall course performace inc. troubleshooting servers determines the grade.)  

    @Author:       James Savage

    Last Updated : 23-08-2023
#>

Clear-Host

# Constants for course setup functions
$GUSTAV_SCRIPT_PATH         = "$PSScriptRoot\TOOL_Functions\1_Course_Setup\GUSTAV_Configuration.ps1"
$FIREWALL_SCRIPT_PATH       = "$PSScriptRoot\TOOL_Functions\1_Course_Setup\FIREWALL_Configuration.ps1"
$DESKTOP_SCRIPT_PATH        = "$PSScriptRoot\TOOL_Functions\1_Course_Setup\DESKTOP_Configuration.ps1"
$OSTCEXAM_SCRIPT_PATH       = "$PSScriptRoot\TOOL_Functions\1_Course_Setup\OSTCEXAM_Configuration.ps1"
$DATABASE_SCRIPT_PATH       = "$PSScriptRoot\TOOL_Functions\1_Course_Setup\DATABASE_Configuration.ps1"
$SERVERISSUES_SCRIPT_PATH   = "$PSScriptRoot\TOOL_Functions\1_Course_Setup\SERVERISSUES_Configuration.ps1" 


$TOOL_LOG_PATH            = "$PSScriptRoot\TOOL_Logs\Tool_info.txt"



#############################################################################################################################
#############################################################################################################################
# FUNCTIONS: for creating an array of VMs and thier DNS names, plus testing the connection of each VM
#############################################################################################################################

# Function that will return all the VM numbers sorted (100, 101, 102, 103 ... etc.).
# For ETC2 and OTC2, the numbers returned will be sorted in groups (100, 200, 101, 201 ... etc.).
function vmArrayCreator {
    param ($ArraySplit, $Course)

    # Empty arrays;$arrayofVmNumber is for 
    [Array]$arrayOfVmNumber = $null
    [Array]$combinedArray   = $null

    # We split the $ArraySplit into multiple small strings containing a Single VM and/or a Range of VMs
    $commaSplitArray = $ArraySplit.Split(',').Trim()

    foreach ($item in $commaSplitArray){
        # If item contains '-' then we have a range of VM's, the below creates the range using the range operator ..
        if($item -match '-'){
            $range = $item.Split('-').Trim()
            $arrayOfVmNumber += $range[0] .. $range[1]}
        # Else we have a single VM, so we append the single VM number to the array
        else{
            $arrayOfVmNumber += [int]$item}
    }

    # Sort the array numerically i.e., 101,102,103 etc.
    $arrayOfSortedVmNumbers = $arrayOfVmNumber | Sort-Object

    # If course is ETC ot OTC2, a second array of VMs must be created with their number +100 from original VM numbers
    if ($Course -eq 'etc' -or $Course -eq 'otc2') {
        $arrayOfExpansionNumber = $arrayOfSortedVmNumbers | ForEach-Object {$_ + 100}
        # We combined the 2 arrays into 1 sorted by set of VMs
        for($i=0; $i -lt $arrayOfSortedVmNumbers.Count; $i++){
            $combinedArray += $arrayOfSortedVmNumbers[$i]
            $combinedArray += $arrayOfExpansionNumber[$i]
        }
        return $combinedArray
    } else {
        return $arrayOfSortedVmNumbers
    }
}

# Creates an array of the DNS names of the VMs
function Get_VM_Name {
    param ($VM_prefix, $VM_number_string, $Course)
    
    $VM_number = vmArrayCreator -ArraySplit $VM_number_string -Course $Course

    # Initialize $vmArray as an array before using it
    [Array]$vmArray = @()

    foreach ($VM in $VM_number){
            $vmArray += $VM_prefix + $VM
    }

    return $vmArray
}

# Functions (x2) to test the availiability of the VM's in the array (connection tests)
function Test_VMs {
    param ($VM_array)

    $unreachableVMs = @()

    foreach ($VM in $VM_array){
        if (!(Test-Connection -ComputerName $VM -Count 1 -Quiet)){
            $unreachableVMs += $VM
            Write-Host "$VM`: Ping unsuccessful" -ForegroundColor Red
        } 
    }

    return $unreachableVMs
}

function Check_VM_Availability {
    param ($VM_array)

    $unreachableVMs = Test_VMs -VM_array $VM_array

    if ($unreachableVMs.Count -gt 0) {
        Write-Host "Unreachable VMs: $($unreachableVMs -join ', ')`n"
        Write-Host "Cancelling operation... please make sure all VMs are reachable, or when requested to enter an array skip the above machines using a comma." -ForegroundColor Red
        Read-Host  "Press enter to continue.."
        # If any of the VM's are unreachable we let the user know the VM's we can't connect to and go back to the main menu!
        mainMenu
    }
    # If all VMs are reachable go back to the function that called this one!
    else { return  }
}

#############################################################################################################################
#############################################################################################################################
# FUNCTION: for setting the Desktop View/settings of each VM
#############################################################################################################################
function DesktopConfiguration {
    param ($ArrayofVMs, $Password)

    # STEP 1: Start the process for altering the Desktop configuration
    $Script:DesktopConfig_Process = Start-Process -FilePath 'powershell' -Verb RunAs -ArgumentList "-File $DESKTOP_SCRIPT_PATH `
    -VM_PASSWORD `"$Password`" `
    -SERVERS `"$ArrayofVMs`"" -PassThru -WindowStyle Hidden
    
    # Wait for the GUSTAV_Configuration.ps1 process to complete before proceeding
    $Script:DesktopConfig_Process | Wait-Process
    
    Write_Info_TOOL "DESKTOP_Configuration.ps1 completed."
}


#############################################################################################################################
#############################################################################################################################
# FUNCTION: for setting the GUSTAV settings of each VM
#############################################################################################################################
function GUSTAVConfiguration {
    param ($ArrayofVMs, $Password, $Course)

    # STEP 1: Start the process for altering the GUSTAV configuration
    $Script:GUSTAVConfig_Process = Start-Process -FilePath 'powershell' -Verb RunAs -ArgumentList "-File $GUSTAV_SCRIPT_PATH `
    -COURSE `"$Course`" `
    -VM_PASSWORD `"$Password`" `
    -SERVERS `"$ArrayofVMs`"" -PassThru -WindowStyle Hidden
    
    # Wait for the GUSTAV_Configuration.ps1 process to complete before proceeding
    $Script:GUSTAVConfig_Process | Wait-Process
    
    Write_Info_TOOL "GUSTAV_Configuration.ps1 completed."
}


#############################################################################################################################
#############################################################################################################################
# FUNCTION: for setting the Firewall settings of each VM
#############################################################################################################################
function FirewallConfiguration {
    param ($ArrayofVMs, $Password, $Course, $Day, $VMType)

    # STEP 1: Start the process for altering the Firewall configuration
    $Script:FirewallConfig_Process = Start-Process -FilePath 'powershell' -Verb RunAs -ArgumentList "-File $FIREWALL_SCRIPT_PATH `
    -COURSE `"$Course`" `
    -COURSEDAY `"$Day`" `
    -VMTYPE `"$VMType`" `
    -VM_PASSWORD `"$Password`" `
    -SERVERS `"$ArrayofVMs`"" -PassThru -WindowStyle Hidden
    
    # Wait for the GUSTAV_Configuration.ps1 process to complete before proceeding
    $Script:FirewallConfig_Process | Wait-Process
    
    Write_Info_TOOL "FIREWALL_Configuration.ps1 completed."
}


#############################################################################################################################
#############################################################################################################################
# FUNCTION: for preparing the OTC-001 and STC-001 server(s) for the exam
#############################################################################################################################
function OSTCExamConfiguration {
    param ($ArrayofVMs, $Password)

    # STEP 1: Start the process for altering the Firewall configuration
    $Script:OSTCExamConfig_Process = Start-Process -FilePath 'powershell' -Verb RunAs -ArgumentList "-File $OSTCEXAM_SCRIPT_PATH `
    -VM_PASSWORD `"$Password`" `
    -SERVERS `"$ArrayofVMs`"" -PassThru -WindowStyle Hidden
    
    # Wait for the GUSTAV_Configuration.ps1 process to complete before proceeding
    $Script:OSTCExamConfig_Process | Wait-Process
    
    Write_Info_TOOL "OSTCEXAM_Configuration.ps1 completed."
}


#############################################################################################################################
#############################################################################################################################
# FUNCTION: for preparing the MC-ACT-001, and STC-002 General Use and Troubleshooting server(s) by restoring the relevant DB
#############################################################################################################################
function DatabaseConfiguration {
    param ($ArrayofVMs, $Password, $Course)

    # STEP 1: Start the process for altering the Firewall configuration
    $Script:DatabaseConfig_Process = Start-Process -FilePath 'powershell' -Verb RunAs -ArgumentList "-File $DATABASE_SCRIPT_PATH `
    -VM_PASSWORD `"$Password`" `
    -COURSE `"$Course`" `
    -VMTYPE `"$VMType`" `
    -SERVERS `"$ArrayofVMs`"" -PassThru -WindowStyle Hidden
    
    # Wait for the GUSTAV_Configuration.ps1 process to complete before proceeding
    $Script:DatabaseConfig_Process | Wait-Process
    
    Write_Info_TOOL "DATABASE_Configuration.ps1 completed."
}


#############################################################################################################################
#############################################################################################################################
# FUNCTION: for preparing the SC-OTC-002, and STC-002 General Use and Troubleshooting server(s) by creating 'server issues'
#############################################################################################################################
function ServerIssuesConfiguration {
    param ($ArrayofVMs, $Password, $Course, $Day, $VMType)

    # STEP 1: Start the process for altering the Firewall configuration
    $Script:ServerIssuesConfig_Process = Start-Process -FilePath 'powershell' -Verb RunAs -ArgumentList "-File $SERVERISSUES_SCRIPT_PATH `
    -COURSE `"$Course`" `
    -COURSEDAY `"$Day`" `
    -VMTYPE `"$VMType`" `
    -VM_PASSWORD `"$Password`" `
    -SERVERS `"$ArrayofVMs`"" -PassThru -WindowStyle Hidden
    
    # Wait for the GUSTAV_Configuration.ps1 process to complete before proceeding
    $Script:ServerIssuesConfig_Process | Wait-Process
    
    Write_Info_TOOL "SERVERISSUES_Configuration.ps1 completed."
}


##################################################################################
# FUNCTION: Write results in a .txt file
##################################################################################
function Write_Info_TOOL($Value) {
    $Global:mutex = New-Object System.Threading.Mutex($false, "GUSTAV_Mutex")
    $mutex.WaitOne()
    Add-Content -Path $TOOL_LOG_PATH -Value $Value
    $mutex.ReleaseMutex()
}



<#################################################################################
##################################################################################
                              Console 'GUI'
#################################################################################>

# Menu 1 function - Course Setup
function menuOne {

    # Variables to control the below 'while' loops - I have a feeling WPF will be easier than this logic...
    # used for selecting the correct course - valid course types = 'otc', 'stc', 'etc', 'otc2', 'stc2', 'mc', 'other'
    $trueOne = $true 

    # used for creating an array of VMs
    $trueTwo = $true 

    # used for selecting the correct type of server - Types are 'general', 'exam', 'trouble'
    $trueThree = $true 

    # used for selecting the correct day - '1' and '2' for all courses except 'otc2' which also has day '3'
    $trueFour = $true 

    # Function starting point...
    Write-Host "`n[1] Course Setup" -ForegroundColor Green

#---### STEP 1 - Select the correct course - valid course types = 'otc', 'stc', 'etc', 'otc2', 'stc2', 'mc'
    While ($trueOne) {
    Write-Host "`nSelect the course you wish to setup for:" -ForegroundColor Cyan
    Write-Host "   [1] OTC" 
    Write-Host "   [2] STC" 
    Write-Host "   [3] ETC"
    Write-Host "   [4] OTC2"
    Write-Host "   [5] STC2"
    Write-Host "   [6] MC"

    # Prompt the user for their choice
    $userChoice1 = Read-Host "`nEnter the number of your choice (1-6)"

        # Use a switch statement to handle different choices
        switch ($userChoice1) {
            1 {
                # [1] OTC selected
                $courseType = 'otc'
                $trueOne = $false
                break  # Move onto next step
            }
            2 {
                # [2] STC selected
                $courseType = 'stc'
                $trueOne = $false
                break  # Move onto next step
            }
            3 {
                # [3] ETC selected
                $courseType = 'etc'
                $trueOne = $false
                break  # Move onto next step
            }
            4 {
                # [4] OTC2 selected
                $courseType = 'otc2'
                $trueOne = $false
                break  # Move onto next step
            }
            5 {
                # [5] STC2 selected
                $courseType = 'stc2'
                $trueOne = $false
                break  # Move onto next step
            }
            6 {
                # [6] OTHER selected
                $courseType = 'mc'
                $trueOne = $false
                break  # Move onto next step
            }
            default {
                # Handle invalid input
                Write-Host "Invalid choice. Please select a number between 1 and 6.`n" -ForegroundColor Red
                continue
            }
        }
    }
#---# End of Step 1 -------------------------


#---# STEP 2 - create the array of VMs   
    While ($trueTwo) { 
        Write-Host "`nEnter the VM Range (type 'help' for more information)" -ForegroundColor Cyan  
        $vmNumbers = Read-Host "VM Range"

        if ($vmNumbers -eq 'help') {
            Write-Host "Help: Enter VM numbers like so; `n   --> for a single VM: <VM Number> i.e., 100`n   --> for a range of VMs: <VM Start Number>-<VM End Number> i.e., 101-110`n   --> for a mix of VMs, any combination of: <VM Number>, <VM Start Number>-<VM End Number>, <VM Number> i.e., 101, 103-108, 110" -ForegroundColor Green
            continue
        }

        # Validate the input using the new regular expression pattern
        $validInputPattern = '^(\d+(-\d+)?(,|$)\s*)+$'
        if ($vmNumbers -notmatch $validInputPattern) {
            Write-Host "Invalid input format. Please enter a valid VM range or type 'help' for more information." -ForegroundColor Red
            continue
        }

        # Call the function to get VM names based on the input range
        $vmArray = Get_VM_Name 'GTRAIN-JS-S' $vmNumbers $courseType
        
        # break out of this loop if a valid range is provided and the function returns the VM names
        $trueTwo = $false
        break
    }
#---# End of Step 2 -------------------------


#---# STEP 3 - get the VM password
    Write-Host "`nEnter the VM password, ensure this is correct!" -ForegroundColor Cyan   
    $vmPassword = Read-Host 'VM Password'
#---# End of Step 3 -------------------------
    
    
#---# STEP 4 - get the correct 'type of server' - Types are 'general', 'exam', 'trouble'   
    While ($trueThree) {

        # 'stc2' course has a 'general', 'exam', and 'trouble' servers
        if ($courseType -eq 'stc2') {
            
            Write-Host "`nSelect the type of server you wish to setup for the SC-STC-002 course:" -ForegroundColor Cyan
            Write-Host "   [1] GENERAL USE" 
            Write-Host "   [2] EXAM USE" 
            Write-Host "   [3] TROUBLESHOOTING USE"
            
            # Prompt the user for their choice
            $userChoice2 = Read-Host "`nEnter the number of your choice (1-3)"

                # Use a switch statement to handle different choices
                switch ($userChoice2) {
                    1 {
                        # [1] GENERAL USE selected
                        $vmType = 'general'
                        $trueThree = $false
                        break  # Move onto next step
                    }
                    2 {
                        # [2] EXAM USE selected
                        $vmType = 'exam'
                        $trueThree = $false
                        break  # Move onto next step
                    }
                    3 {
                        # [3] TROUBLESHOOTING USE selected
                        $vmType = 'trouble'
                        $trueThree = $false
                        break  # Move onto next step
                    }
                    default {
                        # Handle invalid input
                        Write-Host "Invalid choice. Please select a number between 1 and 3.`n" -ForegroundColor Red
                        continue
                    }
                }
            }

        # 'otc2' course has a 'general' and 'exam' servers
        elseif ($courseType -eq 'otc2') {
            
            Write-Host "`nSelect the type of server you wish to setup for the SC-OTC-002 course:" -ForegroundColor Cyan
            Write-Host "   [1] GENERAL USE" 
            Write-Host "   [2] EXAM USE" 
            
            # Prompt the user for their choice
            $userChoice2 = Read-Host "`nEnter the number of your choice (1-2)"

                # Use a switch statement to handle different choices
                switch ($userChoice2) {
                    1 {
                        # [1] GENERAL USE selected
                        $vmType = 'general'
                        $trueThree = $false
                        break  # Move onto next step
                    }
                    2 {
                        # [2] EXAM USE selected
                        $vmType = 'exam'
                        $trueThree = $false
                        break  # Move onto next step
                    }
                    default {
                        # Handle invalid input
                        Write-Host "Invalid choice. Please select a number between 1 and 3.`n" -ForegroundColor Red
                        continue
                    }
                }
            }
        else { 
            Start-Sleep -Seconds 1
            Write-Host "`nFor OTC-001, STC-001, ETC-001 and MC-ACT-001 course, vmType is set to 'general'`n" -ForegroundColor Cyan
            $vmType = 'general' 
            $trueThree = $false
            break  # Move onto next step
        }
    }    
#---# End of Step 4 -------------------------    
    
    
#---# STEP 5 - get the correct 'course day' - '1' and '2' for all courses except 'otc2' which also has day '3'    
    While ($trueFour) {

        # 'otc2' has day '1', '2', and '3' for both 'general' and 'exam' VM Types
        if ($courseType -eq 'otc2') {
            
            Write-Host "`nSelect the correct SC-OTC-002 training 'day':" -ForegroundColor Cyan
            Write-Host "   [1] DAY 1" 
            Write-Host "   [2] DAY 2" 
            Write-Host "   [3] DAY 3"
            
            # Prompt the user for their choice
            $userChoice3 = Read-Host "`nEnter the number of your choice (1-3)"

                # Use a switch statement to handle different choices
                switch ($userChoice3) {
                    1 {
                        # [1] DAY 1 selected
                        $courseDay = 1
                        $trueFour = $false
                        break  # Move onto next step
                    }
                    2 {
                        # [2] DAY 2 selected
                        $courseDay = 2
                        $trueFour = $false
                        break  # Move onto next step
                    }
                    3 {
                        # [3] DAY 3 selected
                        $courseDay = 3
                        $trueFour = $false
                        break  # Move onto next step
                    }
                    default {
                        # Handle invalid input
                        Write-Host "Invalid choice. Please select a number between 1 and 3.`n" -ForegroundColor Red
                        continue
                    }
                }
            }

        # 'stc2' has day '1' and '2' for 'exam' VM Types ONLY
        elseif ($courseType -eq 'stc2' -and $vmType -eq 'exam') {
            
            Write-Host "`nSelect the correct SC-STC-002 training 'day':" -ForegroundColor Cyan
            Write-Host "   [1] DAY 1" 
            Write-Host "   [2] DAY 2" 
            
            # Prompt the user for their choice
            $userChoice3 = Read-Host "`nEnter the number of your choice (1-2)"

                # Use a switch statement to handle different choices
                switch ($userChoice3) {
                    1 {
                        # [1] GENERAL USE selected
                        $courseDay = 1
                        $trueFour = $false
                        break  # Move onto next step
                    }
                    2 {
                        # [2] EXAM USE selected
                        $courseDay = 2
                        $trueFour = $false
                        break  # Move onto next step
                    }
                    default {
                        # Handle invalid input
                        Write-Host "Invalid choice. Please select a number between 1 and 2.`n" -ForegroundColor Red
                        continue
                    }
                }
            }
        else { 
            Start-Sleep -Seconds 1
            Write-Host "`nFor OTC-001, STC-001, ETC-001, STC-002 ('general') and MC-ACT-001 course, courseDay is set to '1'`n" -ForegroundColor Cyan
            $courseDay = 1
            $trueFour = $false
            break  # Move onto next step
        }
    }        
#---# End of Step 5 -------------------------    
    
    
#---# STEP 6 - show the parameters/variables and call the relevant functions    
    
    # Testing we have all of the variables correct!
    Start-Sleep -Seconds 1
    Write-Host "`nYour choices are:" -ForegroundColor Green
    Start-Sleep -Milliseconds 500
    Write-Host "    --> Course Type: $courseType" -ForegroundColor Yellow
    Start-Sleep -Milliseconds 500
    Write-Host "    --> VM Array:    $vmArray" -ForegroundColor Yellow
    Start-Sleep -Milliseconds 500
    Write-Host "    --> VM Password: $vmPassword" -ForegroundColor Yellow
    Start-Sleep -Milliseconds 500
    Write-Host "    --> VM Type:     $vmType" -ForegroundColor Yellow
    Start-Sleep -Milliseconds 500
    Write-Host "    --> Course Day:  $courseDay" -ForegroundColor Yellow 


    #valid course types = 'otc', 'stc', 'etc', 'otc2', 'stc2', 'mc'    
    if ($courseType -eq 'otc') {
        
        #OTC - calls DesktopConfiguration and GustavConfiguration
        Start-Sleep -Milliseconds 500
        Write-Host "`nSC-OTC-001 course setup" -ForegroundColor Green
        Write-Host "**** The script can take some time (approx. 3mins for x10 VMs), therefore please DO NOT cancel, stop or close the script! ****`n" -ForegroundColor Yellow

        # STEP 1: Test if servers are accessible, if not exit the function back to the Main Menu
        Write-Host "Checking that each server in the array of VMs is reachable"
        Check_VM_Availability -VM_array $vmArray
        Write-Host "All VMs are reachable" -ForegroundColor Green
        
        # STEP 2: call DesktopConfiguration
        Write-Host "`nConfiguring the desktops on each VM"
        DesktopConfiguration -ArrayofVMs $vmArray -Password $vmPassword | Out-Null
        Write-Host "VM desktops configured" -ForegroundColor Green
        
        # STEP 3: call GustavConfiguration
        Write-Host "`nConfiguring the camera simulator (GUSTAV) on each VM"
        GUSTAVConfiguration -ArrayofVMs $vmArray -Password $vmPassword -Course $courseType | Out-Null
        Write-Host "VM camera simulators (GUSTAV) configured" -ForegroundColor Green

        # STEP 4: Course setup complete
        Start-Sleep -Milliseconds 500
        Write-Host "`nAll VM's setup ready for the course, don't forget to add a license to each desktop!" -ForegroundColor Green
        Read-Host "Press enter to continue..."

        Start-Sleep -Milliseconds 500
        mainMenu

    }

    elseif ($courseType -eq 'stc') {
        
        #STC - calls DesktopConfiguration and GustavConfiguration
        Start-Sleep -Milliseconds 500
        Write-Host "`nSC-STC-001 course setup" -ForegroundColor Red
        Write-Host "**** The script can take some time (approx. 3mins for x10 VMs), therefore please DO NOT cancel, stop or close the script! ****`n" -ForegroundColor Yellow 

        # STEP 1: Test if servers are accessible, if not exit the function back to the Main Menu
        Write-Host "Checking that each server in the array of VMs is reachable"
        Check_VM_Availability -VM_array $vmArray
        Write-Host "All VMs are reachable" -ForegroundColor Green        

        # STEP 2: call DesktopConfiguration
        Write-Host "`nConfiguring the desktops on each VM"
        DesktopConfiguration -ArrayofVMs $vmArray -Password $vmPassword | Out-Null
        Write-Host "VM desktops configured" -ForegroundColor Green
        
        # STEP 3: call GustavConfiguration
        Write-Host "`nConfiguring the camera simulator (GUSTAV) on each VM"
        GUSTAVConfiguration -ArrayofVMs $vmArray -Password $vmPassword -Course $courseType | Out-Null
        Write-Host "VM camera simulators (GUSTAV) configured" -ForegroundColor Green 

        # STEP 4: Course setup complete
        Start-Sleep -Milliseconds 500
        Write-Host "`nAll VM's setup ready for the course, don't forget to add a license to each desktop!" -ForegroundColor Green
        Read-Host "Press enter to continue..."

        Start-Sleep -Milliseconds 500
        mainMenu   
    }

    elseif ($courseType -eq 'etc') {

        #ETC - calls DesktopConfiguration and GustavConfiguration
        Start-Sleep -Milliseconds 500 
        Write-Host "`nSC-ETC-001 course setup" -ForegroundColor Cyan
        Write-Host "**** The script can take some time (approx. 5mins for x10 VMs), therefore please DO NOT cancel, stop or close the script! ****`n" -ForegroundColor Yellow

        # STEP 1: Test if servers are accessible, if not exit the function back to the Main Menu
        Write-Host "Checking that each server in the array of VMs is reachable"
        Check_VM_Availability -VM_array $vmArray
        Write-Host "All VMs are reachable" -ForegroundColor Green
                
        # STEP 2: call DesktopConfiguration
        Write-Host "`nConfiguring the desktops on each VM"
        DesktopConfiguration -ArrayofVMs $vmArray -Password $vmPassword | Out-Null
        Write-Host "VM desktops configured" -ForegroundColor Green
        
        # STEP 3: call GustavConfiguration
        Write-Host "`nConfiguring the camera simulator (GUSTAV) on each VM"
        GUSTAVConfiguration -ArrayofVMs $vmArray -Password $vmPassword -Course $courseType | Out-Null
        Write-Host "VM camera simulators (GUSTAV) configured" -ForegroundColor Green 

        # STEP 4: Course setup complete
        Start-Sleep -Milliseconds 500
        Write-Host "`nAll VM's setup ready for the course, don't forget to add a license to each desktop!" -ForegroundColor Green
        Read-Host "Press enter to continue..."

        Start-Sleep -Milliseconds 500
        mainMenu  
    }

    elseif ($courseType -eq 'mc') {

        #MC - calls DesktopConfiguration, GustavConfiguration, and DatabaseConfiguration 
        Start-Sleep -Milliseconds 500
        Write-Host "`nMC-ATC-001 course setup" -ForegroundColor Magenta
        Write-Host "**** The script can take some time (approx. 5mins for x10 VMs), therefore please DO NOT cancel, stop or close the script! ****`n" -ForegroundColor Yellow

        # STEP 1: Test if servers are accessible, if not exit the function back to the Main Menu
        Write-Host "Checking that each server in the array of VMs is reachable"
        Check_VM_Availability -VM_array $vmArray
        Write-Host "All VMs are reachable" -ForegroundColor Green
                
        # STEP 2: call DesktopConfiguration
        Write-Host "`nConfiguring the desktops on each VM"
        DesktopConfiguration -ArrayofVMs $vmArray -Password $vmPassword | Out-Null
        Write-Host "VM desktops configured" -ForegroundColor Green

        # STEP 3: call GustavConfiguration
        Write-Host "`nConfiguring the camera simulator (GUSTAV) on each VM"
        GUSTAVConfiguration -ArrayofVMs $vmArray -Password $vmPassword -Course $courseType | Out-Null
        Write-Host "VM camera simulators (GUSTAV) configured" -ForegroundColor Green 

        # STEP 4: call DatabaseConfiguration
        Write-Host "`nRestoring a pre-configured Directory database on each VM"
        DatabaseConfiguration -ArrayofVMs $vmArray -Password $vmPassword -Course $courseType -VMType $vmType | Out-Null
        Write-Host "VM databases restored" -ForegroundColor Green

        # STEP 5: Course setup complete
        Start-Sleep -Milliseconds 500
        Write-Host "`nAll VM's setup ready for the course!" -ForegroundColor Green
        Read-Host "Press enter to continue..."

        Start-Sleep -Milliseconds 500
        mainMenu  
    }

    elseif ($courseType -eq 'stc2' -and $vmType -eq 'general') {

        #STC2 GENERAL USE SERVERS - calls DesktopConfiguration, GustavConfiguration, Firewall Configuration, DatabaseConfiguration and ServerIssuesConfiguration
        Start-Sleep -Milliseconds 500
        Write-Host "`nSC-STC-002 (general use servers) course setup" -ForegroundColor Red
        Write-Host "**** The script can take some time (approx. 5mins for x10 VMs), therefore please DO NOT cancel, stop or close the script! ****`n" -ForegroundColor Yellow

        # STEP 1: Test if servers are accessible, if not exit the function back to the Main Menu
        Write-Host "Checking that each server in the array of VMs is reachable"
        Check_VM_Availability -VM_array $vmArray
        Write-Host "All VMs are reachable" -ForegroundColor Green
                
        # STEP 2: call DesktopConfiguration
        Write-Host "`nConfiguring the desktops on each VM"
        DesktopConfiguration -ArrayofVMs $vmArray -Password $vmPassword | Out-Null
        Write-Host "VM desktops configured" -ForegroundColor Green

        # STEP 3: call GustavConfiguration
        Write-Host "`nConfiguring the camera simulator (GUSTAV) on each VM"
        GUSTAVConfiguration -ArrayofVMs $vmArray -Password $vmPassword -Course $courseType | Out-Null
        Write-Host "VM camera simulators (GUSTAV) configured" -ForegroundColor Green 

        # STEP 4: call FirewallConfiguration
        Write-Host "`nConfiguring the firewall settings on each VM"
        FirewallConfiguration -ArrayofVMs $vmArray -Password $vmPassword -Course $courseType -Day $courseDay -VMType $vmType | Out-Null
        Write-Host "VM firewall settings configured" -ForegroundColor Green 

        # STEP 5: call DatabaseConfiguration
        Write-Host "`nRestoring a pre-configured Directory database on each VM"
        DatabaseConfiguration -ArrayofVMs $vmArray -Password $vmPassword -Course $courseType -VMType $vmType | Out-Null
        Write-Host "VM databases restored" -ForegroundColor Green

        # STEP 6: call ServerIssuesConfiguration
        Write-Host "`nCreating 'some issues' on each VM"
        ServerIssuesConfiguration -ArrayofVMs $vmArray -Password $vmPassword -Course $courseType -Day $courseDay -VMType $vmType | Out-Null
        Write-Host "Issues created successfully" -ForegroundColor Green

        # STEP 7: Course setup complete
        Start-Sleep -Milliseconds 500
        Write-Host "`nAll VM's setup ready for the course!" -ForegroundColor Green
        Read-Host "Press enter to continue..."

        Start-Sleep -Milliseconds 500
        mainMenu  
    }
    
    elseif ($courseType -eq 'stc2' -and $vmType -eq 'trouble') {

        #STC2 TROUBLESHOOTING SERVERS - calls DesktopConfiguration, GustavConfiguration, Firewall Configuration, DatabaseConfiguration and ServerIssuesConfiguration
        Start-Sleep -Milliseconds 500
        Write-Host "`nSC-STC-002 (troubleshooting servers) course setup" -ForegroundColor Red
        Write-Host "**** The script can take some time (approx. 5mins for x10 VMs), therefore please DO NOT cancel, stop or close the script! ****`n" -ForegroundColor Yellow

        # STEP 1: Test if servers are accessible, if not exit the function back to the Main Menu
        Write-Host "Checking that each server in the array of VMs is reachable"
        Check_VM_Availability -VM_array $vmArray
        Write-Host "All VMs are reachable" -ForegroundColor Green
                
        # STEP 2: call DesktopConfiguration
        Write-Host "`nConfiguring the desktops on each VM"
        DesktopConfiguration -ArrayofVMs $vmArray -Password $vmPassword | Out-Null
        Write-Host "VM desktops configured" -ForegroundColor Green

        # STEP 3: call GustavConfiguration
        Write-Host "`nConfiguring the camera simulator (GUSTAV) on each VM"
        GUSTAVConfiguration -ArrayofVMs $vmArray -Password $vmPassword -Course $courseType | Out-Null
        Write-Host "VM camera simulators (GUSTAV) configured" -ForegroundColor Green 

        # STEP 4: call FirewallConfiguration
        Write-Host "`nConfiguring the firewall settings on each VM"
        FirewallConfiguration -ArrayofVMs $vmArray -Password $vmPassword -Course $courseType -Day $courseDay -VMType $vmType | Out-Null
        Write-Host "VM firewall settings configured" -ForegroundColor Green

        # STEP 5: call DatabaseConfiguration
        Write-Host "`nRestoring a pre-configured Directory database on each VM"
        DatabaseConfiguration -ArrayofVMs $vmArray -Password $vmPassword -Course $courseType -VMType $vmType | Out-Null
        Write-Host "VM databases restored" -ForegroundColor Green

        # STEP 6: call ServerIssuesConfiguration
        Write-Host "`nCreating 'some issues' on each VM"
        ServerIssuesConfiguration -ArrayofVMs $vmArray -Password $vmPassword -Course $courseType -Day $courseDay -VMType $vmType | Out-Null
        Write-Host "Issues created successfully" -ForegroundColor Green

        # STEP 7: Course setup complete
        Start-Sleep -Milliseconds 500
        Write-Host "`nAll VM's setup ready for the course!" -ForegroundColor Green
        Read-Host "Press enter to continue..."

        Start-Sleep -Milliseconds 500
        mainMenu  
    }

    elseif ($courseType -eq 'stc2' -and $vmType -eq 'exam' -and $courseDay -eq '1') {

        #STC2 EXAM SERVERS - DAY 1 - calls DesktopConfiguration, GustavConfiguration, and ServerIssuesConfiguration
        Start-Sleep -Milliseconds 500
        Write-Host "`nSC-STC-002 (exam servers - day 1) course setup" -ForegroundColor Red
        Write-Host "**** The script can take some time (approx. 3mins for x10 VMs), therefore please DO NOT cancel, stop or close the script! ****`n" -ForegroundColor Yellow

        # STEP 1: Test if servers are accessible, if not exit the function back to the Main Menu
        Write-Host "Checking that each server in the array of VMs is reachable"
        Check_VM_Availability -VM_array $vmArray
        Write-Host "All VMs are reachable" -ForegroundColor Green
                
        # STEP 2: call DesktopConfiguration
        Write-Host "`nConfiguring the desktops on each VM"
        DesktopConfiguration -ArrayofVMs $vmArray -Password $vmPassword | Out-Null
        Write-Host "VM desktops configured" -ForegroundColor Green

        # STEP 3: call GustavConfiguration
        Write-Host "`nConfiguring the camera simulator (GUSTAV) on each VM"
        GUSTAVConfiguration -ArrayofVMs $vmArray -Password $vmPassword -Course $courseType | Out-Null
        Write-Host "VM camera simulators (GUSTAV) configured" -ForegroundColor Green 

        # STEP 4: call ServerIssuesConfiguration
        Write-Host "`nCreating 'some issues' on each VM"
        ServerIssuesConfiguration -ArrayofVMs $vmArray -Password $vmPassword -Course $courseType -Day $courseDay -VMType $vmType | Out-Null
        Write-Host "Issues created successfully" -ForegroundColor Green

        # STEP 5: Course setup complete
        Start-Sleep -Milliseconds 500
        Write-Host "`nAll VM's setup ready for the course!" -ForegroundColor Green
        Read-Host "Press enter to continue..."

        Start-Sleep -Milliseconds 500
        mainMenu  
    }

    elseif ($courseType -eq 'stc2' -and $vmType -eq 'exam' -and $courseDay -eq '2') {

        #STC2 EXAM SERVERS - DAY 2 - calls ServerIssuesConfiguration 
        Start-Sleep -Milliseconds 500
        Write-Host "`nSC-STC-002 (exam servers - day 2) course setup" -ForegroundColor Red
        Write-Host "**** The script can take some time (approx. 1min for x10 VMs), therefore please DO NOT cancel, stop or close the script! ****`n" -ForegroundColor Yellow

        # STEP 1: Test if servers are accessible, if not exit the function back to the Main Menu
        Write-Host "Checking that each server in the array of VMs is reachable"
        Check_VM_Availability -VM_array $vmArray
        Write-Host "All VMs are reachable" -ForegroundColor Green
                
        # STEP 2: call ServerIssuesConfiguration
        Write-Host "`nCreating 'some issues' on each VM"
        ServerIssuesConfiguration -ArrayofVMs $vmArray -Password $vmPassword -Course $courseType -Day $courseDay -VMType $vmType | Out-Null
        Write-Host "Issues created successfully" -ForegroundColor Green

        # STEP 3: Course setup complete
        Start-Sleep -Milliseconds 500
        Write-Host "`nAll VM's setup ready for the course!" -ForegroundColor Green
        Read-Host "Press enter to continue..."

        Start-Sleep -Milliseconds 500
        mainMenu  
    }

    elseif ($courseType -eq 'otc2' -and $vmType -eq 'general' -and $courseDay -eq '1') {

        #OTC2 GENERAL USE SERVERS - DAY 1 - calls DesktopConfiguration, GustavConfiguration, Firewall Configuration, and ServerIssuesConfiguration
        Start-Sleep -Milliseconds 500
        Write-Host "`nSC-OTC-002 (general use servers - day 1) course setup" -ForegroundColor Green
        Write-Host "**** The script can take some time (approx. 8mins for x10 VMs), therefore please DO NOT cancel, stop or close the script! ****`n" -ForegroundColor Yellow

        # STEP 1: Test if servers are accessible, if not exit the function back to the Main Menu
        Write-Host "Checking that each server in the array of VMs is reachable"
        Check_VM_Availability -VM_array $vmArray
        Write-Host "All VMs are reachable" -ForegroundColor Green
                
        # STEP 2: call DesktopConfiguration
        Write-Host "`nConfiguring the desktops on each VM"
        DesktopConfiguration -ArrayofVMs $vmArray -Password $vmPassword | Out-Null
        Write-Host "VM desktops configured" -ForegroundColor Green

        # STEP 3: call GustavConfiguration
        Write-Host "`nConfiguring the camera simulator (GUSTAV) on each VM"
        GUSTAVConfiguration -ArrayofVMs $vmArray -Password $vmPassword -Course $courseType | Out-Null
        Write-Host "VM camera simulators (GUSTAV) configured" -ForegroundColor Green

        # STEP 4: call FirewallConfiguration
        Write-Host "`nConfiguring the firewall settings on each VM"
        FirewallConfiguration -ArrayofVMs $vmArray -Password $vmPassword -Course $courseType -Day $courseDay -VMType $vmType | Out-Null
        Write-Host "VM firewall settings configured" -ForegroundColor Green

        # STEP 5: call ServerIssuesConfiguration
        Write-Host "`nCreating 'some issues' on each VM"
        ServerIssuesConfiguration -ArrayofVMs $vmArray -Password $vmPassword -Course $courseType -Day $courseDay -VMType $vmType | Out-Null
        Write-Host "Issues created successfully" -ForegroundColor Green

        # STEP 6: Course setup complete
        Start-Sleep -Milliseconds 500
        Write-Host "`nAll VM's setup ready for the course!" -ForegroundColor Green
        Read-Host "Press enter to continue..."

        Start-Sleep -Milliseconds 500
        mainMenu  
    }

    elseif ($courseType -eq 'otc2' -and $vmType -eq 'general' -and $courseDay -eq '2') {

        #OTC2 GENERAL USE SERVERS - DAY 2 - calls ServerIssuesConfiguration
        Start-Sleep -Milliseconds 500
        Write-Host "`nSC-OTC-002 (general use servers - day 2) course setup" -ForegroundColor Green
        Write-Host "**** The script can take some time (approx. 2mins for x10 VMs), therefore please DO NOT cancel, stop or close the script! ****`n" -ForegroundColor Yellow

        # STEP 1: Test if servers are accessible, if not exit the function back to the Main Menu
        Write-Host "Checking that each server in the array of VMs is reachable"
        Check_VM_Availability -VM_array $vmArray
        Write-Host "All VMs are reachable" -ForegroundColor Green
                
        # STEP 2: call ServerIssuesConfiguration
        Write-Host "`nCreating 'some issues' on each VM"
        ServerIssuesConfiguration -ArrayofVMs $vmArray -Password $vmPassword -Course $courseType -Day $courseDay -VMType $vmType | Out-Null
        Write-Host "Issues created successfully" -ForegroundColor Green

        # STEP 3: Course setup complete
        Start-Sleep -Milliseconds 500
        Write-Host "`nAll VM's setup ready for the course!" -ForegroundColor Green
        Read-Host "Press enter to continue..."

        Start-Sleep -Milliseconds 500
        mainMenu  
    }

    elseif ($courseType -eq 'otc2' -and $vmType -eq 'general' -and $courseDay -eq '3') {

        #OTC2 GENERAL USE SERVERS - DAY 3 - calls Firewall Configuration, and ServerIssuesConfiguration
        Start-Sleep -Milliseconds 500
        Write-Host "`nSC-OTC-002 (general use servers - day 3) course setup" -ForegroundColor Green
        Write-Host "**** The script can take some time (approx. 2mins for x10 VMs), therefore please DO NOT cancel, stop or close the script! ****`n" -ForegroundColor Yellow

        # STEP 1: Test if servers are accessible, if not exit the function back to the Main Menu
        Write-Host "Checking that each server in the array of VMs is reachable"
        Check_VM_Availability -VM_array $vmArray
        Write-Host "All VMs are reachable" -ForegroundColor Green
                
        # STEP 2: call FirewallConfiguration
        Write-Host "`nConfiguring the firewall settings on each VM"
        FirewallConfiguration -ArrayofVMs $vmArray -Password $vmPassword -Course $courseType -Day $courseDay -VMType $vmType | Out-Null
        Write-Host "VM firewall settings configured" -ForegroundColor Green

        # STEP 3: call ServerIssuesConfiguration
        Write-Host "`nCreating 'some issues' on each VM"
        ServerIssuesConfiguration -ArrayofVMs $vmArray -Password $vmPassword -Course $courseType -Day $courseDay -VMType $vmType | Out-Null
        Write-Host "Issues created successfully" -ForegroundColor Green

        # STEP 4: Course setup complete
        Start-Sleep -Milliseconds 500
        Write-Host "`nAll VM's setup ready for the course!" -ForegroundColor Green
        Read-Host "Press enter to continue..."

        Start-Sleep -Milliseconds 500
        mainMenu  
    }

    elseif ($courseType -eq 'otc2' -and $vmType -eq 'exam' -and $courseDay -eq '1') {

        #OTC2 EXAM SERVERS - DAY 1 - calls DesktopConfiguration, GustavConfiguration, Firewall Configuration, and ServerIssuesConfiguration
        Start-Sleep -Milliseconds 500
        Write-Host "`nSC-OTC-002 (exam servers - day 1) course setup" -ForegroundColor Green
        Write-Host "**** The script can take some time (approx.8mins for x10 VMs), therefore please DO NOT cancel, stop or close the script! ****`n" -ForegroundColor Yellow

        # STEP 1: Test if servers are accessible, if not exit the function back to the Main Menu
        Write-Host "Checking that each server in the array of VMs is reachable"
        Check_VM_Availability -VM_array $vmArray
        Write-Host "All VMs are reachable" -ForegroundColor Green
                
        # STEP 2: call DesktopConfiguration
        Write-Host "`nConfiguring the desktops on each VM"
        DesktopConfiguration -ArrayofVMs $vmArray -Password $vmPassword | Out-Null
        Write-Host "VM desktops configured" -ForegroundColor Green

        # STEP 3: call GustavConfiguration
        Write-Host "`nConfiguring the camera simulator (GUSTAV) on each VM"
        GUSTAVConfiguration -ArrayofVMs $vmArray -Password $vmPassword -Course $courseType | Out-Null
        Write-Host "VM camera simulators (GUSTAV) configured" -ForegroundColor Green 

        # STEP 4: call FirewallConfiguration
        Write-Host "`nConfiguring the firewall settings on each VM"
        FirewallConfiguration -ArrayofVMs $vmArray -Password $vmPassword -Course $courseType -Day $courseDay -VMType $vmType | Out-Null
        Write-Host "VM firewall settings configured" -ForegroundColor Green

        # STEP 5: call ServerIssuesConfiguration
        Write-Host "`nCreating 'some issues' on each VM"
        ServerIssuesConfiguration -ArrayofVMs $vmArray -Password $vmPassword -Course $courseType -Day $courseDay -VMType $vmType | Out-Null
        Write-Host "Issues created successfully" -ForegroundColor Green

        # STEP 6: Course setup complete
        Start-Sleep -Milliseconds 500
        Write-Host "`nAll VM's setup ready for the course!" -ForegroundColor Green
        Read-Host "Press enter to continue..."

        Start-Sleep -Milliseconds 500
        mainMenu  
    }

    elseif ($courseType -eq 'otc2' -and $vmType -eq 'exam' -and $courseDay -eq '2') {

        #OTC2 EXAM SERVERS - DAY 2 - calls ServerIssuesConfiguration
        Start-Sleep -Milliseconds 500
        Write-Host "`nSC-OTC-002 (exam servers - day 2) course setup" -ForegroundColor Green
        Write-Host "**** The script can take some time (approx. 2mins for x10 VMs), therefore please DO NOT cancel, stop or close the script! ****`n" -ForegroundColor Yellow

        # STEP 1: Test if servers are accessible, if not exit the function back to the Main Menu
        Write-Host "Checking that each server in the array of VMs is reachable"
        Check_VM_Availability -VM_array $vmArray
        Write-Host "All VMs are reachable" -ForegroundColor Green
                
        # STEP 2: call ServerIssuesConfiguration
        Write-Host "`nCreating 'some issues' on each VM"
        ServerIssuesConfiguration -ArrayofVMs $vmArray -Password $vmPassword -Course $courseType -Day $courseDay -VMType $vmType | Out-Null
        Write-Host "Issues created successfully" -ForegroundColor Green

        # STEP 3: Course setup complete
        Start-Sleep -Milliseconds 500
        Write-Host "`nAll VM's setup ready for the course!" -ForegroundColor Green
        Read-Host "Press enter to continue..."

        Start-Sleep -Milliseconds 500
        mainMenu  
    }

    elseif ($courseType -eq 'otc2' -and $vmType -eq 'exam' -and $courseDay -eq '3') {

        #OTC2 EXAM SERVERS - DAY 3 - calls Firewall Configuration, and ServerIssuesConfiguration
        Start-Sleep -Milliseconds 500
        Write-Host "`nSC-OTC-002 (exam servers - day 3) course setup" -ForegroundColor Green
        Write-Host "**** The script can take some time (approx. 2mins for x10 VMs), therefore please DO NOT cancel, stop or close the script! ****`n" -ForegroundColor Yellow

        # STEP 1: Test if servers are accessible, if not exit the function back to the Main Menu
        Write-Host "Checking that each server in the array of VMs is reachable"
        Check_VM_Availability -VM_array $vmArray
        Write-Host "All VMs are reachable" -ForegroundColor Green
                
        # STEP 2: call FirewallConfiguration
        Write-Host "`nConfiguring the firewall settings on each VM"
        FirewallConfiguration -ArrayofVMs $vmArray -Password $vmPassword -Course $courseType -Day $courseDay -VMType $vmType | Out-Null
        Write-Host "VM firewall settings configured" -ForegroundColor Green

        # STEP 3: call ServerIssuesConfiguration
        Write-Host "`nCreating 'some issues' on each VM"
        ServerIssuesConfiguration -ArrayofVMs $vmArray -Password $vmPassword -Course $courseType -Day $courseDay -VMType $vmType | Out-Null
        Write-Host "Issues created successfully" -ForegroundColor Green

        # STEP 4: Course setup complete
        Start-Sleep -Milliseconds 500
        Write-Host "`nAll VM's setup ready for the course!" -ForegroundColor Green
        Read-Host "Press enter to continue..."

        Start-Sleep -Milliseconds 500
        mainMenu  
    }

    else {

        #UNHANDLED EXCEPTION - Push back to Main Menu
        Start-Sleep -Milliseconds 500
        Write-Host "`nOops, something went wrong!`n" -ForegroundColor Red
        Read-Host "Press enter to continue..."
    }

}


# Menu 2 function - Exam Marking
function menuTwo {

    Write-Host "`n[2] Exam Marking" -ForegroundColor Green
    Write-Host "`nThis is a work in progress, exiting script." -ForegroundColor Red
    Exit  # Exit the script
}


# Menu 3 function - Make Servers 'Exam Ready'
function menuThree {

    # Variables to control the below 'while' loops - I have a feeling WPF will be easier than this logic...
    # used for selecting the correct course - valid course types = 'otc', 'stc', 'etc', 'otc2', 'stc2', 'mc', 'other'
    $trueFive = $true

    Write-Host "`n[3] Make Servers 'Exam Ready'" -ForegroundColor Green
    Write-Host "`nNote: This is designed to make OTC-001 and STC-001 machines ready for exam use." -ForegroundColor Yellow
    Write-Host "      There is no need for the students to re-license or add the ACS simulator." -ForegroundColor Yellow

#---# STEP 1 - create the array of VMs   
    While ($trueFive) { 
        Write-Host "`nEnter the VM Range (type 'help' for more information)" -ForegroundColor Cyan  
        $vmNumbers = Read-Host "VM Range"

        if ($vmNumbers -eq 'help') {
            Write-Host "Help: Enter VM numbers like so; `n   --> for a single VM: <VM Number> i.e., 100`n   --> for a range of VMs: <VM Start Number>-<VM End Number> i.e., 101-110`n   --> for a mix of VMs, any combination of: <VM Number>, <VM Start Number>-<VM End Number>, <VM Number> i.e., 101, 103-108, 110" -ForegroundColor Green
            continue
        }

        # Validate the input using the new regular expression pattern
        $validInputPattern = '^(\d+(-\d+)?(,|$)\s*)+$'
        if ($vmNumbers -notmatch $validInputPattern) {
            Write-Host "Invalid input format. Please enter a valid VM range or type 'help' for more information." -ForegroundColor Red
            continue
        }

        # Call the function to get VM names based on the input range
        $vmArray = Get_VM_Name 'GTRAIN-JS-S' $vmNumbers $courseType
        
        # break out of this loop if a valid range is provided and the function returns the VM names
        $trueFive = $false
        break
    }
#---# End of Step 1 -------------------------


#---# STEP 2 - get the VM password
    Write-Host "`nEnter the VM password, ensure this is correct!" -ForegroundColor Cyan   
    $vmPassword = Read-Host 'VM Password'
#---# End of Step 2 -------------------------

    # Testing we have all of the variables correct!
    Start-Sleep -Seconds 1
    Write-Host "Your choices are:" -ForegroundColor Green
    Start-Sleep -Milliseconds 500
    Write-Host "    --> VM Array:    $vmArray" -ForegroundColor Yellow
    Start-Sleep -Milliseconds 500
    Write-Host "    --> VM Password: $vmPassword" -ForegroundColor Yellow


    #Calls OSTCExamConfiguration
    Start-Sleep -Milliseconds 500
    Write-Host "`nSC-OTC-001/SC-STC-001 exam setup" -ForegroundColor Green
    Write-Host "**** The script can take some time (approx. 2mins for x10 VMs), therefore please DO NOT cancel, stop or close the script! ****`n" -ForegroundColor Yellow

    # STEP 1: Test if servers are accessible, if not exit the function back to the Main Menu
    Write-Host "Checking that each server in the array of VMs is reachable"
    Check_VM_Availability -VM_array $vmArray
    Write-Host "All VMs are reachable" -ForegroundColor Green
        
    # STEP 2: call OSTCExamConfiguration
    Write-Host "`nConfiguring the VMs for the exam"
    OSTCExamConfiguration -ArrayofVMs $vmArray -Password $vmPassword | Out-Null
    Write-Host "VMs configured for the exam" -ForegroundColor Green

    # STEP 3: Course setup complete
    Start-Sleep -Milliseconds 500
    Write-Host "`nAll VM's setup ready for the exam!" -ForegroundColor Green
    Read-Host "Press enter to continue..."

    Start-Sleep -Milliseconds 500
    mainMenu

}


# Menu 4 function - About 'T_O_O_L'
function menuFour {

    Write-Host "`n[4] About 'T_O_O_L" -ForegroundColor Green
    Write-Host "`nScript Author:      James Savage"
    Write-Host "Date Last Updated:  21-Aug-2023"
    Write-Host "`nDescription:" -ForegroundColor Yellow
    Write-Host "`n    T_O_O_L (Toolkit for Operational Optimization and Learning) is a customised PowerShell script which can be used for:`n"
    Write-Host "        --> [1] Setting up the Azure VMs for the relevant course(s), this is highly customised to the way I personally deliver training."
    Write-Host "        --> [2] Auto-marking the SC-OTC-001, SC-STC-001, and SC-ETC-001 exam servers. - WIP" -ForegroundColor Red
    Write-Host "        --> [3] Making the SC-OTC-001 and SC-STC-001 servers ready for the exam, there is no need for students to re-license or add the ACS sim."
    Write-Host "        --> [4] This option, for finding out more about T_O_O_L."
    Write-Host "`n    Note 1: T_O_O_L must be copied and put on the 'C Drive' so the path is C:\TOOL - All folders, DB backups and the TOOL scripts should be located in this folder." -ForegroundColor Yellow
    Write-Host "`n    Note 2: T_O_O_L logs can be found here: 'C:\TOOL\TOOL_Logs', there is a logfile for each script that is ran." -ForegroundColor Yellow

    # Give user time to read, when they press enter they go back to the mainMenu
    Read-Host "`nPress Enter to continue..."
}


# Main Menu Function, this gets called when the script is ran initially
function mainMenu {

    Write-Host "##########################################################"
    Write-Host "#                                                        #"
    Write-Host "|                 WELCOME TO T_O_O_L                     |" -ForegroundColor Cyan
    Write-Host "#                                                        #"
    Write-Host "##########################################################"


    #Initial Menu
    While ($true) {
    Write-Host "`nSelect an option:" -ForegroundColor Cyan
    Write-Host "   [1] Course Setup" 
    Write-Host "   [2] Exam Marking (WIP)" -ForegroundColor Red
    Write-Host "   [3] Make Servers 'Exam Ready'"
    Write-Host "   [4] About 'T_O_O_L'"
    Write-Host "   [5] Exit 'T_O_O_L'"

    # Prompt the user for their choice
    $userChoice = Read-Host "`nEnter the number of your choice (1-5)"

        # Use a switch statement to handle different choices
        switch ($userChoice) {
            1 {
                # Call the menuOne function (Course Setup)
                menuOne
            }
            2 {
                # Call the menuTwo function (Exam Marking)
                menuTwo
            }
            3 {
                # Call the menuThree function (Create 'Server Issues')
                menuThree
            }
            4 {
                # Call the menuFour function (About 'T_O_O_L')
                menuFour
            }
            5 {
                # Exit the TOOL
                Write-Host "`nExiting the T_O_O_L" -ForegroundColor Green
                return  # Exit the mainMenu function
            }
            42 {
                # Code for Menu 42
                Write-Host "`nYou selected 42..." -ForegroundColor Yellow
                Write-Host "According to the supercomputer 'Deep Thought' 42 is the meaning of life, the universe, and everything.`n" -ForegroundColor Magenta
                continue 
            }
            1975 {
                # Code for Menu 42
                Write-Host "`nYou selected 1975, an unwise choice, as a French soldier once said..." -ForegroundColor Yellow
                Write-Host "I don't want to talk to you no more, you empty-headed animal food trough wiper! I fart in your general direction! Your mother was a hamster and your father smelt of elderberries!" -ForegroundColor Magenta
                Write-Host "Ah, the French... if you know, you know ;)`n" -ForegroundColor Yellow
                Exit # exit the script... TOOL has had enough!
            }
            default {
                # Handle invalid input
                Write-Host "Invalid choice. Please select a number between 1 and 5.`n" -ForegroundColor Red
                continue
            }
        }
    }
}


### Script starting point
mainMenu