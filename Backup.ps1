<#

.SYNOPSIS 
Copies files from source directory to target directory

.DESCRIPTION 
Script copies files to folder starting with current date in target directory.

.EXAMPLE 
.\PackageDeployer.ps1

.NOTES
author name: Sebastian Nicpon
email: Sebastian.Nicpon@gmail.com
script version: 1.0.0
date: 02 February 2017

#>

#region RETURN CODES

# 0   =   Script Execution Successfull
# 1   =   No .ini file
# 2   =   No Source Paths
# 3   =   No Target Paths
# 4   =   Path Does Not Exist
# 5   =  
# 6   =  
# 7   =  

#endregion RETURN CODES

#region FUNCTIONS


function Get-PrivateProfileString
{
<#

.SYNOPSIS

Retrieves an element from a standard .INI file

.EXAMPLE

Get-PrivateProfileString c:\windows\system32\tcpmon.ini `
    "<Generic Network Card>" Name
Generic Network Card

#>

param(
    ## The INI file to retrieve
    $Path,

    ## The section to retrieve from
    $Category,

    ## The item to retrieve
    $Key
)

Set-StrictMode -Version Latest

## The signature of the Windows API that retrieves INI
## settings
$signature = @'
[DllImport("kernel32.dll")]
public static extern uint GetPrivateProfileString(
    string lpAppName,
    string lpKeyName,
    string lpDefault,
    StringBuilder lpReturnedString,
    uint nSize,
    string lpFileName);
'@

## Create a new type that lets us access the Windows API function
$type = Add-Type -MemberDefinition $signature `
    -Name Win32Utils -Namespace GetPrivateProfileString `
    -Using System.Text -PassThru

## The GetPrivateProfileString function needs a StringBuilder to hold
## its output. Create one, and then invoke the method
$builder = New-Object System.Text.StringBuilder 1024
$null = $type::GetPrivateProfileString($category,
    $key, "", $builder, $builder.Capacity, $path)

## Return the output
$builder.ToString()
}

function Write-Log
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias("LogContent")]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [Alias('LogPath')]
        [string]$Path='C:\Logs\PowerShellLog.log',
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("Error","Warn","Info")]
        [string]$Level="Info",
        
        [Parameter(Mandatory=$false)]
        [switch]$NoClobber
    )

    Begin
    {
        # Set VerbosePreference to Continue so that verbose messages are displayed.
        #$VerbosePreference = 'Continue'
    }
    Process
    {
        
        # If the file already exists and NoClobber was specified, do not write to the log.
        if ((Test-Path $Path) -AND $NoClobber) {
            Write-Error "Log file $Path already exists, and you specified NoClobber. Either delete the file or specify a different name."
            Return
            }

        # If attempting to write to a log file in a folder/path that doesn't exist create the file including the path.
        elseif (!(Test-Path $Path)) {
            Write-Verbose "Creating $Path."
            $NewLogFile = New-Item $Path -Force -ItemType File
            }

        else {
            # Nothing to see here yet.
            }

        # Format Date for our Log File
        $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        # Write message to error, warning, or verbose pipeline and specify $LevelText
        switch ($Level) {
            'Error' {
                Write-Error $Message -ErrorAction SilentlyContinue
                $LevelText = 'ERROR:'
                }
            'Warn' {
                Write-Warning $Message -WarningAction SilentlyContinue
                $LevelText = 'WARNING:'
                }
            'Info' {
                Write-Verbose $Message
                $LevelText = 'INFO:'
                }
            }
        
        # Write log entry to $Path
        "$FormattedDate $LevelText $Message" | Out-File -FilePath $Path -Append
    }
    End
    {
    }
}

#endregion FUNCTIONS

#region VARIABLES

$g_date = get-date -Format "dd-MM-yyy_HH_mm"  

$g_CurrentPath = $MyInvocation.MyCommand.Path

$g_ScriptLocation = Split-Path $g_CurrentPath -Parent

$g_Log = "$g_ScriptLocation\$g_date"

$g_Logs = "$g_ScriptLocation\Logs"

$VerbosePreference = "SilentlyContinue"

#region Ini

$g_IniLocation = "$g_ScriptLocation\Backup.ini"

if(!(Test-Path -Path $g_IniLocation)){ return 1}

#endregion Ini

#region Source\Target 

$g_Source = (Get-PrivateProfileString -Path $g_IniLocation -Category General -Key Source).Split(",")

if($g_Source -eq $null){ return 2}

$g_Target = (Get-PrivateProfileString -Path $g_IniLocation -Category General -Key Target).Split(",")

if($g_Target -eq $null) { return 3}

#endregion Source\Target 

#endregion VARIABLES

#region LOGGING

if(!(Test-Path -Path $g_Logs)) {

    New-Item  -Path $g_Logs -ItemType Directory
}

if(Test-Path -Path "$g_ScriptLocation\*.log") {

    gci $g_ScriptLocation -File | ? {$_.Name -like "*.log"} | Move-Item -Destination $g_Logs -Force
}

#endregion LOGGING

#region COPY

try {
    
    foreach($source in $g_source) {

        [array]$filesArray = gci -Path $source -Recurse -File

        [array]$directoryArray = gci -Path $source -Recurse -Directory

        [array]$toCopy =  $filesArray | Get-Item | Get-FileHash -Algorithm SHA256 

        foreach($targetPath in $g_target) {

            #region Variables

            $g_LogLocal += "${g_Log}_${targetPath}.log"

            [array]$copied = @()

            #endregion Variables

            #region Prepare Files & Directories

            foreach($file in $filesArray) {
        
                $destination = $targetPath + "\" + $g_date + "\" + (Split-Path $file.FullName).Substring(3)

                if(!(Test-Path $destination)) {
            
                    try{

                        $newItem = New-Item $destination -ItemType directory -ErrorAction Stop
                    }
                    catch{
                    
                        $ErrorMessage = $_.Exception.Message

                        $FailedItem = $_.Exception.ItemName
                    }
                }

                try{

                    [array]$copied += Copy-Item $file.FullName $destination -Force -PassThru -ErrorAction Stop `
                                        | Get-FileHash -Algorithm SHA256 -ErrorAction Stop
                }
                catch{

                    $ErrorMessage = $_.Exception.Message

                    $FailedItem = $_.Exception.ItemName
                }
            } # end loop

            #endregion Prepare Files & Directories

            #region check Hash Tables 
       
            for($i = 0 ; $i -lt $toCopy.Length; $i++) {

                if($copied.Hash.Contains($toCopy[$i].Hash)) {

                    $message = "Succesfully copied! `r`n" `
                            + "Source:" + $toCopy[$i].Path + "`r`n" `
                                + "Destination: " + $copied[$i].Path + "`r`n" `
                                    + "Hash:" + $toCopy[$i].Hash + "`r`n" `
                
                    Write-Log -Message $message -Path $g_Log -Level Info
                }
                else {
            
                    $message = "Copying failed! `r`n" `
                                    + "Source:" + $toCopy[$i].Path + "`r`n" `
                                        + "Destination: " + $copied[$i].Path + "`r`n" `
                                            + "Hash:" + $toCopy[$i].Hash + "`r`n" `
                                                + "Hash:" + $copied[$i].Hash + "`r`n" `
                
                    Write-Log -Message $message -Path $g_LogLocal -Level Warn
                }
            } # end loop

            #endregion check Hash Tables  

            Copy-Item $g_LogLocal $targetPath

        } #end loop
    } #end loop
}
catch {

    $ErrorMessage = $_.Exception.Message

    $FailedItem = $_.Exception.ItemName
}

#endregion COPY
