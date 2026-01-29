#SETTINGS
$linuxUser = "devuser"

$appsToInstall = @(
    "Microsoft.WindowsTerminal",
    "Unity.UnityHub",
    "OBSProject.OBSStudio",
    "Google.Chrome",
    "Mozilla.Firefox",
    "Discord.Discord",
    "Valve.Steam",
    "AntibodySoftware.WizTree",
    "Docker.DockerDesktop",
    "astral-sh.uv",
    "CoreyButler.NVMforWindows",
    "Canva.Affinity",
    "Git.Git",
    "CPUID.HWMonitor",
    "Postman.Postman",
    "PrismLauncher.PrismLauncher",
    "HandBrake.HandBrake",
    "Microsoft.VisualStudioCode"
)

$ohMyPoshThemeUrl = "https://raw.githubusercontent.com/Jose-AE/oh-my-posh-template-powerline-prism/main/powerline_prism.omp.json"

$powershellProfile = @'

$showTimeInPrompt = $false

if ($showTimeInPrompt) {
    $global:StartTime = Get-Date
}


#==========Profile Start==========#

$configPath = "$HOME\.oh-my-posh\theme.omp.json"
oh-my-posh init pwsh --config $configPath | Invoke-Expression

#==========Profile End============#

if ($showTimeInPrompt) {
    $global:EndTime = Get-Date
    Write-Host ("Profile load duration: {0} ms" -f ($EndTime - $StartTime).TotalMilliseconds)
}
'@


