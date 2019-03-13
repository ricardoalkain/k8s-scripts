param(
    [string] $s,    # Solution file name. If omited the script needs to run in the solution folder.
    [string] $p,    # Project file path. If omited the script prompts the user for it.
    [string] $h,    # Helm project name. If omited the script prompts the user for it.
    [switch] $f,    # Force the overwriting all files without confirmation
    [switch] $debug # Show the content of all modified/created files.
)

set-executionpolicy remotesigned -s cu
$ErrorActionPreference = "Stop"

Clear-Host

# Constants
$jenkins_version = "{JENKINS_VERSION}"
$docker_registry = "docker-registry.intern-belgianrail.be:9999"
$docker_feed = "proget_test"
$proget_feed = $docker_feed
$secret_db_user = 'DB_USER'
$secret_db_pwd = 'DB_PASSWORD'
$env_db_user = "K8S_$secret_db_user"
$env_db_pwd = "K8S_$secret_db_pwd"
$tag_db_user = "{$secret_db_user}"
$tag_db_pwd = "{$secret_db_pwd}"
$tag_connstr = "User Id=$tag_db_user;Password=$tag_db_pwd"

$probe_live = '/swagger'
$probe_ready = $probe_live

$unknown = '"??????"'


#
# Validations
#
if ($debug) { Write-Host 'Running in DEBUG MODE!' -ForegroundColor DarkYellow }
Write-Host ''

# Check if Helm is instaled
if ((Get-Command "helm.exe" -ErrorAction SilentlyContinue) -eq $null)
{
   Write-Host 'Helm is not properly installed on this machine: "helm.exe" not found in the system path.' -ForegroundColor Red
   exit
}

if ('' -eq $s)
{
    $solution = [System.IO.FileInfo] (@(Get-ChildItem *.sln)[0])

    if ($null -eq $solution)
    {
        Write-Host 'Solution file not found. Run this script in a valid solution folder or use -s to specify a solution file.' -ForegroundColor Red
        exit
    }
}
else
{
    $solution = [System.IO.FileInfo] (Get-ChildItem $s)

    if ($null -eq $solution)
    {
        Write-Host "Solution file '$solution' not found." -ForegroundColor Red
        exit
    }
}

$solution_dir = $solution.Directory.FullName
cd $solution_dir






#
# Get script data
#
Write-Host 'WELCOME!
The solution ' -NoNewline
Write-Host $solution.BaseName -ForegroundColor Cyan -NoNewline
Write-Host ' is about to be configured to deploy and run in the Kubernetes cluster.'
Write-Host ('During the process all created/modified files will be printed. Please check the files before deploying. ' +
'Moreover, as some settings depend on each application, a TODO list will be presented at the end. ' +
'Follow these steps to complete the configuration.')
Write-Host ''

if ('' -eq $h)
{
    $helm_project = Read-Host "Please enter Helm project name. It's recommended to use the form <project>-<application> (e.g. rivdec-associations). This information will also be used to create the Docker image and configure Jenkins file`r`n"
}
else
{
    $helm_project = $h.ToLower()
    Write-Host "Helm project name: " -NoNewline
    Write-Host $helm_project -ForegroundColor Cyan
}
Write-Host ''

if ('' -eq $p)
{
    # Select the entrypoint application
    Write-Host "Available projects:"
    $files_found = @(gci *.csproj -Recurse)

    if ($files_found.Length -eq 0)
    {
        Write-Host "Folder $solution_dir does not have .csproj fies." -ForegroundColor Red
        exit
    }

    $i = 1
    foreach($proj in $files_found)
    {
        Write-Host '  ' $i ': ' -NoNewline -ForegroundColor Cyan
        Write-Host $proj.BaseName
        $i = $i + 1
    }
    echo ''
    $i = Read-Host "Please choose the APPLICATION project"
    $main_proj = [System.IO.FileInfo]$files_found[$i - 1]

}
else
{
    $main_proj = [System.IO.FileInfo] (Get-ChildItem $p)
    Write-Host 'Project to be configured: ' -NoNewline
    Write-Host $($main_proj.Name) -ForegroundColor Cyan
}

