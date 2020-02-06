# Will look for new versions of mods
# If found will download, unpack and replace the mod in the mod-directory
# The file-name will be stripped of versionnumber 
# This way you wont have to reactivate it in the ETS2/ATS client

param([switch]$Silent)

# Start by checking file-paths
$basePath = $PSScriptRoot
$rssUrls = "$basePath\feeds.txt"
$downloadLog = "$basePath\download.log"
$unpackLog = "$basePath\unpack.log"
$7zipPath = "$basePath\7za.exe"
$temporaryDownloadPath = "$env:TEMP\modDownload"
$temporaryUnpackPath = "$env:TEMP\modUnpack"
$userDocumentsPath = "$env:USERPROFILE\Documents"
$atsModPath = "$userDocumentsPath\American Truck Simulator\mod"
$atsModVersions = "$userDocumentsPath\American Truck Simulator\mod_versions.json"
$etsmodPath = "$userDocumentsPath\Euro Truck Simulator 2\mod"
$etsModVersions = "$userDocumentsPath\Euro Truck Simulator 2\mod_versions.json"


if (-not (Test-Path $rssUrls)) {
    Write-Host "File containing rss-paths to search cannot be found. Creating default-file and exiting."
    Start-Sleep -Seconds 5
    "# This file contains the rss-paths to search for downloads, one per line" > $rssUrls
    "# For example: https://atsmods.lt/search/JAZZYCAT/feed/rss2/ or https://ets2.lt/en/search/sounds+for+JAZZYCAT/feed/rss2/" >> $rssUrls
}
if (-not (Test-Path $downloadLog)) {
    "# This file is a log of all downloaded files, stopping the script from downloading the same file twice" > $downloadLog
}
if (-not (Test-Path $unpackLog)) {
    "# This file is a log of all unpacked files" > $unpackLog
}
if (-not (Test-Path $7zipPath)) {
    Write-Error -Message "7-zip cannot be found, please put 7za.exe and 7za.dll in $basePath." -Category OpenError
    return
}
if (-not (Test-Path $atsModPath) -and -not (Test-Path $etsmodPath)) {
    Write-Error -Message "Cannot find ATS or ETS2 mod-directory. Please check that either $atsModPath or $etsmodPath exists." -Category OpenError
    return
}
if ((Test-Path $atsModPath) -and -not (Test-Path $atsModVersions)) {
    "# This file contains the current versions of all automatically downloaded mods" > $atsModVersions
}
if ((Test-Path $etsModPath) -and -not (Test-Path $etsModVersions)) {
    "# This file contains the current versions of all automatically downloaded mods" > $etsModVersions
}
if (-not (Test-Path $temporaryDownloadPath)) {
    New-Item -Path $temporaryDownloadPath -ItemType Directory | Out-Null
}
if (-not (Test-Path $temporaryUnpackPath)) {
    New-Item -Path $temporaryUnpackPath -ItemType Directory | Out-Null
}

# Support-functions

