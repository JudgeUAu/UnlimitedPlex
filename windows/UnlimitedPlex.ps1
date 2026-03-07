#Requires -Version 5.1
# UnlimitedPlex Windows Installer
# GUI setup for Plex + Real-Debrid + Arr Stack
# Requires: Windows 10/11, Docker Desktop with WSL2 backend

# WPF requires STA (Single Threaded Apartment) mode - restart if not in STA
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    $scriptPath = $MyInvocation.MyCommand.Path
    if (-not $scriptPath) { $scriptPath = $PSCommandPath }
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -NoProfile -STA -File `"$scriptPath`"" -Verb RunAs
    exit
}

# Global error log - always write errors here so silent crashes are visible
$Script:ErrorLogPath = Join-Path $env:TEMP "UnlimitedPlex_error.log"
"[$(Get-Date)] Script started" | Out-File $Script:ErrorLogPath -Append

trap {
    $errMsg = "[$(Get-Date)] FATAL ERROR: $_`n$($_.ScriptStackTrace)"
    $errMsg | Out-File $Script:ErrorLogPath -Append
    try {
        [System.Windows.MessageBox]::Show(
            "A fatal error occurred:`n`n$_`n`nFull error log saved to:`n$Script:ErrorLogPath",
            "UnlimitedPlex Error", "OK", "Error")
    } catch {
        $errMsg | Out-File "$env:TEMP\UnlimitedPlex_fatal.log" -Append
    }
    continue
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# =============================================================================
# XAML GUI DEFINITION
# =============================================================================
[xml]$XAML = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="UnlimitedPlex Installer"
    Height="750" Width="900"
    MinHeight="650" MinWidth="800"
    WindowStartupLocation="CenterScreen"
    Background="#1a1a2e">

    <Window.Resources>
        <Style x:Key="PrimaryButton" TargetType="Button">
            <Setter Property="Background" Value="#e94560"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="20,10"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#c73652"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Background" Value="#555"/>
                                <Setter Property="Foreground" Value="#999"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="SecondaryButton" TargetType="Button">
            <Setter Property="Background" Value="#16213e"/>
            <Setter Property="Foreground" Value="#e94560"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Padding" Value="15,8"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="BorderBrush" Value="#e94560"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#1e2d5a"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="InputBox" TargetType="TextBox">
            <Setter Property="Background" Value="#16213e"/>
            <Setter Property="Foreground" Value="#e0e0e0"/>
            <Setter Property="BorderBrush" Value="#0f3460"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,8"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="CaretBrush" Value="White"/>
        </Style>

        <Style x:Key="InputPassword" TargetType="PasswordBox">
            <Setter Property="Background" Value="#16213e"/>
            <Setter Property="Foreground" Value="#e0e0e0"/>
            <Setter Property="BorderBrush" Value="#0f3460"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,8"/>
            <Setter Property="FontSize" Value="12"/>
        </Style>

        <Style x:Key="FieldLabel" TargetType="TextBlock">
            <Setter Property="Foreground" Value="#a0a0c0"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="Margin" Value="0,8,0,3"/>
        </Style>

        <Style x:Key="Card" TargetType="Border">
            <Setter Property="Background" Value="#16213e"/>
            <Setter Property="CornerRadius" Value="8"/>
            <Setter Property="Padding" Value="20"/>
            <Setter Property="Margin" Value="0,0,0,12"/>
        </Style>

        <Style x:Key="OptionCard" TargetType="Border">
            <Setter Property="Background" Value="#16213e"/>
            <Setter Property="CornerRadius" Value="8"/>
            <Setter Property="Padding" Value="15"/>
            <Setter Property="Margin" Value="0,0,8,0"/>
            <Setter Property="BorderThickness" Value="2"/>
            <Setter Property="BorderBrush" Value="#0f3460"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="70"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <Border Grid.Row="0" Background="#0f3460">
            <Grid Margin="25,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel VerticalAlignment="Center">
                    <TextBlock Text="UnlimitedPlex Installer" Foreground="White" FontSize="22" FontWeight="Bold"/>
                    <TextBlock Text="Plex + Real-Debrid + Arr Stack for Windows" Foreground="#a0b4d0" FontSize="11"/>
                </StackPanel>
                <StackPanel Grid.Column="1" VerticalAlignment="Center" Orientation="Horizontal">
                    <Ellipse x:Name="StatusDot" Width="10" Height="10" Fill="#555" Margin="0,0,8,0"/>
                    <TextBlock x:Name="StatusText" Text="Ready" Foreground="#a0b4d0" FontSize="11" VerticalAlignment="Center"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Main Content -->
        <TabControl Grid.Row="1" Background="Transparent" BorderThickness="0" Margin="15,10,15,5">
            <TabControl.Resources>
                <Style TargetType="TabItem">
                    <Setter Property="Background" Value="Transparent"/>
                    <Setter Property="Foreground" Value="#a0a0c0"/>
                    <Setter Property="FontSize" Value="12"/>
                    <Setter Property="Padding" Value="15,8"/>
                    <Setter Property="BorderThickness" Value="0"/>
                    <Setter Property="Template">
                        <Setter.Value>
                            <ControlTemplate TargetType="TabItem">
                                <Border x:Name="TabBorder" Background="Transparent"
                                        BorderThickness="0,0,0,2" BorderBrush="Transparent"
                                        Padding="{TemplateBinding Padding}">
                                    <ContentPresenter ContentSource="Header" HorizontalAlignment="Center"/>
                                </Border>
                                <ControlTemplate.Triggers>
                                    <Trigger Property="IsSelected" Value="True">
                                        <Setter TargetName="TabBorder" Property="BorderBrush" Value="#e94560"/>
                                        <Setter Property="Foreground" Value="White"/>
                                    </Trigger>
                                    <Trigger Property="IsMouseOver" Value="True">
                                        <Setter Property="Foreground" Value="#e0e0e0"/>
                                    </Trigger>
                                </ControlTemplate.Triggers>
                            </ControlTemplate>
                        </Setter.Value>
                    </Setter>
                </Style>
            </TabControl.Resources>

            <!-- TAB 1: SETUP -->
            <TabItem Header="[Setup]">
                <ScrollViewer VerticalScrollBarVisibility="Auto" Background="Transparent">
                    <StackPanel Margin="5,10,5,10">

                        <!-- Prerequisites -->
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Prerequisites" Foreground="White" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,12"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <Border Grid.Column="0" Background="#0f3460" CornerRadius="6" Padding="12" Margin="0,0,6,0">
                                        <StackPanel>
                                            <TextBlock x:Name="DockerStatus" Text="[?] Docker Desktop" Foreground="#ffcc00" FontSize="12" FontWeight="SemiBold"/>
                                            <TextBlock x:Name="DockerVersion" Text="Checking..." Foreground="#a0a0c0" FontSize="10" Margin="0,3,0,0"/>
                                        </StackPanel>
                                    </Border>
                                    <Border Grid.Column="1" Background="#0f3460" CornerRadius="6" Padding="12" Margin="3,0,3,0">
                                        <StackPanel>
                                            <TextBlock x:Name="WSLStatus" Text="[?] WSL2" Foreground="#ffcc00" FontSize="12" FontWeight="SemiBold"/>
                                            <TextBlock x:Name="WSLVersion" Text="Checking..." Foreground="#a0a0c0" FontSize="10" Margin="0,3,0,0"/>
                                        </StackPanel>
                                    </Border>
                                    <Border Grid.Column="2" Background="#0f3460" CornerRadius="6" Padding="12" Margin="6,0,0,0">
                                        <StackPanel>
                                            <TextBlock x:Name="AdminStatus" Text="[?] Admin Rights" Foreground="#ffcc00" FontSize="12" FontWeight="SemiBold"/>
                                            <TextBlock x:Name="AdminVersion" Text="Checking..." Foreground="#a0a0c0" FontSize="10" Margin="0,3,0,0"/>
                                        </StackPanel>
                                    </Border>
                                </Grid>
                                <Button x:Name="CheckPrereqsBtn" Content="Check Prerequisites"
                                        Style="{StaticResource SecondaryButton}"
                                        HorizontalAlignment="Left" Margin="0,12,0,0"/>
                            </StackPanel>
                        </Border>

                        <!-- Setup Option -->
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Setup Option" Foreground="White" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,12"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>

                                    <Border x:Name="Opt1Card" Grid.Column="0" Style="{StaticResource OptionCard}">
                                        <StackPanel>
                                            <TextBlock Text="[1] Basic" Foreground="White" FontSize="13" FontWeight="Bold"/>
                                            <TextBlock Text="Plex + Real-Debrid" Foreground="#e94560" FontSize="11" Margin="0,4,0,6"/>
                                            <TextBlock TextWrapping="Wrap" Foreground="#a0a0c0" FontSize="10"
                                                       Text="- Plex Media Server&#x0a;- Zurg + Rclone&#x0a;- plex_debrid&#x0a;- Simple setup"/>
                                        </StackPanel>
                                    </Border>

                                    <Border x:Name="Opt2Card" Grid.Column="1" Style="{StaticResource OptionCard}"
                                            BorderBrush="#e94560" Margin="4,0,4,0">
                                        <StackPanel>
                                            <TextBlock Text="[2] Arr Stack (Recommended)" Foreground="White" FontSize="13" FontWeight="Bold"/>
                                            <TextBlock Text="Full Media Management" Foreground="#e94560" FontSize="11" Margin="0,4,0,6"/>
                                            <TextBlock TextWrapping="Wrap" Foreground="#a0a0c0" FontSize="10"
                                                       Text="- Everything in Basic&#x0a;- Sonarr + Radarr (4K)&#x0a;- Prowlarr + Overseerr&#x0a;- Decypharr + Pulsarr"/>
                                        </StackPanel>
                                    </Border>

                                    <Border x:Name="Opt3Card" Grid.Column="2" Style="{StaticResource OptionCard}">
                                        <StackPanel>
                                            <TextBlock Text="[3] Arr Stack + NZBDav" Foreground="White" FontSize="13" FontWeight="Bold"/>
                                            <TextBlock Text="Debrid + Usenet" Foreground="#e94560" FontSize="11" Margin="0,4,0,6"/>
                                            <TextBlock TextWrapping="Wrap" Foreground="#a0a0c0" FontSize="10"
                                                       Text="- Everything in Arr Stack&#x0a;- NZBDav Usenet streaming&#x0a;- SABnzbd API mock&#x0a;- Dual download sources"/>
                                        </StackPanel>
                                    </Border>
                                </Grid>
                                <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                                    <RadioButton x:Name="Opt1Radio" Content="Option 1" Foreground="#a0a0c0"
                                                 GroupName="SetupOption" Margin="0,0,20,0" FontSize="11"/>
                                    <RadioButton x:Name="Opt2Radio" Content="Option 2" Foreground="#a0a0c0"
                                                 GroupName="SetupOption" IsChecked="True" Margin="0,0,20,0" FontSize="11"/>
                                    <RadioButton x:Name="Opt3Radio" Content="Option 3" Foreground="#a0a0c0"
                                                 GroupName="SetupOption" FontSize="11"/>
                                </StackPanel>
                            </StackPanel>
                        </Border>

                        <!-- Configuration -->
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Configuration" Foreground="White" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,12"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="15"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <StackPanel Grid.Column="0">
                                        <TextBlock Text="Real-Debrid API Token *" Style="{StaticResource FieldLabel}"/>
                                        <PasswordBox x:Name="RDTokenBox" Style="{StaticResource InputPassword}"
                                                     ToolTip="Get from: real-debrid.com/apitoken"/>
                                        <TextBlock Foreground="#555" FontSize="9" Margin="0,2,0,0" Text="real-debrid.com/apitoken"/>

                                        <TextBlock Text="Plex Token *" Style="{StaticResource FieldLabel}"/>
                                        <PasswordBox x:Name="PlexTokenBox" Style="{StaticResource InputPassword}"
                                                     ToolTip="Get from Plex account settings"/>
                                        <TextBlock Foreground="#555" FontSize="9" Margin="0,2,0,0" Text="plex.tv/claim or account settings"/>

                                        <TextBlock Text="Timezone" Style="{StaticResource FieldLabel}"/>
                                        <TextBox x:Name="TimezoneBox" Style="{StaticResource InputBox}" Text="Etc/UTC"
                                                 ToolTip="e.g. America/New_York, Europe/London, Australia/Sydney"/>
                                    </StackPanel>
                                    <StackPanel Grid.Column="2">
                                        <TextBlock Text="Zurg Version" Style="{StaticResource FieldLabel}"/>
                                        <TextBox x:Name="ZurgVersionBox" Style="{StaticResource InputBox}" Text="v0.9.3-final"/>

                                        <TextBlock Text="WSL2 Distro Name" Style="{StaticResource FieldLabel}"/>
                                        <TextBox x:Name="WSLDistroBox" Style="{StaticResource InputBox}" Text="Ubuntu"
                                                 ToolTip="Name of your WSL2 distro (run 'wsl -l' to check)"/>

                                        <TextBlock x:Name="NZBDavLabel" Text="NZBDav WebDAV Password"
                                                   Style="{StaticResource FieldLabel}" Opacity="0.4"/>
                                        <PasswordBox x:Name="NZBDavPassBox" Style="{StaticResource InputPassword}"
                                                     IsEnabled="False" Opacity="0.4"
                                                     ToolTip="Required for Option 3 only"/>
                                    </StackPanel>
                                </Grid>
                            </StackPanel>
                        </Border>

                        <!-- Install Button -->
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <ProgressBar x:Name="InstallProgress" Grid.Column="0"
                                         Height="38" Minimum="0" Maximum="100" Value="0"
                                         Background="#16213e" Foreground="#e94560"
                                         BorderThickness="0" Margin="0,0,10,0"/>
                            <TextBlock x:Name="ProgressLabel" Text="0%" Foreground="White"
                                       FontSize="12" VerticalAlignment="Center"
                                       HorizontalAlignment="Center"
                                       Grid.Column="0" IsHitTestVisible="False"/>
                            <Button x:Name="InstallBtn" Grid.Column="1"
                                    Content="&gt;&gt; Install" Style="{StaticResource PrimaryButton}"
                                    Width="130" Height="38" Margin="0,0,8,0"/>
                            <Button x:Name="StopBtn" Grid.Column="2"
                                    Content="Stop" Style="{StaticResource SecondaryButton}"
                                    Width="80" Height="38" IsEnabled="False"/>
                        </Grid>

                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- TAB 2: LOG -->
            <TabItem Header="[Log]">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <TextBox x:Name="LogBox" Grid.Row="0"
                             Background="#0d0d1a" Foreground="#00ff88"
                             FontFamily="Consolas" FontSize="11"
                             IsReadOnly="True" TextWrapping="Wrap"
                             VerticalScrollBarVisibility="Auto"
                             HorizontalScrollBarVisibility="Auto"
                             BorderThickness="0" Padding="10" AcceptsReturn="True"/>
                    <StackPanel Grid.Row="1" Orientation="Horizontal"
                                HorizontalAlignment="Right" Margin="0,8,0,0">
                        <Button x:Name="ClearLogBtn" Content="Clear Log"
                                Style="{StaticResource SecondaryButton}" Margin="0,0,8,0"/>
                        <Button x:Name="SaveLogBtn" Content="Save Log"
                                Style="{StaticResource SecondaryButton}"/>
                    </StackPanel>
                </Grid>
            </TabItem>

            <!-- TAB 3: SERVICES -->
            <TabItem Header="[Services]">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                        <StackPanel x:Name="ServicesPanel" Margin="5,10,5,10">
                            <TextBlock Text="Service Status" Foreground="White" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,12"/>
                            <TextBlock Text="Click Refresh to check running services." Foreground="#a0a0c0" FontSize="11"/>
                        </StackPanel>
                    </ScrollViewer>
                    <Button x:Name="RefreshServicesBtn" Grid.Row="1"
                            Content="Refresh Services" Style="{StaticResource SecondaryButton}"
                            HorizontalAlignment="Left" Margin="5,8,0,0"/>
                </Grid>
            </TabItem>

            <!-- TAB 4: HELP -->
            <TabItem Header="[Help]">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="5,10,5,10">
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Quick Start" Foreground="White" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,10"/>
                                <TextBlock TextWrapping="Wrap" Foreground="#c0c0d0" FontSize="12" LineHeight="20">
1. Click 'Check Prerequisites' to verify Docker Desktop and WSL2 are installed.
2. If Docker Desktop is not installed, click the button below to download it.
3. Select your setup option (Option 2 - Arr Stack is recommended).
4. Enter your Real-Debrid API token and Plex token.
5. Click 'Install' to begin.
                                </TextBlock>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Prerequisites" Foreground="White" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,10"/>
                                <TextBlock TextWrapping="Wrap" Foreground="#c0c0d0" FontSize="12" LineHeight="20">
- Windows 10 (version 2004+) or Windows 11
- Docker Desktop with WSL2 backend enabled
- WSL2 with Ubuntu installed (run: wsl --install)
- 8GB+ RAM recommended
- 50GB+ free disk space
                                </TextBlock>
                                <Button x:Name="OpenDockerBtn" Content="Download Docker Desktop"
                                        Style="{StaticResource SecondaryButton}"
                                        HorizontalAlignment="Left" Margin="0,10,0,0"/>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Service URLs (after install)" Foreground="White" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,10"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Grid.Column="0" Foreground="#c0c0d0" FontSize="11" LineHeight="22"
                                               Text="Plex:         http://localhost:32400/web&#x0a;Prowlarr:     http://localhost:9696&#x0a;Radarr:       http://localhost:7878&#x0a;Radarr 4K:    http://localhost:7879&#x0a;Sonarr:       http://localhost:8989"/>
                                    <TextBlock Grid.Column="1" Foreground="#c0c0d0" FontSize="11" LineHeight="22"
                                               Text="Sonarr 4K:    http://localhost:8990&#x0a;Overseerr:    http://localhost:5055&#x0a;Pulsarr:      http://localhost:3003&#x0a;Decypharr:    http://localhost:8282&#x0a;NZBDav:       http://localhost:3000"/>
                                </Grid>
                                <Button x:Name="OpenServicesBtn" Content="Open All Services"
                                        Style="{StaticResource SecondaryButton}"
                                        HorizontalAlignment="Left" Margin="0,10,0,0"/>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Troubleshooting" Foreground="White" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,10"/>
                                <TextBlock TextWrapping="Wrap" Foreground="#c0c0d0" FontSize="12" LineHeight="20">
- If Docker is not detected, make sure Docker Desktop is running.
- If WSL2 is not found, run: wsl --install  in PowerShell as Administrator.
- If install fails, check the Log tab for error details.
- All services run inside WSL2 Ubuntu - use the Services tab to check status.
- To restart services: open WSL2 and run: sudo /root/startup.sh
                                </TextBlock>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
        </TabControl>

        <!-- Footer -->
        <Border Grid.Row="2" Background="#0f3460" Padding="15,8">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock x:Name="FooterStatus" Text="Ready to install."
                           Foreground="#a0b4d0" FontSize="11" VerticalAlignment="Center"/>
                <TextBlock Grid.Column="1" Text="UnlimitedPlex v1.0 | github.com/JudgeUAu/UnlimitedPlex"
                           Foreground="#555" FontSize="10" VerticalAlignment="Center"/>
            </Grid>
        </Border>
    </Grid>
</Window>
'@

# =============================================================================
# LOAD XAML
# =============================================================================
$Reader = [System.Xml.XmlNodeReader]::new($XAML)
$Window = [Windows.Markup.XamlReader]::Load($Reader)

# Get controls
$CheckPrereqsBtn    = $Window.FindName("CheckPrereqsBtn")
$InstallBtn         = $Window.FindName("InstallBtn")
$StopBtn            = $Window.FindName("StopBtn")
$ClearLogBtn        = $Window.FindName("ClearLogBtn")
$SaveLogBtn         = $Window.FindName("SaveLogBtn")
$RefreshServicesBtn = $Window.FindName("RefreshServicesBtn")
$OpenDockerBtn      = $Window.FindName("OpenDockerBtn")
$OpenServicesBtn    = $Window.FindName("OpenServicesBtn")
$LogBox             = $Window.FindName("LogBox")
$InstallProgress    = $Window.FindName("InstallProgress")
$ProgressLabel      = $Window.FindName("ProgressLabel")
$FooterStatus       = $Window.FindName("FooterStatus")
$StatusDot          = $Window.FindName("StatusDot")
$StatusText         = $Window.FindName("StatusText")
$ServicesPanel      = $Window.FindName("ServicesPanel")
$DockerStatus       = $Window.FindName("DockerStatus")
$DockerVersion      = $Window.FindName("DockerVersion")
$WSLStatus          = $Window.FindName("WSLStatus")
$WSLVersion         = $Window.FindName("WSLVersion")
$AdminStatus        = $Window.FindName("AdminStatus")
$AdminVersion       = $Window.FindName("AdminVersion")
$RDTokenBox         = $Window.FindName("RDTokenBox")
$PlexTokenBox       = $Window.FindName("PlexTokenBox")
$TimezoneBox        = $Window.FindName("TimezoneBox")
$ZurgVersionBox     = $Window.FindName("ZurgVersionBox")
$WSLDistroBox       = $Window.FindName("WSLDistroBox")
$NZBDavPassBox      = $Window.FindName("NZBDavPassBox")
$NZBDavLabel        = $Window.FindName("NZBDavLabel")
$Opt1Radio          = $Window.FindName("Opt1Radio")
$Opt2Radio          = $Window.FindName("Opt2Radio")
$Opt3Radio          = $Window.FindName("Opt3Radio")
$Opt1Card           = $Window.FindName("Opt1Card")
$Opt2Card           = $Window.FindName("Opt2Card")
$Opt3Card           = $Window.FindName("Opt3Card")

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================
$Script:StopRequested = $false

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $prefix = switch ($Level) {
        "INFO"    { "[INFO]   " }
        "WARN"    { "[WARN]   " }
        "ERROR"   { "[ERROR]  " }
        "SUCCESS" { "[OK]     " }
        "STEP"    { "[STEP]   " }
        default   { "[INFO]   " }
    }
    $Window.Dispatcher.Invoke({
        $LogBox.AppendText("[$timestamp] $prefix $Message`n")
        $LogBox.ScrollToEnd()
        $FooterStatus.Text = $Message
    })
}

