# SUSE's openQA tests
#
# Copyright © 2016-2018 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

# Summary: Windows 10 installation test module
#    modiffied (only win10 drivers) iso from https://fedoraproject.org/wiki/Windows_Virtio_Drivers is needed
#    Works only with CDMODEL=ide-cd and QEMUCPU=host or core2duo (maybe other but not qemu64)
# Maintainer: Jozef Pupava <jpupava@suse.com>

use base "windowsbasetest";
use strict;
use warnings;

use testapi;

sub run {
    if (get_var('UEFI')) {
        assert_screen 'windows-boot';
        send_key 'spc';    # boot from CD or DVD
    }
    # This test works onlywith CDMODEL=ide-cd due to windows missing scsi drivers which are installed via scsi iso
    assert_screen 'windows-setup', 1000;
    send_key 'alt-n';      # next
    save_screenshot;
    send_key 'alt-i';      # install Now
    save_screenshot;
    send_key 'alt-n';      # next
    assert_screen 'windows-activate';
    if (my $key = get_var('_SECRET_WINDOWS_10_PRO_KEY')) {
        type_password $key . "\n";
        assert_screen([qw(windows-wrong-key windows-license-with-key)]);
        die("The provided product key didn't work...") if (match_has_tag('windows-wrong-key'));
    }
    else {
        assert_and_click 'windows-no-prod-key';
        assert_screen 'windows-select-system';
        send_key_until_needlematch('windows-10-pro', 'down');
        send_key 'alt-n';    # select OS (Win 10 Pro)
        assert_screen 'windows-license';
    }
    send_key 'alt-a';                                                           # accept eula
    send_key 'alt-n';                                                           # next
    assert_screen 'windows-installation-type';
    send_key 'alt-c';                                                           # custom
    assert_screen 'windows-disk-partitioning';
    send_key 'alt-l';                                                           # load driver
    assert_screen 'windows-load-driver';
    send_key 'alt-b';                                                           # browse button
    send_key 'c';
    save_screenshot;
    send_key 'c';                                                               # go to second CD drive with drivers
    send_key 'right';                                                           # ok
    sleep 0.5;
    send_key 'ret';
    wait_still_screen stilltime => 3, timeout => 10;
    send_key_until_needlematch 'windows-all-drivers-selected', 'shift-down';    # select all drivers
    send_key 'alt-n';
    assert_screen 'windows-partitions';
    assert_and_click 'windows-next-install';
    assert_screen 'windows-restart', 600;
    send_key 'alt-r';
}

1;
