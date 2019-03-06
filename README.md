# .NET Core Deployment to Kubernetes

Powershell script to automate configuration of a .NET Core project to be deployed in a Kubernetes cluster using Helm.

## Getting Started

Just download the latest version and run it!
You can run this script in an interactive way, providing all parameters manually, or provide the parameters in the command line and execute with no intervention (i.e. directly from a CI/CD pipeline)

### Prerequisites

- **Powershell 5.0+:** Although Powershell is present in most of Windows machines, this script uses some Powershell 5.0 features, so be sure it is up to date.
- **[Helm 1.6](https://helm.sh/):** Should work with newer versions of Helm too but not tested yet.

### Executing (Interactive Mode)

- Open a Powershell window
- Navigate to the solution folder. Ex: `cd <solution folder>`
- Type the relative or absolute path of the script. Ex: `..\prepare-to-k8s.ps1 -v`
- Follow the instructions

## Deployment

Refer to [Helm] page for details on how to register a Helm Chart and then deploy your application to Kubernetes.

## Built With

* [PowerShell] (https://github.com/PowerShell/PowerShell)
* [Helm 1.6](https://helm.sh/)

## Authors

* **Ricardo A.** - [*Senior Software Engineer*](https://www.linkedin.com/in/ricardo-alkain/)

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details

## Acknowledgments

This script idea has born during a work for Belgian Rails company when we were faced with the need to create and modify Helm charts for dozens of microservices being migrated to their Kubernetes cluster. Another good example of laziness inspiring people XD
