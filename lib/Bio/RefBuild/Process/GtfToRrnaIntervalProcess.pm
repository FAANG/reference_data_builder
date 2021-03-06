package Bio::RefBuild::Process::GtfToRrnaIntervalProcess;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::Process');

use autodie;
use Bio::RefBuild::Util::GtfToRrnaInterval;

sub fetch_input {
    my ($self) = @_;

    my $gtf           = $self->param_required('gtf');
    my $dict          = $self->param_required('dict');
    my $rrna_interval = $self->param_required('rrna_interval');
}

sub run {
    my ($self) = @_;

    $self->dbc
      and $self->dbc->disconnect_when_inactive(1)
      ;    # release this connection for the duration of task

    my $gtf_fh;
    my $gtf = $self->param_required('gtf');

    if ( $gtf =~ m/\.gz$/ ) {
        open( my $gtf_fh, '-|', 'gzip', '-dc', $gtf );
    }
    else {
        open( $gtf_fh, '<', $gtf );
    }

    open( my $dict_fh,          '<', $self->param_required('dict') );
    open( my $rrna_interval_fh, '>', $self->param_required('rrna_interval') );

    my $converter = Bio::RefBuild::Util::GtfToRrnaInterval->new(
        in_fh   => $gtf_fh,
        dict_fh => $dict_fh,
        out_fh  => $rrna_interval_fh,
    );

    $converter->convert();

    map { close($_) } ( $gtf_fh, $dict_fh, $rrna_interval_fh );

}

1;
