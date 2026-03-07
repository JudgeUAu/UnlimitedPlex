#Requires -Version 5.1
# UnlimitedPlex Beta - Windows GUI Installer
# Modular service selector with multiple instance support

# WPF requires STA mode
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    $scriptPath = if ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { $PSCommandPath }
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -NoProfile -STA -File `"$scriptPath`"" -Verb RunAs
    exit
}

$Script:ErrorLogPath = Join-Path $env:TEMP "UnlimitedPlex_Beta_error.log"
"[$(Get-Date)] Beta script started" | Out-File $Script:ErrorLogPath -Append

trap {
    $errMsg = "[$(Get-Date)] FATAL: $_`n$($_.ScriptStackTrace)"
    $errMsg | Out-File $Script:ErrorLogPath -Append
    try { [System.Windows.MessageBox]::Show("Fatal error:`n$_`n`nLog: $Script:ErrorLogPath","UnlimitedPlex Error","OK","Error") }
    catch { $errMsg | Out-File "$env:TEMP\UnlimitedPlex_Beta_fatal.log" -Append }
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
    Height="820" Width="1020"
    MinHeight="700" MinWidth="900"
    WindowStartupLocation="CenterScreen"
    Background="#0d1117">

    <Window.Resources>
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
                            <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#2ea043"/></Trigger>
                            <Trigger Property="IsEnabled" Value="False"><Setter Property="Background" Value="#21262d"/><Setter Property="Foreground" Value="#484f58"/></Trigger>
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
        <Style x:Key="FieldLabel" TargetType="TextBlock">
            <Setter Property="Foreground" Value="#8b949e"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="Margin" Value="0,10,0,3"/>
        </Style>
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
        <Style x:Key="SectionHeader" TargetType="TextBlock">
            <Setter Property="Foreground" Value="#e6edf3"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Margin" Value="0,0,0,10"/>
        </Style>
        <Style x:Key="SvcCheck" TargetType="CheckBox">
            <Setter Property="Foreground" Value="#e6edf3"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>
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
                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                    <Ellipse x:Name="StatusDot" Width="10" Height="10" Fill="#484f58" Margin="0,0,6,0"/>
                    <TextBlock x:Name="StatusText" Text="Ready" Foreground="#8b949e" FontSize="11" VerticalAlignment="Center"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Tabs -->
        <TabControl Grid.Row="1" Background="#0d1117" BorderThickness="0">

            <!-- ================================================================
                 TAB 1: INSTANCES
                 ================================================================ -->
            <TabItem Header="[1] Instances">
                <Grid Background="#0d1117">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <!-- Top info bar -->
                    <Border Grid.Row="0" Background="#161b22" BorderBrush="#30363d" BorderThickness="0,0,0,1" Padding="20,12">
                        <StackPanel>
                            <TextBlock Style="{StaticResource SectionHeader}" Text="Instances" Margin="0"/>
                            <TextBlock Foreground="#8b949e" FontSize="11" TextWrapping="Wrap">
                                Each instance gets its own Radarr, Sonarr and/or Prowlarr on separate ports.
                                Zurg, Decypharr and Plex are always installed globally (once, shared).
                            </TextBlock>

                            <!-- Always-on global services info -->
                            <Border Background="#0d1117" BorderBrush="#1f6feb" BorderThickness="1" CornerRadius="6" Padding="12,8" Margin="0,10,0,0">
                                <StackPanel>
                                    <TextBlock Text="Always installed (global, single instance):" Foreground="#58a6ff" FontSize="11" FontWeight="SemiBold" Margin="0,0,0,6"/>
                                    <WrapPanel>
                                        <Border Background="#161b22" BorderBrush="#30363d" BorderThickness="1" CornerRadius="4" Padding="8,4" Margin="0,0,8,0">
                                            <TextBlock Text="Plex  port:32400" Foreground="#3fb950" FontSize="11"/>
                                        </Border>
                                        <Border Background="#161b22" BorderBrush="#30363d" BorderThickness="1" CornerRadius="4" Padding="8,4" Margin="0,0,8,0">
                                            <TextBlock Text="Zurg  port:9999" Foreground="#3fb950" FontSize="11"/>
                                        </Border>
                                        <Border Background="#161b22" BorderBrush="#30363d" BorderThickness="1" CornerRadius="4" Padding="8,4" Margin="0,0,8,0">
                                            <TextBlock Text="Decypharr  port:8282" Foreground="#3fb950" FontSize="11"/>
                                        </Border>
                                    </WrapPanel>
                                </StackPanel>
                            </Border>

                            <!-- Optional global services -->
                            <Border Background="#0d1117" BorderBrush="#30363d" BorderThickness="1" CornerRadius="6" Padding="12,8" Margin="0,8,0,0">
                                <StackPanel>
                                    <TextBlock Text="Optional global services:" Foreground="#8b949e" FontSize="11" FontWeight="SemiBold" Margin="0,0,0,6"/>
                                    <WrapPanel>
                                        <Border Background="#161b22" BorderBrush="#30363d" BorderThickness="1" CornerRadius="4" Padding="8,6" Margin="0,0,8,0" Width="190">
                                            <StackPanel>
                                                <CheckBox x:Name="ChkTautulli" Style="{StaticResource SvcCheck}" IsChecked="True">
                                                    <StackPanel>
                                                        <TextBlock Text="Tautulli" Foreground="#e6edf3" FontWeight="SemiBold"/>
                                                        <TextBlock Text="Plex analytics  port:8181" Foreground="#8b949e" FontSize="10"/>
                                                    </StackPanel>
                                                </CheckBox>
                                            </StackPanel>
                                        </Border>
                                        <Border Background="#161b22" BorderBrush="#30363d" BorderThickness="1" CornerRadius="4" Padding="8,6" Margin="0,0,8,0" Width="190">
                                            <StackPanel>
                                                <CheckBox x:Name="ChkPulsarr" Style="{StaticResource SvcCheck}" IsChecked="False">
                                                    <StackPanel>
                                                        <TextBlock Text="Pulsarr" Foreground="#e6edf3" FontWeight="SemiBold"/>
                                                        <TextBlock Text="Watchlist sync  port:3003" Foreground="#8b949e" FontSize="10"/>
                                                    </StackPanel>
                                                </CheckBox>
                                            </StackPanel>
                                        </Border>
                                        <Border Background="#161b22" BorderBrush="#30363d" BorderThickness="1" CornerRadius="4" Padding="8,6" Margin="0,0,0,0" Width="220">
                                            <StackPanel>
                                                <CheckBox x:Name="ChkNZBDav" Style="{StaticResource SvcCheck}" IsChecked="False">
                                                    <StackPanel>
                                                        <TextBlock Text="NZBDav" Foreground="#e6edf3" FontWeight="SemiBold"/>
                                                        <TextBlock Text="Usenet streaming  port:3000" Foreground="#8b949e" FontSize="10"/>
                                                    </StackPanel>
                                                </CheckBox>
                                                <StackPanel x:Name="NZBDavPassPanel" Margin="20,4,0,0" Visibility="Collapsed">
                                                    <TextBlock Text="WebDAV Password:" Foreground="#8b949e" FontSize="10" Margin="0,0,0,2"/>
                                                    <PasswordBox x:Name="NZBDavPassBox" Style="{StaticResource PassBox}" Width="150" HorizontalAlignment="Left"/>
                                                </StackPanel>
                                            </StackPanel>
                                        </Border>
                                    </WrapPanel>
                                </StackPanel>
                            </Border>
                        </StackPanel>
                    </Border>

                    <!-- Instances list -->
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Background="#0d1117">
                        <StackPanel x:Name="InstancesPanel" Margin="20,16,20,0"/>
                    </ScrollViewer>

                    <!-- Add instance button -->
                    <Border Grid.Row="2" Background="#161b22" BorderBrush="#30363d" BorderThickness="0,1,0,0" Padding="20,10">
                        <StackPanel Orientation="Horizontal">
                            <Button x:Name="AddInstanceBtn" Style="{StaticResource SecondaryBtn}" Content="+ Add Instance" Margin="0,0,10,0"/>
                            <TextBlock Foreground="#8b949e" FontSize="11" VerticalAlignment="Center">
                                Port offset per instance: +100  (Instance 0: base ports, Instance 1: base+100, etc.)
                            </TextBlock>
                        </StackPanel>
                    </Border>
                </Grid>
            </TabItem>

            <!-- ================================================================
                 TAB 2: CONFIGURATION
                 ================================================================ -->
            <TabItem Header="[2] Configuration">
                <ScrollViewer VerticalScrollBarVisibility="Auto" Background="#0d1117">
                    <StackPanel Margin="24,20" MaxWidth="600">
                        <TextBlock Style="{StaticResource SectionHeader}" Text="Configuration"/>

                        <TextBlock Style="{StaticResource FieldLabel}" Text="Real-Debrid API Token *"/>
                        <PasswordBox x:Name="RDTokenBox" Style="{StaticResource PassBox}"/>
                        <TextBlock Foreground="#8b949e" FontSize="10" Margin="0,3,0,0">Get from: https://real-debrid.com/apitoken</TextBlock>

                        <TextBlock Style="{StaticResource FieldLabel}" Text="Plex Claim Token *"/>
                        <PasswordBox x:Name="PlexTokenBox" Style="{StaticResource PassBox}"/>
                        <TextBlock Foreground="#8b949e" FontSize="10" Margin="0,3,0,0">Get from: https://www.plex.tv/claim (expires in 4 min)</TextBlock>

                        <TextBlock Style="{StaticResource FieldLabel}" Text="Timezone"/>
                        <TextBox x:Name="TimezoneBox" Style="{StaticResource InputBox}" Text="America/New_York"/>
                        <TextBlock Foreground="#8b949e" FontSize="10" Margin="0,3,0,0">Examples: America/New_York, Europe/London, Australia/Sydney</TextBlock>

                        <TextBlock Style="{StaticResource FieldLabel}" Text="Zurg Version"/>
                        <TextBox x:Name="ZurgVersionBox" Style="{StaticResource InputBox}" Text="v0.9.3-final"/>

                        <TextBlock Style="{StaticResource FieldLabel}" Text="WSL2 Distro Name"/>
                        <TextBox x:Name="WSLDistroBox" Style="{StaticResource InputBox}" Text="Ubuntu"/>
                        <TextBlock Foreground="#8b949e" FontSize="10" Margin="0,3,0,0">Run 'wsl -l -q' in PowerShell to see your distro names</TextBlock>

                        <!-- Prerequisites -->
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
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <TextBlock Grid.Row="0" Style="{StaticResource SectionHeader}" Text="Installation"/>

                    <Border Grid.Row="1" Background="#161b22" BorderBrush="#30363d" BorderThickness="1" CornerRadius="6" Padding="14" Margin="0,0,0,12">
                        <StackPanel>
                            <TextBlock Text="Installation Summary" Foreground="#58a6ff" FontSize="12" FontWeight="SemiBold" Margin="0,0,0,8"/>
                            <TextBlock x:Name="SummaryText" Foreground="#8b949e" FontSize="11" TextWrapping="Wrap"
                                       Text="Configure instances in the Instances tab, then click Refresh Summary."/>
                        </StackPanel>
                    </Border>

                    <Grid Grid.Row="2" Margin="0,0,0,12">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="60"/>
                        </Grid.ColumnDefinitions>
                        <ProgressBar x:Name="InstallProgress" Height="8" Value="0" Maximum="100"
                                     Background="#21262d" Foreground="#238636" BorderThickness="0"/>
                        <TextBlock x:Name="ProgressLabel" Grid.Column="1" Text="0%"
                                   Foreground="#8b949e" FontSize="11" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                    </Grid>

                    <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="0,0,0,12">
                        <Button x:Name="InstallBtn" Style="{StaticResource PrimaryBtn}" Content=">> Install" Margin="0,0,10,0"/>
                        <Button x:Name="StopBtn" Style="{StaticResource DangerBtn}" Content="Stop" IsEnabled="False" Margin="0,0,10,0"/>
                        <Button x:Name="UpdateSummaryBtn" Style="{StaticResource SecondaryBtn}" Content="Refresh Summary"/>
                    </StackPanel>

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
                                        <Button x:Name="ClearLogBtn" Style="{StaticResource SecondaryBtn}" Content="Clear" Padding="8,3" FontSize="10"/>
                                        <Button x:Name="SaveLogBtn"  Style="{StaticResource SecondaryBtn}" Content="Save"  Padding="8,3" FontSize="10" Margin="6,0,0,0"/>
                                    </StackPanel>
                                </Grid>
                            </Border>
                            <TextBox Grid.Row="1" x:Name="LogBox"
                                     Background="Transparent" Foreground="#e6edf3"
                                     FontFamily="Consolas" FontSize="11"
                                     IsReadOnly="True" TextWrapping="Wrap"
                                     VerticalScrollBarVisibility="Auto"
                                     BorderThickness="0" Padding="10" MinHeight="280"/>
                        </Grid>
                    </Border>
                </Grid>
            </TabItem>

            <!-- ================================================================
                 TAB 4: STATUS
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
                                <TextBlock Foreground="#e6edf3" FontSize="12" TextWrapping="Wrap" LineHeight="22">
1. Instances tab: Add instances (Main, 4K, Kids, etc.)
   Select Radarr/Sonarr/Prowlarr per instance.
   Choose optional global services (Tautulli, Pulsarr, NZBDav).
2. Configuration tab: Enter RD token, Plex token, timezone.
   Click Check Prerequisites.
3. Install tab: Click Refresh Summary to review, then Install.
                                </TextBlock>
                            </StackPanel>
                        </Border>

                        <Border Background="#161b22" BorderBrush="#30363d" BorderThickness="1" CornerRadius="6" Padding="16" Margin="0,0,0,12">
                            <StackPanel>
                                <TextBlock Text="Architecture" Foreground="#58a6ff" FontSize="13" FontWeight="SemiBold" Margin="0,0,0,8"/>
                                <TextBlock Foreground="#e6edf3" FontSize="12" TextWrapping="Wrap" LineHeight="22">
GLOBAL (single instance, always):
  Plex Media Server  - native install, port 32400
  Zurg + Rclone      - /opt/zurg-testing, mounts /mnt/remote/realdebrid
  Decypharr          - /opt/decypharr, knows all arr instances

GLOBAL (optional, single instance):
  Tautulli           - /opt/tautulli, port 8181
  Pulsarr            - /opt/pulsarr, port 3003
  NZBDav             - /opt/nzbdav, port 3000, mounts /mnt/remote/nzbdav

PER INSTANCE (in /opt/arr-stack, one compose file):
  Radarr             - port 7878, 7978, 8078...
  Sonarr             - port 8989, 9089, 9189...
  Prowlarr           - port 9696, 9796, 9896...

SYMLINKS (created by Decypharr):
  /mnt/symlinks/main_radarr/
  /mnt/symlinks/main_sonarr/
  /mnt/symlinks/4k_radarr/  etc.

PLEX LIBRARIES:
  /mnt/plex/Main/Movies, /mnt/plex/Main/TV
  /mnt/plex/4K/Movies,   /mnt/plex/4K/TV  etc.
                                </TextBlock>
                            </StackPanel>
                        </Border>

                        <Border Background="#161b22" BorderBrush="#30363d" BorderThickness="1" CornerRadius="6" Padding="16" Margin="0,0,0,12">
                            <StackPanel>
                                <TextBlock Text="Port Reference" Foreground="#58a6ff" FontSize="13" FontWeight="SemiBold" Margin="0,0,0,8"/>
                                <TextBlock Foreground="#e6edf3" FontSize="12" TextWrapping="Wrap" LineHeight="22">
Instance 0 (Main):  Radarr:7878  Sonarr:8989  Prowlarr:9696
Instance 1 (4K):    Radarr:7978  Sonarr:9089  Prowlarr:9796
Instance 2 (Kids):  Radarr:8078  Sonarr:9189  Prowlarr:9896
Instance 3:         Radarr:8178  Sonarr:9289  Prowlarr:9996
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
                <TextBlock x:Name="FooterStatus" Text="Ready." Foreground="#8b949e" FontSize="11" VerticalAlignment="Center"/>
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

# Controls
$AddInstanceBtn     = $Window.FindName("AddInstanceBtn")
$InstancesPanel     = $Window.FindName("InstancesPanel")
$ChkTautulli        = $Window.FindName("ChkTautulli")
$ChkPulsarr         = $Window.FindName("ChkPulsarr")
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
# DATA MODEL
# =============================================================================
$Script:Instances     = [System.Collections.Generic.List[hashtable]]::new()
$Script:StopRequested = $false

# Per-instance services (only these 3 are per-instance)
$Script:PerInstanceServices = @(
    @{ Key="radarr";   Label="Radarr";   Desc="Movie management";   BasePort=7878; Default=$true  },
    @{ Key="sonarr";   Label="Sonarr";   Desc="TV show management"; BasePort=8989; Default=$true  },
    @{ Key="prowlarr"; Label="Prowlarr"; Desc="Indexer manager";    BasePort=9696; Default=$true  }
)

# =============================================================================
# HELPERS
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

function Get-SafeName { param([string]$Label)
    return ($Label.ToLower() -replace '[^a-z0-9]','_' -replace '_+$','')
}

function Get-InstancePort { param([int]$BasePort, [int]$Idx)
    return $BasePort + ($Idx * 100)
}

# =============================================================================
# ADD INSTANCE UI
# =============================================================================
function Add-InstanceUI {
    param([string]$DefaultLabel = "")

    $idx = $Script:Instances.Count

    # Name dialog
    $dlg = New-Object System.Windows.Window
    $dlg.Title = "New Instance"
    $dlg.Width = 420; $dlg.Height = 190
    $dlg.WindowStartupLocation = "CenterOwner"
    $dlg.Owner = $Window
    $dlg.Background = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#0d1117"))
    $dlg.ResizeMode = "NoResize"

    $sp = New-Object Windows.Controls.StackPanel; $sp.Margin = "20"

    $lbl = New-Object Windows.Controls.TextBlock
    $lbl.Text = "Instance name (e.g. Main, 4K, Kids, Anime):"
    $lbl.Foreground = [Windows.Media.Brushes]::White; $lbl.Margin = "0,0,0,8"

    $tb = New-Object Windows.Controls.TextBox
    $tb.Text = $DefaultLabel
    $tb.Background = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#161b22"))
    $tb.Foreground = [Windows.Media.Brushes]::White
    $tb.BorderBrush = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#30363d"))
    $tb.Padding = "8,6"; $tb.FontSize = 13; $tb.Margin = "0,0,0,12"

    $btnOk = New-Object Windows.Controls.Button
    $btnOk.Content = "Add Instance"
    $btnOk.Background = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#238636"))
    $btnOk.Foreground = [Windows.Media.Brushes]::White
    $btnOk.Padding = "16,8"; $btnOk.BorderThickness = "0"; $btnOk.HorizontalAlignment = "Left"
    $btnOk.Add_Click({ $dlg.DialogResult = $true; $dlg.Close() })

    $sp.Children.Add($lbl) | Out-Null
    $sp.Children.Add($tb)  | Out-Null
    $sp.Children.Add($btnOk) | Out-Null
    $dlg.Content = $sp
    $tb.Focus() | Out-Null

    if (-not $dlg.ShowDialog() -or [string]::IsNullOrWhiteSpace($tb.Text)) { return }

    $label    = $tb.Text.Trim()
    $safeName = Get-SafeName $label

    $instData = @{ Label=$label; Name=$safeName; Index=$idx; Checks=@{} }

    # Build card
    $card = New-Object Windows.Controls.Border
    $card.Background  = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#161b22"))
    $card.BorderBrush = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#30363d"))
    $card.BorderThickness = "1"; $card.CornerRadius = "8"
    $card.Padding = "16"; $card.Margin = "0,0,0,12"

    $cardSP = New-Object Windows.Controls.StackPanel

    # Header row
    $hdrGrid = New-Object Windows.Controls.Grid
    $c1 = New-Object Windows.Controls.ColumnDefinition; $c1.Width = [Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)
    $c2 = New-Object Windows.Controls.ColumnDefinition; $c2.Width = [Windows.GridLength]::Auto
    $hdrGrid.ColumnDefinitions.Add($c1); $hdrGrid.ColumnDefinitions.Add($c2)

    $titleSP = New-Object Windows.Controls.StackPanel; $titleSP.Orientation = "Horizontal"

    $badge = New-Object Windows.Controls.Border
    $badge.Background = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#1f6feb"))
    $badge.CornerRadius = "4"; $badge.Padding = "6,2"; $badge.Margin = "0,0,8,0"
    $badgeTxt = New-Object Windows.Controls.TextBlock
    $badgeTxt.Text = "Instance $idx"; $badgeTxt.Foreground = [Windows.Media.Brushes]::White; $badgeTxt.FontSize = 10
    $badge.Child = $badgeTxt

    $titleTxt = New-Object Windows.Controls.TextBlock
    $titleTxt.Text = $label; $titleTxt.Foreground = [Windows.Media.Brushes]::White
    $titleTxt.FontSize = 14; $titleTxt.FontWeight = "SemiBold"; $titleTxt.VerticalAlignment = "Center"

    $titleSP.Children.Add($badge)    | Out-Null
    $titleSP.Children.Add($titleTxt) | Out-Null
    [Windows.Controls.Grid]::SetColumn($titleSP, 0)
    $hdrGrid.Children.Add($titleSP) | Out-Null

    $removeBtn = New-Object Windows.Controls.Button
    $removeBtn.Content = "Remove"
    $removeBtn.Background = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#21262d"))
    $removeBtn.Foreground = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#f85149"))
    $removeBtn.BorderBrush = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#30363d"))
    $removeBtn.BorderThickness = "1"; $removeBtn.Padding = "10,4"; $removeBtn.FontSize = 11; $removeBtn.Cursor = "Hand"
    $capturedCard = $card; $capturedData = $instData
    $removeBtn.Add_Click({ $InstancesPanel.Children.Remove($capturedCard); $Script:Instances.Remove($capturedData) | Out-Null }.GetNewClosure())
    [Windows.Controls.Grid]::SetColumn($removeBtn, 1)
    $hdrGrid.Children.Add($removeBtn) | Out-Null
    $cardSP.Children.Add($hdrGrid) | Out-Null

    # Paths info
    $pathTxt = New-Object Windows.Controls.TextBlock
    $pathTxt.Text = "Plex: /mnt/plex/$label/{Movies,TV}   Symlinks: /mnt/symlinks/${safeName}_{radarr,sonarr}"
    $pathTxt.Foreground = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#8b949e"))
    $pathTxt.FontSize = 10; $pathTxt.Margin = "0,6,0,10"
    $cardSP.Children.Add($pathTxt) | Out-Null

    # Service checkboxes (only per-instance services)
    $svcWrap = New-Object Windows.Controls.WrapPanel; $svcWrap.Orientation = "Horizontal"

    foreach ($svcDef in $Script:PerInstanceServices) {
        $port = Get-InstancePort $svcDef.BasePort $idx

        $svcBorder = New-Object Windows.Controls.Border
        $svcBorder.Background = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#0d1117"))
        $svcBorder.BorderBrush = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#21262d"))
        $svcBorder.BorderThickness = "1"; $svcBorder.CornerRadius = "4"
        $svcBorder.Padding = "10,8"; $svcBorder.Margin = "0,0,10,8"; $svcBorder.Width = 170

        $svcSP = New-Object Windows.Controls.StackPanel

        $chk = New-Object Windows.Controls.CheckBox
        $chk.IsChecked = $svcDef.Default
        $chk.Foreground = [Windows.Media.Brushes]::White
        $chk.FontSize = 12; $chk.FontWeight = "SemiBold"; $chk.Content = $svcDef.Label

        $descTxt = New-Object Windows.Controls.TextBlock
        $descTxt.Text = $svcDef.Desc
        $descTxt.Foreground = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#8b949e"))
        $descTxt.FontSize = 10; $descTxt.Margin = "20,2,0,0"

        $portTxt = New-Object Windows.Controls.TextBlock
        $portTxt.Text = "Port: $port"
        $portTxt.Foreground = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#1f6feb"))
        $portTxt.FontSize = 10; $portTxt.Margin = "20,1,0,0"

        $svcSP.Children.Add($chk)     | Out-Null
        $svcSP.Children.Add($descTxt) | Out-Null
        $svcSP.Children.Add($portTxt) | Out-Null
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
# EVENTS
# =============================================================================
$AddInstanceBtn.Add_Click({ Add-InstanceUI })
$ChkNZBDav.Add_Checked({   $NZBDavPassPanel.Visibility = "Visible" })
$ChkNZBDav.Add_Unchecked({ $NZBDavPassPanel.Visibility = "Collapsed" })

# =============================================================================
# PREREQUISITES CHECK
# =============================================================================
$CheckPrereqsBtn.Add_Click({
    Write-Log "Checking prerequisites..." "STEP"

    # Admin
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $pr = [Security.Principal.WindowsPrincipal]$id
        if ($pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            $AdminStatus.Text = "[OK] Administrator"; $AdminStatus.Foreground = [Windows.Media.Brushes]::LightGreen
            $AdminVersion.Text = "Running as admin"; Write-Log "Admin: OK" "SUCCESS"
        } else {
            $AdminStatus.Text = "[!] Not Admin"
            $AdminStatus.Foreground = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#ffcc00"))
            $AdminVersion.Text = "Re-run as Administrator"; Write-Log "Not running as Administrator" "WARN"
        }
    } catch { $AdminStatus.Text = "[X] Admin check failed"; $AdminStatus.Foreground = [Windows.Media.Brushes]::Salmon }

    # Docker
    try {
        $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
        if ($dockerCmd) {
            $dv = & docker --version 2>&1
            if ($LASTEXITCODE -eq 0) {
                $DockerStatus.Text = "[OK] Docker"; $DockerStatus.Foreground = [Windows.Media.Brushes]::LightGreen
                $DockerVersion.Text = "$dv"; Write-Log "Docker: $dv" "SUCCESS"
            } else {
                $DockerStatus.Text = "[!] Docker (not running)"
                $DockerStatus.Foreground = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#ffcc00"))
                $DockerVersion.Text = "Start Docker Desktop"; Write-Log "Docker not running" "WARN"
            }
        } else {
            $DockerStatus.Text = "[X] Docker not found"; $DockerStatus.Foreground = [Windows.Media.Brushes]::Salmon
            $DockerVersion.Text = "Install Docker Desktop"; Write-Log "Docker not found" "ERROR"
        }
    } catch { $DockerStatus.Text = "[X] Docker error"; $DockerStatus.Foreground = [Windows.Media.Brushes]::Salmon }

    # WSL2 - handle UTF-16LE null bytes
    try {
        $wslFound = $false; $distroFound = $false
        $distro = $WSLDistroBox.Text.Trim()

        $wslQuiet = & wsl -l -q 2>&1
        if ($wslQuiet) {
            $wslClean = ($wslQuiet | ForEach-Object { if ($_ -is [string]) { $_ -replace "`0","" } else { "$_" -replace "`0","" } }) -join "`n"
            $wslFound = $true
            if ($wslClean -match [regex]::Escape($distro)) { $distroFound = $true }
        }
        if (-not $distroFound) {
            $testRun = & wsl -d $distro -e echo "ok" 2>&1
            if ($LASTEXITCODE -eq 0 -and "$testRun" -match "ok") { $wslFound = $true; $distroFound = $true }
        }

        if ($distroFound) {
            $WSLStatus.Text = "[OK] WSL2 ($distro)"; $WSLStatus.Foreground = [Windows.Media.Brushes]::LightGreen
            $WSLVersion.Text = "Distro: $distro"; Write-Log "WSL2: OK - $distro" "SUCCESS"
        } elseif ($wslFound) {
            $WSLStatus.Text = "[!] WSL2 (distro not found)"
            $WSLStatus.Foreground = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#ffcc00"))
            $WSLVersion.Text = "Check distro name above"; Write-Log "WSL2 found but '$distro' not detected. Run: wsl -l -q" "WARN"
        } else {
            $WSLStatus.Text = "[X] WSL2 not found"; $WSLStatus.Foreground = [Windows.Media.Brushes]::Salmon
            $WSLVersion.Text = "Run: wsl --install"; Write-Log "WSL2 not found" "ERROR"
        }
    } catch { $WSLStatus.Text = "[X] WSL2 error"; $WSLStatus.Foreground = [Windows.Media.Brushes]::Salmon; Write-Log "WSL2 error: $_" "ERROR" }

    Write-Log "Prerequisites check complete." "INFO"
})

# =============================================================================
# SUMMARY
# =============================================================================
function Update-Summary {
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("Always installed (global):")
    $lines.Add("  Plex Media Server  port:32400")
    $lines.Add("  Zurg + Rclone      port:9999   -> /mnt/remote/realdebrid")
    $lines.Add("  Decypharr          port:8282")
    $lines.Add("")

    $globalSvcs = @()
    if ($ChkTautulli.IsChecked) { $globalSvcs += "Tautulli (port 8181)" }
    if ($ChkPulsarr.IsChecked)  { $globalSvcs += "Pulsarr  (port 3003)" }
    if ($ChkNZBDav.IsChecked)   { $globalSvcs += "NZBDav   (port 3000)" }
    if ($globalSvcs.Count -gt 0) {
        $lines.Add("Optional global services:")
        foreach ($s in $globalSvcs) { $lines.Add("  $s") }
        $lines.Add("")
    }

    if ($Script:Instances.Count -eq 0) {
        $lines.Add("No instances configured. Add instances in the Instances tab.")
    } else {
        $lines.Add("Instances (all in /opt/arr-stack):")
        foreach ($inst in $Script:Instances) {
            $svcs = @()
            foreach ($svcDef in $Script:PerInstanceServices) {
                $chk = $inst.Checks[$svcDef.Key]
                if ($chk -and $chk.IsChecked) {
                    $port = Get-InstancePort $svcDef.BasePort $inst.Index
                    $svcs += "$($svcDef.Label):$port"
                }
            }
            $lines.Add("  [$($inst.Index)] $($inst.Label) ($($inst.Name))")
            $lines.Add("    Services: $($svcs -join '  ')")
            $lines.Add("    Plex:     /mnt/plex/$($inst.Label)/{Movies,TV}")
            $lines.Add("    Symlinks: /mnt/symlinks/$($inst.Name)_{radarr,sonarr}")
        }
    }
    $SummaryText.Text = $lines -join "`n"
}

$UpdateSummaryBtn.Add_Click({ Update-Summary })

# =============================================================================
# BUILD CONFIG JSON
# =============================================================================
function Build-ConfigJson {
    $rdToken   = $RDTokenBox.Password.Trim()
    $plexToken = $PlexTokenBox.Password.Trim()
    $timezone  = $TimezoneBox.Text.Trim()
    $zurgVer   = $ZurgVersionBox.Text.Trim()
    $nzbPass   = $NZBDavPassBox.Password.Trim()

    if ([string]::IsNullOrEmpty($rdToken))   { throw "Real-Debrid token is required." }
    if ([string]::IsNullOrEmpty($plexToken)) { throw "Plex token is required." }
    if ([string]::IsNullOrEmpty($timezone))  { $timezone = "America/New_York" }
    if ([string]::IsNullOrEmpty($zurgVer))   { $zurgVer  = "v0.9.3-final" }
    if ([string]::IsNullOrEmpty($nzbPass))   { $nzbPass  = "changeme" }
    if ($Script:Instances.Count -eq 0)       { throw "No instances configured. Add at least one instance." }

    $instances = @()
    foreach ($inst in $Script:Instances) {
        $svcs = @()
        foreach ($svcDef in $Script:PerInstanceServices) {
            $chk = $inst.Checks[$svcDef.Key]
            if ($chk -and $chk.IsChecked) { $svcs += $svcDef.Key }
        }
        if ($svcs.Count -eq 0) { Write-Log "Instance '$($inst.Label)' has no services - skipping" "WARN"; continue }
        $instances += @{ name=$inst.Name; label=$inst.Label; services=$svcs }
    }

    $globalSvcs = @()
    if ($ChkTautulli.IsChecked) { $globalSvcs += "tautulli" }
    if ($ChkPulsarr.IsChecked)  { $globalSvcs += "pulsarr" }
    if ($ChkNZBDav.IsChecked)   { $globalSvcs += "nzbdav" }

    return (@{
        rd_token        = $rdToken
        plex_token      = $plexToken
        timezone        = $timezone
        zurg_version    = $zurgVer
        nzbdav_password = $nzbPass
        instances       = $instances
        global_services = $globalSvcs
    } | ConvertTo-Json -Depth 5)
}

# =============================================================================
# INSTALL
# =============================================================================
$InstallBtn.Add_Click({
    try { $configJson = Build-ConfigJson }
    catch { [System.Windows.MessageBox]::Show("$_","Validation Error","OK","Warning"); return }

    $wslDistro = $WSLDistroBox.Text.Trim()
    $InstallBtn.IsEnabled = $false; $StopBtn.IsEnabled = $true
    $Script:StopRequested = $false
    Set-Status "Installing..." "#ffcc00"
    Update-Summary

    $capturedConfig     = $configJson
    $capturedDistro     = $wslDistro
    $capturedScriptRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

    $installThread = [System.Threading.Thread]::new([System.Threading.ThreadStart]{
        try {
            Write-Log "================================================" "STEP"
            Write-Log "  UnlimitedPlex Beta Installation Starting" "STEP"
            Write-Log "================================================" "STEP"
            Set-Progress 5 "Preparing..."

            # Write config JSON
            $tmpConfig = [System.IO.Path]::GetTempFileName() + ".json"
            [System.IO.File]::WriteAllText($tmpConfig, $capturedConfig, [System.Text.Encoding]::UTF8)
            $wslConfigPath = (& wsl -d $capturedDistro -e wslpath -u $tmpConfig 2>&1) -replace "`0",""
            Write-Log "Config: $wslConfigPath" "INFO"

            Set-Progress 10 "Copying scripts..."

            # Copy setup_beta.sh
            $src = Join-Path $capturedScriptRoot "setup_beta.sh"
            if (Test-Path $src) {
                $content = [System.IO.File]::ReadAllText($src) -replace "`r`n","`n"
                $tmpFile = [System.IO.Path]::GetTempFileName()
                [System.IO.File]::WriteAllText($tmpFile, $content, [System.Text.Encoding]::UTF8)
                $wslTmp = (& wsl -d $capturedDistro -e wslpath -u $tmpFile 2>&1) -replace "`0",""
                & wsl -d $capturedDistro -e bash -c "cp '$wslTmp' '/root/setup_beta.sh' && chmod +x '/root/setup_beta.sh'" 2>&1 | Out-Null
                Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
                Write-Log "Copied: setup_beta.sh" "INFO"
            } else {
                Write-Log "setup_beta.sh not found locally - downloading from GitHub..." "WARN"
                & wsl -d $capturedDistro -e bash -c "curl -fsSL https://raw.githubusercontent.com/JudgeUAu/UnlimitedPlex/beta/setup_beta.sh -o /root/setup_beta.sh && chmod +x /root/setup_beta.sh" 2>&1 | ForEach-Object { Write-Log "$_" "INFO" }
            }

            Set-Progress 15 "Setting up mounts..."
            & wsl -d $capturedDistro -e bash -c "mount --bind /mnt /mnt 2>/dev/null; mount --make-shared /mnt 2>/dev/null" 2>&1 | Out-Null

            Set-Progress 20 "Running installer..."
            Write-Log "Starting setup_beta.sh - this may take 10-20 minutes..." "STEP"

            if ($Script:StopRequested) { throw "Stopped by user." }

            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName  = "wsl"
            $psi.Arguments = "-d $capturedDistro -e bash -c `"bash /root/setup_beta.sh --config '$wslConfigPath'`""
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError  = $true
            $psi.CreateNoWindow = $true

            $proc = [System.Diagnostics.Process]::new()
            $proc.StartInfo = $psi
            $proc.Start() | Out-Null

            while (-not $proc.StandardOutput.EndOfStream) {
                if ($Script:StopRequested) { $proc.Kill(); throw "Stopped by user." }
                $line = $proc.StandardOutput.ReadLine()
                if ($line) {
                    $lvl = "INFO"
                    if    ($line -match "\[ERROR\]|error")        { $lvl = "ERROR" }
                    elseif($line -match "\[WARN\]|warn")          { $lvl = "WARN" }
                    elseif($line -match "\[OK\]|complete|success") { $lvl = "SUCCESS" }
                    elseif($line -match "\[STEP\]|Step |===")     { $lvl = "STEP" }
                    Write-Log $line $lvl

                    if    ($line -match "Step 0|Dependencies") { Set-Progress 20 "Dependencies..." }
                    elseif($line -match "Step 1|Docker")       { Set-Progress 28 "Docker..." }
                    elseif($line -match "Step 2|Mount")        { Set-Progress 33 "Mounts..." }
                    elseif($line -match "Step 3|Directory")    { Set-Progress 38 "Directories..." }
                    elseif($line -match "Step 4|Plex")         { Set-Progress 45 "Plex..." }
                    elseif($line -match "Step 5|Zurg")         { Set-Progress 55 "Zurg..." }
                    elseif($line -match "Step 6|Network")      { Set-Progress 60 "Network..." }
                    elseif($line -match "Step 7|Arr")          { Set-Progress 68 "Arr stack..." }
                    elseif($line -match "Step 8|Decypharr")    { Set-Progress 76 "Decypharr..." }
                    elseif($line -match "Step 9|Tautulli")     { Set-Progress 82 "Tautulli..." }
                    elseif($line -match "Step 10|Pulsarr")     { Set-Progress 86 "Pulsarr..." }
                    elseif($line -match "Step 11|NZBDav")      { Set-Progress 90 "NZBDav..." }
                    elseif($line -match "Step 12|Startup")     { Set-Progress 95 "Startup..." }
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
            Write-Log "  Plex:      http://localhost:32400/web" "SUCCESS"
            Write-Log "  Zurg:      http://localhost:9999" "SUCCESS"
            Write-Log "  Decypharr: http://localhost:8282" "SUCCESS"
            Write-Log "================================================" "SUCCESS"
            Set-Status "Complete!" "#238636"

            $Window.Dispatcher.Invoke({
                [System.Windows.MessageBox]::Show(
                    "Installation complete!`n`nCheck the Status tab to verify all services are running.",
                    "Success","OK","Information")
            })

        } catch {
            Write-Log "Installation failed: $_" "ERROR"
            Set-Status "Failed" "#da3633"; Set-Progress 0 "Failed"
            $Window.Dispatcher.Invoke({
                [System.Windows.MessageBox]::Show("Installation failed:`n$_`n`nCheck the Install Log tab.","Error","OK","Error")
            })
        } finally {
            $Window.Dispatcher.Invoke({ $InstallBtn.IsEnabled = $true; $StopBtn.IsEnabled = $false })
        }
    })
    $installThread.IsBackground = $true
    $installThread.Start()
})