# Function for getting the download-link from sharemods
function GetDownloadLink {
    param($startPage)
	Write-Host -ForegroundColor Gray "Processing $(Split-Path $startPage -Leaf)"
    $subPage = Invoke-WebRequest -Uri $startPage
    $form = $subPage.RawContent.Substring($subPage.RawContent.IndexOf("Form method"))
    $id = $form.Replace("id"" value=""", "|").Split("|")[1].Split("""")[0]
	$fname = (Split-Path $link -Leaf).Replace(".html", "")
	$userAgent = [Microsoft.PowerShell.Commands.PSUserAgent]::Chrome
    $postParams = @{op="download2"; id="$id"; fname="$fname"; referer="$startPage"; method_free="Confirm Download"}
    $linkPage = Invoke-WebRequest -Uri $startPage -Method POST -Body $postParams -UserAgent $userAgent
    $downloadLink = ($linkPage.Links | Where-Object { $_.href -like "*.7z" -or $_.href -like "*.scs" }).href
    return $downloadLink
}

# Function for showing a balloon-popup with info
function ShowPopup {
    param($title, $message)
    [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
    $global:balloon = New-Object System.Windows.Forms.NotifyIcon
    $path = (Get-Process -id $pid).Path
    $balloon.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($path) 
    $balloon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
    $balloon.BalloonTipText = $message
    $balloon.BalloonTipTitle = $title 
    $balloon.Visible = $true 
    $balloon.ShowBalloonTip(5000)
}

# Function for getting version from filename
function GetVersion {
    param ($fileName)
    if(($fileName -replace 'v(\d+[\._-])+\d+') -ne $fileName) {
        $fileName -match '(\d+[\._-])+\d+' | Out-Null
        $version = $matches[0]
        $version = $version.Replace("-", ".").Replace("_", ".")
    } elseif (($fileName -replace '(\d+[\._-])+\d+') -ne $fileName) {
        $fileName -match '(\d+[\._-])+\d+' | Out-Null
        $version = $matches[0]
        $version = $version.Replace("-", ".").Replace("_", ".")
    } elseif (($fileName -replace 'v\d+') -ne $fileName) {
        $fileName -replace 'v\d+' | Out-Null
        $version = $matches[0]
        $version = $version.Replace("-", ".").Replace("_", ".")
    } else {
        $version = $null
    }
    return $version
}

# Function for moving/unpack a downloaded mod-file
function ProcessDownloadedFile {
    param($filePath,
          [switch]$ETS)

    $modPath = $atsModPath
	$modVersions = $atsModVersions
    if($ETS) {
        $modPath = $etsModPath
	    $modVersions = $etsModVersions
    }  
    
	$json = Get-Content -Path $modVersions
	$allModVersions = $json | ConvertFrom-Json
	if($filePath.EndsWith(".zip") -or $filePath.EndsWith(".7z")) {
		"$filePath is compressed file, checking content" >> $unpackLog
		$filesInZip = . $7zipPath l $filePath
		foreach($row in $filesInZip) {
			if(-not ($row.EndsWith(".scs"))) {
				continue
			}
			"Found a scs-file in row: $row" >> $unpackLog
            $fullFileName = $row.SubString(53)
            $version = GetVersion -fileName $fullFileName
            if($null -eq $version) {
                $version = GetVersion -fileName (Split-Path $filePath -Leaf) 
            }
            if($null -eq $version) {
                "Could not determine version, skipping" >> $unpackLog
                continue
            }
            $basicFileName = ($fullFileName -replace $version)
			$basicFileName = $basicFileName.Replace("__", "_").Replace("_.", ".").Replace("-.", ".")
			"$basicFileName - $version" >> $unpackLog
			if(-not $allModVersions.$basicFileName) {
                if($Silent) {
                    "Unknown mod, will skip." >> $unpackLog
                    continue
                }
                [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
                $answer = [System.Windows.Forms.MessageBox]::Show("$basicFileName has not been installed before, should it be added?" , "New mod-file detected" , 4)
                if($answer -eq "NO") {
                    "Unknown mod, will skip." >> $unpackLog
                    continue
                }
                "Adding new mod." >> $unpackLog
			}	
            if([version]$version -le [version]($allModVersions.$basicFileName)) {
                "Not higher version, skipping $fullFileName" >> $unpackLog
                continue
            }
			
			"Updating $basicFileName to $version" >> $unpackLog
			$outDirCommand = "-o$temporaryUnpackPath"
			. $7zipPath e $filePath $outDirCommand "$fullFileName" -y
			Move-Item -Path "$temporaryUnpackPath\$fullFileName" -Destination "$modPath\$basicFileName" -Force:$true
			"Done with $basicFileName" >> $unpackLog
            ShowPopup -title "$basicFileName updated" -message "$version installed"
			$json = Get-Content -Path $modVersions
			$allModVersions = $json | ConvertFrom-Json
			if($allModVersions.$basicFileName) {
				$allModVersions.$basicFileName = $version
			} else {
				$allModVersions | Add-Member -NotePropertyName $basicFileName -NotePropertyValue $version
			}
			$allModVersionsSorted = New-Object PSCustomObject
			$allModVersions | Get-Member -Type NoteProperty | Sort-Object Name | ForEach-Object { 
				Add-Member -InputObject $allModVersionsSorted -Type NoteProperty -Name $_.Name -Value $allModVersions.$($_.Name)
			}
			$fileData = $allModVersionsSorted | ConvertTo-Json
			Set-Content -Path $modVersions -Value $fileData
		}
		Remove-Item -Path $filePath -Confirm:$false
	}
	if($filePath.EndsWith(".scs")) {
		$fullFileName = Split-Path $filePath -Leaf
		$version = GetVersion -fileName $fullFileName
        if($null -eq $version) {
            "Could not determine version, skipping" >> $unpackLog
            continue
        }
        $basicFileName = ($fullFileName -replace $version)
		$basicFileName = $basicFileName.Replace("__", "_").Replace("_.", ".").Replace("-.", ".")
        if(-not $allModVersions.$basicFileName) {
            if($Silent) {
                "Unknown mod, will skip." >> $unpackLog
                continue
            }
            [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
            $answer = [System.Windows.Forms.MessageBox]::Show("$basicFileName has not been installed before, should it be added?" , "New mod-file detected" , 4)
            if($answer -eq "NO") {
                "Unknown mod, will skip." >> $unpackLog
                continue
            }
            "Adding new mod." >> $unpackLog
        }	
        if([version]$version -le [version]($allModVersions.$basicFileName)) {
            "Not higher version, skipping $fullFileName" >> $unpackLog
            Remove-Item -Path $filePath
            return
        }
		
		"Updating $basicFileName to $version" >> $unpackLog
		Move-Item -Path $filePath -Destination "$modPath\$basicFileName" -Force:$true
		"Done with $basicFileName" >> $unpackLog
		ShowPopup -title "$basicFileName updated" -message "$version installed"
		$json = Get-Content -Path $modVersions
		$allModVersions = $json | ConvertFrom-Json
		if($allModVersions.$basicFileName) {
			$allModVersions.$basicFileName = $version
		} else {
			$allModVersions | Add-Member -NotePropertyName $basicFileName -NotePropertyValue $version
		}
		$allModVersionsSorted = New-Object PSCustomObject
		$allModVersions | Get-Member -Type NoteProperty | Sort-Object Name | ForEach-Object { 
			Add-Member -InputObject $allModVersionsSorted -Type NoteProperty -Name $_.Name -Value $allModVersions.$($_.Name)
		}
		$fileData = $allModVersionsSorted | ConvertTo-Json
		Set-Content -Path $modVersions -Value $fileData
	}
}

# Function for downloading files from RSS-link
function ParseRssLink {
    param ($rssLink)
    $ETS = ($rssLink -like "ets2.lt")
    $page = Invoke-WebRequest -Uri $rssLink -UseBasicParsing
    $links = ($page.Links | Where-Object { $_.href -like "*sharemods*.7z.html" -or $_.href -like "*sharemods*.scs.html" }).href
    foreach($link in $links) {
        if($link -like "*beta*") {
            Write-Host "$(Split-Path $link -Leaf) is beta-mod, skipping"   
            continue     
        }
		$downloadLink = GetDownloadLink -startPage $link
		if(-not $downloadLink) {
			Write-Host "No downloadlink found for $link, skipping"
			continue
		}
        $fileName = Split-Path $downloadLink -Leaf
        $alreadyDownloaded = Get-Content $downloadLog
        if($alreadyDownloaded.Contains($fileName)) {
            Write-Host "$fileName already fetched, skipping"
            break
        }
        $fileName | Out-File $downloadLog -Append

        $saveTarget = "$temporaryDownloadPath\$(Split-Path $downloadLink -Leaf)"
        Write-Host "Downloading $saveTarget from $downloadLink"
        (New-Object System.Net.WebClient).DownloadFile($downloadLink, $saveTarget)
        ProcessDownloadedFile -filePath $saveTarget -ETS:$ETS
    }
}

# Main program

$feedsToCheck = Get-Content $rssUrls

foreach ($row in $feedsToCheck) {
    if($row.StartsWith("#")) {
        continue
    }
    ParseRssLink -rssLink $row
}