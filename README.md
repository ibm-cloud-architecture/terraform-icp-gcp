# Terraform for IBM Cloud Private on Google Cloud Platform

This Terraform configurations uses the [Google Cloud provider](https://www.terraform.io/docs/providers/google/index.html) to provision virtual machines using Google Compute Engine and deploys [IBM Cloud Private](https://www.ibm.com/cloud-computing/products/ibm-cloud-private/) on them.  This Terraform template automates best practices learned from installing ICP at numerous client sites in production and applying them to cloud-native resources on Google Cloud Platform.

This template (on the [`master` branch](https://github.com/ibm-cloud-architecture/terraform-icp-gcp/tree/master)) provisions a highly-available cluster with ICP 3.1.0 Enterprise Edition.

* [Infrastructure Architecture](#infrastructure-architecture)
* [Terraform Automation](#terraform-automation)
* [Installation Procedure](#installation-procedure)
* [Community Edition](#installation-procedure-community-edition)
* [Cluster access](#cluster-access)
* [GCE Cloud Provider](#gce-cloud-provider)

## Infrastructure Architecture

The following diagram outlines the infrastructure architecture.

![ICP on GCE architecture](static/icp_on_gce.png)

- A global VPC and regional subnet is created.  
- The ICP components are deployed across three availability zones in the region.  - Cloud Load Balancers are set up for inbound traffic to applications and control plane.  
- (Not pictured) Cloud NAT is set up for outbound Internet connections.
- (Not pictured) Firewall Rules are set up between cluster nodes
- (Not pictured) Google Filestore is used for image registry persistence

## Terraform Automation

### Prerequisites

1. To use Terraform automation, download the Terraform binaries [here](https://www.terraform.io/).

   On MacOS, you can acquire it using [homebrew](brew.sh) using this command:

   ```bash
   brew install terraform
   ```

1. Create regional Google Filestore bucket in the same region that the ICP cluster will be created and upload the ICP binaries.  Make note of the bucket name.  You can use the `gsutil` command that comes with the [Google Cloud SDK](https://cloud.google.com/sdk/) to do upload the binaries.  

  For ICP 3.1.0-EE, you will need to copy the following:
  - the ICP binary package tarball (`ibm-cloud-private-x86_64-3.1.0.tar.gz`)
  - ICP Docker package (`icp-docker-18.03.1_x86_64`)

  For example, if my bucket is named `my-icp-binaries`:

  ```bash
  gsutil cp ./ibm-cloud-private-x86_64-3.1.0.tar.gz gs://my-icp-binaries
  ```

1. Create a file, `terraform.tfvars` containing the values for the following:

|name | required                        | value        |
|----------------|------------|--------------|
| `region`   | yes           | Region that the ICP cluster will be created in.  By default, uses `us-central1`.  Note that for an HA installation, the selected region should have at least 3 availability zones. |
| `zones`          | yes           | Availability Zones that the ICP will be created in, e.g. `[ "a", "b", "c"]` to install in three availability zones.  By default, uses `["a", "b", "c"]`.  Note to select the region that has at least 3 availability zones for high availability, and that `us-east1` should use `["b", "c", "d"]`.  |
| `ssh_user`     | yes          | Username to ssh into the instances as, will be created     |
| `ssh_key`     | yes          | SSH public key to add to the compute instances, will be added     |
| `image` | no | Base image to use for all compute instances.  This is a map containing a `project` and `family` that corresponds to an OS image.  By default, we use `project = "ubuntu-os-cloud"` and `family = "ubuntu-1604-lts"`.  We have also tested with `project = "rhel-cloud"` and `family = "rhel-7"` for the latest RHEL 7.x image. |
| `docker_package_location` | no         | Google Cloud Storage URL of the ICP docker package for RHEL (e.g. `gs://<bucket>/<filename>`). If this is blank and you are using Ubuntu base images, we will use `docker-ce` from the [Docker apt repository](https://docs.docker.com/install/linux/docker-ce/ubuntu/).  If Docker is already installed in the base image, this step will be skipped. |
| `image_location` | yes         | Google Cloud Storage URL of the ICP binary package (e.g. `s3://<bucket>/ibm-cloud-private-x86_64-3.1.0.tar.gz`). The automation will download the binaries from Google Cloud Storage and perform a `docker load` on the boot node instance. |
| `icp_inception_image` | no | Name of the bootstrap installation image.  By default it uses `ibmcom/icp-inception:3.1.0-ee` to indicate 3.1.0 EE, but this will vary in each release. |

See [Terraform documentation](https://www.terraform.io/intro/getting-started/variables.html) for the format of this file.

1. If using a user-provided TLS certificate containing a custom DNS name, copy `icp-router.crt` and `icp-router.key` to the `cfc-certs` directory.  See [documentation](https://www.ibm.com/support/knowledgecenter/en/SSBS6K_3.1.0/installing/create_ca_cert.html) for more details.  The certificate should contain the `cluster_cname` as a common name, and the DNS entry corresponding should be an A record pointing at the created load balancer IP address of the master console.

1. Provide Google credentials following the instructions [here](https://www.terraform.io/docs/providers/google/getting_started.html#adding-credentials).  The keyfile will be saved as a JSON that you can add to the environment before Terraform execution:

   ```bash
   export GOOGLE_CREDENTIALS=/path/to/google/credentials.json
   ```

1. Initialize Terraform using this command.  This will download all dependent modules, including the [ICP installation module](https://github.com/ibm-cloud-architecture/terraform-module-icp-deploy).

   ```bash
   terraform init
   ```

## Installation Procedure

1. Examine the Terraform plan.  This will print out all the resources that would be created. 

   ```bash
   terraform plan
   ```

1. Run this command to execute the commands and create the resources.

   ```bash
   terraform apply
   ```


## Community Edition

## Cluster access

On success, the Terraform will output the URL to connect to for cluster access, and the generated username and password to use to log in.

## GCE Cloud Provider
