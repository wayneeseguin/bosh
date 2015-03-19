RHEL 7 and CentOS 7 have moved to Nmap-ncat, which is a rewrite of netcat that drops support for the -z option
(naturally, the nmap authors say you should use nmap for port scanning).

There are parts of this BOSH stemcell build process, and the Diego runtime, that depend on the `nc -z`
portscanning feature.

So, for systems that have moved to nmap-ncat, we compile and install GNU Netcat so that `nc -z` works as expected.