function Test-Admin {
    #Check for admin rights
    $IsAdmin = ([Security.Principal.WindowsPrincipal] `
            [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $IsAdmin) {
        Write-Error "This script must be run as Administrator."
        exit 1
    }
}



function Enable-WSL {
    # Install / configure WSL
    Write-Host "[Enable-WSL] Enabling WSL and installing Ubuntu..." -ForegroundColor Cyan
    wsl --install -d Ubuntu --no-launch
    Restart-EnvVariables

    # Create the user and remove password
    Write-Host "[Enable-WSL] Creating user $linuxUser and removing password..." -ForegroundColor Cyan
    wsl -d Ubuntu -u root -- bash -c "
    id $linuxUser 2>/dev/null || useradd -m -s /bin/bash $linuxUser
    passwd -d $linuxUser
    "

    # Enable passwordless sudo
    wsl -d Ubuntu -u root -- bash -c "
    echo '$linuxUser ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/$linuxUser
    chmod 440 /etc/sudoers.d/$linuxUser
    "

    # Set default WSL user
    Write-Host "[Enable-WSL] Setting default WSL user to $linuxUser..." -ForegroundColor Cyan
    ubuntu config --default-user $linuxUser


    #Update and upgrade packages
    Write-Host "[Enable-WSL] Updating and upgrading packages..." -ForegroundColor Cyan
    wsl -d Ubuntu -- bash -c "
    sudo apt update && sudo apt upgrade -y
    "
}




function Get-Missing-Apps {
    Write-Host "[Get-Missing-Apps] Checking installed applications via winget..." -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Gray

    # Get list of all installed packages
    $installedApps = winget list | Out-String


    # Check each app
    $results = @()
    foreach ($app in $appsToInstall) {
        $isInstalled = $installedApps -match [regex]::Escape($app)
        
        $result = [PSCustomObject]@{
            Application = $app
            Installed   = $isInstalled
        }
        
        $results += $result
        
        # Display result with color
        if ($isInstalled) {
            Write-Host "[✓] $app" -ForegroundColor Green
        }
        else {
            Write-Host "[✗] $app" -ForegroundColor Red
        }
    }

    Write-Host ("=" * 60) -ForegroundColor Gray

    # Summary
    $installedCount = ($results | Where-Object { $_.Installed }).Count
    $totalCount = $results.Count

    Write-Host "`nSummary: $installedCount of $totalCount applications installed" -ForegroundColor Cyan


    return $results | Where-Object { -not $_.Installed }
}


#install missing apps
function Install-Missing-Apps {
    Write-Host "[Install-Missing-Apps] Installing missing applications..." -ForegroundColor Cyan

    $missingApps = Get-Missing-Apps

    foreach ($app in $missingApps) {
        Write-Host "[Install-Missing-Apps] Installing $($app.Application)..." -ForegroundColor Yellow
        winget install -e --id $app.Application --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
    }
}



function Set-OhMyPoshConfig {
    Write-Host "[Set-OhMyPoshConfig] Installing and configuring Oh My Posh..." -ForegroundColor Cyan

    winget install -e --id JanDeDobbeleer.OhMyPosh --silent --accept-package-agreements --accept-source-agreements --disable-interactivity

    Restart-EnvVariables

    # Define Vars
    $configDir = "$HOME\.oh-my-posh"
    $configPath = Join-Path $configDir "theme.omp.json"
    $profilePath = "$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"

    #Create config directory if missing
    Write-Host "[Set-OhMyPoshConfig] Creating config directory at $configDir..."
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null

    #Download theme config
    Write-Host "[Set-OhMyPoshConfig] Downloading theme config..."
    Invoke-WebRequest -Uri $ohMyPoshThemeUrl -OutFile $configPath -UseBasicParsing

    #Setup PowerShell profile
    Write-Host "[Set-OhMyPoshConfig] Setting up PowerShell profile at $profilePath..."
    New-Item -ItemType Directory -Path (Split-Path $profilePath) -Force
    Set-Content -Path $profilePath -Value $powershellProfile 

    #Install Oh My Posh in WSL and theme
    wsl -d Ubuntu -- bash -c "
    curl -s https://ohmyposh.dev/install.sh | sudo bash -s -- -d /usr/local/bin
    mkdir -p ~/.oh-my-posh
    curl -sSL $ohMyPoshThemeUrl -o ~/.oh-my-posh/theme.omp.json
    "

    #Setup Oh My Posh in WSL bash profile
    wsl -d Ubuntu -- bash -c '
    eval_line=$(oh-my-posh init bash --config ~/.oh-my-posh/theme.omp.json)

    grep -qxF "$eval_line" ~/.bashrc || {
        echo "$eval_line" >> ~/.bashrc
        echo Added Oh My Posh init to ~/.bashrc
    }
   '
}


function Set-WindowsTerminalConfig {
    Write-Host "[Set-WindowsTerminalConfig] Configuring Windows Terminal..." -ForegroundColor Cyan

    #Install font
    oh-my-posh font install CascadiaCode

    # Path to Windows Terminal settings
    $settingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"

    if (Test-Path $settingsPath) {
        # Load current settings
        $settingsJson = Get-Content $settingsPath -Raw | ConvertFrom-Json

        # Set default profile to PowerShell
        $settingsJson.defaultProfile = "{574e775e-4f2a-5b96-ac1e-a2962a402336}"


        #Set font
        # Ensure 'profiles' exists
        if (-not $settingsJson.profiles) {
            $settingsJson | Add-Member -MemberType NoteProperty -Name profiles -Value @{}
        }

        # Ensure 'defaults' exists
        if (-not $settingsJson.profiles.defaults) {
            $settingsJson.profiles | Add-Member -MemberType NoteProperty -Name defaults -Value @{}
        }

        # Ensure 'font' exists
        if (-not $settingsJson.profiles.defaults.font) {
            $settingsJson.profiles.defaults | Add-Member -MemberType NoteProperty -Name font -Value @{}
        }

        # Now safe to set the font face
        $settingsJson.profiles.defaults.font.face = "CaskaydiaCove Nerd Font Mono"

     
        # Save updated settings
        $settingsJson | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath -Encoding UTF8
        Write-Output "Windows Terminal configured."
    }
    else {
        Write-Warning "Settings file not found at $settingsPath"
    }
}

function Set-GitHubFolder {
    Write-Host "[Set-GitHubFolder] Creating and configuring GitHub folder..." -ForegroundColor Cyan

    $IconUrl = "https://raw.githubusercontent.com/sameerasw/folder-icons/main/ICO/github-alt.ico"
    $githubPath = "$HOME\GitHub"

    # Create folder if it doesn't exist
    if (-not (Test-Path $githubPath)) {
        New-Item -ItemType Directory -Path $githubPath -Force | Out-Null
        Write-Host "[Set-GitHubFolder] Created GitHub folder at $githubPath" -ForegroundColor Cyan
    }
    else {
        Write-Host "[Set-GitHubFolder] GitHub folder already exists at $githubPath" -ForegroundColor Yellow
    }

    # Pin folder to Quick Access
    try {
        $shell = New-Object -ComObject Shell.Application
        $folder = $shell.Namespace($githubPath)
        if ($folder) {
            $folderItem = $folder.Self
            $folderItem.InvokeVerb("pintohome")
            Write-Host "[Set-GitHubFolder] Pinned GitHub folder to Quick Access" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "[Set-GitHubFolder] Error pinning folder: $_" -ForegroundColor Red
    }

    # Download icon from GitHub
    $iconPath = "$githubPath\github.ico"
    try {
        Invoke-WebRequest -Uri $IconUrl -OutFile $iconPath -UseBasicParsing
        Write-Host "[Set-GitHubFolder] Downloaded icon to $iconPath" -ForegroundColor Cyan

        # Make the icon hidden and a system file
        attrib +h +s $iconPath
        Write-Host "[Set-GitHubFolder] Set icon as hidden and system" -ForegroundColor Cyan
    }
    catch {
        Write-Host "[Set-GitHubFolder] Failed to download icon: $_" -ForegroundColor Red
        return
    }

    # Create desktop.ini to set folder icon
    $desktopIniPath = "$githubPath\desktop.ini"
    $desktopIniContent = @"
[.ShellClassInfo]
IconResource=$iconPath,0
IconFile=$iconPath
IconIndex=0
"@
    $desktopIniContent | Set-Content -Path $desktopIniPath -Encoding Unicode

    # Set folder and desktop.ini attributes
    attrib +s $githubPath          # make folder system to apply desktop.ini icon
    attrib +h +s $desktopIniPath   # hide desktop.ini

    Write-Host "[Set-GitHubFolder] Applied custom GitHub icon" -ForegroundColor Green
}


function Restart-EnvVariables {
    # Refresh environment variables
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

function Main {
    Write-Host "Starting setup..." -ForegroundColor Cyan
    Test-Admin
    Enable-WSL
    Set-OhMyPoshConfig
    Set-WindowsTerminalConfig
    Set-GitHubFolder
    
    Install-Missing-Apps
    Write-Host "`nSetup completed successfully!" -ForegroundColor Green
}



# Run main setup
Main

