if ($main_proj -eq $null)
{
    Write-Host 'Invalid option!' -ForegroundColor Red
    Exit
}


# Check main project .NET Core version
$dotnet_version = '@sha256:5f964756fae50873c496915ad952b0f15df8ef985e4ac031d00b7ac0786162d0' #default
$publish_folder = '2.0'
$content = $(Get-Content $main_proj.FullName -Raw)
if ($content -match "<TargetFramework>netcoreapp(.*?)<")
{
    if ($Matches[1] -ne '2.0')
    {
        $dotnet_version = ":$($Matches[1])-aspnetcore-runtime"
        $publish_folder = $Matches[1]
    }
}
else
{
    Write-Error "$($main_proj.BaseName) does not seem to be a valid .NET Core project: expected <TargetFramework>netcoreappXXX</TargetFramework>."
    Exit;
}

$docker_repo, $docker_img = $helm_project.Split('-')
$docker_img_full = $docker_registry + '/' + $docker_feed + '/' + $docker_repo + '/' + $docker_img

Write-Host '.NET Core version: ' -NoNewline
Write-Host $publish_folder -ForegroundColor Cyan



#
# HELM
#
echo ''
Write-Host 'PREPARING HELM  -----------------------------------------------------------------------' -ForegroundColor Cyan

# Create project
if (Test-Path "$solution_dir\helm")
{
    Write-Host "  There's already a Helm project with this name in the Solution. If you continue all files will be ERASED and recreated." -ForegroundColor Yellow
    if ($f)
    {
        $overwrite = "y"
    }
    else
    {
        $overwrite = Read-Host -Prompt "  Continue? [y/n]"
    }
    Write-Host ''
    if ( $overwrite -match "[yY]" )
    {
        Write-Host '  Removing old Helm project... ' -NoNewline
        Remove-Item -path .\helm -Recurse > $null
        Write-Host 'Ok!' -ForegroundColor DarkGreen
        Write-Host ''
    }
    else
    {
        Write-Host 'Operation cancelled. Have a nice day :)'
        Exit
    }
}

mkdir helm > $null
cd .\helm > $null

Write-Host "  - Creating Helm project... " -NoNewline

helm create $helm_project > $null
cd $helm_project > $null
mkdir external > $null

$helm_dir = $solution_dir + '\helm\' + $helm_project
Write-Host $helm_dir -ForegroundColor DarkGreen
cd $solution_dir > $null

# Configure Helm files
Write-Host '  - Configuring Helm files...'
$file = "$helm_dir\Chart.yaml"
$content = ((Get-Content $file) -replace '^version:.*',"version: $jenkins_version" -join "`r`n")

$content | Set-Content $file -Encoding Default

Write-Host "    : $file" -ForegroundColor DarkGreen
if ($debug) { Write-Host $content -ForegroundColor DarkGray }

# FILE: Values
$file = "$helm_dir\values.yaml"

