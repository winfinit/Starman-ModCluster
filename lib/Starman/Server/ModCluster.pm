package Starman::Server::ModCluster;

use 5.008_001;
use strict;
use warnings;
use base 'Starman::Server';
use Net::MCMP;
use Data::Dumper;
use Text::SimpleTable;

sub pre_loop_hook {
	my $self = shift;

	#	warn 'pre loop hook';
	#	warn Dumper $self;

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
			$self->fatal( 'missing mc_port option' );
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

		warn "Loaded Mod_Cluster configurations:\n" . $mcdraw->draw() . "\n";
	}

	# register for a new mcmp

	foreach my $uri ( split ',', $self->{options}->{mc_uri} ) {
		my $mcmp =
		  Net::MCMP->new(
			{ uri => $uri, debug => $self->{options}->{mc_debug} || 0 } );

		#push @mcmp_objects, $mcmp;

		$mcmp->config(
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

		$mcmp->enable_app(
			{
				JvmRoute => $self->{options}->{mc_node_name},
				Alias    => $self->{options}->{mc_alias},
				Context  => $self->{options}->{mc_context}
			}
		  ),

		  $mcmp->status(
			{
				JvmRoute => $self->{options}->{mc_node_name},
				Load     => 99,
			}
		  );
	}

	$self->SUPER::pre_loop_hook(@_);
}

sub pre_server_close_hook {
	my $self = shift;

	foreach my $uri ( split ',', $self->{options}->{mc_uri} ) {
		my $mcmp =
		  Net::MCMP->new(
			{ uri => $uri, debug => $self->{options}->{mc_debug} || 0 } );

		$mcmp->remove_app(
			{
				JvmRoute => $self->{options}->{mc_node_name},
				Alias    => $self->{options}->{mc_alias},
				Context  => $self->{options}->{mc_context}
			}
		);
		$mcmp->remove_route(
			{
				JvmRoute => $self->{options}->{mc_node_name},
			}
		);
	}

	$self->SUPER::pre_server_close_hook(@_);
}

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Starman::ModCluster - Perl extension for blah blah blah

=head1 SYNOPSIS

  use Starman::ModCluster;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for Starman::ModCluster, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=head2 EXPORT

None by default.



=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

Roman Jurkov, E<lt>winfinit@localE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014 by Roman Jurkov

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.18.1 or,
at your option, any later version of Perl 5 you may have available.


=cut
