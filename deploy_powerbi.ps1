# Enable error handling
$ErrorActionPreference = 'Stop'

try {
    # Parameters
    $tenantId = $env:TENANT_ID
    $clientId = $env:CLIENT_ID
    $clientSecret = $env:CLIENT_SECRET
    $pipelineId = $env:PIPELINE_ID
    $sourceStageOrder = $env:SOURCE_STAGE_ORDER    # Retrieve from environment variable
    $targetStageOrder = $env:TARGET_STAGE_ORDER    # Retrieve from environment variable

    # Validate parameters
    if (-not $tenantId) { throw "TENANT_ID environment variable is not set." }
    if (-not $clientId) { throw "CLIENT_ID environment variable is not set." }
    if (-not $clientSecret) { throw "CLIENT_SECRET environment variable is not set." }
    if (-not $pipelineId) { throw "PIPELINE_ID environment variable is not set." }
    if (-not $sourceStageOrder) { throw "SOURCE_STAGE_ORDER environment variable is not set." }
    if (-not $targetStageOrder) { throw "TARGET_STAGE_ORDER environment variable is not set." }

    Write-Host "Authenticating with Azure AD..."

    # Authenticate with Azure AD
    $authUrl = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
    $authBody = @{
        client_id     = $clientId
        client_secret = $clientSecret
        scope         = "https://analysis.windows.net/powerbi/api/.default"
        grant_type    = "client_credentials"
    }

    $authResponse = Invoke-RestMethod -Method Post -Uri $authUrl -Body $authBody
    $accessToken = $authResponse.access_token

    Write-Host "Authentication successful."

    # Set Headers
    $headers = @{
        'Authorization' = "Bearer $accessToken"
        'Content-Type'  = "application/json"
    }

    # Convert stage orders to integers
    $sourceStageOrder = [int]$sourceStageOrder
    $targetStageOrder = [int]$targetStageOrder

    # Retrieve Pipeline Details
    Write-Host "Retrieving pipeline details to verify stage orders..."
    $pipelineDetailsUrl = "https://api.powerbi.com/v1.0/myorg/pipelines/$pipelineId"

    $pipelineDetails = Invoke-RestMethod -Method Get -Uri $pipelineDetailsUrl -Headers $headers -ErrorAction Stop

    # Output the entire pipeline details for debugging
    Write-Host "Full Pipeline Details:"
    $pipelineDetails | ConvertTo-Json -Depth 10 | Write-Host

    # Display each stage's order and name
    Write-Host "Pipeline Stages:"
    foreach ($stage in $pipelineDetails.stages) {
        Write-Host "Stage Order: $($stage.order), Stage Name: $($stage.displayName)"
    }

    # List Artifacts in Test Stage
    Write-Host "Listing artifacts in Test stage (Order: $sourceStageOrder)..."
    $listArtifactsUrl = "https://api.powerbi.com/v1.0/myorg/pipelines/$pipelineId/stages/$sourceStageOrder/artifacts"

    $artifacts = Invoke-RestMethod -Method Get -Uri $listArtifactsUrl -Headers $headers -ErrorAction Stop

    if ($artifacts.value.Count -eq 0) {
        throw "No artifacts found in the Test stage (Order: $sourceStageOrder). Ensure that artifacts are assigned to the Test stage."
    }

    Write-Host "Artifacts in Test Stage:"
    foreach ($artifact in $artifacts.value) {
        Write-Host "Artifact Name: $($artifact.name), Type: $($artifact.type)"
    }

    # Build the request body in the correct order without options
    $deployBody = @{
        sourceStageOrder = $sourceStageOrder
        targetStageOrder = $targetStageOrder
    } | ConvertTo-Json -Depth 5

    # Output the request body for debugging
    Write-Host "Deployment request body:"
    Write-Host $deployBody

    Write-Host "Triggering deployment from stage $sourceStageOrder to stage $targetStageOrder..."

    # Set the deployment URL
    $deployUrl = "https://api.powerbi.com/v1.0/myorg/pipelines/$pipelineId/deploy"

    # Invoke the REST method with enhanced error handling
    $response = Invoke-RestMethod -Method Post -Uri $deployUrl -Headers $headers -Body $deployBody -ErrorAction Stop

    Write-Host "Deployment triggered successfully."

}
catch {
    Write-Error "An error occurred: $($_.Exception.Message)"
    if ($_.Exception.Response -ne $null) {
        $responseStream = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($responseStream)
        $responseBody = $reader.ReadToEnd()
        Write-Error "API Response: $responseBody"
    }
    exit 1
}