$content = (Get-Content $file -Raw) `
    -replace '  tag: stable',"  tag: $jenkins_version" `
    -replace '  repository:.*',"  repository: $docker_img_full" `
    -replace '  type: ClusterIP','  type: LoadBalancer' `
    -replace 'replicaCount: 1','replicaCount: 2' `

$content | Set-Content $file  -Encoding Default
Write-Host "    : $file" -ForegroundColor DarkGreen

if ($debug) { Write-Host $content -ForegroundColor DarkGray }

# FILE: Deployment
$file = "$helm_dir\templates\deployment.yaml"
$content = $(Get-Content $file -Raw)

if ($content -match '([\s\S]*?)((.*)resources:[\s\S]*)')
{
    $yaml_deploy_pre_res = $Matches[1].TrimEnd()
    $yaml_deploy_pos_res = $Matches[2].TrimEnd()
}
else
{
    Write-Host "$file is not in the expected format. Maybe the version of Helm is not compatible whit this script." -ForegroundColor Red
    Exit
}

$content = "$yaml_deploy_pre_res
          volumeMounts:
          - name: {{ template `"$helm_project.name`" . }}-config-general-volume
            mountPath: /app/appsettings.json
            subPath: appsettings.json
          - name: {{ template `"$helm_project.name`" . }}-config-environment-volume
            mountPath: /app/appsettings.{{ .Values.data.environment }}.json
            subPath: appsettings.{{ .Values.data.environment }}.json
          - name: {{ template `"$helm_project.name`" . }}-config-nlog-volume
            mountPath: /app/nlog.config
            subPath: nlog.config
          env:
          - name: ASPNETCORE_ENVIRONMENT
            value: {{ .Values.data.environment | quote }}
          - name: $env_db_user
            valueFrom:
              secretKeyRef:
                name: {{ template `"$helm_project.fullname`" . }}-secret
                key: $secret_db_user
          - name: $env_db_pwd
            valueFrom:
              secretKeyRef:
                name: {{ template `"$helm_project.fullname`" . }}-secret
                key: $secret_db_pwd
$yaml_deploy_pos_res
      volumes:
        - name: {{ template `"$helm_project.name`" . }}-config-general-volume
          configMap:
            name: {{ template `"$helm_project.fullname`" . }}-configmap
            items:
            - key: appsettings.json
              path: appsettings.json
        - name: {{ template `"$helm_project.name`" . }}-config-environment-volume
          configMap:
            name: {{ template `"$helm_project.fullname`" . }}-configmap
            items:
            - key: appsettings.{{ .Values.data.environment }}.json
              path: appsettings.{{ .Values.data.environment }}.json
        - name: {{ template `"$helm_project.name`" . }}-config-nlog-volume
          configMap:
            name: {{ template `"$helm_project.fullname`" . }}-configmap
            items:
            - key: nlog.config
              path: nlog.config"

# Set probes
$content = $content `
    -replace '(livenessProbe:\s*?httpGet:\s*?path:\s*?).*',$('$1';$probe_live) `
    -replace '(readinessProbe:\s*?httpGet:\s*?path:\s*?).*',$('$1';$probe_ready)

$content | Set-Content $file  -Encoding Default

Write-Host "    : $file" -ForegroundColor DarkGreen
if ($debug) { Write-Host $content -ForegroundColor DarkGray }


# FILE: Config Map
$file = "$helm_dir\templates\configmap.yaml"

$content = "apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ template `"$helm_project.fullname`" . }}-configmap
  labels:
    heritage: {{ .Release.Service }}
    release: {{ .Release.Name }}
    chart: {{ .Chart.Name }}-{{ .Chart.Version }}
    app: {{ template `"$helm_project.name`" . }}
data:
  {{ (.Files.Glob `"external/appsettings.json`").AsConfig | indent 2 }}
  {{ (.Files.Glob .Values.data.file).AsConfig | indent 2 }}
  {{ (.Files.Glob `"external/nlog.config`").AsConfig | indent 2 }}"

$content | Set-Content $file  -Encoding Default

Write-Host "    : $file" -ForegroundColor DarkGreen
if ($debug) { Write-Host $content -ForegroundColor DarkGray }





#
# Setting files
#
echo ''
Write-Host 'PREPARING APPLICATION SETTINGS  -------------------------------------------------------' -ForegroundColor Cyan

Write-Host '  - Creating application settings copies for Kubernetes:'

$files_found = @(gci "$($main_proj.Directory.FullName)\appsettings.*.json")

$overwrite = 1

if (-not $f)
{
    if ($files_found -match "kubernetes")
    {
        Write-Host "      There are already App Settings files prepared to Kubernetes in this project. " -ForegroundColor Yellow
        $overwrite = (Read-Host -Prompt "      Do you want to overwrite them? [y/n]") -match "[yY]"
    }
}

$replace_appsettings = 0
foreach($file in $files_found)
{
    if ($file.BaseName.Contains('kubernetes'))
    {
        $file_new = $file.FullName
        $replace_appsettings = $overwrite
    }
    else
    {
        $file_new = $file.FullName.Replace(".json", ".kubernetes.json")
        Copy-Item $file.FullName -Destination $file_new > $null
        $replace_appsettings = 1
    }

    if ($replace_appsettings)
    {
        # Insert User/Password into connection strings
        $content = ((Get-Content $file_new -Raw) `
            -replace 'User Id=[^";]*',"User Id=$tag_db_user
        " `
            -replace 'Password=[^";]*',"Password=$tag_db_pwd" `
            -replace 'Integrated Security=true',$tag_connstr)

        $content | Set-Content $file_new -Encoding Default
        Write-Host "    : $file_new" -ForegroundColor DarkGreen
        if ($debug) { Write-Host $content -ForegroundColor DarkGray }

        # Creates additional values.yaml files
        $content = $(Get-Content $file_new -Raw)
    }

    if ($file.Name -match '\.(.*)\.json')
    {
        $file_env = $Matches[1]

        $yaml = "$helm_dir\values.$($file_env).yaml"

        $content = "data:
  db:
    user: $unknown
    password: $unknown
  file: `"external/$($file.Name)`"
  environment: `"$file_env`""

        $content | Out-File $yaml  -Encoding Default

        Write-Host "    : $yaml" -ForegroundColor DarkGreen
        if ($debug) { Write-Host $content -ForegroundColor DarkGray }
    }
}






#
# SECRETS
#
echo ''
Write-Host 'KUBERNETES SECRETS  -------------------------------------------------------------------' -ForegroundColor Cyan

Write-Host '  - Creating secret file... ' -NoNewline
$yaml = "$helm_dir\templates\secrets.yaml"

$content = "apiVersion: v1
kind: Secret
metadata:
  name: {{ template `"$helm_project.fullname`" . }}-secret
  labels:
    app: {{ template `"$helm_project.fullname`" . }}
    chart: `"{{ .Chart.Name }}-{{ .Chart.Version }}`"
    release: `"{{ .Release.Name }}`"
    heritage: `"{{ .Release.Service }}`"
type: Opaque
data:
  `"$secret_db_user`": |-
    {{ .Values.data.db.user | b64enc }}
  `"$secret_db_pwd`": |-
    {{ .Values.data.db.password | b64enc }}"

$content | Out-File $yaml  -Encoding Default

Write-Host $yaml -ForegroundColor DarkGreen
if ($debug) { Write-Host $content -ForegroundColor DarkGray }




#
# JENKINS
#
echo ''
Write-Host 'JENKINS CONFIG  -----------------------------------------------------------------------' -ForegroundColor Cyan

$file = $solution_dir + '\Jenkinsfile'
Write-Host '  - Modifying Jenkins file... ' -NoNewline

$content = (Get-Content $file -Raw)

if ($content.Contains('import be.belgianrail.jenkins.jobs.DockerPublishOptions'))
{
    Write-Host 'already updated!' -ForegroundColor DarkGray
}
else
{
    $content = ($content `
        -replace '(package.*\s+)(import)', "`$1import be.belgianrail.jenkins.jobs.DockerPublishOptions`r`n`$2") `
        -replace 'options.publishToNuget = true', 'options.publishToNuget = false' `
        -replace '(new MicroservicesJob[\s\S]*)', "def dockerPublishOptions = new DockerPublishOptions()
    dockerPublishOptions.dockerFeed = '$proget_feed'
    dockerPublishOptions.dockerRepository = '$docker_repo'
    dockerPublishOptions.dockerImageName = '$docker_img'
    dockerPublishOptions.dockerFileLocation = '$($main_proj.Directory.Name)'

    options.dockerPublishOptions = dockerPublishOptions
    options.helmChartName = '$helm_project'

    `$1"

    $content | Out-File $file  -Encoding Default

    Write-Host $file -ForegroundColor DarkGreen
    if ($debug) { Write-Host $content -ForegroundColor DarkGray }
}





#
# NLog
#
echo ''
Write-Host 'PREPARING LOG CONFIG FOR CONTAINER ----------------------------------------------------' -ForegroundColor Cyan
cd $main_proj.Directory.FullName > $null

Write-Host "  - Renaming Nlog.config to lower case (avoid problems on Linux containers)... " -NoNewline
Rename-Item 'NLog.config' 'nlog.config' > $null
Write-Host "OK" -ForegroundColor DarkGreen

Write-Host '  - Creating NLog config for Docker... ' -NoNewline
$file_new = ($main_proj.Directory.FullName + "\nlog.docker.config")
$content = '<nlog xmlns="http://www.nlog-project.org/schemas/NLog.xsd"
      xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
      autoReload="true"
      throwExceptions="false"
      internalLogLevel="info"
      internalLogFile="internal-nlog.txt">
  <targets>

    <target xsi:type="ColoredConsole" name="structuredLog">
      <layout xsi:type="JsonLayout" includeAllProperties="true">
        <attribute name="time" layout="${longdate:universalTime:true}" />
        <attribute name="level" layout="${level:upperCase=true}" />
        <attribute name="logger" layout="${logger}" />
        <attribute name="message" layout="${message}" />
        <attribute name="exception" layout="${exception:format=tostring}" />
        <attribute name="aspRequestMethod" layout="${aspnet-request-method}" />
        <attribute name="aspRequestUrl" layout="${aspnet-request-url:IncludePort=true:IncludeQueryString=true}" />
        <attribute name="aspMcvAction" layout="${aspnet-mvc-action}" />
        <attribute name="machineName" layout="${machinename}" />
        <attribute name="threadid" layout="${threadid}" />
        <attribute name="assemblyVersion" layout="${assembly-version}" />
        <attribute name="environment" layout="${environment:ASPNETCORE_ENVIRONMENT}" />
      </layout>
    </target>

  </targets>

  <rules>
    <!--Skip Microsoft logs and so log only own logs-->
    <logger name="Microsoft.*" minlevel="Warn" writeTo="structuredLog" />
    <logger name="Microsoft.EntityFrameworkCore.Database.*" minlevel="Info" writeTo="structuredLog" />
    <logger name="BelgianRail.RivDec.*" minlevel="Trace" writeTo="structuredLog" final="true" />
  </rules>
</nlog>'

$content | Out-File $file_new  -Encoding Default

Write-Host $file_new -ForegroundColor DarkGreen
if ($debug) { Write-Host $content -ForegroundColor DarkGray }






#
# DOCKER
#
echo ''
Write-Host 'DOCKER FILES  -------------------------------------------------------------------------' -ForegroundColor Cyan

# Docker file
$file = $main_proj.Directory.FullName + '\dockerfile'
Write-Host '  - Writing Docker file... ' -NoNewline

$content = "FROM microsoft/aspnetcore$dotnet_version
WORKDIR /app
EXPOSE 80
COPY ./bin/Release/netcoreapp$publish_folder/publish .
ENTRYPOINT [`"dotnet`", `"$($main_proj.BaseName).dll`"]"

$content | Out-File $file -Encoding Default

Write-Host $file -ForegroundColor DarkGreen
if ($debug) { Write-Host $content -ForegroundColor DarkGray }

# Ignore file
$file = $main_proj.Directory.FullName + '\.dockerignore'
Write-Host '  - Writing Ignore file... ' -NoNewline

$content = "**/appsettings.json
**/appsettings.*.json
**/hosting.json
**/nlog*.config"

$content | Out-File $file -Encoding Default

Write-Host $file -ForegroundColor DarkGreen
if ($debug) { Write-Host $content -ForegroundColor DarkGray }






#
# GIT
#
echo ''
Write-Host 'GIT FILES  ----------------------------------------------------------------------------' -ForegroundColor Cyan

# Docker file
$file = $solution_dir + '\.gitignore'
Write-Host '  - Writing Git Ignore file... ' -NoNewline

$content = (Get-Content $file -Raw)
if (-not ($content -match 'helm/\*\*'))
{
    Add-Content $file "
helm/**/*.tgz
helm/**/external/*" -Encoding Default
}
Write-Host 'OK' -ForegroundColor DarkGreen




#
# Solution and project
#

echo ''
Write-Host 'UPDATING SOLUTION  --------------------------------------------------------------------' -ForegroundColor Cyan

# Insert Helm folder into Solution as a WebSite
# We dont need to check if folder already included. VS handles that automatically
$file = $solution.FullName
Write-Host '  - Including Helm folder into solution... ' -NoNewline

$content = $(Get-Content $solution.FullName -Raw)

if ($content.Contains('helm\'))
{
    Write-Host 'already updated!' -ForegroundColor DarkGray
}
else
{
    if ($content -match '([\s\S]*?)(Project\("[\s\S]*)')
    {
        $content = $Matches[1] +
        'Project("{E24C65DC-7377-472B-9ABA-BC803B73C61A}") = "helm", "helm\", "{2BE35EF5-677B-46E4-BB59-59762DAEF6E8}' +
        "`r`nEndProject`r`n" +
        $Matches[2]
    }

    if ($content -match '([\s\S]*?GlobalSection\(ProjectConfigurationPlatforms\)\s=\spostSolution.*)([\s\S]*)')
    {
        $content = $Matches[1] +
        "`t`t{2BE35EF5-677B-46E4-BB59-59762DAEF6E8}.Debug|Any CPU.ActiveCfg = Debug|Any CPU`r`n" +
        "`t`t{2BE35EF5-677B-46E4-BB59-59762DAEF6E8}.Release|Any CPU.ActiveCfg = Debug|Any CPU" +
        $Matches[2]
    }

    $content | Set-Content ($solution.FullName) -Encoding UTF8

    Write-Host $($solution.FullName) -ForegroundColor DarkGreen
    if ($debug) { Write-Host $content -ForegroundColor DarkGray }
}


# "
# <Target Name="PostBuild" AfterTargets="PostBuildEvent">
# <Copy SourceFiles="$(ProjectDir)appsettings.json" DestinationFolder="$(SolutionDir)helm\rivdec-associations\external\" />
# <Copy SourceFiles="$(ProjectDir)appsettings.Development.kubernetes.json" DestinationFiles="$(SolutionDir)helm\rivdec-associations\external\appsettings.Development.json" />
# <Copy SourceFiles="$(ProjectDir)appsettings.Test.kubernetes.json" DestinationFiles="$(SolutionDir)helm\rivdec-associations\external\appsettings.Test.json" />
# <Copy SourceFiles="$(ProjectDir)appsettings.Acceptance.kubernetes.json" DestinationFiles="$(SolutionDir)helm\rivdec-associations\external\appsettings.Acceptance.json" />
# <Copy SourceFiles="$(ProjectDir)appsettings.Production.kubernetes.json" DestinationFiles="$(SolutionDir)helm\rivdec-associations\external\appsettings.Production.json" />
# <Copy SourceFiles="$(ProjectDir)nlog.docker.config" DestinationFiles="$(SolutionDir)helm\rivdec-associations\external\nlog.config" />
# </Target>"






# Manual steps
Write-Host ''
Write-Host ''
Write-Host ''
Write-Host 'TODO: MANUAL SETTINGS -----------------------------------------------------------------' -ForegroundColor Yellow
Write-Host "    . Change descriptions in $helm_dir\Chart.yaml (optional)" -ForegroundColor Yellow
Write-Host "    . Check if 'service.port' value in $helm_dir\values.yaml needs to be changed (default=80)" -ForegroundColor Yellow
Write-Host "    . Set Database user name and password for each 'values.<environment>.yaml' file" -ForegroundColor Yellow
Write-Host "    . Docker image will be created using .NET Core Runtime only. If you need an image with the sdk, then use microsoft/aspnetcore-build or dotnet:2.1-sdk. More info here https://github.com/aspnet/aspnet-docker/tree/master/2.1" -ForegroundColor Yellow
Write-Host "    . Check if the option 'Build' is disabled for the Helm project in Visual Studio (menu Build -> Configuration Manager -> Release)"
if (-not $replace_appsettings)
{
    Write-Host '    . Verify the content of all "appsettings.*.kubernetes.json" files to check if all configurations are correct and updated.'
}



Write-Host ''
Write-Host ''
Write-Host 'OPERATION COMPLETED!' -ForegroundColor Green
Write-Host 'Please, check all TODO items to fully configure this solution for Kubernetes.'
Write-Host 'Have a nice day.'
Write-Host ''
cd $solution_dir

<#

#>