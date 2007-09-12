# ssh/manifests/init.pp - common ssh related components
# Copyright (C) 2007 David Schmitt <david@schmitt.edv-bus.at>
# See LICENSE for the full license granted to you.

class ssh {

class common {
	file {
		"/etc/ssh":
			ensure => directory,
			mode => 0755, owner => root, group => root,
			;
		"$rubysitedir/facter/sshkeys.rb":
			#content => file("$modulesdir/facter/sshkeys.rb"),
			source => "puppet://$servername/ssh/facter/sshkeys.rb",
			mode => 0644;
	}
	group { ssh:
		gid => 204,
		allowdupe => false,
	}
}

class client inherits common {
	package { "openssh-client":
		ensure => installed,
		require => [ File["/etc/ssh"], Group[ssh] ],
	}

	file { "/usr/bin/ssh-agent":
		group => ssh,
		require => Package[openssh-client],
	}
	
	# Now collect all server keys
	Sshkey <<||>>
}

class server inherits client {

	package { "openssh-server":
		ensure => installed,
		require =>  [ File["/etc/ssh"], User[sshd] ],
	}

	user { sshd:
		uid => 204,
		gid => 65534,
		home => "/var/run/sshd",
		shell => "/usr/sbin/nologin",
		allowdupe => false,
	}

	service { ssh:
		ensure => running,
		pattern => "sshd",
		require => Package["openssh-server"],
		subscribe => [ User[sshd], Group["ssh"] ]
	}

	# Now add the key, if we've got one
	case $sshrsakey_key {
		"": { 
			err("no sshrsakey on $fqdn")
		}
		default: {
			#@@sshkey { "$hostname.$domain": type => ssh-dss, key => $sshdsakey_key, ensure => present, }
			debug ( "Storing rsa key for $hostname.$domain" )
			@@sshkey { "$hostname.$domain":
				type => ssh-rsa,
				key => $sshrsakey_key,
				ensure => present,
				require => Package["openssh-client"],
			}
		}
	}

	$real_ssh_port = $ssh_port ? { '' => 22, default => $ssh_port }

	err("User requested ssh on $fqdn with port '${ssh_port}'" )
	err("Configuring ssh on $fqdn with port '${real_ssh_port}'" )

	config{ "Port": ensure => $real_ssh_port }

	nagios2::service{ "ssh_port_${real_ssh_port}": check_command => "ssh_port!$real_ssh_port" }

	define config($ensure) {
		replace { "sshd_config_$name":
			file => "/etc/ssh/sshd_config",
			pattern => "^$name +(?!\\Q$ensure\\E).*",
			replacement => "$name $ensure # set by puppet",
			notify => Service[ssh],
		}
	}

}

}