function Set-Progress {
    param([int]$Value, [string]$Label = "")
    $Window.Dispatcher.Invoke({
        $InstallProgress.Value = $Value
        $ProgressLabel.Text = if ($Label) { $Label } else { "$Value%" }
    })
}

function Set-Status {
    param([string]$Text, [string]$Color = "#555")
    $Window.Dispatcher.Invoke({
        $StatusDot.Fill = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString($Color))
        $StatusText.Text = $Text
    })
}

function Test-DockerRunning {
    try {
        # Try docker directly first
        $dockerPath = Get-Command docker -ErrorAction SilentlyContinue
        if ($dockerPath) {
            & docker info 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { return $true }
        }
        # Fallback: check via WSL
        $distro = $WSLDistroBox.Text.Trim()
        if ($distro) {
            $result = & wsl -d $distro -e bash -c "docker info 2>/dev/null && echo ok" 2>&1
            if ("$result" -match "ok") { return $true }
        }
        return $false
    } catch {
        return $false
    }
}

function Test-AdminRights {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# =============================================================================
# OPTION CARD CLICK HANDLERS
# =============================================================================
$Opt1Card.Add_MouseLeftButtonUp({
    $Opt1Radio.IsChecked = $true
    $Opt1Card.BorderBrush = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#e94560"))
    $Opt2Card.BorderBrush = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#0f3460"))
    $Opt3Card.BorderBrush = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#0f3460"))
    $NZBDavPassBox.IsEnabled = $false
    $NZBDavPassBox.Opacity = 0.4
    $NZBDavLabel.Opacity = 0.4
})

$Opt2Card.Add_MouseLeftButtonUp({
    $Opt2Radio.IsChecked = $true
    $Opt1Card.BorderBrush = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#0f3460"))
    $Opt2Card.BorderBrush = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#e94560"))
    $Opt3Card.BorderBrush = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#0f3460"))
    $NZBDavPassBox.IsEnabled = $false
    $NZBDavPassBox.Opacity = 0.4
    $NZBDavLabel.Opacity = 0.4
})

$Opt3Card.Add_MouseLeftButtonUp({
    $Opt3Radio.IsChecked = $true
    $Opt1Card.BorderBrush = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#0f3460"))
    $Opt2Card.BorderBrush = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#0f3460"))
    $Opt3Card.BorderBrush = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#e94560"))
    $NZBDavPassBox.IsEnabled = $true
    $NZBDavPassBox.Opacity = 1.0
    $NZBDavLabel.Opacity = 1.0
})

# =============================================================================
# CHECK PREREQUISITES
# =============================================================================
$CheckPrereqsBtn.Add_Click({
    Write-Log "Checking prerequisites..." "STEP"

    # Check Admin
    if (Test-AdminRights) {
        $AdminStatus.Text = "[OK] Admin Rights"
        $AdminStatus.Foreground = [Windows.Media.Brushes]::LightGreen
        $AdminVersion.Text = "Running as Administrator"
        Write-Log "Admin rights: OK" "SUCCESS"
    } else {
        $AdminStatus.Text = "[!] Admin Rights"
        $AdminStatus.Foreground = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#ffcc00"))
        $AdminVersion.Text = "Not admin - some steps may fail"
        Write-Log "Not running as Administrator - recommend restarting as Admin" "WARN"
    }

    # Check Docker
    if (Test-DockerRunning) {
        $ver = (& docker version --format "{{.Server.Version}}" 2>&1)
        $DockerStatus.Text = "[OK] Docker Desktop"
        $DockerStatus.Foreground = [Windows.Media.Brushes]::LightGreen
        $DockerVersion.Text = "Version: $ver"
        Write-Log "Docker Desktop: OK (v$ver)" "SUCCESS"
    } else {
        $dockerExe = Get-Command docker -ErrorAction SilentlyContinue
        if ($dockerExe) {
            $DockerStatus.Text = "[!] Docker (not running)"
            $DockerStatus.Foreground = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#ffcc00"))
            $DockerVersion.Text = "Found but not running"
            Write-Log "Docker found but not running - please start Docker Desktop" "WARN"
        } else {
            $DockerStatus.Text = "[X] Docker Desktop"
            $DockerStatus.Foreground = [Windows.Media.Brushes]::Salmon
            $DockerVersion.Text = "Not installed"
            Write-Log "Docker Desktop not found - please install it" "ERROR"
        }
    }

    # Check WSL2
    # NOTE: wsl --list output is UTF-16LE with null bytes - must clean before matching
    try {
        $wslFound = $false
        $distroFound = $false
        $distro = $WSLDistroBox.Text.Trim()

        # Method 1: wsl -l -q (quiet, one distro per line, cleaner output)
        $wslQuiet = & wsl -l -q 2>&1
        if ($LASTEXITCODE -eq 0 -or $wslQuiet) {
            # Strip null bytes and clean the output
            $wslClean = ($wslQuiet | ForEach-Object {
                if ($_ -is [string]) { $_ -replace "`0", "" } else { "$_" -replace "`0", "" }
            }) -join "`n"
            $wslFound = $true
            if ($wslClean -match [regex]::Escape($distro)) {
                $distroFound = $true
            }
        }

        # Method 2: fallback - wsl --list --verbose with null-byte stripping
        if (-not $wslFound) {
            $wslVerbose = & wsl --list --verbose 2>&1
            $wslClean = ($wslVerbose | ForEach-Object {
                if ($_ -is [string]) { $_ -replace "`0", "" } else { "$_" -replace "`0", "" }
            }) -join "`n"
            if ($wslClean -match "NAME" -or $wslClean -match $distro) {
                $wslFound = $true
                if ($wslClean -match [regex]::Escape($distro)) {
                    $distroFound = $true
                }
            }
        }

        # Method 3: try running a simple command in the distro directly
        if (-not $distroFound) {
            $testRun = & wsl -d $distro -e echo "ok" 2>&1
            if ($LASTEXITCODE -eq 0 -and "$testRun" -match "ok") {
                $wslFound = $true
                $distroFound = $true
            }
        }

        if ($distroFound) {
            $WSLStatus.Text = "[OK] WSL2 ($distro)"
            $WSLStatus.Foreground = [Windows.Media.Brushes]::LightGreen
            $WSLVersion.Text = "Distro found: $distro"
            Write-Log "WSL2: OK - distro '$distro' found" "SUCCESS"
        } elseif ($wslFound) {
            $WSLStatus.Text = "[!] WSL2 (no $distro)"
            $WSLStatus.Foreground = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#ffcc00"))
            $WSLVersion.Text = "$distro not found - check distro name above"
            Write-Log "WSL2 found but '$distro' distro not detected. Check the WSL Distro Name field." "WARN"
            Write-Log "Run 'wsl -l -q' in PowerShell to see your distro names." "INFO"
        } else {
            $WSLStatus.Text = "[X] WSL2"
            $WSLStatus.Foreground = [Windows.Media.Brushes]::Salmon
            $WSLVersion.Text = "Not installed - run: wsl --install"
            Write-Log "WSL2 not found. Run: wsl --install" "ERROR"
        }
    } catch {
        $WSLStatus.Text = "[X] WSL2"
        $WSLStatus.Foreground = [Windows.Media.Brushes]::Salmon
        $WSLVersion.Text = "Error checking WSL2"
        Write-Log "Error checking WSL2: $_" "ERROR"
    }

    Write-Log "Prerequisites check complete." "INFO"
})

# =============================================================================
# INSTALL BUTTON
# =============================================================================
$InstallBtn.Add_Click({
    $rdToken    = $RDTokenBox.Password.Trim()
    $plexToken  = $PlexTokenBox.Password.Trim()
    $timezone   = $TimezoneBox.Text.Trim()
    $zurgVer    = $ZurgVersionBox.Text.Trim()
    $wslDistro  = $WSLDistroBox.Text.Trim()
    $nzbdavPass = $NZBDavPassBox.Password.Trim()
    $setupOpt   = if ($Opt1Radio.IsChecked) { 1 } elseif ($Opt3Radio.IsChecked) { 3 } else { 2 }

    if ([string]::IsNullOrEmpty($rdToken)) {
        [System.Windows.MessageBox]::Show("Please enter your Real-Debrid API token.", "Missing Input", "OK", "Warning")
        return
    }
    if ([string]::IsNullOrEmpty($plexToken)) {
        [System.Windows.MessageBox]::Show("Please enter your Plex token.", "Missing Input", "OK", "Warning")
        return
    }
    if ($setupOpt -eq 3 -and [string]::IsNullOrEmpty($nzbdavPass)) {
        [System.Windows.MessageBox]::Show("Please enter a WebDAV password for NZBDav (required for Option 3).", "Missing Input", "OK", "Warning")
        return
    }
    if (-not (Test-DockerRunning)) {
        [System.Windows.MessageBox]::Show("Docker Desktop is not running. Please start Docker Desktop and try again.", "Docker Not Running", "OK", "Warning")
        return
    }

    $InstallBtn.IsEnabled = $false
    $StopBtn.IsEnabled = $true
    $Script:StopRequested = $false
    Set-Status "Installing..." "#ffcc00"

    # Capture variables for thread closure
    $capturedRD      = $rdToken
    $capturedPlex    = $plexToken
    $capturedTZ      = $timezone
    $capturedZurg    = $zurgVer
    $capturedDistro  = $wslDistro
    $capturedNZBPass = $nzbdavPass
    $capturedOpt     = $setupOpt

    $installThread = [System.Threading.Thread]::new([System.Threading.ThreadStart]{
        try {
            Write-Log "================================================" "STEP"
            Write-Log "  UnlimitedPlex Installation Starting" "STEP"
            Write-Log "  Option: $capturedOpt | Distro: $capturedDistro" "STEP"
            Write-Log "================================================" "STEP"

            Set-Progress 5 "Preparing..."

            # Copy scripts to WSL
            Write-Log "Copying setup scripts to WSL2..." "INFO"
            $scriptRoot = Split-Path -Parent $PSScriptRoot
            $scripts = @("setup.sh","setup_plex_debrid.sh","setup_arr_stack.sh","setup_nzbdav.sh","fix_startup.sh","verify_setup.sh")
            foreach ($s in $scripts) {
                $src = Join-Path $scriptRoot $s
                if (Test-Path $src) {
                    $content = [System.IO.File]::ReadAllText($src) -replace "`r`n", "`n"
                    $tmpFile = [System.IO.Path]::GetTempFileName()
                    [System.IO.File]::WriteAllText($tmpFile, $content, [System.Text.Encoding]::UTF8)
                    $wslTmp = & wsl -d $capturedDistro -e wslpath -u $tmpFile 2>&1
                    & wsl -d $capturedDistro -e bash -c "cp '$wslTmp' '/root/$s' && chmod +x '/root/$s'" 2>&1 | Out-Null
                    Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
                    Write-Log "  Copied: $s" "INFO"
                } else {
                    Write-Log "  Not found locally: $s" "WARN"
                }
            }

            Set-Progress 15 "Scripts ready..."
            if ($Script:StopRequested) { throw "Stopped by user." }

            # Ensure /mnt is shared
            Write-Log "Setting up /mnt as shared mount..." "INFO"
            & wsl -d $capturedDistro -e bash -c "mount --bind /mnt /mnt 2>/dev/null; mount --make-shared /mnt 2>/dev/null" 2>&1 | Out-Null

            Set-Progress 20 "Running setup..."
            Write-Log "Starting installation (Option $capturedOpt)..." "STEP"
            Write-Log "This may take 10-20 minutes. Please wait..." "INFO"

            # Build wrapper script
            $wrapper = @"
#!/bin/bash
set -e
export RD_API_TOKEN='$capturedRD'
export PLEX_TOKEN='$capturedPlex'
export TZ='$capturedTZ'
export ZURG_VERSION='$capturedZurg'
export DEBIAN_FRONTEND=noninteractive
export AUTO_INSTALL=1
cd /root
echo '[STEP] Running base setup...'
bash /root/setup_plex_debrid.sh
"@
            if ($capturedOpt -ge 2) {
                $wrapper += "`necho '[STEP] Running arr stack setup...'`nbash /root/setup_arr_stack.sh"
            }
            if ($capturedOpt -eq 3) {
                $wrapper += "`nexport WEBDAV_PASSWORD='$capturedNZBPass'`necho '[STEP] Running NZBDav setup...'`nbash /root/setup_nzbdav.sh"
            }
            $wrapper += "`necho '[STEP] Setup complete!'"

            # Write wrapper to WSL temp
            $tmpWrapper = [System.IO.Path]::GetTempFileName() + ".sh"
            [System.IO.File]::WriteAllText($tmpWrapper, ($wrapper -replace "`r`n","`n"), [System.Text.Encoding]::UTF8)
            $wslWrapper = & wsl -d $capturedDistro -e wslpath -u $tmpWrapper 2>&1
            & wsl -d $capturedDistro -e bash -c "chmod +x '$wslWrapper'" 2>&1 | Out-Null

            # Run and stream output
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "wsl"
            $psi.Arguments = "-d $capturedDistro -e bash $wslWrapper"
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.CreateNoWindow = $true

            $proc = [System.Diagnostics.Process]::new()
            $proc.StartInfo = $psi
            $proc.Start() | Out-Null

            while (-not $proc.StandardOutput.EndOfStream) {
                if ($Script:StopRequested) { $proc.Kill(); throw "Stopped by user." }
                $line = $proc.StandardOutput.ReadLine()
                if ($line) {
                    $lvl = "INFO"
                    if ($line -match "\[ERROR\]|error") { $lvl = "ERROR" }
                    elseif ($line -match "\[WARN\]|warn") { $lvl = "WARN" }
                    elseif ($line -match "\[OK\]|success|complete|done") { $lvl = "SUCCESS" }
                    elseif ($line -match "\[STEP\]|Step |===") { $lvl = "STEP" }
                    Write-Log $line $lvl

                    if ($line -match "Step 1|system update")    { Set-Progress 25 "System update..." }
                    elseif ($line -match "Step 2|Docker")       { Set-Progress 35 "Installing Docker..." }
                    elseif ($line -match "Step 3|Zurg")         { Set-Progress 45 "Setting up Zurg..." }
                    elseif ($line -match "Step 4|Plex")         { Set-Progress 55 "Installing Plex..." }
                    elseif ($line -match "Step 5|arr stack")    { Set-Progress 65 "Deploying arr stack..." }
                    elseif ($line -match "Step 6|Decypharr")    { Set-Progress 75 "Setting up Decypharr..." }
                    elseif ($line -match "Step 7|configur")     { Set-Progress 85 "Configuring services..." }
                    elseif ($line -match "NZBDav")              { Set-Progress 90 "Setting up NZBDav..." }
                    elseif ($line -match "complete|finished")   { Set-Progress 95 "Finishing..." }
                }
            }
            $proc.WaitForExit()
            Remove-Item $tmpWrapper -Force -ErrorAction SilentlyContinue

            if ($proc.ExitCode -ne 0) {
                $err = $proc.StandardError.ReadToEnd()
                if ($err) { Write-Log "STDERR: $err" "ERROR" }
                throw "Script exited with code $($proc.ExitCode)"
            }

            Set-Progress 100 "Complete!"
            Write-Log "================================================" "SUCCESS"
            Write-Log "  Installation Complete!" "SUCCESS"
            Write-Log "================================================" "SUCCESS"
            Write-Log "  Plex:      http://localhost:32400/web" "SUCCESS"
            Write-Log "  Radarr:    http://localhost:7878" "SUCCESS"
            Write-Log "  Sonarr:    http://localhost:8989" "SUCCESS"
            Write-Log "  Prowlarr:  http://localhost:9696" "SUCCESS"
            Write-Log "  Overseerr: http://localhost:5055" "SUCCESS"
            if ($capturedOpt -eq 3) { Write-Log "  NZBDav:    http://localhost:3000" "SUCCESS" }
            Write-Log "================================================" "SUCCESS"
            Set-Status "Installation complete!" "#00ff88"

            $Window.Dispatcher.Invoke({
                [System.Windows.MessageBox]::Show(
                    "Installation complete!`n`nYour services are now running.`nCheck the Services tab to verify everything is working.",
                    "Success", "OK", "Information")
            })

        } catch {
            Write-Log "Installation failed: $_" "ERROR"
            Set-Status "Installation failed" "#ff4444"
            Set-Progress 0 "Failed"
            $Window.Dispatcher.Invoke({
                [System.Windows.MessageBox]::Show("Installation failed:`n$_`n`nCheck the Log tab for details.", "Error", "OK", "Error")
            })
        } finally {
            $Window.Dispatcher.Invoke({
                $InstallBtn.IsEnabled = $true
                $StopBtn.IsEnabled = $false
            })
        }
    })

    $installThread.IsBackground = $true
    $installThread.Start()
})

# =============================================================================
# STOP BUTTON
# =============================================================================
$StopBtn.Add_Click({
    $Script:StopRequested = $true
    Write-Log "Stop requested - waiting for current step to finish..." "WARN"
    Set-Status "Stopping..." "#ffcc00"
})

# =============================================================================
# REFRESH SERVICES
# =============================================================================
$RefreshServicesBtn.Add_Click({
    Write-Log "Checking service status..." "INFO"
    $ServicesPanel.Children.Clear()

    $header = New-Object Windows.Controls.TextBlock
    $header.Text = "Service Status"
    $header.Foreground = [Windows.Media.Brushes]::White
    $header.FontSize = 14
    $header.FontWeight = "SemiBold"
    $header.Margin = "0,0,0,12"
    $ServicesPanel.Children.Add($header) | Out-Null

    $services = @(
        @{ Name = "Plex";         Container = "plexmediaserver"; Port = 32400; Path = "/web" },
        @{ Name = "Zurg";         Container = "zurg";            Port = 9999;  Path = "" },
        @{ Name = "Prowlarr";     Container = "prowlarr";        Port = 9696;  Path = "" },
        @{ Name = "Radarr";       Container = "radarr";          Port = 7878;  Path = "" },
        @{ Name = "Radarr 4K";    Container = "radarr4k";        Port = 7879;  Path = "" },
        @{ Name = "Sonarr";       Container = "sonarr";          Port = 8989;  Path = "" },
        @{ Name = "Sonarr 4K";    Container = "sonarr4k";        Port = 8990;  Path = "" },
        @{ Name = "Overseerr";    Container = "overseerr";       Port = 5055;  Path = "" },
        @{ Name = "Pulsarr";      Container = "pulsarr";         Port = 3003;  Path = "" },
        @{ Name = "Decypharr";    Container = "decypharr";       Port = 8282;  Path = "" },
        @{ Name = "NZBDav";       Container = "nzbdav";          Port = 3000;  Path = "" },
        @{ Name = "FlareSolverr"; Container = "flaresolverr";    Port = 8191;  Path = "" }
    )

    $wslDistro = $WSLDistroBox.Text.Trim()

    foreach ($svc in $services) {
        $running = $false
        try {
            $result = & wsl -d $wslDistro -e bash -c "docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^$($svc.Container)$' && echo running || echo stopped" 2>&1
            $running = ($result -match "running")
        } catch { }

        $border = New-Object Windows.Controls.Border
        $border.Background = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#16213e"))
        $border.CornerRadius = "6"
        $border.Padding = "12,8"
        $border.Margin = "0,0,0,4"

        $grid = New-Object Windows.Controls.Grid
        $c1 = New-Object Windows.Controls.ColumnDefinition; $c1.Width = "Auto"
        $c2 = New-Object Windows.Controls.ColumnDefinition; $c2.Width = "*"
        $c3 = New-Object Windows.Controls.ColumnDefinition; $c3.Width = "Auto"
        $grid.ColumnDefinitions.Add($c1)
        $grid.ColumnDefinitions.Add($c2)
        $grid.ColumnDefinitions.Add($c3)

        $dot = New-Object Windows.Controls.TextBlock
        $dot.Text = if ($running) { "[ ON ]" } else { "[ -- ]" }
        $dot.Foreground = if ($running) { [Windows.Media.Brushes]::LightGreen } else { [Windows.Media.Brushes]::Gray }
        $dot.FontSize = 11
        $dot.FontFamily = "Consolas"
        $dot.VerticalAlignment = "Center"
        $dot.Margin = "0,0,10,0"
        [Windows.Controls.Grid]::SetColumn($dot, 0)

        $nameBlock = New-Object Windows.Controls.TextBlock
        $nameBlock.Text = "$($svc.Name)  (port $($svc.Port))"
        $nameBlock.Foreground = if ($running) { [Windows.Media.Brushes]::White } else { [Windows.Media.Brushes]::Gray }
        $nameBlock.FontSize = 12
        $nameBlock.VerticalAlignment = "Center"
        [Windows.Controls.Grid]::SetColumn($nameBlock, 1)

        $grid.Children.Add($dot) | Out-Null
        $grid.Children.Add($nameBlock) | Out-Null

        if ($running) {
            $url = "http://localhost:$($svc.Port)$($svc.Path)"
            $openBtn = New-Object Windows.Controls.Button
            $openBtn.Content = "Open"
            $openBtn.Background = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#0f3460"))
            $openBtn.Foreground = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#e94560"))
            $openBtn.BorderThickness = "0"
            $openBtn.Padding = "10,4"
            $openBtn.FontSize = 11
            $openBtn.Cursor = "Hand"
            $capturedUrl = $url
            $openBtn.Add_Click({ Start-Process $capturedUrl }.GetNewClosure())
            [Windows.Controls.Grid]::SetColumn($openBtn, 2)
            $grid.Children.Add($openBtn) | Out-Null
        }

        $border.Child = $grid
        $ServicesPanel.Children.Add($border) | Out-Null
    }

    Write-Log "Service status refreshed." "INFO"
})

# =============================================================================
# OTHER BUTTONS
# =============================================================================
$ClearLogBtn.Add_Click({ $LogBox.Clear() })

$SaveLogBtn.Add_Click({
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Filter = "Log files (*.log)|*.log|Text files (*.txt)|*.txt"
    $dialog.FileName = "unlimitedplex_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    if ($dialog.ShowDialog() -eq "OK") {
        $LogBox.Text | Out-File $dialog.FileName -Encoding UTF8
        Write-Log "Log saved to: $($dialog.FileName)" "SUCCESS"
    }
})

$OpenDockerBtn.Add_Click({ Start-Process "https://www.docker.com/products/docker-desktop/" })

$OpenServicesBtn.Add_Click({
    foreach ($url in @("http://localhost:32400/web","http://localhost:9696","http://localhost:7878","http://localhost:8989","http://localhost:5055")) {
        Start-Process $url
        Start-Sleep -Milliseconds 300
    }
})

# =============================================================================
# STARTUP
# =============================================================================
Write-Log "UnlimitedPlex Installer started." "INFO"
Write-Log "Click 'Check Prerequisites' to begin." "INFO"
Write-Log "Error log: $Script:ErrorLogPath" "INFO"

"[$(Get-Date)] Window about to show" | Out-File $Script:ErrorLogPath -Append

try {
    $Window.ShowDialog() | Out-Null
} catch {
    $errMsg = "[$(Get-Date)] ShowDialog error: $_"
    $errMsg | Out-File $Script:ErrorLogPath -Append
    [System.Windows.MessageBox]::Show(
        "Failed to show window:`n$_`n`nError log: $Script:ErrorLogPath",
        "UnlimitedPlex Error", "OK", "Error")
}

"[$(Get-Date)] Script ended normally" | Out-File $Script:ErrorLogPath -Append