Write-Host "Monitoring Power Plan (Press Ctrl+C to stop)..." -ForegroundColor Cyan

while ($true) {
    # Clear the screen
    Clear-Host
    
    # Get the active power plan
    $activePlan = powercfg /getactivescheme
    
    # Extract the name using regex
    if ($activePlan -match '\((.*)\)') {
        $planName = $matches[1]
    } else {
        $planName = "Unknown"
    }

    # Display the output
    Write-Host "--- Real-Time Power Monitor ---" -ForegroundColor Yellow
    Write-Host "Current Power Plan: $planName" -ForegroundColor Green
    Write-Host "Last Updated: $(Get-Date -Format 'HH:mm:ss')"
    Write-Host "-------------------------------"
    Write-Host "(Press Ctrl+C to stop)"
    
    # Wait for 1 second before refreshing
    Start-Sleep -Seconds 1
}
