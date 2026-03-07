#Requires -Version 5.1
# UnlimitedPlex Beta - Windows GUI Installer
# Modular service selector with multiple instance support

# WPF requires STA mode
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    $scriptPath = if ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { $PSCommandPath }
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -NoProfile -STA -File `"$scriptPath`"" -Verb RunAs
    exit
}

# Error log
$Script:ErrorLogPath = Join-Path $env:TEMP "UnlimitedPlex_Beta_error.log"
"[$(Get-Date)] Beta script started" | Out-File $Script:ErrorLogPath -Append

trap {
    $errMsg = "[$(Get-Date)] FATAL: $_`n$($_.ScriptStackTrace)"
    $errMsg | Out-File $Script:ErrorLogPath -Append
    try {
        [System.Windows.MessageBox]::Show("Fatal error:`n$_`n`nLog: $Script:ErrorLogPath","UnlimitedPlex Error","OK","Error")
    } catch { $errMsg | Out-File "$env:TEMP\UnlimitedPlex_Beta_fatal.log" -Append }
    continue
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# =============================================================================
# XAML GUI
# =============================================================================
[xml]$XAML = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="UnlimitedPlex Beta Installer"
    Height="820" Width="1000"
    MinHeight="700" MinWidth="900"
    WindowStartupLocation="CenterScreen"
    Background="#0d1117">

    <Window.Resources>
        <!-- Buttons -->
        <Style x:Key="PrimaryBtn" TargetType="Button">
            <Setter Property="Background" Value="#238636"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="18,9"/>
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
                                <Setter Property="Background" Value="#2ea043"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Background" Value="#21262d"/>
                                <Setter Property="Foreground" Value="#484f58"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="DangerBtn" TargetType="Button" BasedOn="{StaticResource PrimaryBtn}">
            <Setter Property="Background" Value="#da3633"/>
        </Style>
        <Style x:Key="SecondaryBtn" TargetType="Button" BasedOn="{StaticResource PrimaryBtn}">
            <Setter Property="Background" Value="#21262d"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="BorderBrush" Value="#30363d"/>
        </Style>
        <!-- Labels -->
        <Style x:Key="FieldLabel" TargetType="TextBlock">
            <Setter Property="Foreground" Value="#8b949e"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="Margin" Value="0,10,0,3"/>
        </Style>
        <!-- Inputs -->
        <Style x:Key="InputBox" TargetType="TextBox">
            <Setter Property="Background" Value="#161b22"/>
            <Setter Property="Foreground" Value="#e6edf3"/>
            <Setter Property="BorderBrush" Value="#30363d"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="CaretBrush" Value="White"/>
        </Style>
        <Style x:Key="PassBox" TargetType="PasswordBox">
            <Setter Property="Background" Value="#161b22"/>
            <Setter Property="Foreground" Value="#e6edf3"/>
            <Setter Property="BorderBrush" Value="#30363d"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="FontSize" Value="12"/>
        </Style>
        <!-- Section header -->
        <Style x:Key="SectionHeader" TargetType="TextBlock">
            <Setter Property="Foreground" Value="#e6edf3"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Margin" Value="0,0,0,10"/>
        </Style>
        <!-- Service checkbox card -->
        <Style x:Key="ServiceCard" TargetType="Border">
            <Setter Property="Background" Value="#161b22"/>
            <Setter Property="BorderBrush" Value="#30363d"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="6"/>
            <Setter Property="Padding" Value="12,10"/>
            <Setter Property="Margin" Value="0,0,8,8"/>
        </Style>
        <!-- CheckBox style -->
        <Style x:Key="SvcCheck" TargetType="CheckBox">
            <Setter Property="Foreground" Value="#e6edf3"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>
        <!-- Tab style -->
        <Style TargetType="TabItem">
            <Setter Property="Background" Value="#161b22"/>
            <Setter Property="Foreground" Value="#8b949e"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Padding" Value="14,8"/>
            <Setter Property="BorderThickness" Value="0"/>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="60"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="44"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <Border Grid.Row="0" Background="#161b22" BorderBrush="#30363d" BorderThickness="0,0,0,1">
            <Grid Margin="20,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock Text="UnlimitedPlex" Foreground="#58a6ff" FontSize="20" FontWeight="Bold"/>
                    <Border Background="#238636" CornerRadius="4" Padding="6,2" Margin="10,0,0,0" VerticalAlignment="Center">
                        <TextBlock Text="BETA" Foreground="White" FontSize="10" FontWeight="Bold"/>
                    </Border>
                    <TextBlock Text=" - Modular Installer" Foreground="#8b949e" FontSize="14" VerticalAlignment="Center"/>
                </StackPanel>
                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,0,0">
                    <Ellipse x:Name="StatusDot" Width="10" Height="10" Fill="#484f58" Margin="0,0,6,0"/>
                    <TextBlock x:Name="StatusText" Text="Ready" Foreground="#8b949e" FontSize="11" VerticalAlignment="Center"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Main tabs -->
        <TabControl Grid.Row="1" Background="#0d1117" BorderThickness="0" Margin="0">

            <!-- ================================================================
                 TAB 1: SERVICES
                 ================================================================ -->
            <TabItem Header="[1] Services">
                <ScrollViewer VerticalScrollBarVisibility="Auto" Background="#0d1117">
                    <StackPanel Margin="24,20">

                        <TextBlock Style="{StaticResource SectionHeader}" Text="Select Services per Instance"/>
                        <TextBlock Foreground="#8b949e" FontSize="11" Margin="0,0,0,16" TextWrapping="Wrap">
                            Plex Media Server is always installed. Add instances below (e.g. Main, 4K, Kids)
                            and choose which services each instance gets. Each instance runs on separate ports.
                        </TextBlock>

                        <!-- Global services -->
                        <Border Background="#161b22" BorderBrush="#30363d" BorderThickness="1" CornerRadius="8" Padding="16" Margin="0,0,0,16">
                            <StackPanel>
                                <TextBlock Text="Global Services (installed once, shared)" Foreground="#58a6ff" FontSize="13" FontWeight="SemiBold" Margin="0,0,0,12"/>
                                <TextBlock Foreground="#8b949e" FontSize="11" Margin="0,0,0,10">These services are installed once and shared across all instances.</TextBlock>
                                <WrapPanel>
                                    <Border Style="{StaticResource ServiceCard}" Width="200">
                                        <StackPanel>
                                            <CheckBox x:Name="ChkTautulli" Style="{StaticResource SvcCheck}" IsChecked="True">
                                                <StackPanel>
                                                    <TextBlock Text="Tautulli" Foreground="#e6edf3" FontWeight="SemiBold"/>
                                                    <TextBlock Text="Plex analytics" Foreground="#8b949e" FontSize="10"/>
                                                </StackPanel>
                                            </CheckBox>
                                        </StackPanel>
                                    </Border>
                                    <Border Style="{StaticResource ServiceCard}" Width="200">
                                        <StackPanel>
                                            <CheckBox x:Name="ChkNZBDav" Style="{StaticResource SvcCheck}" IsChecked="False">
                                                <StackPanel>
                                                    <TextBlock Text="NZBDav" Foreground="#e6edf3" FontWeight="SemiBold"/>
                                                    <TextBlock Text="Usenet streaming" Foreground="#8b949e" FontSize="10"/>
                                                </StackPanel>
                                            </CheckBox>
                                            <StackPanel x:Name="NZBDavPassPanel" Margin="20,6,0,0" Visibility="Collapsed">
                                                <TextBlock Text="WebDAV Password:" Foreground="#8b949e" FontSize="10" Margin="0,0,0,3"/>
                                                <PasswordBox x:Name="NZBDavPassBox" Style="{StaticResource PassBox}" Width="140" HorizontalAlignment="Left"/>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>
                                </WrapPanel>
                            </StackPanel>
                        </Border>

                        <!-- Instances panel -->
                        <StackPanel x:Name="InstancesPanel"/>

                        <!-- Add instance button -->
                        <Button x:Name="AddInstanceBtn" Style="{StaticResource SecondaryBtn}"
                                Content="+ Add Instance" HorizontalAlignment="Left" Margin="0,8,0,0"/>

                        <TextBlock Foreground="#8b949e" FontSize="10" Margin="0,8,0,0" TextWrapping="Wrap">
                            Port allocation: Instance 0 uses base ports (Radarr:7878, Sonarr:8989, etc.)
                            Instance 1 uses base+100 (Radarr:7978, Sonarr:9089, etc.)
                        </TextBlock>

                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- ================================================================
                 TAB 2: CONFIGURATION
                 ================================================================ -->
            <TabItem Header="[2] Configuration">
                <ScrollViewer VerticalScrollBarVisibility="Auto" Background="#0d1117">
                    <StackPanel Margin="24,20" MaxWidth="600">

                        <TextBlock Style="{StaticResource SectionHeader}" Text="Configuration"/>

                        <!-- RD Token -->
                        <TextBlock Style="{StaticResource FieldLabel}" Text="Real-Debrid API Token *"/>
                        <PasswordBox x:Name="RDTokenBox" Style="{StaticResource PassBox}"/>
                        <TextBlock Foreground="#8b949e" FontSize="10" Margin="0,3,0,0">
                            Get from: https://real-debrid.com/apitoken
                        </TextBlock>

                        <!-- Plex Token -->
                        <TextBlock Style="{StaticResource FieldLabel}" Text="Plex Claim Token *"/>
                        <PasswordBox x:Name="PlexTokenBox" Style="{StaticResource PassBox}"/>
                        <TextBlock Foreground="#8b949e" FontSize="10" Margin="0,3,0,0">
                            Get from: https://www.plex.tv/claim (expires in 4 min)
                        </TextBlock>

                        <!-- Timezone -->
                        <TextBlock Style="{StaticResource FieldLabel}" Text="Timezone"/>
                        <TextBox x:Name="TimezoneBox" Style="{StaticResource InputBox}" Text="America/New_York"/>
                        <TextBlock Foreground="#8b949e" FontSize="10" Margin="0,3,0,0">
                            Examples: America/New_York, Europe/London, Australia/Sydney
                        </TextBlock>

                        <!-- Zurg Version -->
                        <TextBlock Style="{StaticResource FieldLabel}" Text="Zurg Version"/>
                        <TextBox x:Name="ZurgVersionBox" Style="{StaticResource InputBox}" Text="v0.9.3-final"/>

                        <!-- WSL Distro -->
                        <TextBlock Style="{StaticResource FieldLabel}" Text="WSL2 Distro Name"/>
                        <TextBox x:Name="WSLDistroBox" Style="{StaticResource InputBox}" Text="Ubuntu"/>
                        <TextBlock Foreground="#8b949e" FontSize="10" Margin="0,3,0,0">
                            Run 'wsl -l -q' in PowerShell to see your distro names
                        </TextBlock>

                        <!-- Prereqs check -->
                        <Border Background="#161b22" BorderBrush="#30363d" BorderThickness="1" CornerRadius="6" Padding="14" Margin="0,20,0,0">
                            <StackPanel>
                                <TextBlock Text="Prerequisites" Foreground="#58a6ff" FontSize="13" FontWeight="SemiBold" Margin="0,0,0,10"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <StackPanel Grid.Column="0" Margin="0,0,8,0">
                                        <TextBlock x:Name="DockerStatus" Text="[?] Docker" Foreground="#ffcc00" FontSize="12" FontWeight="SemiBold"/>
                                        <TextBlock x:Name="DockerVersion" Text="Checking..." Foreground="#8b949e" FontSize="10" Margin="0,3,0,0"/>
                                    </StackPanel>
                                    <StackPanel Grid.Column="1" Margin="0,0,8,0">
                                        <TextBlock x:Name="WSLStatus" Text="[?] WSL2" Foreground="#ffcc00" FontSize="12" FontWeight="SemiBold"/>
                                        <TextBlock x:Name="WSLVersion" Text="Checking..." Foreground="#8b949e" FontSize="10" Margin="0,3,0,0"/>
                                    </StackPanel>
                                    <StackPanel Grid.Column="2">
                                        <TextBlock x:Name="AdminStatus" Text="[?] Admin" Foreground="#ffcc00" FontSize="12" FontWeight="SemiBold"/>
                                        <TextBlock x:Name="AdminVersion" Text="Checking..." Foreground="#8b949e" FontSize="10" Margin="0,3,0,0"/>
                                    </StackPanel>
                                </Grid>
                                <Button x:Name="CheckPrereqsBtn" Style="{StaticResource SecondaryBtn}"
                                        Content="Check Prerequisites" Margin="0,12,0,0" HorizontalAlignment="Left"/>
                            </StackPanel>
                        </Border>

                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- ================================================================
                 TAB 3: INSTALL
                 ================================================================ -->
            <TabItem Header="[3] Install">
                <Grid Background="#0d1117" Margin="24,20">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <TextBlock Grid.Row="0" Style="{StaticResource SectionHeader}" Text="Installation"/>

                    <!-- Summary box -->
                    <Border Grid.Row="1" x:Name="SummaryBorder" Background="#161b22" BorderBrush="#30363d"
                            BorderThickness="1" CornerRadius="6" Padding="14" Margin="0,0,0,12">
                        <StackPanel>
                            <TextBlock Text="Installation Summary" Foreground="#58a6ff" FontSize="12" FontWeight="SemiBold" Margin="0,0,0,8"/>
                            <TextBlock x:Name="SummaryText" Foreground="#8b949e" FontSize="11" TextWrapping="Wrap"
                                       Text="Configure services and instances in the Services tab, then click Install."/>
                        </StackPanel>
                    </Border>

                    <!-- Progress -->
                    <Grid Grid.Row="2" Margin="0,0,0,12">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="60"/>
                        </Grid.ColumnDefinitions>
                        <ProgressBar x:Name="InstallProgress" Height="8" Value="0" Maximum="100"
                                     Background="#21262d" Foreground="#238636" BorderThickness="0"/>
                        <TextBlock x:Name="ProgressLabel" Grid.Column="1" Text="0%" Foreground="#8b949e"
                                   FontSize="11" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                    </Grid>

                    <!-- Buttons -->
                    <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="0,0,0,12" VerticalAlignment="Top">
                        <Button x:Name="InstallBtn" Style="{StaticResource PrimaryBtn}" Content=">> Install" Margin="0,0,10,0"/>
                        <Button x:Name="StopBtn" Style="{StaticResource DangerBtn}" Content="Stop" IsEnabled="False" Margin="0,0,10,0"/>
                        <Button x:Name="UpdateSummaryBtn" Style="{StaticResource SecondaryBtn}" Content="Refresh Summary"/>
                    </StackPanel>

                    <!-- Log -->
                    <Border Grid.Row="4" Background="#161b22" BorderBrush="#30363d" BorderThickness="1" CornerRadius="6">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>
                            <Border Grid.Row="0" Background="#21262d" CornerRadius="6,6,0,0" Padding="10,6">
                                <Grid>
                                    <TextBlock Text="Install Log" Foreground="#8b949e" FontSize="11"/>
                                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                                        <Button x:Name="ClearLogBtn" Style="{StaticResource SecondaryBtn}"
                                                Content="Clear" Padding="8,3" FontSize="10"/>
                                        <Button x:Name="SaveLogBtn" Style="{StaticResource SecondaryBtn}"
                                                Content="Save" Padding="8,3" FontSize="10" Margin="6,0,0,0"/>
                                    </StackPanel>
                                </Grid>
                            </Border>
                            <TextBox Grid.Row="1" x:Name="LogBox"
                                     Background="Transparent" Foreground="#e6edf3"
                                     FontFamily="Consolas" FontSize="11"
                                     IsReadOnly="True" TextWrapping="Wrap"
                                     VerticalScrollBarVisibility="Auto"
                                     BorderThickness="0" Padding="10"
                                     MinHeight="300"/>
                        </Grid>
                    </Border>

                </Grid>
            </TabItem>

            <!-- ================================================================
                 TAB 4: SERVICES STATUS
                 ================================================================ -->
            <TabItem Header="[4] Status">
                <Grid Background="#0d1117" Margin="24,20">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" Style="{StaticResource SectionHeader}" Text="Service Status"/>
                    <Button Grid.Row="1" x:Name="RefreshServicesBtn" Style="{StaticResource SecondaryBtn}"
                            Content="Refresh Status" HorizontalAlignment="Left" Margin="0,0,0,16"/>
                    <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto">
                        <WrapPanel x:Name="ServicesPanel" Orientation="Horizontal"/>
                    </ScrollViewer>
                </Grid>
            </TabItem>

            <!-- ================================================================
                 TAB 5: HELP
                 ================================================================ -->
            <TabItem Header="[5] Help">
                <ScrollViewer VerticalScrollBarVisibility="Auto" Background="#0d1117">
                    <StackPanel Margin="24,20" MaxWidth="700">
                        <TextBlock Style="{StaticResource SectionHeader}" Text="Help &amp; Documentation"/>

                        <Border Background="#161b22" BorderBrush="#30363d" BorderThickness="1" CornerRadius="6" Padding="16" Margin="0,0,0,12">
                            <StackPanel>
                                <TextBlock Text="Quick Start" Foreground="#58a6ff" FontSize="13" FontWeight="SemiBold" Margin="0,0,0,8"/>
                                <TextBlock Foreground="#e6edf3" FontSize="12" TextWrapping="Wrap" LineHeight="20">
1. Go to the Services tab and add at least one instance.
2. Select which services each instance should have.
3. Go to Configuration tab and enter your tokens.
4. Click Check Prerequisites to verify Docker and WSL2.
5. Go to Install tab, click Refresh Summary to review.
6. Click Install to begin.
                                </TextBlock>
                            </StackPanel>
                        </Border>

                        <Border Background="#161b22" BorderBrush="#30363d" BorderThickness="1" CornerRadius="6" Padding="16" Margin="0,0,0,12">
                            <StackPanel>
                                <TextBlock Text="Services Explained" Foreground="#58a6ff" FontSize="13" FontWeight="SemiBold" Margin="0,0,0,8"/>
                                <TextBlock Foreground="#e6edf3" FontSize="12" TextWrapping="Wrap" LineHeight="22">
Zurg         - Mounts your Real-Debrid library as a virtual filesystem
Radarr       - Automated movie management and requests
Sonarr       - Automated TV show management and requests
Prowlarr     - Indexer manager (connects to Radarr/Sonarr)
Decypharr    - qBittorrent API mock, routes downloads via Real-Debrid
Pulsarr      - Syncs your Plex watchlist to Radarr/Sonarr
Tautulli     - Plex analytics, statistics and notifications (global)
NZBDav       - Usenet streaming via WebDAV (global)
                                </TextBlock>
                            </StackPanel>
                        </Border>

                        <Border Background="#161b22" BorderBrush="#30363d" BorderThickness="1" CornerRadius="6" Padding="16" Margin="0,0,0,12">
                            <StackPanel>
                                <TextBlock Text="Multiple Instances" Foreground="#58a6ff" FontSize="13" FontWeight="SemiBold" Margin="0,0,0,8"/>
                                <TextBlock Foreground="#e6edf3" FontSize="12" TextWrapping="Wrap" LineHeight="22">
Each instance is a separate set of services with its own ports.

Example setup:
  Main  - Zurg, Radarr, Sonarr, Prowlarr, Decypharr
  4K    - Zurg, Radarr, Sonarr, Decypharr
  Kids  - Radarr, Sonarr

Port allocation (base + instance_index * 100):
  Instance 0 (Main): Radarr:7878  Sonarr:8989  Prowlarr:9696
  Instance 1 (4K):   Radarr:7978  Sonarr:9089  Prowlarr:9796
  Instance 2 (Kids): Radarr:8078  Sonarr:9189  Prowlarr:9896
                                </TextBlock>
                            </StackPanel>
                        </Border>

                        <Border Background="#161b22" BorderBrush="#30363d" BorderThickness="1" CornerRadius="6" Padding="16" Margin="0,0,0,12">
                            <StackPanel>
                                <TextBlock Text="Troubleshooting" Foreground="#58a6ff" FontSize="13" FontWeight="SemiBold" Margin="0,0,0,8"/>
                                <TextBlock Foreground="#e6edf3" FontSize="12" TextWrapping="Wrap" LineHeight="22">
- Error log: %TEMP%\UnlimitedPlex_Beta_error.log
- Run 'wsl -l -q' to find your exact WSL distro name
- Make sure Docker Desktop is running before installing
- Run this script as Administrator
- GitHub: https://github.com/JudgeUAu/UnlimitedPlex
                                </TextBlock>
                            </StackPanel>
                        </Border>

                    </StackPanel>
                </ScrollViewer>
            </TabItem>

        </TabControl>

        <!-- Footer -->
        <Border Grid.Row="2" Background="#161b22" BorderBrush="#30363d" BorderThickness="0,1,0,0" Padding="20,0">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock x:Name="FooterStatus" Text="Ready."
                           Foreground="#8b949e" FontSize="11" VerticalAlignment="Center"/>
                <TextBlock Grid.Column="1" Text="UnlimitedPlex Beta | github.com/JudgeUAu/UnlimitedPlex"
                           Foreground="#484f58" FontSize="10" VerticalAlignment="Center"/>
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
$AddInstanceBtn     = $Window.FindName("AddInstanceBtn")
$InstancesPanel     = $Window.FindName("InstancesPanel")
$ChkTautulli        = $Window.FindName("ChkTautulli")
$ChkNZBDav          = $Window.FindName("ChkNZBDav")
$NZBDavPassPanel    = $Window.FindName("NZBDavPassPanel")
$NZBDavPassBox      = $Window.FindName("NZBDavPassBox")
$RDTokenBox         = $Window.FindName("RDTokenBox")
$PlexTokenBox       = $Window.FindName("PlexTokenBox")
$TimezoneBox        = $Window.FindName("TimezoneBox")
$ZurgVersionBox     = $Window.FindName("ZurgVersionBox")
$WSLDistroBox       = $Window.FindName("WSLDistroBox")
$CheckPrereqsBtn    = $Window.FindName("CheckPrereqsBtn")
$DockerStatus       = $Window.FindName("DockerStatus")
$DockerVersion      = $Window.FindName("DockerVersion")
$WSLStatus          = $Window.FindName("WSLStatus")
$WSLVersion         = $Window.FindName("WSLVersion")
$AdminStatus        = $Window.FindName("AdminStatus")
$AdminVersion       = $Window.FindName("AdminVersion")
$InstallBtn         = $Window.FindName("InstallBtn")
$StopBtn            = $Window.FindName("StopBtn")
$UpdateSummaryBtn   = $Window.FindName("UpdateSummaryBtn")
$SummaryText        = $Window.FindName("SummaryText")
$InstallProgress    = $Window.FindName("InstallProgress")
$ProgressLabel      = $Window.FindName("ProgressLabel")
$LogBox             = $Window.FindName("LogBox")
$ClearLogBtn        = $Window.FindName("ClearLogBtn")
$SaveLogBtn         = $Window.FindName("SaveLogBtn")
$RefreshServicesBtn = $Window.FindName("RefreshServicesBtn")
$ServicesPanel      = $Window.FindName("ServicesPanel")
$FooterStatus       = $Window.FindName("FooterStatus")
$StatusDot          = $Window.FindName("StatusDot")
$StatusText         = $Window.FindName("StatusText")

# =============================================================================
# INSTANCE DATA MODEL
# =============================================================================
$Script:Instances = [System.Collections.Generic.List[hashtable]]::new()
$Script:StopRequested = $false

$Script:ServiceDefs = @(
    @{ Key="zurg";      Label="Zurg";      Desc="Real-Debrid mount";         Default=$true  },
    @{ Key="radarr";    Label="Radarr";    Desc="Movie management";           Default=$true  },
    @{ Key="sonarr";    Label="Sonarr";    Desc="TV show management";         Default=$true  },
    @{ Key="prowlarr";  Label="Prowlarr";  Desc="Indexer manager";            Default=$true  },
    @{ Key="decypharr"; Label="Decypharr"; Desc="qBittorrent mock for RD";    Default=$true  },
    @{ Key="pulsarr";   Label="Pulsarr";   Desc="Plex watchlist sync";        Default=$false }
)

# Base ports
$Script:BasePorts = @{
    zurg      = 9999
    radarr    = 7878
    sonarr    = 8989
    prowlarr  = 9696
    decypharr = 8282
    pulsarr   = 3003
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "HH:mm:ss"
    $prefix = switch ($Level) {
        "INFO"    { "[INFO]   " }
        "WARN"    { "[WARN]   " }
        "ERROR"   { "[ERROR]  " }
        "SUCCESS" { "[OK]     " }
        "STEP"    { "[STEP]   " }
        default   { "[INFO]   " }
    }
    $Window.Dispatcher.Invoke({
        $LogBox.AppendText("[$ts] $prefix $Message`n")
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
    param([string]$Text, [string]$Color = "#484f58")
    $Window.Dispatcher.Invoke({
        $StatusDot.Fill = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString($Color))
        $StatusText.Text = $Text
    })
}

function Get-InstancePort {
    param([string]$ServiceKey, [int]$InstanceIndex)
    $base = $Script:BasePorts[$ServiceKey]
    if ($null -eq $base) { return 0 }
    return $base + ($InstanceIndex * 100)
}

function Get-SafeName {
    param([string]$Label)
    return ($Label.ToLower() -replace '[^a-z0-9]','_' -replace '_+$','')
}

# =============================================================================
# INSTANCE UI BUILDER
# =============================================================================
function Add-InstanceUI {
    param([string]$DefaultLabel = "")

    $idx = $Script:Instances.Count

    # Ask for instance name
    $nameForm = New-Object System.Windows.Window
    $nameForm.Title = "New Instance"
    $nameForm.Width = 400
    $nameForm.Height = 180
    $nameForm.WindowStartupLocation = "CenterOwner"
    $nameForm.Owner = $Window
    $nameForm.Background = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#0d1117"))
    $nameForm.ResizeMode = "NoResize"

    $sp = New-Object Windows.Controls.StackPanel
    $sp.Margin = "20"

    $lbl = New-Object Windows.Controls.TextBlock
    $lbl.Text = "Instance name (e.g. Main, 4K, Kids, Anime):"
    $lbl.Foreground = [Windows.Media.Brushes]::White
    $lbl.Margin = "0,0,0,8"

    $tb = New-Object Windows.Controls.TextBox
    $tb.Text = $DefaultLabel
    $tb.Background = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#161b22"))
    $tb.Foreground = [Windows.Media.Brushes]::White
    $tb.BorderBrush = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#30363d"))
    $tb.Padding = "8,6"
    $tb.FontSize = 13
    $tb.Margin = "0,0,0,12"

    $btnOk = New-Object Windows.Controls.Button
    $btnOk.Content = "Add Instance"
    $btnOk.Background = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#238636"))
    $btnOk.Foreground = [Windows.Media.Brushes]::White
    $btnOk.Padding = "16,8"
    $btnOk.BorderThickness = "0"
    $btnOk.HorizontalAlignment = "Left"
    $btnOk.Add_Click({ $nameForm.DialogResult = $true; $nameForm.Close() })

    $sp.Children.Add($lbl) | Out-Null
    $sp.Children.Add($tb)  | Out-Null
    $sp.Children.Add($btnOk) | Out-Null
    $nameForm.Content = $sp
    $tb.Focus() | Out-Null

    $result = $nameForm.ShowDialog()
    if (-not $result -or [string]::IsNullOrWhiteSpace($tb.Text)) { return }

    $label    = $tb.Text.Trim()
    $safeName = Get-SafeName $label

    # Create instance data
    $instData = @{
        Label    = $label
        Name     = $safeName
        Index    = $idx
        Checks   = @{}
    }

    # Build instance card UI
    $card = New-Object Windows.Controls.Border
    $card.Background  = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#161b22"))
    $card.BorderBrush = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#30363d"))
    $card.BorderThickness = "1"
    $card.CornerRadius = "8"
    $card.Padding = "16"
    $card.Margin = "0,0,0,12"

    $cardSP = New-Object Windows.Controls.StackPanel

    # Card header
    $headerGrid = New-Object Windows.Controls.Grid
    $col1 = New-Object Windows.Controls.ColumnDefinition; $col1.Width = [Windows.GridLength]::new(1, [Windows.GridUnitType]::Star)
    $col2 = New-Object Windows.Controls.ColumnDefinition; $col2.Width = [Windows.GridLength]::Auto
    $headerGrid.ColumnDefinitions.Add($col1)
    $headerGrid.ColumnDefinitions.Add($col2)

    $titleSP = New-Object Windows.Controls.StackPanel
    $titleSP.Orientation = "Horizontal"

    $idxBadge = New-Object Windows.Controls.Border
    $idxBadge.Background = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#1f6feb"))
    $idxBadge.CornerRadius = "4"
    $idxBadge.Padding = "6,2"
    $idxBadge.Margin = "0,0,8,0"
    $idxTxt = New-Object Windows.Controls.TextBlock
    $idxTxt.Text = "Instance $idx"
    $idxTxt.Foreground = [Windows.Media.Brushes]::White
    $idxTxt.FontSize = 10
    $idxBadge.Child = $idxTxt

    $titleTxt = New-Object Windows.Controls.TextBlock
    $titleTxt.Text = $label
    $titleTxt.Foreground = [Windows.Media.Brushes]::White
    $titleTxt.FontSize = 14
    $titleTxt.FontWeight = "SemiBold"
    $titleTxt.VerticalAlignment = "Center"

    $titleSP.Children.Add($idxBadge) | Out-Null
    $titleSP.Children.Add($titleTxt) | Out-Null
    [Windows.Controls.Grid]::SetColumn($titleSP, 0)
    $headerGrid.Children.Add($titleSP) | Out-Null

    # Remove button
    $removeBtn = New-Object Windows.Controls.Button
    $removeBtn.Content = "Remove"
    $removeBtn.Background = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#21262d"))
    $removeBtn.Foreground = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#f85149"))
    $removeBtn.BorderBrush = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#30363d"))
    $removeBtn.BorderThickness = "1"
    $removeBtn.Padding = "10,4"
    $removeBtn.FontSize = 11
    $removeBtn.Cursor = "Hand"
    $capturedCard = $card
    $capturedData = $instData
    $removeBtn.Add_Click({
        $InstancesPanel.Children.Remove($capturedCard)
        $Script:Instances.Remove($capturedData) | Out-Null
    }.GetNewClosure())
    [Windows.Controls.Grid]::SetColumn($removeBtn, 1)
    $headerGrid.Children.Add($removeBtn) | Out-Null

    $cardSP.Children.Add($headerGrid) | Out-Null

    # Port info
    $portTxt = New-Object Windows.Controls.TextBlock
    $portTxt.Text = "Ports: Radarr=$(Get-InstancePort 'radarr' $idx)  Sonarr=$(Get-InstancePort 'sonarr' $idx)  Prowlarr=$(Get-InstancePort 'prowlarr' $idx)  Zurg=$(Get-InstancePort 'zurg' $idx)"
    $portTxt.Foreground = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#8b949e"))
    $portTxt.FontSize = 10
    $portTxt.Margin = "0,6,0,10"
    $cardSP.Children.Add($portTxt) | Out-Null

    # Service checkboxes
    $svcWrap = New-Object Windows.Controls.WrapPanel
    $svcWrap.Orientation = "Horizontal"

    foreach ($svcDef in $Script:ServiceDefs) {
        $svcBorder = New-Object Windows.Controls.Border
        $svcBorder.Background = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#0d1117"))
        $svcBorder.BorderBrush = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#21262d"))
        $svcBorder.BorderThickness = "1"
        $svcBorder.CornerRadius = "4"
        $svcBorder.Padding = "10,7"
        $svcBorder.Margin = "0,0,8,8"
        $svcBorder.Width = 160

        $svcSP = New-Object Windows.Controls.StackPanel

        $chk = New-Object Windows.Controls.CheckBox
        $chk.IsChecked = $svcDef.Default
        $chk.Foreground = [Windows.Media.Brushes]::White
        $chk.FontSize = 12
        $chk.FontWeight = "SemiBold"
        $chk.Content = $svcDef.Label

        $descTxt = New-Object Windows.Controls.TextBlock
        $descTxt.Text = $svcDef.Desc
        $descTxt.Foreground = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#8b949e"))
        $descTxt.FontSize = 10
        $descTxt.Margin = "20,2,0,0"

        $portLabel = New-Object Windows.Controls.TextBlock
        $portLabel.Text = "Port: $(Get-InstancePort $svcDef.Key $idx)"
        $portLabel.Foreground = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#1f6feb"))
        $portLabel.FontSize = 10
        $portLabel.Margin = "20,1,0,0"

        $svcSP.Children.Add($chk)      | Out-Null
        $svcSP.Children.Add($descTxt)  | Out-Null
        $svcSP.Children.Add($portLabel)| Out-Null
        $svcBorder.Child = $svcSP
        $svcWrap.Children.Add($svcBorder) | Out-Null

        $instData.Checks[$svcDef.Key] = $chk
    }

    $cardSP.Children.Add($svcWrap) | Out-Null
    $card.Child = $cardSP
    $InstancesPanel.Children.Add($card) | Out-Null
    $Script:Instances.Add($instData) | Out-Null
}

# =============================================================================
# ADD INSTANCE BUTTON
# =============================================================================
$AddInstanceBtn.Add_Click({ Add-InstanceUI })

# NZBDav password toggle
$ChkNZBDav.Add_Checked({   $NZBDavPassPanel.Visibility = "Visible" })
$ChkNZBDav.Add_Unchecked({ $NZBDavPassPanel.Visibility = "Collapsed" })

# =============================================================================
# PREREQUISITES CHECK
# =============================================================================
$CheckPrereqsBtn.Add_Click({
    Write-Log "Checking prerequisites..." "STEP"

    # Admin check
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $pr = [Security.Principal.WindowsPrincipal]$id
        if ($pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            $AdminStatus.Text = "[OK] Administrator"
            $AdminStatus.Foreground = [Windows.Media.Brushes]::LightGreen
            $AdminVersion.Text = "Running as admin"
            Write-Log "Admin rights: OK" "SUCCESS"
        } else {
            $AdminStatus.Text = "[!] Not Admin"
            $AdminStatus.Foreground = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#ffcc00"))
            $AdminVersion.Text = "Re-run as Administrator"
            Write-Log "Not running as Administrator" "WARN"
        }
    } catch {
        $AdminStatus.Text = "[X] Admin check failed"
        $AdminStatus.Foreground = [Windows.Media.Brushes]::Salmon
    }

    # Docker check
    try {
        $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
        if ($dockerCmd) {
            $dv = & docker --version 2>&1
            if ($LASTEXITCODE -eq 0) {
                $DockerStatus.Text = "[OK] Docker"
                $DockerStatus.Foreground = [Windows.Media.Brushes]::LightGreen
                $DockerVersion.Text = "$dv"
                Write-Log "Docker: $dv" "SUCCESS"
            } else {
                $DockerStatus.Text = "[!] Docker (not running)"
                $DockerStatus.Foreground = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#ffcc00"))
                $DockerVersion.Text = "Start Docker Desktop"
                Write-Log "Docker installed but not running" "WARN"
            }
        } else {
            $DockerStatus.Text = "[X] Docker not found"
            $DockerStatus.Foreground = [Windows.Media.Brushes]::Salmon
            $DockerVersion.Text = "Install Docker Desktop"
            Write-Log "Docker not found" "ERROR"
        }
    } catch {
        $DockerStatus.Text = "[X] Docker error"
        $DockerStatus.Foreground = [Windows.Media.Brushes]::Salmon
        Write-Log "Docker check error: $_" "ERROR"
    }

    # WSL2 check - handle UTF-16LE null bytes
    try {
        $wslFound = $false
        $distroFound = $false
        $distro = $WSLDistroBox.Text.Trim()

        $wslQuiet = & wsl -l -q 2>&1
        if ($wslQuiet) {
            $wslClean = ($wslQuiet | ForEach-Object {
                if ($_ -is [string]) { $_ -replace "`0","" } else { "$_" -replace "`0","" }
            }) -join "`n"
            $wslFound = $true
            if ($wslClean -match [regex]::Escape($distro)) { $distroFound = $true }
        }

        if (-not $distroFound) {
            $testRun = & wsl -d $distro -e echo "ok" 2>&1
            if ($LASTEXITCODE -eq 0 -and "$testRun" -match "ok") {
                $wslFound = $true; $distroFound = $true
            }
        }

        if ($distroFound) {
            $WSLStatus.Text = "[OK] WSL2 ($distro)"
            $WSLStatus.Foreground = [Windows.Media.Brushes]::LightGreen
            $WSLVersion.Text = "Distro: $distro"
            Write-Log "WSL2: OK - $distro found" "SUCCESS"
        } elseif ($wslFound) {
            $WSLStatus.Text = "[!] WSL2 (distro not found)"
            $WSLStatus.Foreground = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#ffcc00"))
            $WSLVersion.Text = "Check distro name above"
            Write-Log "WSL2 found but '$distro' not detected. Run: wsl -l -q" "WARN"
        } else {
            $WSLStatus.Text = "[X] WSL2 not found"
            $WSLStatus.Foreground = [Windows.Media.Brushes]::Salmon
            $WSLVersion.Text = "Run: wsl --install"
            Write-Log "WSL2 not found" "ERROR"
        }
    } catch {
        $WSLStatus.Text = "[X] WSL2 error"
        $WSLStatus.Foreground = [Windows.Media.Brushes]::Salmon
        Write-Log "WSL2 check error: $_" "ERROR"
    }

    Write-Log "Prerequisites check complete." "INFO"
})

# =============================================================================
# UPDATE SUMMARY
# =============================================================================
function Update-Summary {
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("Plex Media Server: always installed")
    $lines.Add("")

    if ($Script:Instances.Count -eq 0) {
        $lines.Add("No instances configured. Go to Services tab and add instances.")
    } else {
        foreach ($inst in $Script:Instances) {
            $svcs = @()
            foreach ($svcDef in $Script:ServiceDefs) {
                $chk = $inst.Checks[$svcDef.Key]
                if ($chk -and $chk.IsChecked) { $svcs += $svcDef.Label }
            }
            $lines.Add("Instance [$($inst.Index)] $($inst.Label) ($($inst.Name))")
            $lines.Add("  Services: $($svcs -join ', ')")
            $lines.Add("")
        }
    }

    $globalSvcs = @()
    if ($ChkTautulli.IsChecked) { $globalSvcs += "Tautulli (port 8181)" }
    if ($ChkNZBDav.IsChecked)   { $globalSvcs += "NZBDav (port 3000)" }
    if ($globalSvcs.Count -gt 0) {
        $lines.Add("Global Services: $($globalSvcs -join ', ')")
    }

    $SummaryText.Text = $lines -join "`n"
}

$UpdateSummaryBtn.Add_Click({ Update-Summary })

# =============================================================================
# BUILD CONFIG JSON
# =============================================================================
function Build-ConfigJson {
    $rdToken    = $RDTokenBox.Password.Trim()
    $plexToken  = $PlexTokenBox.Password.Trim()
    $timezone   = $TimezoneBox.Text.Trim()
    $zurgVer    = $ZurgVersionBox.Text.Trim()
    $nzbPass    = $NZBDavPassBox.Password.Trim()

    if ([string]::IsNullOrEmpty($rdToken))   { throw "Real-Debrid token is required." }
    if ([string]::IsNullOrEmpty($plexToken)) { throw "Plex token is required." }
    if ([string]::IsNullOrEmpty($timezone))  { $timezone = "America/New_York" }
    if ([string]::IsNullOrEmpty($zurgVer))   { $zurgVer = "v0.9.3-final" }
    if ([string]::IsNullOrEmpty($nzbPass))   { $nzbPass = "changeme" }

    if ($Script:Instances.Count -eq 0) { throw "No instances configured. Add at least one instance in the Services tab." }

    $instances = @()
    foreach ($inst in $Script:Instances) {
        $svcs = @()
        foreach ($svcDef in $Script:ServiceDefs) {
            $chk = $inst.Checks[$svcDef.Key]
            if ($chk -and $chk.IsChecked) { $svcs += $svcDef.Key }
        }
        if ($svcs.Count -eq 0) {
            Write-Log "Instance '$($inst.Label)' has no services selected - skipping" "WARN"
            continue
        }
        $instances += @{
            name     = $inst.Name
            label    = $inst.Label
            services = $svcs
        }
    }

    $globalSvcs = @()
    if ($ChkTautulli.IsChecked) { $globalSvcs += "tautulli" }
    if ($ChkNZBDav.IsChecked)   { $globalSvcs += "nzbdav" }

    $config = @{
        rd_token        = $rdToken
        plex_token      = $plexToken
        timezone        = $timezone
        zurg_version    = $zurgVer
        nzbdav_password = $nzbPass
        instances       = $instances
        global_services = $globalSvcs
    }

    return ($config | ConvertTo-Json -Depth 5)
}

# =============================================================================
# INSTALL BUTTON
# =============================================================================
$InstallBtn.Add_Click({
    # Validate
    try {
        $configJson = Build-ConfigJson
    } catch {
        [System.Windows.MessageBox]::Show("$_", "Validation Error", "OK", "Warning")
        return
    }

    $wslDistro = $WSLDistroBox.Text.Trim()

    $InstallBtn.IsEnabled = $false
    $StopBtn.IsEnabled = $true
    $Script:StopRequested = $false
    Set-Status "Installing..." "#ffcc00"
    Update-Summary

    $capturedConfig = $configJson
    $capturedDistro = $wslDistro
    $capturedScriptRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

    $installThread = [System.Threading.Thread]::new([System.Threading.ThreadStart]{
        try {
            Write-Log "================================================" "STEP"
            Write-Log "  UnlimitedPlex Beta Installation Starting" "STEP"
            Write-Log "================================================" "STEP"

            Set-Progress 5 "Preparing..."

            # Write config JSON to temp file
            $tmpConfig = [System.IO.Path]::GetTempFileName() + ".json"
            [System.IO.File]::WriteAllText($tmpConfig, $capturedConfig, [System.Text.Encoding]::UTF8)
            $wslConfigPath = & wsl -d $capturedDistro -e wslpath -u $tmpConfig 2>&1
            Write-Log "Config written to: $wslConfigPath" "INFO"

            Set-Progress 10 "Copying scripts..."

            # Copy setup_beta.sh to WSL
            $scripts = @("setup_beta.sh")
            foreach ($s in $scripts) {
                $src = Join-Path $capturedScriptRoot $s
                if (Test-Path $src) {
                    $content = [System.IO.File]::ReadAllText($src) -replace "`r`n","`n"
                    $tmpFile = [System.IO.Path]::GetTempFileName()
                    [System.IO.File]::WriteAllText($tmpFile, $content, [System.Text.Encoding]::UTF8)
                    $wslTmp = & wsl -d $capturedDistro -e wslpath -u $tmpFile 2>&1
                    & wsl -d $capturedDistro -e bash -c "cp '$wslTmp' '/root/$s' && chmod +x '/root/$s'" 2>&1 | Out-Null
                    Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
                    Write-Log "Copied: $s" "INFO"
                } else {
                    Write-Log "Script not found locally: $src" "WARN"
                    Write-Log "Attempting to download from GitHub..." "INFO"
                    & wsl -d $capturedDistro -e bash -c "curl -fsSL https://raw.githubusercontent.com/JudgeUAu/UnlimitedPlex/main/$s -o /root/$s && chmod +x /root/$s" 2>&1 | ForEach-Object { Write-Log "$_" "INFO" }
                }
            }

            Set-Progress 15 "Setting up mounts..."
            & wsl -d $capturedDistro -e bash -c "mount --bind /mnt /mnt 2>/dev/null; mount --make-shared /mnt 2>/dev/null" 2>&1 | Out-Null

            Set-Progress 20 "Running installer..."
            Write-Log "Starting setup_beta.sh..." "STEP"
            Write-Log "This may take 10-20 minutes. Please wait..." "INFO"

            if ($Script:StopRequested) { throw "Stopped by user." }

            # Build run command
            $runCmd = "bash /root/setup_beta.sh --config '$wslConfigPath'"

            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "wsl"
            $psi.Arguments = "-d $capturedDistro -e bash -c `"$runCmd`""
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
                    if ($line -match "\[ERROR\]|error")       { $lvl = "ERROR" }
                    elseif ($line -match "\[WARN\]|warn")     { $lvl = "WARN" }
                    elseif ($line -match "\[OK\]|complete")   { $lvl = "SUCCESS" }
                    elseif ($line -match "\[STEP\]|Step |===") { $lvl = "STEP" }
                    Write-Log $line $lvl

                    if    ($line -match "Step 0|Dependencies") { Set-Progress 20 "Dependencies..." }
                    elseif($line -match "Step 1|Docker")       { Set-Progress 30 "Docker..." }
                    elseif($line -match "Step 2|Mount")        { Set-Progress 35 "Mounts..." }
                    elseif($line -match "Step 3|Plex")         { Set-Progress 45 "Plex..." }
                    elseif($line -match "Step 12|Network")     { Set-Progress 55 "Network..." }
                    elseif($line -match "Step 13|Instance")    { Set-Progress 65 "Instances..." }
                    elseif($line -match "Step 14|Global")      { Set-Progress 80 "Global services..." }
                    elseif($line -match "Step 15|Startup")     { Set-Progress 90 "Startup..." }
                    elseif($line -match "Complete!")           { Set-Progress 100 "Done!" }
                }
            }
            $proc.WaitForExit()
            Remove-Item $tmpConfig -Force -ErrorAction SilentlyContinue

            if ($proc.ExitCode -ne 0) {
                $err = $proc.StandardError.ReadToEnd()
                if ($err) { Write-Log "STDERR: $err" "ERROR" }
                throw "Installer exited with code $($proc.ExitCode)"
            }

            Set-Progress 100 "Complete!"
            Write-Log "================================================" "SUCCESS"
            Write-Log "  Installation Complete!" "SUCCESS"
            Write-Log "  Plex: http://localhost:32400/web" "SUCCESS"
            Write-Log "================================================" "SUCCESS"
            Set-Status "Installation complete!" "#238636"

            $Window.Dispatcher.Invoke({
                [System.Windows.MessageBox]::Show(
                    "Installation complete!`n`nCheck the Status tab to verify all services are running.",
                    "Success", "OK", "Information")
            })

        } catch {
            Write-Log "Installation failed: $_" "ERROR"
            Set-Status "Failed" "#da3633"
            Set-Progress 0 "Failed"
            $Window.Dispatcher.Invoke({
                [System.Windows.MessageBox]::Show("Installation failed:`n$_`n`nCheck the Install Log tab.", "Error", "OK", "Error")
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
    Write-Log "Stop requested..." "WARN"
    Set-Status "Stopping..." "#ffcc00"
})

# =============================================================================
# REFRESH SERVICES STATUS
# =============================================================================
$RefreshServicesBtn.Add_Click({
    $ServicesPanel.Children.Clear()
    $wslDistro = $WSLDistroBox.Text.Trim()

    # Build dynamic service list from current instances
    $allServices = [System.Collections.Generic.List[hashtable]]::new()
    $allServices.Add(@{ Name="Plex"; Container="plexmediaserver"; Port=32400; Path="/web" })

    foreach ($inst in $Script:Instances) {
        foreach ($svcDef in $Script:ServiceDefs) {
            $chk = $inst.Checks[$svcDef.Key]
            if ($chk -and $chk.IsChecked) {
                $port = Get-InstancePort $svcDef.Key $inst.Index
                $allServices.Add(@{
                    Name      = "$($svcDef.Label) [$($inst.Label)]"
                    Container = "$($svcDef.Key)_$($inst.Name)"
                    Port      = $port
                    Path      = ""
                })
            }
        }
    }

    if ($ChkTautulli.IsChecked) { $allServices.Add(@{ Name="Tautulli"; Container="tautulli"; Port=8181; Path="" }) }
    if ($ChkNZBDav.IsChecked)   { $allServices.Add(@{ Name="NZBDav";   Container="nzbdav";   Port=3000; Path="" }) }

    foreach ($svc in $allServices) {
        $running = $false
        try {
            $result = & wsl -d $wslDistro -e bash -c "docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^$($svc.Container)$' && echo running || echo stopped" 2>&1
            $running = ("$result" -match "running")
        } catch {}

        $card = New-Object Windows.Controls.Border
        $card.Background = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#161b22"))
        $card.BorderBrush = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString($(if ($running) { "#238636" } else { "#30363d" })))
        $card.BorderThickness = "1"
        $card.CornerRadius = "6"
        $card.Padding = "12,10"
        $card.Margin = "0,0,10,10"
        $card.Width = 180

        $sp = New-Object Windows.Controls.StackPanel

        $statusTxt = New-Object Windows.Controls.TextBlock
        $statusTxt.Text = if ($running) { "[ON] $($svc.Name)" } else { "[--] $($svc.Name)" }
        $statusTxt.Foreground = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString($(if ($running) { "#3fb950" } else { "#8b949e" })))
        $statusTxt.FontSize = 12
        $statusTxt.FontWeight = "SemiBold"
        $statusTxt.TextWrapping = "Wrap"

        $portTxt = New-Object Windows.Controls.TextBlock
        $portTxt.Text = "Port: $($svc.Port)"
        $portTxt.Foreground = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#8b949e"))
        $portTxt.FontSize = 10
        $portTxt.Margin = "0,3,0,6"

        $sp.Children.Add($statusTxt) | Out-Null
        $sp.Children.Add($portTxt)   | Out-Null

        if ($running) {
            $url = "http://localhost:$($svc.Port)$($svc.Path)"
            $openBtn = New-Object Windows.Controls.Button
            $openBtn.Content = "Open"
            $openBtn.Background = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#1f6feb"))
            $openBtn.Foreground = [Windows.Media.Brushes]::White
            $openBtn.BorderThickness = "0"
            $openBtn.Padding = "10,4"
            $openBtn.FontSize = 11
            $openBtn.HorizontalAlignment = "Left"
            $capturedUrl = $url
            $openBtn.Add_Click({ Start-Process $capturedUrl }.GetNewClosure())
            $sp.Children.Add($openBtn) | Out-Null
        }

        $card.Child = $sp
        $ServicesPanel.Children.Add($card) | Out-Null
    }

    Write-Log "Service status refreshed." "INFO"
})

# =============================================================================
# LOG BUTTONS
# =============================================================================
$ClearLogBtn.Add_Click({ $LogBox.Clear() })
$SaveLogBtn.Add_Click({
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter = "Log files (*.log)|*.log|Text files (*.txt)|*.txt"
    $dlg.FileName = "unlimitedplex_beta_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    if ($dlg.ShowDialog() -eq "OK") {
        $LogBox.Text | Out-File $dlg.FileName -Encoding UTF8
        Write-Log "Log saved: $($dlg.FileName)" "SUCCESS"
    }
})

# =============================================================================
# STARTUP - Add default "Main" instance
# =============================================================================
Write-Log "UnlimitedPlex Beta Installer started." "INFO"
Write-Log "Add instances in the Services tab, then configure and install." "INFO"

# Auto-add a default "Main" instance to get users started
Add-InstanceUI -DefaultLabel "Main"

"[$(Get-Date)] Window about to show" | Out-File $Script:ErrorLogPath -Append

try {
    $Window.ShowDialog() | Out-Null
} catch {
    $errMsg = "[$(Get-Date)] ShowDialog error: $_"
    $errMsg | Out-File $Script:ErrorLogPath -Append
    [System.Windows.MessageBox]::Show("Failed to show window:`n$_`n`nLog: $Script:ErrorLogPath","Error","OK","Error")
}

"[$(Get-Date)] Script ended" | Out-File $Script:ErrorLogPath -Append