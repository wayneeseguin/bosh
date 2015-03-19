shared_examples_for 'an OS image' do
  context 'installed by base_<os>' do
    describe command('dig -v') do # required by agent
      it { should return_exit_status(0) }
    end

    describe command('which crontab') do
      it { should return_exit_status(0) }
    end
  end

  context 'installed by bosh_sudoers' do
    describe file('/etc/sudoers') do
      it { should be_file }
      it { should contain '#includedir /etc/sudoers.d' }
    end
  end

  context 'installed by bosh_users' do
    describe command("grep -q 'export PATH=/var/vcap/bosh/bin:$PATH\n' /root/.bashrc") do
      it { should return_exit_status(0) }
    end

    describe command("grep -q 'export PATH=/var/vcap/bosh/bin:$PATH\n' /home/vcap/.bashrc") do
      it { should return_exit_status(0) }
    end

    describe command("stat -c %a ~vcap") do
      it { should return_stdout("755") }
    end
  end

  context 'installed by rsyslog_build' do
   
    # on CentOS 7 and RHEL 7, this file moved to /etc because with systemd, there is no /etc/init dir anymore
  #   chroot_dir = SpecInfra::Backend::Exec.instance.chroot_dir
  #   syslog_conf_file = "#{chroot_dir}/etc/init/rsyslog_build.conf"
  #   print "looking for syslog_conf_file at #{syslog_conf_file}\n"
  #   if ! File.exists?(syslog_conf_file) then
  #     syslog_conf_file = "#{chroot_dir}/etc/rsyslog_build.conf"
  #   end
  #
  #   print "found syslog_conf_file => #{syslog_conf_file}\n"
  #
  #   describe file(syslog_conf_file) do
  #     it { should contain('/usr/local/sbin/rsyslogd') }
  #   end
  #
  #   describe file('/etc/rsyslog_build.conf') do
  #     it { should be_file }
  #   end
  #
  #   describe user('syslog') do
  #     it { should exist }
  #   end
  #
  #   describe group('adm') do
  #     it { should exist }
  #   end
  #
  #   describe command('rsyslogd -v') do
  #     it { should return_stdout /7\.4\.6/ }
  #   end
  #
  #   # Make sure that rsyslog_build starts with the machine
  #   describe file('/etc/init.d/rsyslog_build') do
  #     it { should be_file }
  #     it { should be_executable }
  #   end
  #
  #   describe service('rsyslog_build') do
  #     it { should be_enabled.with_level(2) }
  #     it { should be_enabled.with_level(3) }
  #     it { should be_enabled.with_level(4) }
  #     it { should be_enabled.with_level(5) }
  #   end
  end
end
