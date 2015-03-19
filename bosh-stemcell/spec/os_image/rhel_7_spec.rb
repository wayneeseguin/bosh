require 'spec_helper'

describe 'RHEL OS image', os_image: true do
  it_behaves_like 'an OS image'

  describe package('apt') do
    it { should_not be_installed }
  end

  describe package('rpm') do
    it { should be_installed }
  end

  context 'installed by base_rhel' do
    %w(
      redhat-release-server
      epel-release
    ).each do |pkg|
      describe package(pkg) do
        it { should be_installed }
      end
    end

    describe file('/etc/sysconfig/network') do
      it { should be_file }
    end

    describe file('/etc/localtime') do
      it { should be_file }
      it { should contain 'UTC' }
    end

    describe file('/etc/locale.conf') do
      it { should be_file }
      it { should contain 'en_US.UTF-8' }
    end
  end

  context 'installed by base_centos_packages' do
    %w(
      bison
      bzip2-devel
      cmake
      curl
      dhclient
      flex
      gdb
      glibc-static
      iptables
      libcap-devel
      libuuid-devel
      libxml2
      libxml2-devel
      libxslt
      libxslt-devel
      lsof
      openssh-server
      openssl-devel
      parted
      psmisc
      quota
      readline-devel
      rpm-build
      rpmdevtools
      rsync
      runit
      strace
      sudo
      sysstat
      systemd
      tcpdump
      traceroute
      unzip
      wget
      zip
    ).each do |pkg|
      describe package(pkg) do
        it { should be_installed }
      end
    end
  end

  context 'installed by base_ssh' do
    subject(:sshd_config) { file('/etc/ssh/sshd_config') }

    it 'disallows CBC ciphers' do
      ciphers = %w(
          aes256-ctr
          aes192-ctr
          aes128-ctr
        ).join(',')
      expect(sshd_config).to contain(/^Ciphers #{ciphers}$/)
    end

    it 'disallows insecure HMACs' do
      macs = %w(
          hmac-sha2-512
          hmac-sha2-256
          hmac-ripemd160
        ).join(',')
      expect(sshd_config).to contain(/^MACs #{macs}$/)
    end
  end

  context 'installed by system_grub' do
    describe package('grub2-tools') do
      it { should be_installed }
    end
  end

  context 'installed by system_kernel' do
    %w(
      kernel
      kernel-headers
    ).each do |pkg|
      describe package(pkg) do
        it { should be_installed }
      end
    end
  end

  context 'readahead-collector should be disabled' do
    describe file('/etc/sysconfig/readahead') do
      it { should be_file }
      it { should contain 'READAHEAD_COLLECT="no"' }
      it { should contain 'READAHEAD_COLLECT_ON_RPM="no"' }
    end
  end

  context 'rsyslog_build' do
    describe file('/etc/rsyslog_build.d/enable-kernel-logging.conf') do
      # Make sure imklog module is not loaded in rsyslog_build
      # to avoid CentOS stemcell pegging CPU on AWS
      it { should_not be_file } # (do not add $ in front of ModLoad because it will break the serverspec regex match)
    end
  end
end
