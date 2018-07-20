# SUSE's openQA tests
#
# Copyright © 2018 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

# Summary: Use IPA framework to test public cloud SUSE images
#
# Maintainer: Clemens Famulla-Conrad <cfamullaconrad@suse.de>

use base "consoletest";
use strict;
use testapi;
use utils;
use File::Basename;
use serial_terminal 'select_virtio_console';


sub find_secgroup {
    my ($name) = @_;

    my $out = script_output("aws ec2 describe-security-groups --group-names '$name'", 30, proceed_on_failure => 1);
    if ($out =~ /"GroupId":\s+"([^"]+)"/) {
        return $1;
    }
    return;
}

sub save_logs {
    my $output = script_output("find ipa_results -type f");
    for my $file (split(/\n/, $output)) {
        if ($file =~ m'ipa_results/ec2/ami-[0-9a-z]+/i-[0-9a-z]+/[0-9]{14}\.(log|results)') {
            upload_logs($file, failok => 1);
        }
    }
}

sub run {

    select_virtio_console();

    die "Public cloud provider isn't supported" unless check_var('PUBLIC_CLOUD_PROVIDER', "EC2");

    zypper_call('ar ' . get_required_var('PUBLIC_CLOUD_TOOLS_REPO'));
    zypper_call('--gpg-auto-import-keys in python3-ipa python3-ipa-tests');

    # WAR install awscli from pip instead of using the package bcs#1095041
    zypper_call('in gcc python3-pip');
    if (check_var('DISTRI', 'opensuse')) {
        zypper_call('in python3-devel');
        assert_script_run("pip3 install pycrypto");
    }
    assert_script_run("pip3 install awscli");
    assert_script_run("pip3 install keyring");

    assert_script_run("export AWS_ACCESS_KEY_ID=" . get_required_var('PUBLIC_CLOUD_KEY_ID'));
    assert_script_run("export AWS_SECRET_ACCESS_KEY=" . get_required_var('PUBLIC_CLOUD_KEY_SECRET'));
    assert_script_run("export AWS_DEFAULT_REGION='eu-central-1'");

    # Create SSH key
    assert_script_run("aws ec2 delete-key-pair --key-name QA_SSH_KEY");
    assert_script_run("aws ec2 create-key-pair --key-name QA_SSH_KEY --query 'KeyMaterial' --output text > QA_SSH_KEY.pem");

    # Create/find security group
    my $secgroup_id = find_secgroup("qa_secgroup");
    if (!defined($secgroup_id)) {
        assert_script_run("aws ec2 create-security-group --group-name qa_secgroup --description 'SSH_OPEN'");
        assert_script_run("aws ec2 authorize-security-group-ingress --group-name qa_secgroup --protocol tcp --port 22 --cidr 0.0.0.0/0");
        assert_script_run("aws ec2 authorize-security-group-ingress --group-name qa_secgroup --protocol icmp --cidr 0.0.0.0/0 --port 0 ");
        $secgroup_id = find_secgroup("qa_secgroup");
        die "Failed on creating security group " unless $secgroup_id;
    }

    my $ami_id = get_required_var("PUBLIC_CLOUD_IMAGE_ID");

    #Prestart instance, cause IPA might use the wrong security group
    my ($instance_id)
      = script_output("aws ec2 run-instances --image-id $ami_id --instance-type t2.large --key-name QA_SSH_KEY --security-group-ids qa_secgroup")
      =~ /"InstanceId":\s*"([^"]+)"/;

    # Create some folders, ipa will need them
    assert_script_run("mkdir -p ~/ipa/tests/");
    assert_script_run("mkdir -p .config/ipa");
    assert_script_run("touch .config/ipa/config");
    assert_script_run("ipa list");

    assert_script_run(
        "ipa test ec2 "
          . "--access-key-id '"
          . get_required_var('PUBLIC_CLOUD_KEY_ID') . "' "
          . "--secret-access-key '"
          . get_required_var('PUBLIC_CLOUD_KEY_SECRET') . "' "
          . "-D 'IPA test $ami_id' "
          . "--distro sles "
          . "-R '$instance_id' "
          . "--region 'eu-central-1' "
          . "-u ec2-user "
          . "--ssh-private-key QA_SSH_KEY.pem "
          . "--ssh-key-name QA_SSH_KEY "
          . "--results-dir ipa_results "
          . "test_sles "
          . "test_sles_ec2 "
          . "test_sles_on_demand ",
        timeout => 600
    );

    save_logs;
}

sub post_fail_hook {

    save_logs;

    # Terminate all instances
    my $out = script_output("aws ec2 describe-instances");
    for my $line (split(/\r?\n/, $out)) {
        if ($line =~ /"InstanceId":\s+"([^"]+)"/) {
            script_run("aws ec2 terminate-instances --instance-ids $1");
        }
    }
}

1;

=head1 Discussion

This module use IPA tool to test public cloud SLE images.
Logs are uploaded at the end.

=head1 Configuration

=head2 PUBLIC_CLOUD_IMAGE_ID

The image ID which is used to instanciate a VM and run tests on it.

=head2 PUBLIC_CLOUD_PROVIDER

The type of the CSP (Cloud service provider). Currently only EC2 is allowed.

=head2 PUBLIC_CLOUD_TOOLS_REPO

The URL to the cloud:tools repo. 
(e.g. http://download.opensuse.org/repositories/Cloud:/Tools/openSUSE_Tumbleweed/Cloud:Tools.repo)

=head2 PUBLIC_CLOUD_KEY_ID

The CSP credentials key-id to used to access API.

=head2 PUBLIC_CLOUD_KEY_SECRET

The CSP credentials secret used to access API.

=cut

