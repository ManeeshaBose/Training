#Script to verify that all Hawk related processes are not runining, uninstall hawk and (re)install lastest Hawk

#Variables that define location of Hawk install folder and name of latest installer
  $Installer_Path = "C:\3genlabs\hawk\syntheticnode\service\install\versions\"

# Insure C:\3genlabs\hawk\syntheticnode\service\install\versions exists
if (!(Test-Path $Installer_Path)) {New-Item -ItemType Directory $Installer_Path -Force}

# Move any 3GenLabs_HawkSyntheticNodeService installers from current folder to hawk installer folder
Move-Item 3GenLabs_HawkSyntheticNodeService*.msi -Destination $Installer_Path -Verbose -Force

$Installer_Files = Get-ChildItem -Path $Installer_Path -Name 3GenLabs_HawkSyntheticNodeService*.msi | Sort-Object -Descending
$Installer_Files_Top_Index = $Installer_Files.Length-1

Write-Output "Available Installers in C:\3genlabs\hawk\syntheticnode\service\install\versions:"
foreach ($Installer_File in $Installer_Files)
{
 $FileName = $Installer_File
 $Index = $Installer_Files.IndexOf($Installer_File)
 Write-Output " $index $FileName"
}

do {
    try {
        $numOk = $true
        [int]$Installer_File_Index = Read-host "Select the Installer File (0 - $Installer_Files_Top_Index)"
        } # end try
    catch {$numOK = $false}
    } # end do
until (($Installer_File_Index -ge 0 -and $Installer_File_Index -le $Installer_Files_Top_Index  ) -and $numOK)

# Define installer file to use
  $Installer_File = $Installer_Files[$Installer_File_Index]

Write-Output "Ready to install $Installer_File. Press any key to procced or Ctrl-C to Cancel"
Pause

#Query WMI for Hawk installer Object
$hawk = Get-WmiObject -Class Win32_Product | Where-Object {$_.Name -eq 'Hawk\SyntheticNode\Service'}


function Hawk-Folder-Cleanup {
# Function to move all configuration, cache and log files to $ENV:temp

Write-Host "Would you like to cleaup Agent configuration, cache and log files? (Default is No)" -ForegroundColor Yellow
    $Readhost = Read-Host " ( y / n ) "
    Switch ($ReadHost)
     {
       Y {Write-host "Proceeding with Agent Cleanup" ; $Do_Cleanup = $true}
       N {Write-Host "Skipping Agent cleanup" ; $Do_Cleanup = $false}
       Default {Write-Host "Skipping Agent cleanup" ; $Do_Cleanup = $false}
     } # End of Y/N Switch

    if ($Do_Cleanup -eq $true)
    {
    # Create dump foder
      $Dump_Folder = $env:TEMP + ('\Hawk_Dump_' +  (Get-Date -Format FileDateTimeUniversal))
      New-Item -ItemType Directory -Path $Dump_Folder -Force

    # Define folders to cleanup
      $Cleanup_Paths = @(
                         'C:\3genlabs\hawk\syntheticnode\apisvc',
                         'C:\3genlabs\hawk\syntheticnode\application',
                         'C:\3genlabs\hawk\syntheticnode\service\cache',
                         'C:\3genlabs\hawk\syntheticnode\service\chrome',
                         'C:\3genlabs\hawk\syntheticnode\service\input',
                         'C:\3genlabs\hawk\syntheticnode\service\log',
                         'C:\3genlabs\hawk\syntheticnode\synthetic_node_configuration*'
                         'C:\3genlabs\hawk\syntheticnode\service\synthetic_node_configuration*'
                        )

    # Move Cleanup_Paths to Dump_Folder
      Write-Output "Agent configuration, cache and log files will be dumpted into" $Dump_Folder

      foreach ($Path in $Cleanup_Paths)
      {
        if(Test-Path $Path)
        {
        Move-Item -Path $Path -Destination $Dump_Folder -Verbose -Force
        }
        else {Write-Output "$Path is not present"}
      }
    }
} #End of function Hawk-Folder-Cleanup

function Stop-Hawk-Service {
  #Check if Hawk Service still running and stop it (using separate processing stream)
   if ((Get-Service Hawk* -ErrorAction SilentlyContinue).Status -ne "Stopped") {
      Write-Output "Hawk Service is not Stopped. Attempting to Stop"
       start-process powershell.exe -verb runas -ArgumentList {Stop-Service Hawk* -Force -Verbose -ErrorAction SilentlyContinue}
   } #End of if
} #End of function Stop-Hawk-Service

