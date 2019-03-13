# .NET Core Deployment to Kubernetes

Powershell script to automate configuration of a .NET Core project to be deployed in a Kubernetes cluster using Helm.

## Getting Started

Just download the latest version and run it!
You can run this script in an interactive way, providing all parameters manually, or provide the parameters in the command line and execute with no intervention (i.e. directly from a CI/CD pipeline)

### Prerequisites

- **PowerShell 5.0+:** Although PowerShell is present in most of Windows machines, this script uses some PowerShell 5.0 features, so be sure it is up to date.
- **Helm 1.6** Should work with newer versions of Helm too but not tested yet.

### Executing (Interactive Mode)

- Open a Powershell window
- Navigate to the solution folder. Ex: `cd <solution folder>`
- Type the relative or absolute path of the script. Ex: `..\prepare-to-k8s.ps1`
- Follow the instructions

### Executing (Command Line)

- Open a PowerShell window
- Navigate to the script folder or type the full path. Ex: `C:\Tools\k8s\scripts\prepare-to-k8s.ps1 {parameters}`

#### Parameters

    | Param   | Description
    | ------- | -----------
    | -s      | Solution file name. If omited the script needs to run in the solution folder.
    | -p      | Project file path. If omited the script prompts the user for it.
    | -h      | Helm project name. If omited the script prompts the user for it.
    | -f      | Force the overwriting all files without confirmation.
    | -debug  | Show the content of all modified/created files.

## Deployment

Refer to [Helm](https://helm.sh/) page for details on how to register a Helm Chart and then deploy your application to Kubernetes.

## Built With

* [PowerShell](https://github.com/PowerShell/PowerShell)
* [Helm 1.6](https://helm.sh/)

## Authors

* [**Ricardo A.**](https://www.linkedin.com/in/ricardo-alkain/) - *Senior Software Engineer*

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details

## Acknowledgments

This script idea has born during a work for Belgian Rails company. We were faced with the need to create and modify Helm charts for dozens of microservices being migrated to our Kubernetes cluster.
Just another good example of laziness inspiring people XD

### TODO

- Make the script more "generic". Still contains lots of conventions that can/should be replaced by parameters.
- Make a Bash version of the script to use it in other OS.