$StopBtn.Add_Click({ $Script:StopRequested = $true; Write-Log "Stop requested..." "WARN"; Set-Status "Stopping..." "#ffcc00" })

# =============================================================================
# REFRESH SERVICES STATUS
# =============================================================================
$RefreshServicesBtn.Add_Click({
    $ServicesPanel.Children.Clear()
    $wslDistro = $WSLDistroBox.Text.Trim()

    # Build full service list dynamically
    $allSvcs = [System.Collections.Generic.List[hashtable]]::new()
    $allSvcs.Add(@{ Name="Plex";      Container="plexmediaserver"; Port=32400; Path="/web" })
    $allSvcs.Add(@{ Name="Zurg";      Container="zurg";            Port=9999;  Path="" })
    $allSvcs.Add(@{ Name="Decypharr"; Container="decypharr";       Port=8282;  Path="" })

    foreach ($inst in $Script:Instances) {
        foreach ($svcDef in $Script:PerInstanceServices) {
            $chk = $inst.Checks[$svcDef.Key]
            if ($chk -and $chk.IsChecked) {
                $port = Get-InstancePort $svcDef.BasePort $inst.Index
                $allSvcs.Add(@{
                    Name      = "$($svcDef.Label) [$($inst.Label)]"
                    Container = "$($svcDef.Key)_$($inst.Name)"
                    Port      = $port
                    Path      = ""
                })
            }
        }
    }

    if ($ChkTautulli.IsChecked) { $allSvcs.Add(@{ Name="Tautulli"; Container="tautulli"; Port=8181; Path="" }) }
    if ($ChkPulsarr.IsChecked)  { $allSvcs.Add(@{ Name="Pulsarr";  Container="pulsarr";  Port=3003; Path="" }) }
    if ($ChkNZBDav.IsChecked)   { $allSvcs.Add(@{ Name="NZBDav";   Container="nzbdav";   Port=3000; Path="" }) }

    foreach ($svc in $allSvcs) {
        $running = $false
        try {
            $result = & wsl -d $wslDistro -e bash -c "docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^$($svc.Container)$' && echo running || echo stopped" 2>&1
            $running = ("$result" -match "running")
        } catch {}

        $borderColor = if ($running) { "#238636" } else { "#30363d" }
        $statusColor = if ($running) { "#3fb950" } else { "#8b949e" }
        $statusLabel = if ($running) { "[ON]" } else { "[--]" }

        $card = New-Object Windows.Controls.Border
        $card.Background = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#161b22"))
        $card.BorderBrush = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString($borderColor))
        $card.BorderThickness = "1"; $card.CornerRadius = "6"
        $card.Padding = "12,10"; $card.Margin = "0,0,10,10"; $card.Width = 185

        $sp = New-Object Windows.Controls.StackPanel

        $stTxt = New-Object Windows.Controls.TextBlock
        $stTxt.Text = "$statusLabel $($svc.Name)"
        $stTxt.Foreground = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString($statusColor))
        $stTxt.FontSize = 12; $stTxt.FontWeight = "SemiBold"; $stTxt.TextWrapping = "Wrap"

        $portTxt = New-Object Windows.Controls.TextBlock
        $portTxt.Text = "Port: $($svc.Port)"
        $portTxt.Foreground = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#8b949e"))
        $portTxt.FontSize = 10; $portTxt.Margin = "0,3,0,6"

        $sp.Children.Add($stTxt)   | Out-Null
        $sp.Children.Add($portTxt) | Out-Null

        if ($running) {
            $url = "http://localhost:$($svc.Port)$($svc.Path)"
            $openBtn = New-Object Windows.Controls.Button
            $openBtn.Content = "Open"
            $openBtn.Background = [Windows.Media.SolidColorBrush]([Windows.Media.ColorConverter]::ConvertFromString("#1f6feb"))
            $openBtn.Foreground = [Windows.Media.Brushes]::White
            $openBtn.BorderThickness = "0"; $openBtn.Padding = "10,4"; $openBtn.FontSize = 11; $openBtn.HorizontalAlignment = "Left"
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
# STARTUP
# =============================================================================
Write-Log "UnlimitedPlex Beta Installer started." "INFO"
Write-Log "Add instances in the Instances tab, then go to Configuration and Install." "INFO"

# Auto-add a default Main instance
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