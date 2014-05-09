package Starman::Server::ModCluster;

use 5.008_001;
use strict;
use warnings;
use base 'Starman::Server';
use Net::MCMP;
use Text::SimpleTable;

sub pre_loop_hook {
	my $self = shift;


	# register for a new mcmp

	foreach my $uri ( split ',', $self->{options}->{mc_uri} ) {
		my $mcmp =
		  Net::MCMP->new(
			{ uri => $uri, debug => $self->{options}->{mc_debug} || 0 } );

		#push @mcmp_objects, $mcmp;

		$self->mcmp_config($mcmp);
		$self->mcmp_enable_app($mcmp);
		$self->start_mc_status;
	}

	$self->SUPER::pre_loop_hook(@_);
}

sub start_mc_status {
	my $self = shift;

	local $!;
	my $pid = fork;
	if ( !defined $pid ) {
		$self->fatal("Unable to fork mod_cluster status child [$!]");
	}

	if ( $pid == 0 ) {
		$SIG{'INT'} = $SIG{'TERM'} = $SIG{'QUIT'} = sub {
			$self->log( 4, "exiting mod_cluster status reporter" );
			# just exit, no need to have stop hook
			exit;
		};
		$SIG{'PIPE'} = 'IGNORE';
		$SIG{'CHLD'} = 'DEFAULT';
		$SIG{'HUP'}  = 'DEFAULT';

		$self->log( 4, "mod_cluster status reporter forked ($$)" );
		$0 = "Starman::ModCluster status reporter";

		my @mcmp_obj;
		foreach my $uri ( split ',', $self->{options}->{mc_uri} ) {
			my $mcmp =
			  Net::MCMP->new(
				{ uri => $uri, debug => $self->{options}->{mc_debug} || 0 } );
			push @mcmp_obj, $mcmp;
		}

		while (1) {
			foreach my $mcmp (@mcmp_obj) {
				$self->mcmp_status($mcmp);

			}
			if ( exists $self->{options}->{mc_status_disable} && defined $self->{options}->{mc_status_interval} ) {
				# communicate just init status, and exit;
				last;
			} else {
				sleep( $self->{options}->{mc_status_interval} || 30 );			
			}
		}

		$self->log(4, "exiting mod_cluster status reporter");
		exit;
	}
}

sub mcmp_config {
	my ( $self, $mcmp ) = @_;
	
		unless ( exists $self->{options}->{mc_host} ) {
		if ( defined $self->{options}->{host} ) {
			$self->{options}->{mc_host} = $self->{options}->{mc_host};
		}
		else {
			$self->fatal('missing mc_host option');
		}
	}

	unless ( exists $self->{options}->{mc_port} ) {
		if ( defined $self->{options}->{port} ) {
			$self->{options}->{mc_port} = $self->{options}->{port};
		}
		elsif ( exists $ENV{SERVER_PORT} && defined $ENV{SERVER_PORT} ) {
			$self->{options}->{mc_port} = $ENV{SERVER_PORT};
		}
		else {
			$self->fatal('missing mc_port option');
		}
	}

	unless ( exists $self->{options}->{mc_type}
		&& defined $self->{options}->{mc_type} )
	{
		$self->{options}->{mc_type} = $ENV{'psgi.url_scheme'} || 'http';
	}

	unless ( exists $self->{options}->{mc_alias}
		&& defined $self->{options}->{mc_alias} )
	{
		$self->{options}->{mc_alias} = 'StarmanServer';
	}

	my @uris;

	if ( ref $self->{options}->{mc_uri} eq 'ARRAY' ) {
		$self->{options}->{mc_uri} = join ',', @{ $self->{options}->{mc_uri} };
	}

	foreach my $key (qw/mc_context mc_alias/) {
		if ( exists $self->{options}->{$key}
			&& ref $self->{options}->{$key} eq 'ARRAY' )
		{
			$self->{options}->{$key} = join ',', @{ $self->{options}->{$key} };
		}
	}

	if ( $self->{options}->{mc_debug} ) {
		my $mcdraw =
		  Text::SimpleTable->new( [ 20, 'Configuration' ], [ 51, 'Value' ] );

		foreach my $key ( keys %{ $self->{options} } ) {
			next unless $key =~ /^mc_/;
			$mcdraw->row( $key, $self->{options}->{$key} );
		}

		$self->log( 2,
			"Loaded Mod_Cluster configurations:\n" . $mcdraw->draw() );
	}
	
	
	return $mcmp->config(
		{
			Balancer     => $self->{options}->{mc_balancer},
			WaitWorker   => $self->{options}->{mc_wait_worker},
			MaxAttempts  => $self->{options}->{mc_max_attempts},
			JvmRoute     => $self->{options}->{mc_node_name},
			Domain       => $self->{options}->{mc_domain},
			Host         => $self->{options}->{mc_host},
			Port         => $self->{options}->{mc_port},
			Type         => $self->{options}->{mc_type},
			FlushPackets => $self->{options}->{mc_flush_packets},
			FlushWait    => $self->{options}->{mc_flush_wait},
			Ping         => $self->{options}->{mc_ping},
			Smax         => $self->{options}->{mc_smax},
			Ttl          => $self->{options}->{mc_ttl},
			Timeout      => $self->{options}->{mc_timeoutt},
			Context      => $self->{options}->{mc_context},
			Alias        => $self->{options}->{mc_alias},
		}
	);
}

