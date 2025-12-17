# Build and push GitHub Actions runner image to GHCR
# Usage: .\build-and-push.ps1 [github-username-or-org] [image-tag]

param(
    [string]$GitHubOwner = "",
    [string]$ImageTag = "latest"
)

# Get GitHub owner if not provided
if ([string]::IsNullOrEmpty($GitHubOwner)) {
    $GitHubOwner = Read-Host "Enter your GitHub username or organization name"
}

if ([string]::IsNullOrEmpty($GitHubOwner)) {
    Write-Error "GitHub owner is required"
    exit 1
}

# GHCR image name (must match docker-compose.yml)
$ImageName = "ghcr.io/$GitHubOwner/actions-runner-flutter"
$FullImageTag = "${ImageName}:${ImageTag}"

Write-Host ""
Write-Host "Building and pushing image to GHCR"
Write-Host "Image: $FullImageTag"
Write-Host ""

# Check if logged into GHCR
Write-Host "Checking Docker login status..."
$loginCheck = docker info 2>&1 | Select-String -Pattern "ghcr.io"
if (-not $loginCheck) {
    Write-Host ""
    Write-Host "You need to login to GHCR first."
    Write-Host "Create a Personal Access Token (PAT) with 'write:packages' permission at:"
    Write-Host "https://github.com/settings/tokens"
    Write-Host ""
    $token = Read-Host "Enter your GitHub PAT (or press Enter to skip login check)" -AsSecureString
    if ($token) {
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($token)
        $plainToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        Write-Host "Logging into GHCR..."
        echo $plainToken | docker login ghcr.io -u $GitHubOwner --password-stdin
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to login to GHCR"
            exit 1
        }
    }
}

# Build the image (--no-cache ensures Flutter and other tools get latest versions)
Write-Host ""
Write-Host "Building image: $FullImageTag"
Write-Host "This may take several minutes (using --no-cache to get latest Flutter)..."
docker build --no-cache -f Dockerfile.runner -t $FullImageTag .

if ($LASTEXITCODE -ne 0) {
    Write-Error "Build failed"
    exit 1
}

Write-Host ""
Write-Host "Build successful!"
Write-Host ""

# Ask if user wants to push
$push = Read-Host "Push image to GHCR? (Y/n)"
if ($push -eq "" -or $push -eq "Y" -or $push -eq "y") {
    Write-Host ""
    Write-Host "Pushing image to GHCR..."
    docker push $FullImageTag
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Push failed. Make sure you're logged in and have write permissions."
        Write-Host ""
        Write-Host "To login manually, run:"
        Write-Host "  echo YOUR_PAT | docker login ghcr.io -u $GitHubOwner --password-stdin"
        exit 1
    }
    
    Write-Host ""
    Write-Host "Successfully pushed: $FullImageTag"
    Write-Host ""
    Write-Host "To use this image, update your docker-compose.yml:"
    Write-Host "  image: $FullImageTag"
    Write-Host ""
    Write-Host "Or pull it later with:"
    Write-Host "  docker pull $FullImageTag"
} else {
    Write-Host ""
    Write-Host "Image built but not pushed: $FullImageTag"
    Write-Host "Push manually with: docker push $FullImageTag"
}




