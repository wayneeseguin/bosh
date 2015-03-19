# bosh-stemcell

Tools for creating stemcells

## Bringing up stemcell building VM

### Once-off manual steps:

Note: Use US East (Northern Virginia) region when using AWS in following steps. AMI (Amazon Machine Image) to be used for the stemcell building VM is in the US East (Northern Virginia) region.

0. Upload a keypair called "bosh" to AWS that you'll use to connect to the remote vm later
0. Create "bosh-stemcell" security group on AWS to allow SSH access to the stemcell (once per AWS account)
0. Add instructions to set BOSH_AWS_... environment variables
0. Install the vagrant plugins we use:

        vagrant plugin install vagrant-berkshelf
        vagrant plugin install vagrant-omnibus
        vagrant plugin install vagrant-aws --plugin-version 0.5.0

### Bring up the vagrant stemcell building VM

From a fresh copy of the bosh repo:

    export BOSH_AWS_ACCESS_KEY_ID=YOUR-AWS-ACCESS-KEY
    export BOSH_AWS_SECRET_ACCESS_KEY=YOUR-AWS-SECRET-KEY
    cd bosh-stemcell
    vagrant up remote --provider=aws

## Updating source code on stemcell building VM

With existing stemcell building VM run:

    export BOSH_AWS_ACCESS_KEY_ID=YOUR-AWS-ACCESS-KEY
    export BOSH_AWS_SECRET_ACCESS_KEY=YOUR-AWS-SECRET-KEY
    cd bosh-stemcell
    vagrant provision remote

## Configure your local ssh and scp to communicate with the stemcell building VM

Once the stemcell builing machine is up, run:

    vagrant ssh-config remote

Then copy the resulting output into your `~/.ssh/config` file.

Once this has been done, you can ssh into the stemcell building machine with `ssh remote`
and you can copy files to and from it using `scp localfile remote:/path/to/destination`

## Build an OS image

An OS image is a tarball that contains a snapshot of an entire OS filesystem that contains all the libraries and system utilities that the BOSH agent depends on. It does not contain the BOSH agent or the virtualization tools: there is [a separate Rake task](#building-the-stemcell-with-local-os-image) that adds the BOSH agent and a chosen set of virtualization tools to any base OS image, thereby producing a stemcell.

If you have changes that will require new OS image you need to build one. A stemcell with a custom OS image can be built using the stemcell-building VM described above.

    vagrant ssh -c '
      cd /bosh
      bundle exec rake stemcell:build_os_image[ubuntu,trusty,/tmp/ubuntu_base_image.tgz]
    ' remote

The arguments to `stemcell:build_os_image` are:

1. *`operating_system_name`* identifies which type of OS to fetch. Determines which package repository and packaging tool will be used to download and assemble the files. Must match a value recognized by the  [OperatingSystem](lib/bosh/stemcell/operating_system.rb) module. Currently, `ubuntu` `centos` and `rhel` are recognized.
2. *`operating_system_version`* an identifier that the system may use to decide which release of the OS to download. Acceptable values depend on the operating system. For `ubuntu`, use `trusty`. For `centos` and `rhel`, use `7`.
3. *`os_image_path`* the path to write the finished OS image tarball to. If a file exists at this path already, it will be overwritten without warning.

### Special requirements for building a RHEL OS image

There are a few extra steps you need to do before building a RHEL OS image:

1. On your local machine, get a copy of the file `/etc/pki/product/69.pem` from an existing RHEL 7 system and place it at `../stemcell_builder/stages/base_rhel/assets/69.pem`
2. Start up or re-provision the stemcell building machine (run `vagrant up` or `vagrant provision` from this directory)
3. Download the RHEL 7 install DVD image and use `scp` to copy it to the stemcell building machine
4. On the stemcell building machine, mount the RHEL 7 DVD at `/mnt/rhel`:

        # mount rhel-server-7.0-x86_64-dvd.iso /mnt/rhel

5. On the stemcell building machine, put your Red Hat Account username and password into environment variables:

        $ export RHN_USERNAME=my-rh-username@company.com
        $ export RHN_PASSWORD=my-password

6. On the stemcell building machine, run the stemcell building rake task:

        $ cd /bosh
        $ bundle exec rake stemcell:build_os_image[rhel,7,/tmp/rhel_7_base_image.tgz]

See below [Building the stemcell with local OS image](#building-the-stemcell-with-local-os-image) on how to build stemcell with the new OS image.

## Building a stemcell

### Building the stemcell with published OS image

Substitute *\<current_build\>* with the current build number, which can be found by looking at [bosh artifacts](http://bosh_artifacts.cfapps.io).
The final two arguments are the S3 bucket and key for the OS image to use, which can be found by reading the OS\_IMAGES document in this project.

    vagrant ssh -c '
      cd /bosh
      CANDIDATE_BUILD_NUMBER=<current_build> http_proxy=http://localhost:3142/ bundle exec rake stemcell:build[vsphere,esxi,centos,nil,go,bosh-os-images,bosh-centos-6_6-os-image.tgz]
    ' remote


### Building the stemcell with local OS image

    vagrant ssh -c '
      cd /bosh
      bundle exec rake stemcell:build_with_local_os_image[aws,xen,ubuntu,trusty,go,/tmp/ubuntu_base_image.tgz]
    ' remote


Public OS images can be obtained here:

* latest Ubuntu - https://s3.amazonaws.com/bosh-os-images/bosh-ubuntu-trusty-os-image.tgz
* latest Centos - https://s3.amazonaws.com/bosh-os-images/bosh-centos-6_6-os-image.tgz

### Building light stemcell

AWS stemcells can be shipped in light format which includes a reference to a public AMI. This speeds up the process of uploading the stemcell to AWS. To build a light stemcell:

    vagrant ssh -c '
      cd /bosh
      export BOSH_AWS_ACCESS_KEY_ID=YOUR-AWS-ACCESS-KEY
      export BOSH_AWS_SECRET_ACCESS_KEY=YOUR-AWS-SECRET-KEY
      bundle exec rake stemcell:build_light[/tmp/bosh-stemcell.tgz,hvm]
    ' remote

### When things go sideways

If you find yourself debugging any of the above processes, here is what you need to know:

1. Most of the action happens in Bash scripts, which are referred to as _stages_, and can
   be found in `stemcell_builder/stages/<stage_name>/apply.sh`.
2. You should make all changes on your local machine, and sync them over to the AWS stemcell
   building machine using `vagrant provision remote` as explained earlier on this page.
3. While debugging a particular stage that is failing, you can resume the process from that
   stage by adding `resume_from=<stage_name>` to the end of your `bundle exec rake` command.
   When a stage's `apply.sh` fails, you should see a message of the form
   `Can't find stage '<stage>' to resume from. Aborting.` so you know which stage failed and
   where you can resume from after fixing the problem.

   For example:

   ```
   bundle exec rake stemcell:build_os_image[ubuntu,trusty,/tmp/ubuntu_base_image.tgz] resume_from=rsyslog_build
   ```