function Stop-Hawk-Processes {
  #List of Processes spawned by the HawkSyntheticNodeService that need to be killed before (un)installing new version
    $ProcessList = @(
        "HawkSyntheticNodeService",
        "HawkSyntheticNodeApplication",
        "Launcher",
        "catchpoint_chrome",
        "catchpoint_chrome.exe",
        "TraceRouteUdp",
        "snsvctest",
        "HawkSyntheticNodeApplicationTest",
        "SnApiSvc",
        "dotnet"
    ) #End of $ProcessList

  #Loop to verify that Hawk related processes are not running
    #Check if any of the processes are running
      while ((Get-Process $ProcessList -ErrorAction SilentlyContinue) -ne $null) {
        #Loop through the list
          Foreach ($process in $ProcessList) {
            if((Get-Process $Process -ErrorAction SilentlyContinue) -ne $null) {
             #Attempt to stop using PowerShell Stop-Process
              Write-Output "Stopping process $Process"
              Stop-Process -Name $process -Verbose -Force
              Start-Sleep 2
               #Check if PowerShell Stop-Process failed to stop and use WMI instead
                if((Get-Process $Process -ErrorAction SilentlyContinue) -ne $null) {
                  $WmiProcess = Get-WmiObject win32_process | Where-Object {$_.Name -match $Process}
                    If ($WmiProcess -ne $null) {
                      Write-Output "Terminating $WmiProcess.Name"
                      $WmiProcess.Terminate()
                    } #End of If
                } #End of If
            } #End of if
        #Check if Hawk Service is running and attempt to stopm
          Stop-Hawk-Service
          } #End of Foreach
      } #End of While Loop
} #End of function Stop-Hawk-Processes

#Check if current version is already installed
    if($hawk -ne $null) {
        if ($hawk.PackageName -eq $Installer_File) {
          Write-Output "Terminating Task" $Hawk.PackageName "is already installed"
          Exit 0
        } #End of if
          else {
              Write-Output $Hawk.PackageName " is currently installed"
          } #End of else
      } #End of if


#Check if Hawk Service is running and attempt to stop
  Stop-Hawk-Service
#Run function to kill Hawk related processes
  Stop-Hawk-Processes
#Check if Hawk Service is running and attempt to stop
  Stop-Hawk-Service
#Run function to kill Hawk related processes
  Stop-Hawk-Processes

#Check if Hawk is installed but Hawk service is missing and repair Hawk installation
$HawkService = Get-Service HawkSyntheticNodeService -ErrorAction SilentlyContinue
  if(($hawk -ne $null) -and ($HawkService -eq $null)) {
    Write-Output "Hawk needs to be repaired. Running Repair"
  #Exract path and filename of installer used to install Hawk
    $InstallerPath = $hawk.InstallSource + $hawk.PackageName
      If (Test-Path $InstallerPath) {
       #Perform a repair
        msiexec.exe /fa $InstallerPath | Out-Null
      # Sleeping to allow AIP to install new version
      Start-sleep 120
      #Query WMI for Hawk installer Object
      $hawk = Get-WmiObject -Class Win32_Product | Where-Object {$_.Name -eq 'Hawk\SyntheticNode\Service'}
      #Check if up-to-date version is already installed
          if($hawk -ne $null) {
              if ($hawk.PackageName -eq $Installer_File) {
                Write-Output "Terminating Task. AIP installed:" $Hawk.PackageName
                Exit 0
              } #End of if
            } #End of if
      } #End of If
  } #End of if
    else {
        Write-Output "Hawk doesn't need to be repaired"
    } #End of else

#Query WMI for Hawk installer Object
  $hawk = Get-WmiObject -Class Win32_Product | Where-Object {$_.Name -eq 'Hawk\SyntheticNode\Service'}

  #Check if Hawk Service is running and attempt to stopm
    Stop-Hawk-Service
  #Run function to kill Hawk related processes
    Stop-Hawk-Processes
  #Check if Hawk Service is running and attempt to stopm
    Stop-Hawk-Service
  #Run function to kill Hawk related processes
    Stop-Hawk-Processes

#Uninstall Hawk using WMI (if installed)
    if($hawk -ne $null) {
      Write-Output "Uninstalling" $Hawk.PackageName
      $hawk.Uninstall()
    } #End of if
      else {
          Write-Output "Hawk is not installed"
      } #End of else

# Run Agent Cleanup funciton
  Hawk-Folder-Cleanup

#Verify that Launcher (Broker) scheduled task has been removed
  #(Installer will fail if task if present. Will be fixed in later releases.)

#Define task variales
  $taskname = "Launch SNB-IE broker"
  $taskfoler = "Catchpoint"
  $taskpath = "\" + $taskfoler + "\"
  $task = Get-ScheduledTask -TaskPath $taskpath -TaskName $taskname -ErrorAction SilentlyContinue

    if ($task -ne $null) {
    #Check if task is running and stop it
      if ($task.State -eq "Running") {
        Write-output "Task $task.name"
        Stop-ScheduledTask -TaskPath $taskpath -TaskName $taskname
      } # End of if statement

    #Unregister scheduled task
      Unregister-ScheduledTask -TaskPath $taskpath -TaskName $taskname -Confirm:$false

    #Delete Task Folder
      $scheduleObject = New-Object -ComObject schedule.service
      $scheduleObject.connect()
      $rootFolder = $scheduleObject.GetFolder("\")
      $rootFolder.DeleteFolder($taskfoler,$unll)
    } # End of if statement

#Install Hawk, using installer file defined by $Installer_File variable
  $Installer_File = $Installer_Path + $Installer_File
  Write-Output "Installing $Installer_File"
    Start-Process $Installer_File /quiet -Wait
    #Query WMI for Hawk installer Object
    $hawk = Get-WmiObject -Class Win32_Product | Where-Object {$_.Name -eq 'Hawk\SyntheticNode\Service'}
    Write-Output $hawk.PackageName "Installed"