sub mcmp_enable_app {
	my ( $self, $mcmp ) = @_;

	return $mcmp->enable_app(
		{
			JvmRoute => $self->{options}->{mc_node_name},
			Alias    => $self->{options}->{mc_alias},
			Context  => $self->{options}->{mc_context}
		}
	  ),
	  ;
}

sub mcmp_status {
	my ( $self, $mcmp ) = @_;

	$self->log( 4, "sending mcmp status to " . $mcmp->uri );

	my $response = $mcmp->status(
		{
			JvmRoute => $self->{options}->{mc_node_name},
			Load     => 99,
		}
	);

	if ( $response->{State} ne 'OK' ) {
		$self->log( 1, "STATUS response is not OK: " . $response->{Status} );
	}

	return $response;

}

sub mcmp_remove_app {
	my ( $self, $mcmp ) = @_;

	return $mcmp->remove_app(
		{
			JvmRoute => $self->{options}->{mc_node_name},
			Alias    => $self->{options}->{mc_alias},
			Context  => $self->{options}->{mc_context}
		}
	);
}

sub mcmp_remove_route {
	my ( $self, $mcmp ) = @_;
	return $mcmp->remove_route(
		{
			JvmRoute => $self->{options}->{mc_node_name},
		}
	);
}

sub pre_server_close_hook {
	my $self = shift;

	foreach my $uri ( split ',', $self->{options}->{mc_uri} ) {
		my $mcmp =
		  Net::MCMP->new(
			{ uri => $uri, debug => $self->{options}->{mc_debug} || 0 } );

		$self->mcmp_remove_app($mcmp);
		$self->mcmp_remove_route($mcmp);

	}

	$self->SUPER::pre_server_close_hook(@_);
}

1;
__END__
=encoding utf-8

=for stopwords

=head1 NAME

Starman::Server::ModCluster - extension to Starman::Server that registers pre_server_close_hook and 
pre_loop_hook of Net::Server to register and remove node from a cluster.


=head1 DESCRIPTION

This module is not intended to use directly. It should be used via L<starman-modcluster> command


=head1 SEE ALSO

L<starman-modcluster> L<Starman>

=head1 AUTHOR

Roman Jurkov, E<lt>winfinit@cpan.org<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014- by Roman Jurkov

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.18.1 or,
at your option, any later version of Perl 5 you may have available.


=cut
